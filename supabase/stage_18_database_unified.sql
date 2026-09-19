-- Hala Talab Partners - Stage 18
-- Unified, idempotent database setup for profiles, stores and products.
-- Run this whole file once in Supabase SQL Editor.

create extension if not exists pgcrypto;

-- Shared updated_at trigger function
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Partner profiles
create table if not exists public.partner_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  email text,
  role text not null default 'business'
    check (role in ('business', 'driver')),
  business_type text,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'rejected', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.partner_profiles enable row level security;

drop policy if exists "Users can view own profile" on public.partner_profiles;
create policy "Users can view own profile"
on public.partner_profiles for select
to authenticated
using (auth.uid() = id);

drop policy if exists "Users can insert own profile" on public.partner_profiles;
create policy "Users can insert own profile"
on public.partner_profiles for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.partner_profiles;
create policy "Users can update own profile"
on public.partner_profiles for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop trigger if exists partner_profiles_set_updated_at on public.partner_profiles;
create trigger partner_profiles_set_updated_at
before update on public.partner_profiles
for each row execute function public.set_updated_at();

-- Automatically create/update a profile when an Auth user is created
create or replace function public.handle_new_partner_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.partner_profiles (
    id, full_name, phone, email, role, business_type
  ) values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    coalesce(new.raw_user_meta_data ->> 'phone', new.phone),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'role', 'business'),
    new.raw_user_meta_data ->> 'business_type'
  )
  on conflict (id) do update set
    full_name = coalesce(excluded.full_name, public.partner_profiles.full_name),
    phone = coalesce(excluded.phone, public.partner_profiles.phone),
    email = coalesce(excluded.email, public.partner_profiles.email),
    role = coalesce(excluded.role, public.partner_profiles.role),
    business_type = coalesce(excluded.business_type, public.partner_profiles.business_type),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_partner_profile on auth.users;
create trigger on_auth_user_created_partner_profile
after insert or update of raw_user_meta_data, email, phone on auth.users
for each row execute function public.handle_new_partner_user();

-- Backfill users created before this SQL was run
insert into public.partner_profiles (
  id, full_name, phone, email, role, business_type, status
)
select
  u.id,
  u.raw_user_meta_data ->> 'full_name',
  coalesce(u.raw_user_meta_data ->> 'phone', u.phone),
  u.email,
  coalesce(u.raw_user_meta_data ->> 'role', 'business'),
  u.raw_user_meta_data ->> 'business_type',
  'pending'
from auth.users u
on conflict (id) do update set
  full_name = coalesce(excluded.full_name, public.partner_profiles.full_name),
  phone = coalesce(excluded.phone, public.partner_profiles.phone),
  email = coalesce(excluded.email, public.partner_profiles.email),
  role = coalesce(excluded.role, public.partner_profiles.role),
  business_type = coalesce(excluded.business_type, public.partner_profiles.business_type),
  updated_at = now();

-- Stores
create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null,
  description text,
  phone text not null,
  address_text text not null,
  business_type text not null default 'restaurant',
  logo_url text,
  cover_url text,
  delivery_available boolean not null default true,
  approval_status text not null default 'pending'
    check (approval_status in ('pending', 'approved', 'rejected', 'suspended')),
  is_active boolean not null default false,
  is_open boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists stores_owner_id_idx on public.stores(owner_id);

alter table public.stores enable row level security;

drop policy if exists "Store owners can view own store" on public.stores;
create policy "Store owners can view own store"
on public.stores for select
to authenticated
using (auth.uid() = owner_id);

drop policy if exists "Store owners can create own store" on public.stores;
create policy "Store owners can create own store"
on public.stores for insert
to authenticated
with check (auth.uid() = owner_id);

drop policy if exists "Store owners can update own store" on public.stores;
create policy "Store owners can update own store"
on public.stores for update
to authenticated
using (auth.uid() = owner_id)
with check (auth.uid() = owner_id);

drop trigger if exists stores_set_updated_at on public.stores;
create trigger stores_set_updated_at
before update on public.stores
for each row execute function public.set_updated_at();

-- Products
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  description text,
  category_name text,
  price numeric(12,2) not null default 0 check (price >= 0),
  image_url text,
  is_available boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists products_store_id_idx on public.products(store_id);
create index if not exists products_store_available_idx on public.products(store_id, is_available);

alter table public.products enable row level security;

drop policy if exists "Store owners can view own products" on public.products;
create policy "Store owners can view own products"
on public.products for select
to authenticated
using (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
);

drop policy if exists "Store owners can create own products" on public.products;
create policy "Store owners can create own products"
on public.products for insert
to authenticated
with check (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
);

drop policy if exists "Store owners can update own products" on public.products;
create policy "Store owners can update own products"
on public.products for update
to authenticated
using (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
);

drop policy if exists "Store owners can delete own products" on public.products;
create policy "Store owners can delete own products"
on public.products for delete
to authenticated
using (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
);

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();

-- Ask PostgREST to refresh its schema cache immediately.
notify pgrst, 'reload schema';
