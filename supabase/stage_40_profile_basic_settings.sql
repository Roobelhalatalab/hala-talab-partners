-- Hala Talab Partners - Stage 40
-- Profile + basic restaurant settings. Safe additive migration; no existing data is deleted.

alter table public.stores add column if not exists commercial_registration text;
alter table public.stores add column if not exists identity_document text;
alter table public.stores add column if not exists delivery_zones jsonb not null default '[]'::jsonb;
alter table public.stores add column if not exists payment_methods jsonb not null default '["cash"]'::jsonb;
alter table public.stores add column if not exists order_notification_settings jsonb not null default '{"new_orders":true,"cancellations":true,"status_changes":true,"sound":true}'::jsonb;

-- Keep old rows usable if any nullable values were introduced manually.
update public.stores set delivery_zones = '[]'::jsonb where delivery_zones is null;
update public.stores set payment_methods = '["cash"]'::jsonb where payment_methods is null;
update public.stores
set order_notification_settings = '{"new_orders":true,"cancellations":true,"status_changes":true,"sound":true}'::jsonb
where order_notification_settings is null;

notify pgrst, 'reload schema';

select
  to_regclass('public.stores') as stores,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='commercial_registration') as profile_documents_ready,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='delivery_zones') as delivery_zones_ready,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='payment_methods') as payment_methods_ready,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='order_notification_settings') as order_notifications_ready;
