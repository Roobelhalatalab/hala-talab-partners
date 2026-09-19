-- Hala Talab — Stage 115 Unified Location Pipeline
-- One source of truth for customer, store and driver coordinates.
-- Safe to run more than once.

alter table public.orders add column if not exists delivery_latitude double precision;
alter table public.orders add column if not exists delivery_longitude double precision;
alter table public.stores add column if not exists latitude double precision;
alter table public.stores add column if not exists longitude double precision;

-- Customer writes the selected delivery coordinates onto their own order.
create or replace function public.set_customer_order_delivery_location(
  p_order_id uuid,
  p_latitude double precision,
  p_longitude double precision
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_latitude is null or p_latitude < -90 or p_latitude > 90 then raise exception 'INVALID_LATITUDE'; end if;
  if p_longitude is null or p_longitude < -180 or p_longitude > 180 then raise exception 'INVALID_LONGITUDE'; end if;

  update public.orders
     set delivery_latitude = p_latitude,
         delivery_longitude = p_longitude,
         updated_at = now()
   where id = p_order_id
     and customer_id = auth.uid();

  if not found then raise exception 'ORDER_NOT_FOUND_OR_FORBIDDEN'; end if;
end;
$$;

-- Driver active orders always include BOTH store and customer coordinates.
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

revoke all on function public.set_customer_order_delivery_location(uuid,double precision,double precision) from public;
revoke all on function public.get_driver_active_orders() from public;
revoke all on function public.get_current_driver_assigned_order() from public;
grant execute on function public.set_customer_order_delivery_location(uuid,double precision,double precision) to authenticated;
grant execute on function public.get_driver_active_orders() to authenticated;
grant execute on function public.get_current_driver_assigned_order() to authenticated;

notify pgrst, 'reload schema';

select
  to_regprocedure('public.set_customer_order_delivery_location(uuid,double precision,double precision)') is not null as customer_location_rpc,
  to_regprocedure('public.get_driver_active_orders()') is not null as driver_active_orders_rpc,
  to_regprocedure('public.get_current_driver_assigned_order()') is not null as driver_current_order_rpc,
  true as stage_115_ready;
