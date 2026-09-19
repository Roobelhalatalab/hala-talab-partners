-- Hala Talab Partners - Stage 65
-- Final offers/coupons rules and reusable checkout discount quote.
-- Safe migration: no existing offer/coupon/order data is deleted.

create extension if not exists pgcrypto;

-- Keep legacy Stage 20 tables compatible and strengthen their constraints/indexes.
alter table public.coupons add column if not exists per_customer_limit integer;
alter table public.coupons add column if not exists updated_at timestamptz not null default now();
alter table public.store_promotions add column if not exists updated_at timestamptz not null default now();

do $$ begin
  if not exists (select 1 from pg_constraint where conname='coupons_max_discount_positive') then
    alter table public.coupons add constraint coupons_max_discount_positive check (max_discount is null or max_discount > 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='coupons_per_customer_limit_positive') then
    alter table public.coupons add constraint coupons_per_customer_limit_positive check (per_customer_limit is null or per_customer_limit > 0);
  end if;
end $$;

create unique index if not exists coupons_store_code_upper_uidx
  on public.coupons(store_id, upper(code));
create index if not exists promotions_active_window_idx
  on public.store_promotions(store_id, is_active, start_at, end_at);
create index if not exists coupons_active_window_idx
  on public.coupons(store_id, is_active, start_at, end_at);

-- Usage ledger. This will be written by the secure customer-order function when
-- customer checkout is finalized; the store app can already read aggregate counts.
create table if not exists public.coupon_usages (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id) on delete cascade,
  order_id uuid references public.orders(id) on delete cascade,
  customer_id uuid references auth.users(id) on delete set null,
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  created_at timestamptz not null default now(),
  unique (coupon_id, order_id)
);
create index if not exists coupon_usages_coupon_idx on public.coupon_usages(coupon_id, created_at desc);
create index if not exists coupon_usages_customer_idx on public.coupon_usages(customer_id, coupon_id);
alter table public.coupon_usages enable row level security;

drop policy if exists "owners read own coupon usages" on public.coupon_usages;
create policy "owners read own coupon usages" on public.coupon_usages
for select to authenticated
using (exists (
  select 1 from public.coupons c
  join public.stores s on s.id = c.store_id
  where c.id = coupon_usages.coupon_id and s.owner_id = auth.uid()
));

drop policy if exists "customers read own coupon usages" on public.coupon_usages;
create policy "customers read own coupon usages" on public.coupon_usages
for select to authenticated using (customer_id = auth.uid());

-- Updated timestamps.
drop trigger if exists store_promotions_set_updated_at on public.store_promotions;
create trigger store_promotions_set_updated_at before update on public.store_promotions
for each row execute function public.set_updated_at();
drop trigger if exists coupons_set_updated_at on public.coupons;
create trigger coupons_set_updated_at before update on public.coupons
for each row execute function public.set_updated_at();

-- Owners may only manage rows that belong to their own store.
alter table public.store_promotions enable row level security;
alter table public.coupons enable row level security;
drop policy if exists "owners manage own promotions" on public.store_promotions;
create policy "owners manage own promotions" on public.store_promotions
for all to authenticated
using (exists (select 1 from public.stores s where s.id=store_promotions.store_id and s.owner_id=auth.uid()))
with check (exists (select 1 from public.stores s where s.id=store_promotions.store_id and s.owner_id=auth.uid()));
drop policy if exists "owners manage own coupons" on public.coupons;
create policy "owners manage own coupons" on public.coupons
for all to authenticated
using (exists (select 1 from public.stores s where s.id=coupons.store_id and s.owner_id=auth.uid()))
with check (exists (select 1 from public.stores s where s.id=coupons.store_id and s.owner_id=auth.uid()));

-- Public/client visibility is limited to currently usable records.
drop policy if exists "public reads active promotions" on public.store_promotions;
create policy "public reads active promotions" on public.store_promotions
for select to anon, authenticated
using (is_active and now() >= start_at and now() < end_at);
drop policy if exists "public reads active coupons" on public.coupons;
create policy "public reads active coupons" on public.coupons
for select to anon, authenticated
using (is_active and now() >= start_at and now() < end_at and (usage_limit is null or used_count < usage_limit));

