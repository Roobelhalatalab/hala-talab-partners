-- Hala Talab Stage 49 / 140
-- FINAL unified account registry for Customer / Business / Driver / Admin.
-- This replaces the experimental Stage 44-48 / 135-139 auth SQL files.
-- Run ONE copy only (Client Stage 49 OR Partners Stage 140).
-- Safe to re-run: it removes old conflicting auth triggers/functions first.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 0) Stop every older auth-role trigger that can interfere with this migration.
-- ---------------------------------------------------------------------------
drop trigger if exists on_auth_user_created_partner on auth.users;
drop trigger if exists on_auth_user_created_partner_profile on auth.users;
drop trigger if exists hala_account_role_sync on auth.users;
drop trigger if exists hala_account_role_delete on auth.users;
drop trigger if exists hala_auth_role_registry_insert on auth.users;
drop trigger if exists hala_auth_role_registry_email on auth.users;
drop trigger if exists hala_auth_role_registry_delete on auth.users;

-- Remove old function overloads. The old 3-argument function had a default
-- parameter, which made calls to the 2-argument overload ambiguous (42725).
drop function if exists public._sync_hala_account_role_from_auth() cascade;
drop function if exists public._delete_hala_account_role_from_auth() cascade;
drop function if exists public.get_account_role_for_email(text) cascade;
drop function if exists public.get_account_role_for_email(varchar) cascade;
drop function if exists public.register_current_customer_account() cascade;
drop function if exists public._infer_hala_account_role(uuid,text,jsonb) cascade;
drop function if exists public._infer_hala_account_role(uuid,varchar,jsonb) cascade;
drop function if exists public._infer_hala_account_role(uuid,text) cascade;
drop function if exists public._infer_hala_account_role(uuid,varchar) cascade;
drop function if exists public._infer_hala_account_role(uuid) cascade;
drop function if exists public._hala_auth_role_on_insert() cascade;
drop function if exists public._hala_auth_email_sync() cascade;
drop function if exists public._hala_auth_delete_cleanup() cascade;
drop function if exists public._hala_has_uuid_ref(text,text,uuid) cascade;
drop function if exists public._hala_customer_evidence(uuid) cascade;
drop function if exists public._hala_explicit_auth_role(uuid) cascade;

