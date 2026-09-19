-- Hala Talab Partners - Stage 18 Safe Database Repair
-- This migration preserves existing users and rows. It does NOT drop tables.
-- Paste the whole file into Supabase SQL Editor and press Run once.

create extension if not exists pgcrypto;

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

-- 1) Keep the existing partner_profiles table and add anything missing.
create table if not exists public.partner_profiles (
  id uuid primary key references auth.users(id) on delete cascade
);

alter table public.partner_profiles add column if not exists full_name text;
alter table public.partner_profiles add column if not exists phone text;
alter table public.partner_profiles add column if not exists email text;
alter table public.partner_profiles add column if not exists role text;
alter table public.partner_profiles add column if not exists business_type text;
alter table public.partner_profiles add column if not exists status text;
alter table public.partner_profiles add column if not exists created_at timestamptz;
alter table public.partner_profiles add column if not exists updated_at timestamptz;

-- Migrate the older partner_type column into role when it exists.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'partner_profiles'
      and column_name = 'partner_type'
  ) then
    execute $sql$
      update public.partner_profiles
      set role = coalesce(nullif(role, ''), nullif(partner_type, ''), 'business')
      where role is null or role = ''
    $sql$;
  else
    update public.partner_profiles
    set role = 'business'
    where role is null or role = '';
  end if;
end
$$;

update public.partner_profiles
set status = 'pending'
where status is null or status = '';

update public.partner_profiles
set created_at = now()
where created_at is null;

update public.partner_profiles
set updated_at = now()
where updated_at is null;

alter table public.partner_profiles alter column role set default 'business';
alter table public.partner_profiles alter column status set default 'pending';
alter table public.partner_profiles alter column created_at set default now();
alter table public.partner_profiles alter column updated_at set default now();

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

create or replace function public.handle_new_partner_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.partner_profiles (
    id, full_name, phone, email, role, business_type, status
  ) values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    coalesce(new.raw_user_meta_data ->> 'phone', new.phone),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'role', new.raw_user_meta_data ->> 'partner_type', 'business'),
    new.raw_user_meta_data ->> 'business_type',
    'pending'
  )
  on conflict (id) do update set
    full_name = coalesce(excluded.full_name, public.partner_profiles.full_name),
    phone = coalesce(excluded.phone, public.partner_profiles.phone),
    email = coalesce(excluded.email, public.partner_profiles.email),
    role = coalesce(excluded.role, public.partner_profiles.role, 'business'),
    business_type = coalesce(excluded.business_type, public.partner_profiles.business_type),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_partner_profile on auth.users;
create trigger on_auth_user_created_partner_profile
after insert or update of raw_user_meta_data, email, phone on auth.users
for each row execute function public.handle_new_partner_user();

insert into public.partner_profiles (
  id, full_name, phone, email, role, business_type, status
)
select
  u.id,
  u.raw_user_meta_data ->> 'full_name',
  coalesce(u.raw_user_meta_data ->> 'phone', u.phone),
  u.email,
  coalesce(u.raw_user_meta_data ->> 'role', u.raw_user_meta_data ->> 'partner_type', 'business'),
  u.raw_user_meta_data ->> 'business_type',
  'pending'
from auth.users u
on conflict (id) do update set
  full_name = coalesce(excluded.full_name, public.partner_profiles.full_name),
  phone = coalesce(excluded.phone, public.partner_profiles.phone),
  email = coalesce(excluded.email, public.partner_profiles.email),
  role = coalesce(excluded.role, public.partner_profiles.role, 'business'),
  business_type = coalesce(excluded.business_type, public.partner_profiles.business_type),
  updated_at = now();

-- 2) Create or repair stores without deleting existing store data.
create table if not exists public.stores (
  id uuid primary key default gen_random_uuid()
);

alter table public.stores add column if not exists owner_id uuid references auth.users(id) on delete cascade;
alter table public.stores add column if not exists name text;
alter table public.stores add column if not exists description text;
alter table public.stores add column if not exists phone text;
alter table public.stores add column if not exists address_text text;
alter table public.stores add column if not exists business_type text;
alter table public.stores add column if not exists logo_url text;
alter table public.stores add column if not exists cover_url text;
alter table public.stores add column if not exists delivery_available boolean;
alter table public.stores add column if not exists approval_status text;
alter table public.stores add column if not exists is_active boolean;
alter table public.stores add column if not exists is_open boolean;
alter table public.stores add column if not exists created_at timestamptz;
alter table public.stores add column if not exists updated_at timestamptz;

update public.stores set business_type = 'restaurant' where business_type is null or business_type = '';
update public.stores set delivery_available = true where delivery_available is null;
update public.stores set approval_status = 'pending' where approval_status is null or approval_status = '';
update public.stores set is_active = false where is_active is null;
update public.stores set is_open = false where is_open is null;
update public.stores set created_at = now() where created_at is null;
update public.stores set updated_at = now() where updated_at is null;

alter table public.stores alter column business_type set default 'restaurant';
alter table public.stores alter column delivery_available set default true;
alter table public.stores alter column approval_status set default 'pending';
alter table public.stores alter column is_active set default false;
alter table public.stores alter column is_open set default false;
alter table public.stores alter column created_at set default now();
alter table public.stores alter column updated_at set default now();

create unique index if not exists stores_owner_id_unique_idx on public.stores(owner_id) where owner_id is not null;
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

-- 3) Create or repair products without deleting existing products.
create table if not exists public.products (
  id uuid primary key default gen_random_uuid()
);

alter table public.products add column if not exists store_id uuid references public.stores(id) on delete cascade;
alter table public.products add column if not exists name text;
alter table public.products add column if not exists description text;
alter table public.products add column if not exists category_name text;
alter table public.products add column if not exists price numeric(12,2);
alter table public.products add column if not exists image_url text;
alter table public.products add column if not exists is_available boolean;
alter table public.products add column if not exists sort_order integer;
alter table public.products add column if not exists created_at timestamptz;
alter table public.products add column if not exists updated_at timestamptz;

update public.products set price = 0 where price is null;
update public.products set is_available = true where is_available is null;
update public.products set sort_order = 0 where sort_order is null;
update public.products set created_at = now() where created_at is null;
update public.products set updated_at = now() where updated_at is null;

alter table public.products alter column price set default 0;
alter table public.products alter column is_available set default true;
alter table public.products alter column sort_order set default 0;
alter table public.products alter column created_at set default now();
alter table public.products alter column updated_at set default now();

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

notify pgrst, 'reload schema';

-- Optional verification result shown in the Results panel.
select
  to_regclass('public.partner_profiles') as partner_profiles,
  to_regclass('public.stores') as stores,
  to_regclass('public.products') as products;
