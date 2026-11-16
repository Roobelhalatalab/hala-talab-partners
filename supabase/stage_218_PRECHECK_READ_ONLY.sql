-- Hala Talab Stage 1 PRECHECK (READ ONLY)
-- This file changes NOTHING. Run it first and review the results before the migration.

select 'phone_account_registry' as item,
       count(*) as rows,
       count(distinct phone_e164) as distinct_phones,
       count(distinct auth_user_id) as distinct_auth_users
from public.phone_account_registry;

select 'phone_pin_credentials' as item,
       count(*) as rows,
       count(distinct phone_e164) as distinct_phones,
       count(distinct auth_user_id) as distinct_auth_users
from public.phone_pin_credentials;

select
  date_trunc('month', created_at at time zone 'Asia/Baghdad')::date as baghdad_month,
  count(*) as orders,
  count(distinct store_id) as stores,
  min(order_number) as min_visible_number,
  max(order_number) as max_visible_number
from public.orders
group by 1
order by 1 desc
limit 12;

select
  to_regclass('public.store_order_counters') as old_counter_table,
  to_regclass('public.store_order_monthly_counters') as new_monthly_counter_table;
