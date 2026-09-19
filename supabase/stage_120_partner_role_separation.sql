-- Hala Talab Partners - Stage 120
-- Permanent Store/Driver account separation.
-- Run once in Supabase SQL Editor before testing this build.

-- partner_profiles.role is the authoritative account type.
-- A normal authenticated partner may edit profile fields, but may never turn
-- a store account into a driver account (or the opposite).
create or replace function public.prevent_partner_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and old.role is distinct from new.role then
    raise exception 'partner_role_is_immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists partner_profiles_role_immutable on public.partner_profiles;
create trigger partner_profiles_role_immutable
before update of role on public.partner_profiles
for each row execute function public.prevent_partner_role_change();

-- Keep roles restricted to the two partner applications.
alter table public.partner_profiles
  drop constraint if exists partner_profiles_role_check;
alter table public.partner_profiles
  add constraint partner_profiles_role_check
  check (role in ('business', 'driver'));

-- Self-service profile updates must still belong to the signed-in account.
drop policy if exists "Partners can update own profile" on public.partner_profiles;
create policy "Partners can update own profile"
on public.partner_profiles for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

notify pgrst, 'reload schema';
