-- Hala Talab Partners: initial profile table and security policies.
-- Run this file once in Supabase Dashboard > SQL Editor > New query.

create table if not exists public.partner_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  email text,
  role text not null check (role in ('business', 'driver')),
  business_type text check (
    business_type is null or business_type in (
      'restaurant', 'grocery', 'sweets', 'pharmacy',
      'cafe', 'hookah', 'beverages', 'flowers'
    )
  ),
  account_status text not null default 'pending'
    check (account_status in ('pending', 'active', 'suspended', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.partner_profiles enable row level security;

create policy "Partners can view own profile"
on public.partner_profiles for select
to authenticated
using ((select auth.uid()) = id);

create policy "Partners can update own profile"
on public.partner_profiles for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create or replace function public.handle_new_partner_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.partner_profiles (
    id, full_name, phone, email, role, business_type
  ) values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'role', 'business'),
    nullif(new.raw_user_meta_data ->> 'business_type', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_partner on auth.users;
create trigger on_auth_user_created_partner
after insert on auth.users
for each row execute procedure public.handle_new_partner_user();
