-- Hala Talab SAFE migration: shared customer phone + monthly store order numbering
-- Version: SAFE-2 (no DROP TABLE, no CASCADE, existing store_order_counters is preserved)
-- Goals:
--   1) A business/driver phone may also own a separate CUSTOMER account.
--   2) Visible order numbers restart from 1 per store at each new Baghdad calendar month.
-- Safety:
--   * Does NOT delete orders, stores, users, partner profiles, or the old counter table.
--   * Does NOT DROP any table.
--   * The only removals are obsolete UNIQUE/PK constraints/indexes that block the new behavior.
--   * Runs inside one transaction: any SQL error rolls the whole migration back.

begin;

-- ---------------------------------------------------------------------------
-- A) Phone/PIN registry: customer role may coexist with a partner role.
-- ---------------------------------------------------------------------------

-- Old schema made phone_e164 the primary key (one phone == one role).
-- Replace that key with (phone_e164, account_role); existing rows are preserved.
alter table public.phone_account_registry
  drop constraint if exists phone_account_registry_pkey;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.phone_account_registry'::regclass
      and contype = 'p'
  ) then
    alter table public.phone_account_registry
      add constraint phone_account_registry_pkey
      primary key (phone_e164, account_role);
  end if;
end $$;

-- One auth user must still map to exactly one role/account.
create unique index if not exists phone_account_registry_auth_user_unique_idx
  on public.phone_account_registry(auth_user_id);

-- Old schema also made phone_e164 unique in PIN credentials.
-- PIN credentials are already keyed by auth_user_id, so remove only that extra uniqueness.
alter table public.phone_pin_credentials
  drop constraint if exists phone_pin_credentials_phone_e164_key;

create index if not exists idx_phone_pin_credentials_phone
  on public.phone_pin_credentials(phone_e164);

create or replace function public.has_phone_account_role(p_phone_e164 text, p_role text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.phone_account_registry r
    where r.phone_e164 = p_phone_e164
      and r.account_role = lower(trim(p_role))
  );
$$;

grant execute on function public.has_phone_account_role(text,text) to anon, authenticated;

-- Compatibility helper: if a phone has multiple roles, do not return an arbitrary one.
create or replace function public.get_account_role_for_phone(p_phone_e164 text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  with roles as (
    select array_agg(r.account_role order by r.account_role) as items,
           count(*) as n
    from public.phone_account_registry r
    where r.phone_e164 = p_phone_e164
  )
  select case
    when n = 0 then 'unregistered'
    when n = 1 then items[1]
    else 'multiple'
  end
  from roles;
$$;

grant execute on function public.get_account_role_for_phone(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- B) Monthly visible order sequence per store.
-- ---------------------------------------------------------------------------

-- Add the month used for the visible number. Existing order UUIDs never change.
alter table public.orders
  add column if not exists order_sequence_month date;

update public.orders
set order_sequence_month = date_trunc('month', created_at at time zone 'Asia/Baghdad')::date
where order_sequence_month is null;

alter table public.orders
  alter column order_sequence_month
  set default date_trunc('month', now() at time zone 'Asia/Baghdad')::date;

-- The old unique index blocks reuse of #1 next month, so remove only that index.
-- No order rows are deleted.
drop index if exists public.orders_store_order_number_unique_idx;

-- For the CURRENT Baghdad month only, restart existing visible numbers from 1.
-- Previous months keep their historical order numbers unchanged.
with current_month as (
  select date_trunc('month', now() at time zone 'Asia/Baghdad')::date as m
), ranked as (
  select o.id,
         row_number() over (
           partition by o.store_id, o.order_sequence_month
           order by o.created_at asc, o.id asc
         )::bigint as monthly_number
  from public.orders o, current_month c
  where o.order_sequence_month = c.m
)
update public.orders o
set order_number = r.monthly_number
from ranked r
where r.id = o.id;

alter table public.orders
  alter column order_sequence_month set not null;

create unique index if not exists orders_store_month_order_number_unique_idx
  on public.orders(store_id, order_sequence_month, order_number);

-- IMPORTANT: keep the old public.store_order_counters table untouched for rollback/history.
-- Use a NEW monthly counter table instead of dropping/rebuilding the old one.
create table if not exists public.store_order_monthly_counters (
  store_id uuid not null references public.stores(id) on delete cascade,
  sequence_month date not null,
  last_number bigint not null default 0 check (last_number >= 0),
  updated_at timestamptz not null default now(),
  primary key (store_id, sequence_month)
);

-- This table is internal only; clients never read/write it directly.
alter table public.store_order_monthly_counters enable row level security;
revoke all on table public.store_order_monthly_counters from anon, authenticated;

-- Synchronize monthly counters with the highest visible number already present.
insert into public.store_order_monthly_counters(store_id, sequence_month, last_number, updated_at)
select store_id,
       order_sequence_month,
       coalesce(max(order_number), 0),
       now()
from public.orders
group by store_id, order_sequence_month
on conflict (store_id, sequence_month) do update
set last_number = greatest(public.store_order_monthly_counters.last_number, excluded.last_number),
    updated_at = now();

create or replace function public.hala_assign_store_order_number()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_next bigint;
  v_month date;
begin
  if new.store_id is null then
    raise exception 'store_id is required before assigning order_number';
  end if;

  v_month := date_trunc(
    'month',
    coalesce(new.created_at, now()) at time zone 'Asia/Baghdad'
  )::date;

  insert into public.store_order_monthly_counters(store_id, sequence_month, last_number, updated_at)
  values (new.store_id, v_month, 1, now())
  on conflict (store_id, sequence_month) do update
    set last_number = public.store_order_monthly_counters.last_number + 1,
        updated_at = now()
  returning last_number into v_next;

  new.order_sequence_month := v_month;
  new.order_number := v_next;
  return new;
end;
$$;

revoke all on function public.hala_assign_store_order_number() from public;
grant execute on function public.hala_assign_store_order_number() to anon, authenticated, service_role;

-- Replace only the trigger wiring; the orders themselves are untouched.
drop trigger if exists trg_hala_assign_store_order_number on public.orders;
create trigger trg_hala_assign_store_order_number
before insert on public.orders
for each row
execute function public.hala_assign_store_order_number();

commit;

-- Expected behavior:
-- Store A, September: historical numbers stay as they were.
-- Store A, current/new month: #1, #2, #3, ...
-- Store B: its own independent monthly sequence.
