create extension if not exists pgcrypto;

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

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists stores_set_updated_at on public.stores;
create trigger stores_set_updated_at
before update on public.stores
for each row execute function public.set_updated_at();