-- ---------------------------------------------------------------------------
-- 1) Server-owned registries. App users cannot write these tables directly.
-- ---------------------------------------------------------------------------
create table if not exists public.customer_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.account_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role text not null check (role in ('customer','business','driver','admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Defensive repair in case an interrupted experimental migration ever renamed
-- user_id to driver_id. Normally these blocks do nothing.
do $$
begin
  if to_regclass('public.customer_accounts') is not null
     and not exists (
       select 1 from information_schema.columns
       where table_schema='public' and table_name='customer_accounts' and column_name='user_id'
     )
     and exists (
       select 1 from information_schema.columns
       where table_schema='public' and table_name='customer_accounts' and column_name='driver_id'
     ) then
    execute 'alter table public.customer_accounts rename column driver_id to user_id';
  end if;

  if to_regclass('public.account_roles') is not null
     and not exists (
       select 1 from information_schema.columns
       where table_schema='public' and table_name='account_roles' and column_name='user_id'
     )
     and exists (
       select 1 from information_schema.columns
       where table_schema='public' and table_name='account_roles' and column_name='driver_id'
     ) then
    execute 'alter table public.account_roles rename column driver_id to user_id';
  end if;
end $$;

alter table public.customer_accounts enable row level security;
alter table public.account_roles enable row level security;
revoke all on table public.customer_accounts from anon, authenticated;
revoke all on table public.account_roles from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Schema-safe evidence helpers.
--    They avoid hard-coding a column on a table that may not exist yet.
-- ---------------------------------------------------------------------------
create or replace function public._hala_has_uuid_ref(
  p_table text,
  p_column text,
  p_uid uuid
) returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_exists boolean := false;
begin
  if p_uid is null then return false; end if;
  if to_regclass(format('public.%I', p_table)) is null then return false; end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name=p_table and column_name=p_column
  ) then return false; end if;

  execute format(
    'select exists(select 1 from public.%I where %I = $1)',
    p_table, p_column
  ) into v_exists using p_uid;
  return coalesce(v_exists,false);
end;
$$;

create or replace function public._hala_explicit_auth_role(p_uid uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_role text;
  v_account_role text;
begin
  select lower(trim(coalesce(raw_user_meta_data->>'role',''))),
         lower(trim(coalesce(raw_user_meta_data->>'account_role','')))
    into v_role, v_account_role
  from auth.users where id=p_uid;

  if v_account_role in ('customer','business','driver','admin') then
    return v_account_role;
  end if;
  if v_role in ('customer','business','driver','admin') then
    return v_role;
  end if;
  return null;
end;
$$;

create or replace function public._hala_customer_evidence(p_uid uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_explicit text;
  v_contact_phone text;
begin
  if p_uid is null then return false; end if;

  if exists(select 1 from public.customer_accounts where user_id=p_uid) then
    return true;
  end if;

  v_explicit := public._hala_explicit_auth_role(p_uid);
  if v_explicit = 'customer' then return true; end if;
  if v_explicit in ('business','driver','admin') then return false; end if;

  -- Customer-owned operational data is strong legacy evidence.
  if public._hala_has_uuid_ref('orders','customer_id',p_uid) then return true; end if;
  if public._hala_has_uuid_ref('customer_notifications','customer_id',p_uid) then return true; end if;
  if public._hala_has_uuid_ref('customer_support_conversations','customer_id',p_uid) then return true; end if;
  if public._hala_has_uuid_ref('coupon_usages','customer_id',p_uid) then return true; end if;
  if public._hala_has_uuid_ref('store_reviews','customer_id',p_uid) then return true; end if;
  if public._hala_has_uuid_ref('product_reviews','customer_id',p_uid) then return true; end if;
  if public._hala_has_uuid_ref('driver_reviews','customer_id',p_uid) then return true; end if;

  -- Legacy Client accounts stored the phone in contact_phone. Only use this
  -- weak evidence when the account has no real store/driver record.
  select trim(coalesce(raw_user_meta_data->>'contact_phone',''))
    into v_contact_phone from auth.users where id=p_uid;
  if coalesce(v_contact_phone,'') <> ''
     and not public._hala_has_uuid_ref('stores','owner_id',p_uid)
     and not public._hala_has_uuid_ref('driver_basic_profiles','driver_id',p_uid) then
    return true;
  end if;

  return false;
end;
$$;

-- ONE authoritative inference function. No overloads and no default arguments.
create or replace function public._infer_hala_account_role(p_uid uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_role text;
begin
  if p_uid is null then return null; end if;

  -- 1) Admin is always authoritative.
  if to_regclass('public.admin_users') is not null then
    execute 'select case when exists(select 1 from public.admin_users where id=$1 and coalesce(is_active,true)=true) then ''admin''::text else null end'
      into v_role using p_uid;
    if v_role is not null then return v_role; end if;
  end if;

  -- 2) Server-owned customer registry is authoritative for a customer.
  if exists(select 1 from public.customer_accounts where user_id=p_uid) then
    return 'customer';
  end if;

  -- 3) Real operational partner records are stronger than stale profile rows.
  if public._hala_has_uuid_ref('stores','owner_id',p_uid) then
    return 'business';
  end if;
  if public._hala_has_uuid_ref('driver_basic_profiles','driver_id',p_uid) then
    return 'driver';
  end if;

  -- 4) Explicit role captured at auth-user creation.
  v_role := public._hala_explicit_auth_role(p_uid);
  if v_role in ('customer','business','driver','admin') then
    return v_role;
  end if;

  -- 5) Legacy customer evidence (orders, notifications, contact_phone, etc.).
  if public._hala_customer_evidence(p_uid) then
    return 'customer';
  end if;

  -- 6) partner_profiles is the final legacy fallback only. A polluted old
  -- customer is already caught by the customer checks above.
  if to_regclass('public.partner_profiles') is not null then
    execute 'select role::text from public.partner_profiles where id=$1 and role in (''business'',''driver'') limit 1'
      into v_role using p_uid;
    if v_role in ('business','driver') then return v_role; end if;
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) Repair current users deterministically before enabling new triggers.
-- ---------------------------------------------------------------------------
-- First remove any customer-registry row that conflicts with strong partner/admin
-- evidence. This makes the migration self-healing after earlier experimental runs.
delete from public.customer_accounts c
where public._hala_has_uuid_ref('stores','owner_id',c.user_id)
   or public._hala_has_uuid_ref('driver_basic_profiles','driver_id',c.user_id)
   or coalesce(public._hala_explicit_auth_role(c.user_id),'') in ('business','driver','admin')
   or (
     to_regclass('public.admin_users') is not null
     and exists(select 1 from public.admin_users a where a.id=c.user_id and coalesce(a.is_active,true)=true)
   );

