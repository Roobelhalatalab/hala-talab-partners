-- Hala Talab Partners - Stage 12
-- Run once after the initial partner_profiles table was created.
-- This adds missing columns safely and creates the automatic profile trigger.

alter table public.partner_profiles
  add column if not exists account_status text not null default 'pending',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.partner_profiles
  drop constraint if exists partner_profiles_role_check;

alter table public.partner_profiles
  add constraint partner_profiles_role_check
  check (role in ('business', 'driver'));

alter table public.partner_profiles
  drop constraint if exists partner_profiles_business_type_check;

alter table public.partner_profiles
  add constraint partner_profiles_business_type_check
  check (
    business_type is null or business_type in (
      'restaurant', 'grocery', 'sweets', 'pharmacy',
      'cafe', 'hookah', 'beverages', 'flowers'
    )
  );

alter table public.partner_profiles
  drop constraint if exists partner_profiles_account_status_check;

alter table public.partner_profiles
  add constraint partner_profiles_account_status_check
  check (account_status in ('pending', 'active', 'suspended', 'rejected'));

create or replace function public.handle_new_partner_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.partner_profiles (
    id,
    full_name,
    phone,
    email,
    role,
    business_type
  ) values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    new.email,
    coalesce(new.raw_user_meta_data ->> 'role', 'business'),
    nullif(new.raw_user_meta_data ->> 'business_type', '')
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    phone = excluded.phone,
    email = excluded.email,
    role = excluded.role,
    business_type = excluded.business_type,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_partner on auth.users;
create trigger on_auth_user_created_partner
after insert on auth.users
for each row execute procedure public.handle_new_partner_user();

-- Backfill profiles for users created before this trigger existed.
insert into public.partner_profiles (
  id,
  full_name,
  phone,
  email,
  role,
  business_type
)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'full_name', ''),
  nullif(u.raw_user_meta_data ->> 'phone', ''),
  u.email,
  coalesce(u.raw_user_meta_data ->> 'role', 'business'),
  nullif(u.raw_user_meta_data ->> 'business_type', '')
from auth.users u
on conflict (id) do nothing;
