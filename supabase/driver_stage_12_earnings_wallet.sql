-- Hala Talab Partners - Driver Stage 12
-- Driver earnings & wallet summary from real delivered orders.
-- No demo data. Safe to run more than once.

create or replace function public.get_driver_earnings_wallet()
returns jsonb
language sql
security definer
set search_path = public
as $$
  with delivered as (
    select
      o.id,
      o.order_number,
      coalesce(o.delivery_fee, 0)::numeric as earning,
      coalesce(o.delivered_at, o.updated_at, o.created_at) as happened_at
    from public.orders o
    where auth.uid() is not null
      and o.driver_id = auth.uid()
      and o.status = 'delivered'
  ),
  totals as (
    select
      coalesce(sum(earning), 0)::numeric as total_earnings,
      coalesce(sum(earning) filter (where happened_at >= date_trunc('month', now())), 0)::numeric as month_earnings,
      coalesce(sum(earning) filter (where happened_at >= date_trunc('week', now())), 0)::numeric as week_earnings,
      coalesce(sum(earning) filter (where happened_at >= date_trunc('day', now())), 0)::numeric as today_earnings,
      count(*) filter (where happened_at >= date_trunc('day', now()))::int as today_orders,
      count(*)::int as delivered_orders
    from delivered
  ),
  daily as (
    select jsonb_agg(
      jsonb_build_object(
        'date', d::date,
        'amount', coalesce((select sum(x.earning) from delivered x where x.happened_at >= d and x.happened_at < d + interval '1 day'), 0)
      ) order by d
    ) as points
    from generate_series(date_trunc('day', now()) - interval '6 days', date_trunc('day', now()), interval '1 day') d
  ),
  tx as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'order_id', id,
        'order_number', order_number,
        'amount', earning,
        'created_at', happened_at,
        'kind', 'delivery'
      ) order by happened_at desc
    ), '[]'::jsonb) as rows
    from (
      select * from delivered order by happened_at desc limit 30
    ) q
  )
  select jsonb_build_object(
    'wallet_balance', totals.total_earnings,
    'total_earnings', totals.total_earnings,
    'month_earnings', totals.month_earnings,
    'week_earnings', totals.week_earnings,
    'today_earnings', totals.today_earnings,
    'today_orders', totals.today_orders,
    'delivered_orders', totals.delivered_orders,
    'daily_earnings', coalesce(daily.points, '[]'::jsonb),
    'transactions', tx.rows
  )
  from totals, daily, tx;
$$;

revoke all on function public.get_driver_earnings_wallet() from public;
grant execute on function public.get_driver_earnings_wallet() to authenticated;

notify pgrst, 'reload schema';

select to_regprocedure('public.get_driver_earnings_wallet()') as earnings_rpc;
