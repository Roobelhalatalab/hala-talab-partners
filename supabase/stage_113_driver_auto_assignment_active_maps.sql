-- Hala Talab Partners — Stage 113
-- Driver auto-assignment flow + active-order visibility + map coordinates.
-- Safe to run more than once. Existing orders are preserved.

-- The current production flow (Stage 79) keeps an assigned driver's order in
-- status = 'ready' until pickup. Therefore ready + driver_id must be treated as
-- an active driver trip everywhere.
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
      coalesce(
        (
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
        ),
        '[]'::jsonb
      ) as items
    from public.orders o
    join public.stores s on s.id = o.store_id
    where auth.uid() is not null
      and o.driver_id = auth.uid()
      and o.status in ('ready', 'assigned', 'picked_up')
  ) x;
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
      coalesce(
        (
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
        ),
        '[]'::jsonb
      ) as items
    from public.orders o
    join public.stores s on s.id = o.store_id
    where auth.uid() is not null
      and o.driver_id = auth.uid()
      and o.status in ('ready', 'assigned', 'picked_up')
    order by o.updated_at desc
    limit 1
  ) x;
$$;

-- Align the atomic claim RPC with the no-extra-acceptance flow.
-- Claiming assigns only driver_id and keeps status='ready' until pickup.
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
    and o.status in ('ready','assigned','picked_up') limit 1;
  if found then return; end if;

  select count(*)::integer into v_active_count
  from public.orders o
  where o.driver_id=auth.uid() and o.status in ('ready','assigned','picked_up');
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

revoke all on function public.get_driver_active_orders() from public;
revoke all on function public.get_current_driver_assigned_order() from public;
revoke all on function public.claim_driver_delivery_offer(uuid) from public;
grant execute on function public.get_driver_active_orders() to authenticated;
grant execute on function public.get_current_driver_assigned_order() to authenticated;
grant execute on function public.claim_driver_delivery_offer(uuid) to authenticated;

notify pgrst, 'reload schema';

select
  to_regprocedure('public.get_driver_active_orders()') as active_orders_rpc,
  to_regprocedure('public.get_current_driver_assigned_order()') as current_order_rpc,
  to_regprocedure('public.claim_driver_delivery_offer(uuid)') as claim_rpc,
  true as stage_113_ready;
