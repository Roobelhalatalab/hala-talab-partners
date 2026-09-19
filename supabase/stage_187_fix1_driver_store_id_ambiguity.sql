-- Hala Talab — Partners Stage 187 FIX1
-- Fix: "column reference store_id is ambiguous" when a driver opens/claims a notification.
-- Safe/idempotent. No orders, notifications, stores, drivers, or assignments are deleted.

begin;

-- Make the store-owner RLS expression explicit. This avoids an unqualified
-- store_id leaking into queries/functions that also expose a store_id column.
drop policy if exists "driver scope store owner read" on public.driver_delivery_scope;
create policy "driver scope store owner read"
on public.driver_delivery_scope
for select to authenticated
using (
  public.driver_delivery_scope.store_id is not null
  and exists (
    select 1
    from public.stores s
    where s.id = public.driver_delivery_scope.store_id
      and s.owner_id = auth.uid()
  )
);

-- Canonical eligibility with fully-qualified columns only.
create or replace function public.driver_can_take_store(
  p_driver_id uuid,
  p_store_id uuid
)
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

-- Reassert the available-offer RPC with explicit aliases.
create or replace function public.get_available_driver_delivery_offer()
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
language sql
security definer
set search_path = public
as $$
  select
    o.id as order_id,
    o.order_number as order_number,
    o.store_id as store_id,
    s.name as store_name,
    s.address_text as store_address,
    o.customer_name as customer_name,
    o.customer_phone as customer_phone,
    o.delivery_address as delivery_address,
    o.delivery_fee as delivery_fee,
    o.payment_method as payment_method,
    o.created_at as created_at
  from public.orders o
  join public.stores s on s.id = o.store_id
  where auth.uid() is not null
    and public.driver_can_take_store(auth.uid(), o.store_id)
    and (
      select count(*)
      from public.orders ao
      where ao.driver_id = auth.uid()
        and ao.status in ('ready','assigned','picked_up')
    ) < 10
    and o.status = 'ready'
    and o.driver_id is null
    and not exists (
      select 1
      from public.driver_order_rejections r
      where r.driver_id = auth.uid()
        and r.order_id = o.id
    )
  order by o.ready_at nulls last, o.created_at
  limit 1
$$;

-- IMPORTANT: RETURNS TABLE creates PL/pgSQL variables named store_id, etc.
-- Every table column is therefore qualified, and the conflict directive is
-- explicit so an older/stale function body cannot resolve store_id wrongly.
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
#variable_conflict use_column
declare
  v_active_count integer;
  v_store_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select o.store_id
    into v_store_id
  from public.orders o
  where o.id = p_order_id;

  if v_store_id is null then
    raise exception 'Delivery offer is no longer available';
  end if;

  if not public.driver_can_take_store(auth.uid(), v_store_id) then
    raise exception 'This order is not available for this driver';
  end if;

  -- Idempotent: if this driver already owns the order, just return it.
  return query
  select
    o.id as order_id,
    o.order_number as order_number,
    o.store_id as store_id,
    s.name as store_name,
    s.address_text as store_address,
    o.customer_name as customer_name,
    o.customer_phone as customer_phone,
    o.delivery_address as delivery_address,
    o.delivery_fee as delivery_fee,
    o.payment_method as payment_method,
    o.created_at as created_at
  from public.orders o
  join public.stores s on s.id = o.store_id
  where o.id = p_order_id
    and o.driver_id = auth.uid()
    and o.status in ('ready','assigned','picked_up')
  limit 1;

  if found then
    return;
  end if;

  select count(*)::integer
    into v_active_count
  from public.orders ao
  where ao.driver_id = auth.uid()
    and ao.status in ('ready','assigned','picked_up');

  if v_active_count >= 10 then
    raise exception 'Driver active order limit reached';
  end if;

  return query
  with claimed_order as (
    update public.orders as uo
       set driver_id = auth.uid(),
           updated_at = now()
     where uo.id = p_order_id
       and uo.status = 'ready'
       and uo.driver_id is null
       and public.driver_can_take_store(auth.uid(), uo.store_id)
    returning uo.id,
              uo.order_number,
              uo.store_id,
              uo.customer_name,
              uo.customer_phone,
              uo.delivery_address,
              uo.delivery_fee,
              uo.payment_method,
              uo.created_at
  )
  select
    co.id as order_id,
    co.order_number as order_number,
    co.store_id as store_id,
    s.name as store_name,
    s.address_text as store_address,
    co.customer_name as customer_name,
    co.customer_phone as customer_phone,
    co.delivery_address as delivery_address,
    co.delivery_fee as delivery_fee,
    co.payment_method as payment_method,
    co.created_at as created_at
  from claimed_order co
  join public.stores s on s.id = co.store_id;

  if not found then
    raise exception 'Delivery offer is no longer available';
  end if;
