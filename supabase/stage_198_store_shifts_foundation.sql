-- Hala Talab Partners - Stage 198 / Shift S1
-- Store shifts foundation only. Backward compatible with existing single-shift stores.
-- IMPORTANT: Database stores TIME values canonically; the Partner UI will display 12-hour Arabic time (صباحًا/مساءً) in Stage S2.

create extension if not exists pgcrypto;

-- 1) Keep every existing store on the legacy/single-shift behavior by default.
alter table public.stores
  add column if not exists shift_mode smallint not null default 1;

alter table public.stores
  add column if not exists store_timezone text not null default 'Asia/Baghdad';

alter table public.stores drop constraint if exists stores_shift_mode_valid;
alter table public.stores
  add constraint stores_shift_mode_valid check (shift_mode in (1, 2));

comment on column public.stores.shift_mode is
  '1 = legacy/single working-hours mode; 2 = morning/evening shift mode.';
comment on column public.stores.store_timezone is
  'IANA timezone used to determine which shift is currently open.';

-- 2) Shift definitions. No rows are required for stores that use shift_mode=1.
create table if not exists public.store_shifts (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  shift_code text not null,
  display_name text not null,
  start_time time without time zone not null,
  end_time time without time zone not null,
  is_active boolean not null default true,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint store_shifts_code_valid check (shift_code in ('morning', 'evening')),
  constraint store_shifts_store_code_unique unique (store_id, shift_code)
);

create index if not exists store_shifts_store_id_idx
  on public.store_shifts(store_id, sort_order, start_time);

-- 3) Optional many-to-many assignment.
--    No assignment rows = item remains available for all shifts (backward compatibility).
create table if not exists public.store_category_shifts (
  category_id uuid not null references public.product_categories(id) on delete cascade,
  shift_id uuid not null references public.store_shifts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (category_id, shift_id)
);

create table if not exists public.store_product_shifts (
  product_id uuid not null references public.products(id) on delete cascade,
  shift_id uuid not null references public.store_shifts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (product_id, shift_id)
);

create index if not exists store_category_shifts_shift_idx
  on public.store_category_shifts(shift_id);
create index if not exists store_product_shifts_shift_idx
  on public.store_product_shifts(shift_id);

-- 4) Guard against linking a category/product to a shift belonging to another store.
create or replace function public.hala_validate_category_shift_store()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_category_store uuid;
  v_shift_store uuid;
begin
  select store_id into v_category_store
  from public.product_categories
  where id = new.category_id;

  select store_id into v_shift_store
  from public.store_shifts
  where id = new.shift_id;

  if v_category_store is null or v_shift_store is null or v_category_store <> v_shift_store then
    raise exception 'Category and shift must belong to the same store';
  end if;

  return new;
end;
$$;

create or replace function public.hala_validate_product_shift_store()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_product_store uuid;
  v_shift_store uuid;
begin
  select store_id into v_product_store
  from public.products
  where id = new.product_id;

  select store_id into v_shift_store
  from public.store_shifts
  where id = new.shift_id;

  if v_product_store is null or v_shift_store is null or v_product_store <> v_shift_store then
    raise exception 'Product and shift must belong to the same store';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_category_shift_store on public.store_category_shifts;
create trigger trg_validate_category_shift_store
before insert or update on public.store_category_shifts
for each row execute function public.hala_validate_category_shift_store();

drop trigger if exists trg_validate_product_shift_store on public.store_product_shifts;
create trigger trg_validate_product_shift_store
before insert or update on public.store_product_shifts
for each row execute function public.hala_validate_product_shift_store();

-- 5) Updated-at trigger (reuses the project's standard helper if present).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists store_shifts_set_updated_at on public.store_shifts;
create trigger store_shifts_set_updated_at
before update on public.store_shifts
for each row execute function public.set_updated_at();

-- 6) Helper: determines whether a shift is open at a given instant.
-- Handles normal ranges (08:00-15:00) and overnight ranges (18:00-02:00).
create or replace function public.hala_shift_is_open(
  p_shift_id uuid,
  p_at timestamptz default now()
)
returns boolean
language sql
stable
set search_path = public
as $$
  select case
    when sh.id is null or not sh.is_active then false
    when sh.start_time = sh.end_time then true
    when sh.start_time < sh.end_time then
      (p_at at time zone coalesce(nullif(s.store_timezone, ''), 'Asia/Baghdad'))::time >= sh.start_time
      and
      (p_at at time zone coalesce(nullif(s.store_timezone, ''), 'Asia/Baghdad'))::time < sh.end_time
    else
      (p_at at time zone coalesce(nullif(s.store_timezone, ''), 'Asia/Baghdad'))::time >= sh.start_time
      or
      (p_at at time zone coalesce(nullif(s.store_timezone, ''), 'Asia/Baghdad'))::time < sh.end_time
  end
  from public.store_shifts sh
  join public.stores s on s.id = sh.store_id
  where sh.id = p_shift_id
  limit 1;
$$;

-- 7) RLS: owner manages only his own shift configuration.
alter table public.store_shifts enable row level security;
alter table public.store_category_shifts enable row level security;
alter table public.store_product_shifts enable row level security;

drop policy if exists "store owners manage own shifts" on public.store_shifts;
create policy "store owners manage own shifts"
on public.store_shifts for all to authenticated
using (
  exists (
    select 1 from public.stores s
    where s.id = store_shifts.store_id and s.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.stores s
    where s.id = store_shifts.store_id and s.owner_id = auth.uid()
  )
);

drop policy if exists "store owners manage own category shifts" on public.store_category_shifts;
create policy "store owners manage own category shifts"
on public.store_category_shifts for all to authenticated
using (
  exists (
    select 1
    from public.product_categories c
    join public.stores s on s.id = c.store_id
    where c.id = store_category_shifts.category_id and s.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.product_categories c
    join public.stores s on s.id = c.store_id
    where c.id = store_category_shifts.category_id and s.owner_id = auth.uid()
  )
);

drop policy if exists "store owners manage own product shifts" on public.store_product_shifts;
create policy "store owners manage own product shifts"
on public.store_product_shifts for all to authenticated
using (
  exists (
    select 1
    from public.products p
    join public.stores s on s.id = p.store_id
    where p.id = store_product_shifts.product_id and s.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.products p
    join public.stores s on s.id = p.store_id
    where p.id = store_product_shifts.product_id and s.owner_id = auth.uid()
  )
);

-- Read access for customer/public-menu integration will be finalized in the client/menu stages.
-- Keeping Stage S1 owner-only avoids widening current public permissions prematurely.

notify pgrst, 'reload schema';

-- Verification output: existing stores should show shift_mode=1 after this migration.
select
  to_regclass('public.store_shifts') as store_shifts,
  to_regclass('public.store_category_shifts') as store_category_shifts,
  to_regclass('public.store_product_shifts') as store_product_shifts,
  exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='stores' and column_name='shift_mode'
  ) as shift_mode_ready;
