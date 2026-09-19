-- Hala Talab — Partners Stage 187
-- Driver Delivery Flow Final Stabilization
-- Run ONCE after Stage 185 + Stage 186. Safe/idempotent; no orders are deleted.
-- Goals:
--   1) store drivers receive only their store orders;
--   2) Hala Talab drivers receive all eligible ready orders;
--   3) reassigning/changing driver scope can re-notify existing ready work;
--   4) push is retried on a deliberate notification refresh without firing on read/unread changes;
--   5) one atomic claim RPC is used by polling, in-app notification taps and push taps.

begin;

-- Canonical eligibility. Keep the decision in the database, not in Flutter.
create or replace function public.driver_can_take_store(p_driver_id uuid, p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select d.is_active
      and (
        d.driver_type = 'hala'
        or (d.driver_type = 'store' and d.store_id = p_store_id)
      )
    from public.driver_delivery_scope d
    where d.driver_id = p_driver_id
  ), false)
$$;

revoke all on function public.driver_can_take_store(uuid,uuid) from public;
grant execute on function public.driver_can_take_store(uuid,uuid) to authenticated;

-- Unified atomic claim. Re-running the action for an order already owned by the
-- current driver is idempotent and returns that trip instead of failing.
create or replace function public.claim_driver_delivery_offer(p_order_id uuid)
returns table(
  order_id uuid,
  order_number bigint,
  store_id uuid,
  store_name text,
  store_address text,
  customer_name text,
  customer_phone text,
  delivery_address text,
  delivery_fee numeric,
  payment_method text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active_count integer;
  v_store uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select o.store_id into v_store
  from public.orders o
  where o.id = p_order_id;

  if v_store is null then
    raise exception 'Delivery offer is no longer available';
  end if;

  if not public.driver_can_take_store(auth.uid(), v_store) then
    raise exception 'This order is not available for this driver';
  end if;

  -- Idempotent path: notification may be tapped after polling already claimed it.
  return query
  select o.id, o.order_number, o.store_id, s.name, s.address_text,
         o.customer_name, o.customer_phone, o.delivery_address,
         o.delivery_fee, o.payment_method, o.created_at
  from public.orders o
  join public.stores s on s.id = o.store_id
  where o.id = p_order_id
    and o.driver_id = auth.uid()
    and o.status in ('ready','assigned','picked_up')
  limit 1;
  if found then return; end if;

  select count(*)::int into v_active_count
  from public.orders
  where driver_id = auth.uid()
    and status in ('ready','assigned','picked_up');

  if v_active_count >= 10 then
    raise exception 'Driver active order limit reached';
  end if;

  return query
  with claimed as (
    update public.orders o
       set driver_id = auth.uid(),
           updated_at = now()
     where o.id = p_order_id
       and o.status = 'ready'
       and o.driver_id is null
       and public.driver_can_take_store(auth.uid(), o.store_id)
    returning o.*
  )
  select c.id, c.order_number, c.store_id, s.name, s.address_text,
         c.customer_name, c.customer_phone, c.delivery_address,
         c.delivery_fee, c.payment_method, c.created_at
  from claimed c
  join public.stores s on s.id = c.store_id;

  if not found then
    raise exception 'Delivery offer is no longer available';
  end if;
end
$$;

revoke all on function public.claim_driver_delivery_offer(uuid) from public;
grant execute on function public.claim_driver_delivery_offer(uuid) to authenticated;

-- A ready order fans out to every currently eligible driver. If the same
-- available notification already exists, refresh created_at instead of silently
-- doing nothing; Stage 187's push trigger below treats that refresh as an
-- intentional re-dispatch.
create or replace function public.hala_notify_eligible_drivers_ready_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'ready' or new.driver_id is not null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status is not distinct from new.status
     and old.store_id is not distinct from new.store_id
     and old.driver_id is not distinct from new.driver_id then
    return new;
  end if;

  insert into public.driver_notifications(
    driver_id, order_id, order_number, event_type, is_read, read_at, created_at
  )
  select d.driver_id, new.id, new.order_number::text, 'available', false, null, now()
  from public.driver_delivery_scope d
  where d.is_active = true
    and (
      d.driver_type = 'hala'
      or (d.driver_type = 'store' and d.store_id = new.store_id)
    )
  on conflict (driver_id, order_id, event_type)
  do update set
    is_read = false,
    read_at = null,
    created_at = excluded.created_at;

  return new;
end
$$;

-- Reassignment/type switch must also work for already-ready orders. This is
-- especially important when Admin changes a driver from store -> Hala or vice versa.
create or replace function public.hala_notify_driver_after_scope_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active is not true then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.is_active is not distinct from new.is_active
     and old.driver_type is not distinct from new.driver_type
     and old.store_id is not distinct from new.store_id then
    return new;
  end if;

  insert into public.driver_notifications(
    driver_id, order_id, order_number, event_type, is_read, read_at, created_at
  )
  select new.driver_id, q.id, q.order_number::text, 'available', false, null, now()
  from (
    select o.id, o.order_number
    from public.orders o
    where o.status = 'ready'
      and o.driver_id is null
      and (
        new.driver_type = 'hala'
        or (new.driver_type = 'store' and o.store_id = new.store_id)
      )
    order by o.ready_at nulls last, o.created_at
    limit 10
  ) q
  on conflict (driver_id, order_id, event_type)
  do update set
    is_read = false,
    read_at = null,
    created_at = excluded.created_at;

  return new;
end
$$;

-- Reassert triggers from Stage 186.
drop trigger if exists hala_orders_ready_driver_fanout on public.orders;
create trigger hala_orders_ready_driver_fanout
after insert or update of status, driver_id, store_id on public.orders
for each row execute function public.hala_notify_eligible_drivers_ready_order();

drop trigger if exists hala_driver_scope_ready_backfill on public.driver_delivery_scope;
create trigger hala_driver_scope_ready_backfill
after insert or update of driver_type, store_id, is_active on public.driver_delivery_scope
for each row execute function public.hala_notify_driver_after_scope_assignment();

-- The existing pg_net enqueue function is reused. Fire on INSERT and only on an
-- intentional created_at refresh; marking a notification read must NOT resend push.
drop trigger if exists hala_driver_notifications_push on public.driver_notifications;
create trigger hala_driver_notifications_push
after insert or update of created_at on public.driver_notifications
for each row execute function public.hala_enqueue_driver_notification_push();

-- Self diagnostics used during QA. No raw FCM token is exposed to the client.
create or replace function public.driver_delivery_runtime_status()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'driver_id', auth.uid(),
    'driver_type', d.driver_type,
    'store_id', d.store_id,
    'scope_active', coalesce(d.is_active,false),
    'push_tokens', (
      select count(*) from public.device_push_tokens t
      where t.user_id = auth.uid() and t.role = 'driver'
    ),
    'ready_offers_visible', (
      select count(*) from public.orders o
      where o.status = 'ready' and o.driver_id is null
        and public.driver_can_take_store(auth.uid(), o.store_id)
    ),
    'active_orders', (
      select count(*) from public.orders o
      where o.driver_id = auth.uid() and o.status in ('ready','assigned','picked_up')
    ),
    'unread_notifications', (
      select count(*) from public.driver_notifications n
      where n.driver_id = auth.uid() and n.is_read = false
    )
  )
  from public.driver_delivery_scope d
  where d.driver_id = auth.uid()
$$;

revoke all on function public.driver_delivery_runtime_status() from public;
grant execute on function public.driver_delivery_runtime_status() to authenticated;

alter table public.driver_notifications replica identity full;

commit;
notify pgrst, 'reload schema';

select
  to_regprocedure('public.claim_driver_delivery_offer(uuid)') is not null as unified_claim_ready,
  to_regprocedure('public.driver_delivery_runtime_status()') is not null as diagnostics_ready,
  exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname='public'
      and c.relname='driver_notifications'
      and t.tgname='hala_driver_notifications_push'
      and t.tgenabled <> 'D'
  ) as driver_push_trigger_ready;
