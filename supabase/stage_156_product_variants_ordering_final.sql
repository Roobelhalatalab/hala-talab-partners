-- Hala Talab Partners - Stage 156
-- Final product variants + editable ordering migration.
-- This version intentionally does NOT use pg_temp tables, so it can be pasted
-- into Supabase SQL Editor and safely re-run without temp-relation failures.

begin;

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  name text not null,
  price numeric(14,2) not null check (price >= 0),
  sort_order integer not null check (sort_order >= 1),
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists product_variants_product_sort_unique_idx
  on public.product_variants(product_id, sort_order);
create unique index if not exists product_variants_product_name_unique_idx
  on public.product_variants(product_id, lower(btrim(name)));

alter table public.product_variants enable row level security;
drop policy if exists product_variants_read on public.product_variants;
create policy product_variants_read
on public.product_variants
for select
using (
  is_available = true
  or exists (
    select 1
    from public.products p
    join public.stores s on s.id = p.store_id
    where p.id = product_variants.product_id
      and s.owner_id = auth.uid()
  )
);
grant select on public.product_variants to anon, authenticated;

create or replace function public.store_replace_product_variants_v2(
  p_store_id uuid,
  p_product_id uuid,
  p_variants jsonb
)
returns table(variant_id uuid, name text, price numeric, sort_order integer, is_available boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_variants jsonb := coalesce(p_variants, '[]'::jsonb);
begin
  select s.owner_id into v_owner from public.stores s where s.id = p_store_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not allowed to edit product variants for this store';
  end if;
  if not exists (select 1 from public.products p where p.id = p_product_id and p.store_id = p_store_id) then
    raise exception 'Product not found';
  end if;
  if jsonb_typeof(v_variants) <> 'array' then raise exception 'Variants must be a JSON array'; end if;
  if jsonb_array_length(v_variants) > 50 then raise exception 'A product cannot have more than 50 variants'; end if;

  if exists (
    select 1
    from jsonb_array_elements(v_variants) v(item)
    where btrim(v.item->>'name') = ''
       or char_length(btrim(v.item->>'name')) > 80
       or nullif(v.item->>'price','') is null
       or (v.item->>'price')::numeric < 0
  ) then
    raise exception 'Each variant needs a valid name and non-negative price';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_variants) v(item)
    group by lower(btrim(v.item->>'name'))
    having count(*) > 1
  ) then
    raise exception 'Variant names must be unique inside a product';
  end if;

  delete from public.product_variants where product_id = p_product_id;

  insert into public.product_variants(product_id, name, price, sort_order, is_available, updated_at)
  select p_product_id,
         btrim(v.item->>'name'),
         (v.item->>'price')::numeric(14,2),
         v.ordinality::integer,
         coalesce((v.item->>'is_available')::boolean, true),
         now()
  from jsonb_array_elements(v_variants) with ordinality as v(item, ordinality);

  return query
  select pv.id, pv.name, pv.price, pv.sort_order, pv.is_available
  from public.product_variants pv
  where pv.product_id = p_product_id
  order by pv.sort_order;
end;
$$;
grant execute on function public.store_replace_product_variants_v2(uuid, uuid, jsonb) to authenticated;

-- Normalize every existing product group to 1..N. Set NULL first so no old
-- duplicate can conflict while the final sequence is written.
alter table public.products add column if not exists sort_order integer;
drop index if exists public.products_store_category_sort_unique_idx;

with ranked as (
  select id,
         row_number() over (
           partition by store_id, coalesce(category_name, '')
           order by sort_order nulls last, created_at, name, id
         )::integer as new_pos
  from public.products
)
update public.products p
set sort_order = -7000000 - r.new_pos
from ranked r
where p.id = r.id;

update public.products
set sort_order = -(sort_order + 7000000)
where sort_order <= -7000001;

create unique index products_store_category_sort_unique_idx
  on public.products (store_id, (coalesce(category_name, '')), sort_order)
  where sort_order is not null;

create or replace function public.store_set_product_position_v4(
  p_store_id uuid,
  p_product_id uuid,
  p_position integer
)
returns table(product_id uuid, sort_order integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_category text;
  v_count integer;
  v_target integer;
begin
  if p_position is null or p_position < 1 then raise exception 'Position must be 1 or greater'; end if;
  select s.owner_id into v_owner from public.stores s where s.id = p_store_id;
  if v_owner is null or v_owner <> auth.uid() then raise exception 'Not allowed to reorder products for this store'; end if;

  select coalesce(p.category_name, '') into v_category
  from public.products p
  where p.id = p_product_id and p.store_id = p_store_id;
  if not found then raise exception 'Product not found'; end if;

  perform pg_advisory_xact_lock(hashtext('hala-product-order-v4:' || p_store_id::text || ':' || v_category));

  select count(*) into v_count
  from public.products
  where store_id = p_store_id and coalesce(category_name, '') = v_category;
  v_target := least(greatest(p_position, 1), greatest(v_count, 1));

  -- Move the whole group to a unique negative range first.  This preserves
  -- the current order and leaves every positive slot free, so 1->5 / 5->1
  -- cannot collide with the unique index.
  update public.products
  set sort_order = -8000000 - coalesce(sort_order, 0)
  where store_id = p_store_id and coalesce(category_name, '') = v_category;

  with ordered_others as (
    select id,
           row_number() over (order by sort_order desc, created_at, name, id)::integer as pos
    from public.products
    where store_id = p_store_id
      and coalesce(category_name, '') = v_category
      and id <> p_product_id
  ), final_positions as (
    select id, case when pos < v_target then pos else pos + 1 end as new_pos
    from ordered_others
    union all
    select p_product_id, v_target
  )
  update public.products p
  set sort_order = f.new_pos
  from final_positions f
  where p.id = f.id;

  return query
  select p.id, p.sort_order
  from public.products p
  where p.store_id = p_store_id and coalesce(p.category_name, '') = v_category
  order by p.sort_order, p.created_at, p.name, p.id;
end;
$$;
grant execute on function public.store_set_product_position_v4(uuid, uuid, integer) to authenticated;

notify pgrst, 'reload schema';
commit;

select
  true as stage_156_ready,
  (select count(*) from public.product_variants) as total_variants,
  (select count(*) from public.products where sort_order is null) as products_without_order,
  (
    select count(*) from (
      select store_id, coalesce(category_name, '') as category_name, sort_order
      from public.products
      where sort_order is not null
      group by store_id, coalesce(category_name, ''), sort_order
      having count(*) > 1
    ) d
  ) as duplicate_groups;
