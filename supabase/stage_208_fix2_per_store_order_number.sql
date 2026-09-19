-- Hala Talab Partners - Stage 208 Fix 2
-- Independent order numbering per store.
-- Safe goal: keep order UUID as the real unique identifier, while the visible
-- order_number restarts from 1 for each store and increments independently.
-- Existing orders are renumbered per store by created_at, id.

begin;

-- 1) Remove the old global uniqueness / identity behavior if present.
alter table public.orders
  drop constraint if exists orders_order_number_key;

alter table public.orders
  alter column order_number drop identity if exists;

-- 2) Backfill every existing store independently: 1, 2, 3, ...
with ranked as (
  select
    id,
    row_number() over (
      partition by store_id
      order by created_at asc, id asc
    )::bigint as local_order_number
  from public.orders
)
update public.orders o
set order_number = r.local_order_number
from ranked r
where r.id = o.id;

-- 3) Visible order numbers only need to be unique inside the same store.
create unique index if not exists orders_store_order_number_unique_idx
  on public.orders(store_id, order_number);

-- 4) Store-specific counters provide concurrency-safe numbering for new orders.
create table if not exists public.store_order_counters (
  store_id uuid primary key references public.stores(id) on delete cascade,
  last_number bigint not null default 0 check (last_number >= 0),
  updated_at timestamptz not null default now()
);

-- Sync counters to the highest existing number for each store.
insert into public.store_order_counters(store_id, last_number, updated_at)
select store_id, coalesce(max(order_number), 0), now()
from public.orders
group by store_id
on conflict (store_id) do update
set last_number = greatest(public.store_order_counters.last_number, excluded.last_number),
    updated_at = now();

-- Counter table is internal only. Clients do not need direct access.
revoke all on table public.store_order_counters from anon, authenticated;

create or replace function public.hala_assign_store_order_number()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_next bigint;
begin
  if new.store_id is null then
    raise exception 'store_id is required before assigning order_number';
  end if;

  -- Always assign server-side so every store owns its own sequence.
  insert into public.store_order_counters(store_id, last_number, updated_at)
  values (new.store_id, 1, now())
  on conflict (store_id) do update
    set last_number = public.store_order_counters.last_number + 1,
        updated_at = now()
  returning last_number into v_next;

  new.order_number := v_next;
  return new;
end;
$$;

revoke all on function public.hala_assign_store_order_number() from public;
grant execute on function public.hala_assign_store_order_number() to anon, authenticated, service_role;

drop trigger if exists trg_hala_assign_store_order_number on public.orders;
create trigger trg_hala_assign_store_order_number
before insert on public.orders
for each row
execute function public.hala_assign_store_order_number();

-- All existing/new rows must have a visible number.
alter table public.orders
  alter column order_number set not null;

commit;

-- Expected behavior after running this migration:
-- Store A: #1, #2, #3, ...
-- Store B: #1, #2, #3, ...
-- Store C: #1, #2, #3, ...
-- The UUID orders.id remains globally unique and continues to be used internally.
