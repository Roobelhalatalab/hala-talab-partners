-- Hala Talab Partners - Stage 134
-- Fast driver onboarding + optional admin approval switch.
-- Run once in Supabase SQL Editor.

create extension if not exists pgcrypto;

-- Basic driver profile: only the information needed for the MVP.
create table if not exists public.driver_basic_profiles (
  driver_id uuid primary key references auth.users(id) on delete cascade,
  vehicle_type text not null check (vehicle_type in ('motorcycle','car','bicycle')),
  plate_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.driver_basic_profiles enable row level security;

drop policy if exists "Drivers can read own basic profile" on public.driver_basic_profiles;
create policy "Drivers can read own basic profile"
on public.driver_basic_profiles for select
to authenticated
using (auth.uid() = driver_id);

drop policy if exists "Drivers can create own basic profile" on public.driver_basic_profiles;
create policy "Drivers can create own basic profile"
on public.driver_basic_profiles for insert
to authenticated
with check (
  auth.uid() = driver_id
  and exists (
    select 1 from public.partner_profiles p
    where p.id = auth.uid() and p.role = 'driver'
  )
);

drop policy if exists "Drivers can update own basic profile" on public.driver_basic_profiles;
create policy "Drivers can update own basic profile"
on public.driver_basic_profiles for update
to authenticated
using (auth.uid() = driver_id)
with check (auth.uid() = driver_id);

-- Keep admin approval infrastructure available even when approval is disabled.
create table if not exists public.admin_driver_reviews (
  driver_id uuid primary key references auth.users(id) on delete cascade,
  review_status text not null default 'pending'
    check (review_status in ('pending','approved','rejected','suspended')),
  notes text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Existing admin system settings table is used by the dashboard.
create table if not exists public.admin_system_settings (
  setting_key text primary key,
  setting_value text not null,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.admin_system_settings(setting_key, setting_value)
values ('driver_approval_required', 'false')
on conflict (setting_key) do nothing;

create or replace function public.driver_approval_is_required()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce((
    select setting_value
    from public.admin_system_settings
    where setting_key = 'driver_approval_required'
  ), 'false')) in ('true','1','yes','on');
$$;

grant execute on function public.driver_approval_is_required() to authenticated;

-- New driver accounts are automatically approved while the switch is OFF.
-- When the switch is ON they start as pending and require admin approval.
create or replace function public.sync_driver_review_on_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'driver' then
    insert into public.admin_driver_reviews(driver_id, review_status, reviewed_at)
    values (
      new.id,
      case when public.driver_approval_is_required() then 'pending' else 'approved' end,
      case when public.driver_approval_is_required() then null else now() end
    )
    on conflict (driver_id) do nothing;

    -- Status mirrors the effective access state for simple reporting.
    if public.driver_approval_is_required() then
      new.status := 'pending';
    else
      new.status := 'active';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists partner_profile_driver_review_sync on public.partner_profiles;
create trigger partner_profile_driver_review_sync
before insert or update of role on public.partner_profiles
for each row execute function public.sync_driver_review_on_profile();

-- Backfill drivers that already exist. With the default OFF setting they remain active.
insert into public.admin_driver_reviews(driver_id, review_status, reviewed_at)
select p.id,
       case when public.driver_approval_is_required() then 'pending' else 'approved' end,
       case when public.driver_approval_is_required() then null else now() end
from public.partner_profiles p
where p.role = 'driver'
on conflict (driver_id) do nothing;

-- While direct registration is open, normalize old pending drivers as approved.
-- This makes today's MVP drivers remain active if approval is enabled later.
update public.admin_driver_reviews
set review_status = 'approved', reviewed_at = coalesce(reviewed_at, now())
where review_status = 'pending'
  and not public.driver_approval_is_required();

update public.partner_profiles p
set status = case
  when r.review_status = 'approved' then 'active'
  when r.review_status = 'suspended' then 'suspended'
  when r.review_status = 'rejected' then 'rejected'
  else 'pending'
end,
updated_at = now()
from public.admin_driver_reviews r
where p.id = r.driver_id and p.role = 'driver';

-- Single authoritative access check used by the driver app.
create or replace function public.driver_access_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  required boolean;
  review text;
begin
  if uid is null then
    raise exception 'driver_not_signed_in';
  end if;
  if not exists (select 1 from public.partner_profiles where id = uid and role = 'driver') then
    raise exception 'driver_role_required';
  end if;

  required := public.driver_approval_is_required();
  select review_status into review
  from public.admin_driver_reviews
  where driver_id = uid;
  review := coalesce(review, case when required then 'pending' else 'approved' end);

  return jsonb_build_object(
    'approval_required', required,
    'review_status', review,
    'allowed', case
      when review in ('rejected','suspended') then false
      when required then review = 'approved'
      else true
    end
  );
end;
$$;

grant execute on function public.driver_access_state() to authenticated;

notify pgrst, 'reload schema';

select
  not public.driver_approval_is_required() as driver_signup_open_now,
  (select count(*) from public.partner_profiles where role='driver') as drivers_found,
  true as driver_fast_signup_ready;
