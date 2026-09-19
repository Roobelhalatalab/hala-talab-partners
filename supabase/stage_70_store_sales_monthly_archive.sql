-- Hala Talab Store - Stage 70
-- Daily / weekly / monthly completed-order sales + permanent monthly archive.
-- Safe and re-runnable. Uses existing delivered orders as the source of truth.

create or replace function public.get_store_sales_overview()
returns jsonb
language sql
security definer
set search_path = public
as $$
with my_store as (
  select id from public.stores where owner_id = auth.uid() limit 1
), delivered as (
  select
    o.id,
    coalesce(o.delivered_at, o.created_at) as completed_at,
    greatest(coalesce(o.subtotal, 0) - coalesce(o.discount_amount, 0), 0)::numeric as revenue
  from public.orders o
  join my_store s on s.id = o.store_id
  where o.status = 'delivered'
), local_rows as (
  select
    id,
    timezone('Asia/Baghdad', completed_at) as local_completed_at,
    revenue
  from delivered
), totals as (
  select
    count(*) filter (where local_completed_at::date = timezone('Asia/Baghdad', now())::date)::int as today_orders,
    coalesce(sum(revenue) filter (where local_completed_at::date = timezone('Asia/Baghdad', now())::date), 0)::numeric as today_revenue,
    count(*) filter (where local_completed_at >= date_trunc('week', timezone('Asia/Baghdad', now())))::int as week_orders,
    coalesce(sum(revenue) filter (where local_completed_at >= date_trunc('week', timezone('Asia/Baghdad', now()))), 0)::numeric as week_revenue,
    count(*) filter (where local_completed_at >= date_trunc('month', timezone('Asia/Baghdad', now())))::int as month_orders,
    coalesce(sum(revenue) filter (where local_completed_at >= date_trunc('month', timezone('Asia/Baghdad', now()))), 0)::numeric as month_revenue,
    count(*)::int as total_delivered_orders,
    coalesce(sum(revenue), 0)::numeric as total_revenue
  from local_rows
), archive as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'month_start', to_char(month_start, 'YYYY-MM-01'),
      'orders_count', orders_count,
      'revenue', revenue
    ) order by month_start desc
  ), '[]'::jsonb) as rows
  from (
    select
      date_trunc('month', local_completed_at)::date as month_start,
      count(*)::int as orders_count,
      coalesce(sum(revenue), 0)::numeric as revenue
    from local_rows
    group by 1
    order by 1 desc
  ) q
)
select jsonb_build_object(
  'today_orders', t.today_orders,
  'today_revenue', t.today_revenue,
  'week_orders', t.week_orders,
  'week_revenue', t.week_revenue,
  'month_orders', t.month_orders,
  'month_revenue', t.month_revenue,
  'total_delivered_orders', t.total_delivered_orders,
  'total_revenue', t.total_revenue,
  'monthly_archive', a.rows
)
from totals t cross join archive a;
$$;

revoke all on function public.get_store_sales_overview() from public;
grant execute on function public.get_store_sales_overview() to authenticated;

notify pgrst, 'reload schema';
select to_regprocedure('public.get_store_sales_overview()') as stage_70_sales_rpc;