-- Returns one authoritative discount quote. Offers and coupons do NOT stack:
-- the larger valid discount is selected. This prevents accidental double-discounting.
create or replace function public.quote_store_discount(
  p_store_id uuid,
  p_subtotal numeric,
  p_coupon_code text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subtotal numeric(12,2) := greatest(coalesce(p_subtotal,0),0);
  v_offer public.store_promotions;
  v_coupon public.coupons;
  v_offer_discount numeric(12,2) := 0;
  v_coupon_discount numeric(12,2) := 0;
  v_customer_uses integer := 0;
begin
  if not exists (select 1 from public.stores s where s.id=p_store_id) then
    raise exception 'Store not found';
  end if;

  select sp.* into v_offer
  from public.store_promotions sp
  where sp.store_id=p_store_id and sp.is_active
    and now() >= sp.start_at and now() < sp.end_at
    and v_subtotal >= sp.minimum_order
  order by
    case when sp.discount_type='percentage' then v_subtotal*sp.discount_value/100 else sp.discount_value end desc,
    sp.created_at desc
  limit 1;

  if found then
    v_offer_discount := case when v_offer.discount_type='percentage'
      then round(v_subtotal*v_offer.discount_value/100,2)
      else v_offer.discount_value end;
    v_offer_discount := least(v_offer_discount,v_subtotal);
  end if;

  if nullif(trim(coalesce(p_coupon_code,'')),'') is not null then
    select c.* into v_coupon
    from public.coupons c
    where c.store_id=p_store_id and upper(c.code)=upper(trim(p_coupon_code))
      and c.is_active and now() >= c.start_at and now() < c.end_at
      and v_subtotal >= c.minimum_order
      and (c.usage_limit is null or c.used_count < c.usage_limit)
    limit 1;

    if found then
      if v_coupon.per_customer_limit is not null and auth.uid() is not null then
        select count(*)::integer into v_customer_uses
        from public.coupon_usages cu
        where cu.coupon_id=v_coupon.id and cu.customer_id=auth.uid();
        if v_customer_uses >= v_coupon.per_customer_limit then
          v_coupon := null;
        end if;
      end if;
    end if;

    if v_coupon.id is not null then
      v_coupon_discount := case when v_coupon.discount_type='percentage'
        then round(v_subtotal*v_coupon.discount_value/100,2)
        else v_coupon.discount_value end;
      if v_coupon.max_discount is not null then
        v_coupon_discount := least(v_coupon_discount,v_coupon.max_discount);
      end if;
      v_coupon_discount := least(v_coupon_discount,v_subtotal);
    end if;
  end if;

  if v_coupon_discount > v_offer_discount then
    return jsonb_build_object(
      'discount_amount',v_coupon_discount,'source','coupon',
      'coupon_id',v_coupon.id,'promotion_id',null,'title',v_coupon.title,
      'code',v_coupon.code,'subtotal',v_subtotal,'total_after_discount',greatest(v_subtotal-v_coupon_discount,0)
    );
  elsif v_offer_discount > 0 then
    return jsonb_build_object(
      'discount_amount',v_offer_discount,'source','promotion',
      'coupon_id',null,'promotion_id',v_offer.id,'title',v_offer.title,
      'code',null,'subtotal',v_subtotal,'total_after_discount',greatest(v_subtotal-v_offer_discount,0)
    );
  end if;

  return jsonb_build_object(
    'discount_amount',0,'source','none','coupon_id',null,'promotion_id',null,
    'title',null,'code',null,'subtotal',v_subtotal,'total_after_discount',v_subtotal
  );
end;
$$;

revoke all on function public.quote_store_discount(uuid,numeric,text) from public;
grant execute on function public.quote_store_discount(uuid,numeric,text) to anon, authenticated;

notify pgrst, 'reload schema';
select
  to_regclass('public.store_promotions') as store_promotions,
  to_regclass('public.coupons') as coupons,
  to_regclass('public.coupon_usages') as coupon_usages,
  to_regprocedure('public.quote_store_discount(uuid,numeric,text)') as quote_store_discount,
  true as stage_65_ready;
