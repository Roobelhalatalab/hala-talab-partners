-- Hala Talab Partners - Stage 20: offers and coupons
create extension if not exists pgcrypto;

create table if not exists public.store_promotions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  title text not null,
  description text,
  discount_type text not null default 'percentage' check (discount_type in ('percentage','fixed')),
  discount_value numeric(12,2) not null check (discount_value > 0),
  minimum_order numeric(12,2) not null default 0 check (minimum_order >= 0),
  start_at timestamptz not null default now(),
  end_at timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_at > start_at),
  check (discount_type <> 'percentage' or discount_value <= 100)
);

create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  code text not null,
  title text not null,
  discount_type text not null default 'percentage' check (discount_type in ('percentage','fixed')),
  discount_value numeric(12,2) not null check (discount_value > 0),
  minimum_order numeric(12,2) not null default 0 check (minimum_order >= 0),
  max_discount numeric(12,2),
  usage_limit integer,
  used_count integer not null default 0,
  start_at timestamptz not null default now(),
  end_at timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, code),
  check (end_at > start_at),
  check (usage_limit is null or usage_limit > 0),
  check (used_count >= 0),
  check (discount_type <> 'percentage' or discount_value <= 100)
);

create index if not exists store_promotions_store_id_idx on public.store_promotions(store_id);
create index if not exists coupons_store_id_idx on public.coupons(store_id);
create index if not exists coupons_code_idx on public.coupons(code);

alter table public.store_promotions enable row level security;
alter table public.coupons enable row level security;

drop policy if exists "owners manage own promotions" on public.store_promotions;
create policy "owners manage own promotions" on public.store_promotions
for all to authenticated
using (exists (select 1 from public.stores s where s.id = store_promotions.store_id and s.owner_id = auth.uid()))
with check (exists (select 1 from public.stores s where s.id = store_promotions.store_id and s.owner_id = auth.uid()));

drop policy if exists "owners manage own coupons" on public.coupons;
create policy "owners manage own coupons" on public.coupons
for all to authenticated
using (exists (select 1 from public.stores s where s.id = coupons.store_id and s.owner_id = auth.uid()))
with check (exists (select 1 from public.stores s where s.id = coupons.store_id and s.owner_id = auth.uid()));

-- Client apps may read active offers/coupons; validation remains enforced by checkout logic.
drop policy if exists "public reads active promotions" on public.store_promotions;
create policy "public reads active promotions" on public.store_promotions
for select to anon, authenticated
using (is_active and now() between start_at and end_at);

drop policy if exists "public reads active coupons" on public.coupons;
create policy "public reads active coupons" on public.coupons
for select to anon, authenticated
using (is_active and now() between start_at and end_at and (usage_limit is null or used_count < usage_limit));

notify pgrst, 'reload schema';
select to_regclass('public.store_promotions') as store_promotions, to_regclass('public.coupons') as coupons;
