-- Hala Talab Partners - Stage 79
-- Stable store-order bridge + notification repair + forward-only driver flow.
-- Built on the last pre-Stage-77 app base that was proven to receive orders.
-- Safe to run more than once. No existing orders or notifications are deleted.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1) Store order reads through SECURITY DEFINER RPCs.
--    This avoids a silent empty list if a client-side RLS/read path is temporarily
--    out of sync, while still restricting rows to the signed-in store owner.
-- ---------------------------------------------------------------------------
create or replace function public.get_my_store_orders_v2()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      to_jsonb(o) || jsonb_build_object(
        'order_items', coalesce(
          (
            select jsonb_agg(to_jsonb(oi) order by oi.created_at)
            from public.order_items oi
            where oi.order_id = o.id
          ),
          '[]'::jsonb
        )
      )
      order by o.created_at desc
    ),
    '[]'::jsonb
  )
  from public.orders o
  join public.stores s on s.id = o.store_id
  where auth.uid() is not null
    and s.owner_id = auth.uid();
$$;

create or replace function public.get_my_store_order_v2(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(o) || jsonb_build_object(
    'order_items', coalesce(
      (
        select jsonb_agg(to_jsonb(oi) order by oi.created_at)
        from public.order_items oi
        where oi.order_id = o.id
      ),
      '[]'::jsonb
    )
  )
  from public.orders o
  join public.stores s on s.id = o.store_id
  where auth.uid() is not null
    and s.owner_id = auth.uid()
    and o.id = p_order_id
  limit 1;
$$;

revoke all on function public.get_my_store_orders_v2() from public;
revoke all on function public.get_my_store_order_v2(uuid) from public;
grant execute on function public.get_my_store_orders_v2() to authenticated;
grant execute on function public.get_my_store_order_v2(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Store notifications: restore the proven insert trigger and add a protected
--    read RPC so the dialog and badge cannot silently miss rows because of RLS.
-- ---------------------------------------------------------------------------
create table if not exists public.store_notifications (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  type text not null default 'system',
  title text not null,
  body text,
  data jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create or replace function public.notify_store_new_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.store_notifications(store_id,type,title,body,data,is_read)
  values (
    new.store_id,
    'new_order',
    'طلب جديد #' || coalesce(new.order_number::text,left(new.id::text,8)),
    'وصل طلب جديد بقيمة ' || coalesce(new.total,0)::text || ' د.ع',
    jsonb_build_object(
      'order_id',new.id,
      'order_number',new.order_number,
      'status',new.status,
      'total',new.total
    ),
    false
  );
  return new;
end;
$$;

drop trigger if exists orders_create_store_notification on public.orders;
create trigger orders_create_store_notification
after insert on public.orders
for each row execute function public.notify_store_new_order();

create or replace function public.get_my_store_notifications_v2(p_limit integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc), '[]'::jsonb)
  from (
    select n.*
    from public.store_notifications n
    join public.stores s on s.id = n.store_id
    where auth.uid() is not null
      and s.owner_id = auth.uid()
    order by n.created_at desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) n;
$$;

create or replace function public.get_my_store_unread_notification_count()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::bigint
  from public.store_notifications n
  join public.stores s on s.id=n.store_id
  where auth.uid() is not null
    and s.owner_id=auth.uid()
    and n.is_read=false;
$$;

revoke all on function public.get_my_store_notifications_v2(integer) from public;
revoke all on function public.get_my_store_unread_notification_count() from public;
grant execute on function public.get_my_store_notifications_v2(integer) to authenticated;
grant execute on function public.get_my_store_unread_notification_count() to authenticated;

-- Preserve normal RLS policies as a secondary path.
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.store_notifications enable row level security;

drop policy if exists "Store owners can view own orders" on public.orders;
create policy "Store owners can view own orders"
on public.orders for select to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = orders.store_id and s.owner_id = auth.uid()
));

drop policy if exists "Store owners can view own order items" on public.order_items;
create policy "Store owners can view own order items"
on public.order_items for select to authenticated
using (exists (
  select 1
  from public.orders o
  join public.stores s on s.id = o.store_id
  where o.id = order_items.order_id and s.owner_id = auth.uid()
));

drop policy if exists "Store owners can view notifications" on public.store_notifications;
create policy "Store owners can view notifications"
on public.store_notifications for select to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = store_notifications.store_id and s.owner_id = auth.uid()
));

-- ---------------------------------------------------------------------------
-- 3) Driver flow: accepting a READY order only assigns the driver.
--    Customer status stays READY until pickup; pickup advances to PICKED_UP.
-- ---------------------------------------------------------------------------
create or replace function public.claim_driver_delivery_offer(p_order_id uuid)
returns table (
  order_id uuid, order_number bigint, store_id uuid, store_name text,
  store_address text, customer_name text, customer_phone text,
  delivery_address text, delivery_fee numeric, payment_method text, created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare v_active_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  return query
  select o.id, o.order_number, o.store_id, s.name, s.address_text,
         o.customer_name, o.customer_phone, o.delivery_address,
         o.delivery_fee, o.payment_method, o.created_at
  from public.orders o join public.stores s on s.id=o.store_id
  where o.id=p_order_id and o.driver_id=auth.uid()
    and o.status in ('ready','picked_up') limit 1;
  if found then return; end if;

  select count(*)::integer into v_active_count
  from public.orders o
  where o.driver_id=auth.uid() and o.status in ('ready','picked_up');
  if v_active_count >= 10 then raise exception 'Driver active order limit reached'; end if;

  return query
  with claimed as (
    update public.orders o
       set driver_id=auth.uid(), updated_at=now()
     where o.id=p_order_id and o.status='ready' and o.driver_id is null
     returning o.*
  )
  select c.id,c.order_number,c.store_id,s.name,s.address_text,c.customer_name,
         c.customer_phone,c.delivery_address,c.delivery_fee,c.payment_method,c.created_at
  from claimed c join public.stores s on s.id=c.store_id;
  if not found then raise exception 'Delivery offer is no longer available'; end if;
end;
$$;

create or replace function public.driver_confirm_order_pickup(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_order public.orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.orders o
     set status='picked_up', picked_up_at=coalesce(o.picked_up_at,now()), updated_at=now()
   where o.id=p_order_id and o.driver_id=auth.uid() and o.status='ready'
   returning o.* into v_order;
  if v_order.id is null then raise exception 'Order is not available for pickup confirmation'; end if;
  return public.get_current_driver_assigned_order();
end;
$$;

revoke all on function public.claim_driver_delivery_offer(uuid) from public;
revoke all on function public.driver_confirm_order_pickup(uuid) from public;
grant execute on function public.claim_driver_delivery_offer(uuid) to authenticated;
grant execute on function public.driver_confirm_order_pickup(uuid) to authenticated;

-- Realtime remains enabled, but the app no longer depends on a polling patch.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='store_notifications'
  ) then
    alter publication supabase_realtime add table public.store_notifications;
  end if;
end $$;

notify pgrst, 'reload schema';

select
  to_regprocedure('public.get_my_store_orders_v2()') is not null as store_orders_rpc,
  to_regprocedure('public.get_my_store_order_v2(uuid)') is not null as store_order_rpc,
  to_regprocedure('public.get_my_store_notifications_v2(integer)') is not null as store_notifications_rpc,
  exists (
    select 1 from pg_trigger
    where tgname='orders_create_store_notification' and not tgisinternal
  ) as notification_trigger,
  true as stage_79_ready;
