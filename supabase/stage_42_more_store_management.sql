-- Hala Talab Partners - Stage 42
-- More > Manage your store: categories, add-ons and reviews.

create extension if not exists pgcrypto;

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.product_addons (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  price numeric(12,2) not null default 0 check (price >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.store_reviews (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  customer_id uuid references auth.users(id) on delete set null,
  customer_name text,
  rating numeric(2,1) not null check (rating >= 1 and rating <= 5),
  comment text,
  created_at timestamptz not null default now()
);

create index if not exists product_categories_store_id_idx on public.product_categories(store_id);
create index if not exists product_addons_store_id_idx on public.product_addons(store_id);
create index if not exists store_reviews_store_id_idx on public.store_reviews(store_id);

alter table public.product_categories enable row level security;
alter table public.product_addons enable row level security;
alter table public.store_reviews enable row level security;

-- Store owners manage their categories.
drop policy if exists "store owners manage product categories" on public.product_categories;
create policy "store owners manage product categories"
on public.product_categories for all to authenticated
using (exists (select 1 from public.stores s where s.id = store_id and s.owner_id = auth.uid()))
with check (exists (select 1 from public.stores s where s.id = store_id and s.owner_id = auth.uid()));

-- Store owners manage their add-ons.
drop policy if exists "store owners manage product addons" on public.product_addons;
create policy "store owners manage product addons"
on public.product_addons for all to authenticated
using (exists (select 1 from public.stores s where s.id = store_id and s.owner_id = auth.uid()))
with check (exists (select 1 from public.stores s where s.id = store_id and s.owner_id = auth.uid()));

-- Store owners can read reviews for their own store.
drop policy if exists "store owners read store reviews" on public.store_reviews;
create policy "store owners read store reviews"
on public.store_reviews for select to authenticated
using (exists (select 1 from public.stores s where s.id = store_id and s.owner_id = auth.uid()));

-- Authenticated customers can create a review tied to themselves.
drop policy if exists "customers create store reviews" on public.store_reviews;
create policy "customers create store reviews"
on public.store_reviews for insert to authenticated
with check (customer_id = auth.uid());

notify pgrst, 'reload schema';

select
  to_regclass('public.product_categories') as product_categories,
  to_regclass('public.product_addons') as product_addons,
  to_regclass('public.store_reviews') as store_reviews;
