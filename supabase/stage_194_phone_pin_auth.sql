-- Hala Talab Phone + 4-digit PIN authentication
-- Replaces the temporary WhatsApp/SMS OTP experiment.
-- Safe to run more than once. Business/order data is not deleted.

create extension if not exists pgcrypto;

create table if not exists public.phone_account_registry (
  phone_e164 text primary key,
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  account_role text not null check (account_role in ('customer','business','driver','admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_phone_account_registry_user on public.phone_account_registry(auth_user_id);
alter table public.phone_account_registry enable row level security;

create table if not exists public.phone_pin_credentials (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  phone_e164 text not null unique,
  pin_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.phone_pin_credentials enable row level security;

-- Remove only the temporary WhatsApp OTP challenge table from Stage 83/193.
drop table if exists public.whatsapp_otp_challenges cascade;

create or replace function public.hala_normalize_iraqi_phone(p_phone text)
returns text language plpgsql immutable as $$
declare v_digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
begin
  if left(v_digits,5)='00964' then v_digits := substring(v_digits from 3); end if;
  if left(v_digits,1)='0' then v_digits := substring(v_digits from 2); end if;
  if left(v_digits,3)<>'964' then v_digits := '964' || v_digits; end if;
  if v_digits !~ '^9647[0-9]{9}$' then return null; end if;
  return '+' || v_digits;
end; $$;

-- Server-only helpers. PINs are bcrypt-hashed by PostgreSQL and never stored as plaintext.
create or replace function public.server_set_phone_pin(p_user_id uuid, p_phone_e164 text, p_pin text)
returns void language plpgsql security definer set search_path=public, extensions as $$
begin
  if p_pin !~ '^[0-9]{4}$' then raise exception 'INVALID_PIN'; end if;
  insert into public.phone_pin_credentials(auth_user_id, phone_e164, pin_hash, failed_attempts, locked_until, updated_at)
  values (p_user_id, p_phone_e164, crypt(p_pin, gen_salt('bf', 10)), 0, null, now())
  on conflict (auth_user_id) do update set
    phone_e164=excluded.phone_e164,
    pin_hash=excluded.pin_hash,
    failed_attempts=0,
    locked_until=null,
    updated_at=now();
end; $$;
revoke all on function public.server_set_phone_pin(uuid,text,text) from public, anon, authenticated;
grant execute on function public.server_set_phone_pin(uuid,text,text) to service_role;

create or replace function public.server_check_phone_pin(p_user_id uuid, p_pin text)
returns text language plpgsql security definer set search_path=public, extensions as $$
declare
  v_row public.phone_pin_credentials%rowtype;
  v_attempts integer;
begin
  select * into v_row from public.phone_pin_credentials where auth_user_id=p_user_id for update;
  if not found then return 'PIN_NOT_SET'; end if;
  if v_row.locked_until is not null and v_row.locked_until > now() then return 'PIN_LOCKED'; end if;

  if v_row.pin_hash = crypt(p_pin, v_row.pin_hash) then
    update public.phone_pin_credentials set failed_attempts=0, locked_until=null, updated_at=now() where auth_user_id=p_user_id;
    return 'OK';
  end if;

  v_attempts := coalesce(v_row.failed_attempts,0)+1;
  if v_attempts >= 5 then
    update public.phone_pin_credentials set failed_attempts=0, locked_until=now()+interval '15 minutes', updated_at=now() where auth_user_id=p_user_id;
    return 'PIN_LOCKED';
  end if;
  update public.phone_pin_credentials set failed_attempts=v_attempts, updated_at=now() where auth_user_id=p_user_id;
  return 'PIN_INCORRECT';
end; $$;
revoke all on function public.server_check_phone_pin(uuid,text) from public, anon, authenticated;
grant execute on function public.server_check_phone_pin(uuid,text) to service_role;

-- Preserve/migrate existing customer, store and driver accounts into the phone registry.
insert into public.phone_account_registry(phone_e164, auth_user_id, account_role)
select public.hala_normalize_iraqi_phone(coalesce(u.raw_user_meta_data->>'contact_phone',u.raw_user_meta_data->>'phone')),
       u.id,
       ar.role
from auth.users u
join public.account_roles ar on ar.user_id=u.id
where ar.role in ('customer','business','driver','admin')
  and public.hala_normalize_iraqi_phone(coalesce(u.raw_user_meta_data->>'contact_phone',u.raw_user_meta_data->>'phone')) is not null
on conflict do nothing;

insert into public.phone_account_registry(phone_e164, auth_user_id, account_role)
select public.hala_normalize_iraqi_phone(p.phone), p.id, p.role
from public.partner_profiles p
where p.role in ('business','driver')
  and public.hala_normalize_iraqi_phone(p.phone) is not null
on conflict do nothing;

create or replace function public.get_current_account_role()
returns text language plpgsql security definer set search_path=public as $$
declare v_role text;
begin
  if auth.uid() is null then return 'anonymous'; end if;
  select r.account_role into v_role from public.phone_account_registry r where r.auth_user_id=auth.uid() limit 1;
  if v_role is not null then return v_role; end if;
  select lower(coalesce(u.raw_user_meta_data->>'account_role',u.raw_user_meta_data->>'role','')) into v_role from auth.users u where u.id=auth.uid();
  return case when v_role in ('customer','business','driver','admin') then v_role else 'unknown' end;
end; $$;
grant execute on function public.get_current_account_role() to authenticated;

create or replace function public.get_account_role_for_phone(p_phone_e164 text)
returns text language sql security definer set search_path=public as $$
  select coalesce((select r.account_role from public.phone_account_registry r where r.phone_e164=p_phone_e164 limit 1),'unregistered');
$$;
grant execute on function public.get_account_role_for_phone(text) to anon, authenticated;



-- Stage PIN recovery: admin-reviewed reset requests (no SMS/WhatsApp dependency).
create table if not exists public.phone_pin_reset_requests (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  phone_e164 text not null,
  account_role text not null check (account_role in ('customer','business','driver')),
  status text not null default 'pending' check (status in ('pending','issued','completed','rejected','expired','cancelled')),
  code_hash text,
  code_expires_at timestamptz,
  failed_attempts integer not null default 0,
  requested_at timestamptz not null default now(),
  issued_at timestamptz,
  completed_at timestamptz,
  handled_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
create index if not exists idx_phone_pin_reset_requests_status on public.phone_pin_reset_requests(status, requested_at desc);
create index if not exists idx_phone_pin_reset_requests_user on public.phone_pin_reset_requests(auth_user_id, requested_at desc);
alter table public.phone_pin_reset_requests enable row level security;

create or replace function public.hala_is_admin()
returns boolean language plpgsql security definer set search_path=public as $$
declare v_role text;
begin
  if auth.uid() is null then return false; end if;
  if exists(select 1 from public.admin_users a where a.id=auth.uid() and lower(coalesce(a.role,'admin'))='admin' and coalesce(a.is_active,true)) then return true; end if;
  select lower(role) into v_role from public.account_roles where user_id=auth.uid() limit 1;
  if v_role='admin' then return true; end if;
  select lower(coalesce(raw_user_meta_data->>'account_role',raw_user_meta_data->>'role','')) into v_role from auth.users where id=auth.uid();
  return v_role='admin';
end; $$;
grant execute on function public.hala_is_admin() to authenticated;

-- Admin dashboard can read requests only if the signed-in user is an admin.
drop policy if exists phone_pin_reset_admin_select on public.phone_pin_reset_requests;
create policy phone_pin_reset_admin_select on public.phone_pin_reset_requests
for select to authenticated using (public.hala_is_admin());

create or replace function public.server_request_phone_pin_reset(p_user_id uuid, p_phone_e164 text, p_role text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if p_role not in ('customer','business','driver') then raise exception 'UNSUPPORTED_ROLE'; end if;
  update public.phone_pin_reset_requests
     set status='cancelled', updated_at=now()
   where auth_user_id=p_user_id and status in ('pending','issued');
  insert into public.phone_pin_reset_requests(auth_user_id,phone_e164,account_role,status)
  values(p_user_id,p_phone_e164,p_role,'pending') returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.server_request_phone_pin_reset(uuid,text,text) from public, anon, authenticated;
grant execute on function public.server_request_phone_pin_reset(uuid,text,text) to service_role;

create or replace function public.admin_issue_phone_pin_reset_code(p_request_id uuid)
returns table(request_id uuid, recovery_code text, expires_at timestamptz)
language plpgsql security definer set search_path=public, extensions as $$
declare
  v_code text;
  v_exp timestamptz := now()+interval '15 minutes';
  v_exists boolean;
begin
  if not public.hala_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  select true into v_exists from public.phone_pin_reset_requests where id=p_request_id and status in ('pending','issued') for update;
  if not coalesce(v_exists,false) then raise exception 'RESET_REQUEST_NOT_OPEN'; end if;
  v_code := lpad((floor(random()*1000000)::integer)::text,6,'0');
  update public.phone_pin_reset_requests
     set status='issued', code_hash=crypt(v_code,gen_salt('bf',10)), code_expires_at=v_exp,
         failed_attempts=0, issued_at=now(), handled_by=auth.uid(), updated_at=now()
   where id=p_request_id;
  return query select p_request_id,v_code,v_exp;
end; $$;
revoke all on function public.admin_issue_phone_pin_reset_code(uuid) from public, anon;
grant execute on function public.admin_issue_phone_pin_reset_code(uuid) to authenticated;

create or replace function public.admin_reject_phone_pin_reset(p_request_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.hala_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  update public.phone_pin_reset_requests set status='rejected', handled_by=auth.uid(), updated_at=now()
   where id=p_request_id and status in ('pending','issued');
end; $$;
revoke all on function public.admin_reject_phone_pin_reset(uuid) from public, anon;
grant execute on function public.admin_reject_phone_pin_reset(uuid) to authenticated;

create or replace function public.server_redeem_phone_pin_reset_code(p_user_id uuid,p_role text,p_code text,p_new_pin text)
returns text language plpgsql security definer set search_path=public, extensions as $$
declare
  v public.phone_pin_reset_requests%rowtype;
  v_attempts integer;
  v_phone text;
begin
  if p_new_pin !~ '^[0-9]{4}$' then return 'INVALID_PIN'; end if;
  if p_code !~ '^[0-9]{6}$' then return 'INVALID_RECOVERY_CODE'; end if;
  select * into v from public.phone_pin_reset_requests
   where auth_user_id=p_user_id and account_role=p_role and status='issued'
   order by issued_at desc nulls last limit 1 for update;
  if not found then return 'RESET_CODE_NOT_ISSUED'; end if;
  if v.code_expires_at is null or v.code_expires_at<=now() then
    update public.phone_pin_reset_requests set status='expired',updated_at=now() where id=v.id;
    return 'RESET_CODE_EXPIRED';
  end if;
  if v.failed_attempts>=5 then return 'RESET_CODE_LOCKED'; end if;
  if v.code_hash is null or v.code_hash<>crypt(p_code,v.code_hash) then
    v_attempts:=v.failed_attempts+1;
    update public.phone_pin_reset_requests set failed_attempts=v_attempts,updated_at=now() where id=v.id;
    return case when v_attempts>=5 then 'RESET_CODE_LOCKED' else 'RESET_CODE_INCORRECT' end;
  end if;
  select phone_e164 into v_phone from public.phone_account_registry where auth_user_id=p_user_id;
  perform public.server_set_phone_pin(p_user_id,v_phone,p_new_pin);
  update public.phone_pin_reset_requests set status='completed',completed_at=now(),code_hash=null,updated_at=now() where id=v.id;
  return 'OK';
end; $$;
revoke all on function public.server_redeem_phone_pin_reset_code(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.server_redeem_phone_pin_reset_code(uuid,text,text,text) to service_role;

select 'phone_pin_auth_ready' as status;
