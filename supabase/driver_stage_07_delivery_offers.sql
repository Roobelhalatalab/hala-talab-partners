-- Hala Talab Partners - Driver Stage 07
-- Secure driver delivery offers + atomic accept/reject.
-- Safe to run more than once. Existing orders are preserved.

create extension if not exists pgcrypto;

create table if not exists public.driver_order_rejections (
  driver_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (driver_id, order_id)
);

alter table public.driver_order_rejections enable row level security;

-- The app accesses this table only through the RPC functions below.
revoke all on table public.driver_order_rejections from anon, authenticated;

create or replace function public.get_available_driver_delivery_offer()
returns table (
  order_id uuid,
  order_number bigint,
  store_id uuid,
  store_name text,
  store_address text,
  customer_name text,
  customer_phone text,
  delivery_address text,
  delivery_fee numeric,
  payment_method text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    o.id,
    o.order_number,
    o.store_id,
    s.name,
    s.address_text,
    o.customer_name,
    o.customer_phone,
    o.delivery_address,
    o.delivery_fee,
    o.payment_method,
    o.created_at
  from public.orders o
  join public.stores s on s.id = o.store_id
  where auth.uid() is not null
    and o.status = 'ready'
    and o.driver_id is null
    and not exists (
      select 1
      from public.driver_order_rejections r
      where r.driver_id = auth.uid()
        and r.order_id = o.id
    )
  order by o.ready_at nulls last, o.created_at
  limit 1;
$$;

create or replace function public.claim_driver_delivery_offer(p_order_id uuid)
returns table (
  order_id uuid,
  order_number bigint,
  store_id uuid,
  store_name text,
  store_address text,
  customer_name text,
  customer_phone text,
  delivery_address text,
  delivery_fee numeric,
  payment_method text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  return query
  with claimed as (
    update public.orders o
       set driver_id = auth.uid(),
           status = 'assigned',
           updated_at = now()
     where o.id = p_order_id
       and o.status = 'ready'
       and o.driver_id is null
     returning o.*
  )
  select
    c.id,
    c.order_number,
    c.store_id,
    s.name,
    s.address_text,
    c.customer_name,
    c.customer_phone,
    c.delivery_address,
    c.delivery_fee,
    c.payment_method,
    c.created_at
  from claimed c
  join public.stores s on s.id = c.store_id;

  if not found then
    raise exception 'Delivery offer is no longer available';
  end if;
end;
$$;

create or replace function public.reject_driver_delivery_offer(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  insert into public.driver_order_rejections(driver_id, order_id)
  select auth.uid(), o.id
  from public.orders o
  where o.id = p_order_id
    and o.status = 'ready'
    and o.driver_id is null
  on conflict (driver_id, order_id) do nothing;
end;
$$;

revoke all on function public.get_available_driver_delivery_offer() from public;
revoke all on function public.claim_driver_delivery_offer(uuid) from public;
revoke all on function public.reject_driver_delivery_offer(uuid) from public;

grant execute on function public.get_available_driver_delivery_offer() to authenticated;
grant execute on function public.claim_driver_delivery_offer(uuid) to authenticated;
grant execute on function public.reject_driver_delivery_offer(uuid) to authenticated;

notify pgrst, 'reload schema';

select
  to_regclass('public.driver_order_rejections') as driver_order_rejections,
  to_regprocedure('public.get_available_driver_delivery_offer()') as get_offer_rpc,
  to_regprocedure('public.claim_driver_delivery_offer(uuid)') as claim_offer_rpc,
  to_regprocedure('public.reject_driver_delivery_offer(uuid)') as reject_offer_rpc;
