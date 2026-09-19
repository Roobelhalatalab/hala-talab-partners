-- Hala Talab Partners - Driver Stage 14 FIX 2
-- Compatibility repair for existing driver_reviews schemas. Safe to run more than once.

alter table if exists public.driver_reviews
  add column if not exists customer_name text;

notify pgrst, 'reload schema';

select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'driver_reviews'
order by ordinal_position;
