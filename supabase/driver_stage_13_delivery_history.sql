-- Hala Talab Partners - Driver Stage 13
-- Delivery history for the authenticated driver from real orders only.
-- Safe to run more than once. No existing data is deleted.

create or replace function public.get_driver_delivery_history()
returns jsonb
language sql
security definer
set search_path = public
as $$
  with history as (
    select
      o.id as order_id,
      o.order_number,
      o.status,
      o.store_id,
      s.name as store_name,
      s.address_text as store_address,
      o.customer_name,
      o.delivery_address,
      o.payment_method,
      coalesce(o.delivery_fee, 0)::numeric as earning,
      coalesce(o.total, 0)::numeric as order_total,
      o.created_at,
      o.updated_at,
      o.picked_up_at,
      o.delivered_at,
      coalesce(o.delivered_at, o.updated_at, o.created_at) as happened_at
    from public.orders o
    join public.stores s on s.id = o.store_id
    where auth.uid() is not null
      and o.driver_id = auth.uid()
  ),
  summary as (
    select
      count(*)::int as total_orders,
      count(*) filter (where status = 'delivered')::int as completed_orders,
      count(*) filter (where status in ('cancelled', 'canceled'))::int as cancelled_orders,
      count(*) filter (where status not in ('delivered', 'cancelled', 'canceled'))::int as incomplete_orders,
      coalesce(sum(earning) filter (where status = 'delivered'), 0)::numeric as total_earnings
    from history
  ),
  rejects as (
    select count(*)::int as rejected_offers
    from public.driver_order_rejections r
    where r.driver_id = auth.uid()
  ),
  rows_json as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'order_id', order_id,
        'order_number', order_number,
        'status', status,
        'store_id', store_id,
        'store_name', store_name,
        'store_address', store_address,
        'customer_name', customer_name,
        'delivery_address', delivery_address,
        'payment_method', payment_method,
        'earning', earning,
        'order_total', order_total,
        'created_at', created_at,
        'picked_up_at', picked_up_at,
        'delivered_at', delivered_at,
        'happened_at', happened_at
      ) order by happened_at desc
    ), '[]'::jsonb) as rows
    from history
  )
  select jsonb_build_object(
    'total_orders', summary.total_orders,
    'completed_orders', summary.completed_orders,
    'cancelled_orders', summary.cancelled_orders,
    'incomplete_orders', summary.incomplete_orders,
    'total_earnings', summary.total_earnings,
    'rejected_offers', rejects.rejected_offers,
    'acceptance_rate', case
      when summary.total_orders + rejects.rejected_offers = 0 then 0
      else round((summary.total_orders::numeric * 100) / (summary.total_orders + rejects.rejected_offers), 1)
    end,
    'orders', rows_json.rows
  )
  from summary, rejects, rows_json;
$$;

revoke all on function public.get_driver_delivery_history() from public;
grant execute on function public.get_driver_delivery_history() to authenticated;

notify pgrst, 'reload schema';

select to_regprocedure('public.get_driver_delivery_history()') as delivery_history_rpc;