-- Register legacy customers only when there is no strong partner/admin proof.
insert into public.customer_accounts(user_id,email,updated_at)
select u.id, lower(trim(u.email)), now()
from auth.users u
where u.email is not null
  and public._hala_customer_evidence(u.id)
  and not public._hala_has_uuid_ref('stores','owner_id',u.id)
  and not public._hala_has_uuid_ref('driver_basic_profiles','driver_id',u.id)
  and coalesce(public._hala_explicit_auth_role(u.id),'') not in ('business','driver','admin')
  and not (
    to_regclass('public.admin_users') is not null
    and exists(select 1 from public.admin_users a where a.id=u.id and coalesce(a.is_active,true)=true)
  )
on conflict (user_id) do update set email=excluded.email, updated_at=now();

-- Remove only proven legacy pollution: a registered customer cannot also keep
-- a bare partner profile unless a real store/driver record proves that role.
delete from public.partner_profiles p
where exists(select 1 from public.customer_accounts c where c.user_id=p.id)
  and not public._hala_has_uuid_ref('stores','owner_id',p.id)
  and not public._hala_has_uuid_ref('driver_basic_profiles','driver_id',p.id)
  and coalesce(public._hala_explicit_auth_role(p.id),'') not in ('business','driver');

-- Rebuild account_roles from authoritative inference; do not preserve stale rows.
delete from public.account_roles;
insert into public.account_roles(user_id,email,role,updated_at)
select u.id, lower(trim(u.email)), public._infer_hala_account_role(u.id), now()
from auth.users u
where u.email is not null
  and public._infer_hala_account_role(u.id) is not null;

-- ---------------------------------------------------------------------------
-- 4) New-account registry. Only EXPLICIT signup roles create role records.
--    There is NO default-to-business behavior anymore.
-- ---------------------------------------------------------------------------
create or replace function public._hala_auth_role_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_role text;
  v_email text;
  v_category_id uuid;
begin
  v_email := lower(trim(coalesce(new.email,'')));
  v_role := lower(trim(coalesce(
    new.raw_user_meta_data->>'account_role',
    new.raw_user_meta_data->>'role',
    ''
  )));

  if v_email='' or v_role not in ('customer','business','driver') then
    return new;
  end if;

  if v_role='customer' then
    insert into public.customer_accounts(user_id,email,updated_at)
    values(new.id,v_email,now())
    on conflict (user_id) do update set email=excluded.email,updated_at=now();
  else
    -- Partners are created only by an explicit business/driver signup.
    if to_regclass('public.partner_profiles') is not null then
      insert into public.partner_profiles(id,full_name,phone,email,role,business_type)
      values(
        new.id,
        coalesce(new.raw_user_meta_data->>'full_name',''),
        nullif(coalesce(new.raw_user_meta_data->>'phone',new.raw_user_meta_data->>'contact_phone'),''),
        new.email,
        v_role,
        nullif(new.raw_user_meta_data->>'business_type','')
      )
      on conflict (id) do update set
        full_name=excluded.full_name,
        phone=excluded.phone,
        email=excluded.email,
        business_type=coalesce(excluded.business_type,public.partner_profiles.business_type),
        updated_at=now();

      -- Preserve dynamic store category when the column exists.
      if exists(
        select 1 from information_schema.columns
        where table_schema='public' and table_name='partner_profiles' and column_name='system_category_id'
      ) then
        begin
          v_category_id := nullif(new.raw_user_meta_data->>'system_category_id','')::uuid;
        exception when others then
          v_category_id := null;
        end;
        if v_category_id is not null then
          execute 'update public.partner_profiles set system_category_id=$1, updated_at=now() where id=$2'
            using v_category_id,new.id;
        end if;
      end if;
    end if;
  end if;

  insert into public.account_roles(user_id,email,role,updated_at)
  values(new.id,v_email,v_role,now())
  on conflict (user_id) do update set email=excluded.email,role=excluded.role,updated_at=now();
  return new;
end;
$$;

create trigger hala_auth_role_registry_insert
after insert on auth.users
for each row execute function public._hala_auth_role_on_insert();

-- Email changes update lookup fields only. They NEVER change a role.
create or replace function public._hala_auth_email_sync()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_email text;
begin
  v_email:=lower(trim(coalesce(new.email,'')));
  if v_email='' then return new; end if;
  update public.account_roles set email=v_email,updated_at=now() where user_id=new.id;
  update public.customer_accounts set email=v_email,updated_at=now() where user_id=new.id;
  if to_regclass('public.partner_profiles') is not null then
    execute 'update public.partner_profiles set email=$1,updated_at=now() where id=$2'
      using new.email,new.id;
  end if;
  return new;