end
$$;

revoke all on function public.get_available_driver_delivery_offer() from public;
revoke all on function public.claim_driver_delivery_offer(uuid) from public;
grant execute on function public.get_available_driver_delivery_offer() to authenticated;
grant execute on function public.claim_driver_delivery_offer(uuid) to authenticated;

-- Reassert active-order payload with coordinates; this is what drives the map
-- immediately after a successful claim.
create or replace function public.get_driver_active_orders()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc), '[]'::jsonb)
  from (
    select
      o.id as order_id,
      o.order_number,
      o.status,
      o.store_id,
      s.name as store_name,
      s.address_text as store_address,
      s.phone as store_phone,
      s.latitude as store_latitude,
      s.longitude as store_longitude,
      o.customer_name,
      o.customer_phone,
      o.delivery_address,
      o.delivery_latitude,
      o.delivery_longitude,
      o.notes,
      o.subtotal,
      o.delivery_fee,
      o.discount_amount,
      o.total,
      o.payment_method,
      o.payment_status,
      o.created_at,
      o.updated_at,
      o.picked_up_at,
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', oi.id,
            'product_name', oi.product_name,
            'quantity', oi.quantity,
            'unit_price', oi.unit_price,
            'total_price', oi.total_price,
            'notes', oi.notes
          ) order by oi.created_at
        )
        from public.order_items oi
        where oi.order_id = o.id
      ), '[]'::jsonb) as items
    from public.orders o
    join public.stores s on s.id = o.store_id
    where auth.uid() is not null
      and o.driver_id = auth.uid()
      and o.status in ('ready','assigned','picked_up')
  ) x
$$;

create or replace function public.get_current_driver_assigned_order()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select to_jsonb(x)
  from (
    select
      o.id as order_id,
      o.order_number,
      o.status,
      o.store_id,
      s.name as store_name,
      s.address_text as store_address,
      s.phone as store_phone,
      s.latitude as store_latitude,
      s.longitude as store_longitude,
      o.customer_name,
      o.customer_phone,
      o.delivery_address,
      o.delivery_latitude,
      o.delivery_longitude,
      o.notes,
      o.subtotal,
      o.delivery_fee,
      o.discount_amount,
      o.total,
      o.payment_method,
      o.payment_status,
      o.created_at,
      o.updated_at,
      o.picked_up_at
    from public.orders o
    join public.stores s on s.id = o.store_id
    where auth.uid() is not null
      and o.driver_id = auth.uid()
      and o.status in ('ready','assigned','picked_up')
    order by o.updated_at desc
    limit 1
  ) x
$$;

revoke all on function public.get_driver_active_orders() from public;
revoke all on function public.get_current_driver_assigned_order() from public;
grant execute on function public.get_driver_active_orders() to authenticated;
grant execute on function public.get_current_driver_assigned_order() to authenticated;

commit;
notify pgrst, 'reload schema';

select
  to_regprocedure('public.claim_driver_delivery_offer(uuid)') is not null as claim_rpc_ready,
  to_regprocedure('public.get_driver_active_orders()') is not null as active_orders_rpc_ready,
  to_regprocedure('public.get_current_driver_assigned_order()') is not null as current_order_rpc_ready;
