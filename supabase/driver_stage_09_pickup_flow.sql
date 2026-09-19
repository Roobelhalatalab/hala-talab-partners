-- Hala Talab Partners - Driver Stage 09
-- Driver pickup confirmation and active-trip continuation.
-- Safe to run more than once. Existing orders are preserved.

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
      and o.status in ('assigned', 'picked_up')
    order by o.updated_at desc
    limit 1
  ) x;
$$;

create or replace function public.driver_confirm_order_pickup(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.orders o
     set status = 'picked_up',
         picked_up_at = coalesce(o.picked_up_at, now()),
         updated_at = now()
   where o.id = p_order_id
     and o.driver_id = auth.uid()
     and o.status = 'assigned'
  returning o.* into v_order;

  if v_order.id is null then
    raise exception 'Order is not available for pickup confirmation';
  end if;

  return public.get_current_driver_assigned_order();
end;
$$;

revoke all on function public.get_current_driver_assigned_order() from public;
revoke all on function public.driver_confirm_order_pickup(uuid) from public;
grant execute on function public.get_current_driver_assigned_order() to authenticated;
grant execute on function public.driver_confirm_order_pickup(uuid) to authenticated;

notify pgrst, 'reload schema';

select
  to_regprocedure('public.get_current_driver_assigned_order()') as active_trip_rpc,
  to_regprocedure('public.driver_confirm_order_pickup(uuid)') as confirm_pickup_rpc;