end;
$$;

create trigger hala_auth_role_registry_email
after update of email on auth.users
for each row execute function public._hala_auth_email_sync();

create or replace function public._hala_auth_delete_cleanup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.account_roles where user_id=old.id;
  delete from public.customer_accounts where user_id=old.id;
  return old;
end;
$$;

create trigger hala_auth_role_registry_delete
after delete on auth.users
for each row execute function public._hala_auth_delete_cleanup();

-- ---------------------------------------------------------------------------
-- 5) Public lookup used BEFORE OTP. It distinguishes all states explicitly.
-- ---------------------------------------------------------------------------
create or replace function public.get_account_role_for_email(p_email text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text := lower(trim(coalesce(p_email,'')));
  v_uid uuid;
  v_role text;
begin
  if v_email='' then return 'unknown'; end if;

  select id into v_uid from auth.users where lower(email)=v_email limit 1;
  if v_uid is null then return 'unregistered'; end if;

  select role into v_role from public.account_roles where user_id=v_uid;
  if v_role in ('customer','business','driver','admin') then return v_role; end if;

  v_role:=public._infer_hala_account_role(v_uid);
  if v_role in ('customer','business','driver','admin') then
    insert into public.account_roles(user_id,email,role,updated_at)
    values(v_uid,v_email,v_role,now())
    on conflict (user_id) do update set email=excluded.email,role=excluded.role,updated_at=now();
    return v_role;
  end if;

  return 'unknown';
end;
$$;

-- Authenticated Client finalization. Idempotent, but cannot convert a real partner.
create or replace function public.register_current_customer_account()
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid:=auth.uid();
  v_email text;
  v_role text;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select lower(trim(email)) into v_email from auth.users where id=v_uid;
  if coalesce(v_email,'')='' then raise exception 'email required'; end if;

  v_role:=public._infer_hala_account_role(v_uid);
  if v_role in ('business','driver','admin') then
    raise exception 'account already belongs to another role';
  end if;
  if public._hala_has_uuid_ref('stores','owner_id',v_uid) then
    raise exception 'account already belongs to business';
  end if;
  if public._hala_has_uuid_ref('driver_basic_profiles','driver_id',v_uid) then
    raise exception 'account already belongs to driver';
  end if;

  insert into public.customer_accounts(user_id,email,updated_at)
  values(v_uid,v_email,now())
  on conflict (user_id) do update set email=excluded.email,updated_at=now();

  insert into public.account_roles(user_id,email,role,updated_at)
  values(v_uid,v_email,'customer',now())
  on conflict (user_id) do update set email=excluded.email,role='customer',updated_at=now();

  -- Remove a bare polluted legacy partner row only when no operational partner exists.
  if to_regclass('public.partner_profiles') is not null
     and not public._hala_has_uuid_ref('stores','owner_id',v_uid)
     and not public._hala_has_uuid_ref('driver_basic_profiles','driver_id',v_uid) then
    execute 'delete from public.partner_profiles where id=$1' using v_uid;
  end if;
  return 'customer';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6) Permissions.
-- ---------------------------------------------------------------------------
revoke all on function public._hala_has_uuid_ref(text,text,uuid) from public,anon,authenticated;
revoke all on function public._hala_explicit_auth_role(uuid) from public,anon,authenticated;
revoke all on function public._hala_customer_evidence(uuid) from public,anon,authenticated;
revoke all on function public._infer_hala_account_role(uuid) from public,anon,authenticated;
revoke all on function public._hala_auth_role_on_insert() from public,anon,authenticated;
revoke all on function public._hala_auth_email_sync() from public,anon,authenticated;
revoke all on function public._hala_auth_delete_cleanup() from public,anon,authenticated;
revoke all on function public.get_account_role_for_email(text) from public;
grant execute on function public.get_account_role_for_email(text) to anon,authenticated;
revoke all on function public.register_current_customer_account() from public;
grant execute on function public.register_current_customer_account() to authenticated;

notify pgrst, 'reload schema';

select
  'final_account_registry_ready' as check_name,
  true as ready,
  count(*) filter(where role='customer') as customers,
  count(*) filter(where role='business') as businesses,
  count(*) filter(where role='driver') as drivers,
  count(*) filter(where role='admin') as admins,
  count(*) as total_roles,
  (select count(*) from auth.users u where u.email is not null and not exists(select 1 from public.account_roles r where r.user_id=u.id)) as unknown_users,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='_infer_hala_account_role') as infer_function_versions
from public.account_roles;
