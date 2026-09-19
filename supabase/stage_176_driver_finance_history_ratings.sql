-- Hala Talab Partners - Stage 176 Driver Functional Review
-- Safe to run more than once. No destructive changes.

create or replace function public.get_driver_dues_summary()
returns jsonb
language sql
security definer
set search_path = public
as $$
with p as (
  select pay_type, base_amount from public.driver_compensation_profiles
  where driver_id = auth.uid() and active limit 1
),
d as (
  select coalesce(sum(amount) filter(where kind <> 'bonus'),0)::numeric base_due,
         coalesce(sum(amount) filter(where kind = 'bonus'),0)::numeric bonus_due
  from public.driver_dues where driver_id = auth.uid()
),
x as (
  select coalesce(sum(amount),0)::numeric paid_amount
  from public.driver_payments where driver_id = auth.uid()
),
w as (
  select count(*) filter(where status='delivered')::int delivered_orders,
         count(distinct coalesce(delivered_at,updated_at,created_at)::date) filter(where status='delivered')::int work_days,
         count(*) filter(where status='delivered' and coalesce(delivered_at,updated_at,created_at)>=date_trunc('day',now()))::int today_orders
  from public.orders where driver_id=auth.uid()
),
payments_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'amount',amount,'period_label',period_label,'note',note,'paid_at',paid_at,'status','paid'
  ) order by paid_at desc, id desc),'[]'::jsonb) rows
  from (select * from public.driver_payments where driver_id=auth.uid() order by paid_at desc,id desc limit 100) q
),
dues_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'amount',amount,'kind',kind,'period_label',period_label,'due_date',due_date,'note',note,'created_at',created_at
  ) order by created_at desc,id desc),'[]'::jsonb) rows
  from (select * from public.driver_dues where driver_id=auth.uid() order by created_at desc,id desc limit 100) q
)
select jsonb_build_object(
  'pay_type',coalesce((select pay_type from p),'custom'),
  'pay_type_label',case coalesce((select pay_type from p),'custom') when 'daily' then 'يومي' when 'weekly' then 'أسبوعي' when 'monthly' then 'شهري' when 'fixed' then 'ثابت' else 'حسب اتفاق الإدارة' end,
  'base_due',d.base_due,'bonus_due',d.bonus_due,'paid_amount',x.paid_amount,
  'outstanding_due',greatest(d.base_due+d.bonus_due-x.paid_amount,0),
  'delivered_orders',w.delivered_orders,'work_days',w.work_days,'today_orders',w.today_orders,
  'payments',payments_json.rows,'dues',dues_json.rows
) from d,x,w,payments_json,dues_json;
$$;
revoke all on function public.get_driver_dues_summary() from public;
grant execute on function public.get_driver_dues_summary() to authenticated;

create or replace function public.get_driver_delivery_history()
returns jsonb language sql security definer set search_path=public as $$
with history as (
  select o.id order_id,o.order_number,o.status,o.store_id,s.name store_name,s.address_text store_address,
         o.customer_name,o.delivery_address,o.payment_method,coalesce(o.delivery_fee,0)::numeric earning,
         coalesce(o.total,0)::numeric order_total,o.notes,o.created_at,o.updated_at,o.picked_up_at,o.delivered_at,
         coalesce(o.delivered_at,o.updated_at,o.created_at) happened_at,
         null::text cancellation_reason
  from public.orders o join public.stores s on s.id=o.store_id
  where auth.uid() is not null and o.driver_id=auth.uid()
), summary as (
  select count(*)::int total_orders,count(*) filter(where status='delivered')::int completed_orders,
         count(*) filter(where status in('cancelled','canceled','rejected'))::int cancelled_orders,
         count(*) filter(where status not in('delivered','cancelled','canceled','rejected'))::int incomplete_orders,
         coalesce(sum(earning) filter(where status='delivered'),0)::numeric total_earnings from history
), rejects as (
  select count(*)::int rejected_offers from public.driver_order_rejections where driver_id=auth.uid()
), rows_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'order_id',order_id,'order_number',order_number,'status',status,'store_id',store_id,'store_name',store_name,
    'store_address',store_address,'customer_name',customer_name,'delivery_address',delivery_address,
    'payment_method',payment_method,'earning',earning,'order_total',order_total,'notes',notes,
    'cancellation_reason',cancellation_reason,'created_at',created_at,'picked_up_at',picked_up_at,
    'delivered_at',delivered_at,'happened_at',happened_at
  ) order by happened_at desc,order_id desc),'[]'::jsonb) rows from history
)
select jsonb_build_object('total_orders',summary.total_orders,'completed_orders',summary.completed_orders,
  'cancelled_orders',summary.cancelled_orders,'incomplete_orders',summary.incomplete_orders,
  'total_earnings',summary.total_earnings,'rejected_offers',rejects.rejected_offers,
  'acceptance_rate',case when summary.total_orders+rejects.rejected_offers=0 then 0 else round((summary.total_orders::numeric*100)/(summary.total_orders+rejects.rejected_offers),1) end,
  'orders',rows_json.rows) from summary,rejects,rows_json;
$$;
revoke all on function public.get_driver_delivery_history() from public;
grant execute on function public.get_driver_delivery_history() to authenticated;
notify pgrst,'reload schema';
