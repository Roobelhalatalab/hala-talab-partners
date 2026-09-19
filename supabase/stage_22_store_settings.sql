-- Hala Talab Partners - Stage 22
-- Safely extends the existing stores table. No existing data is deleted.

alter table public.stores add column if not exists email text;
alter table public.stores add column if not exists logo_url text;
alter table public.stores add column if not exists cover_url text;
alter table public.stores add column if not exists delivery_fee numeric(12,2) not null default 0;
alter table public.stores add column if not exists minimum_order numeric(12,2) not null default 0;
alter table public.stores add column if not exists preparation_minutes integer not null default 30;
alter table public.stores add column if not exists opening_time text not null default '09:00';
alter table public.stores add column if not exists closing_time text not null default '23:00';
alter table public.stores add column if not exists updated_at timestamptz not null default now();

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists stores_set_updated_at on public.stores;
create trigger stores_set_updated_at
before update on public.stores
for each row execute function public.set_updated_at();

notify pgrst, 'reload schema';

select
  to_regclass('public.stores') as stores,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='delivery_fee') as delivery_settings_ready,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='opening_time') as working_hours_ready;
