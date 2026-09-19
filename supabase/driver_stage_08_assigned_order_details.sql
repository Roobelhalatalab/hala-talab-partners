-- Hala Talab Partners - Driver Stage 08
-- Secure assigned-order details for the authenticated driver.
-- Safe to run more than once. No existing data is deleted.

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
      and o.status = 'assigned'
    order by o.updated_at desc
    limit 1
  ) x;
$$;

revoke all on function public.get_current_driver_assigned_order() from public;
grant execute on function public.get_current_driver_assigned_order() to authenticated;

notify pgrst, 'reload schema';

select to_regprocedure('public.get_current_driver_assigned_order()') as get_current_driver_assigned_order_rpc;
