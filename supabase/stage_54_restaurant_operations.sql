-- Hala Talab Partners - Stage 54
-- Restaurant location, delivery/pickup and weekly working hours.
-- Safe additive migration. Existing data is preserved.

alter table public.stores add column if not exists latitude double precision;
alter table public.stores add column if not exists longitude double precision;
alter table public.stores add column if not exists location_note text;
alter table public.stores add column if not exists pickup_available boolean not null default true;
alter table public.stores add column if not exists working_hours jsonb not null default '{
  "saturday":{"enabled":true,"open":"09:00","close":"23:00"},
  "sunday":{"enabled":true,"open":"09:00","close":"23:00"},
  "monday":{"enabled":true,"open":"09:00","close":"23:00"},
  "tuesday":{"enabled":true,"open":"09:00","close":"23:00"},
  "wednesday":{"enabled":true,"open":"09:00","close":"23:00"},
  "thursday":{"enabled":true,"open":"09:00","close":"23:00"},
  "friday":{"enabled":true,"open":"09:00","close":"23:00"}
}'::jsonb;

update public.stores
set working_hours = jsonb_build_object(
  'saturday', jsonb_build_object('enabled', true, 'open', coalesce(opening_time, '09:00'), 'close', coalesce(closing_time, '23:00')),
  'sunday', jsonb_build_object('enabled', true, 'open', coalesce(opening_time, '09:00'), 'close', coalesce(closing_time, '23:00')),
  'monday', jsonb_build_object('enabled', true, 'open', coalesce(opening_time, '09:00'), 'close', coalesce(closing_time, '23:00')),
  'tuesday', jsonb_build_object('enabled', true, 'open', coalesce(opening_time, '09:00'), 'close', coalesce(closing_time, '23:00')),
  'wednesday', jsonb_build_object('enabled', true, 'open', coalesce(opening_time, '09:00'), 'close', coalesce(closing_time, '23:00')),
  'thursday', jsonb_build_object('enabled', true, 'open', coalesce(opening_time, '09:00'), 'close', coalesce(closing_time, '23:00')),
  'friday', jsonb_build_object('enabled', true, 'open', coalesce(opening_time, '09:00'), 'close', coalesce(closing_time, '23:00'))
)
where working_hours is null or working_hours = '{}'::jsonb;

notify pgrst, 'reload schema';

select
  to_regclass('public.stores') as stores,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='latitude') as location_ready,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='pickup_available') as pickup_ready,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='working_hours') as weekly_hours_ready;
