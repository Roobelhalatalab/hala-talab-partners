-- Hala Talab Partners - Stage 152
-- Final product sequence repair.
-- 1) Repairs every existing duplicate/gap to 1..N per store/category.
-- 2) Enforces one unique position per store/category.
-- 3) Uses a new, unambiguous RPC so old cached function versions cannot win.
-- Safe to run more than once.

alter table public.products add column if not exists sort_order integer;

-- Remove the previous index while we repair any rows that were created before
-- the Stage 151 RPC was active.
drop index if exists public.products_store_category_sort_unique_idx;

-- Two-phase normalization prevents collisions even when the table already has
-- duplicate or partially ordered data.
create temporary table if not exists pg_temp.hala_stage152_all_orders (
  id uuid primary key,
  new_pos integer not null
) on commit drop;
truncate pg_temp.hala_stage152_all_orders;

insert into pg_temp.hala_stage152_all_orders(id, new_pos)
select id,
       row_number() over (
         partition by store_id, coalesce(category_name, '')
         order by sort_order nulls last, created_at, name, id
       )::integer
from public.products;

update public.products p
set sort_order = -2000000 - f.new_pos
from pg_temp.hala_stage152_all_orders f
where p.id = f.id;

update public.products p
set sort_order = f.new_pos
from pg_temp.hala_stage152_all_orders f
where p.id = f.id;

create unique index products_store_category_sort_unique_idx
  on public.products (store_id, (coalesce(category_name, '')), sort_order)
  where sort_order is not null;

create or replace function public.store_set_product_position_v2(
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
  if p_position is null or p_position < 1 then
    raise exception 'Position must be 1 or greater';
  end if;

  select s.owner_id into v_owner from public.stores s where s.id = p_store_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not allowed to reorder products for this store';
  end if;

  select coalesce(p.category_name, '') into v_category
  from public.products p
  where p.id = p_product_id and p.store_id = p_store_id;
  if not found then raise exception 'Product not found'; end if;

  -- One writer at a time for a store. This closes the race that could allow
  -- two rapid saves to compete for the same position.
  perform pg_advisory_xact_lock(hashtext('hala-product-order:' || p_store_id::text));

  select count(*) into v_count
  from public.products
  where store_id = p_store_id and coalesce(category_name, '') = v_category;
  v_target := least(greatest(p_position, 1), greatest(v_count, 1));

  create temporary table if not exists pg_temp.hala_stage152_target (
    id uuid primary key,
    new_pos integer not null unique
  ) on commit drop;
  truncate pg_temp.hala_stage152_target;

  insert into pg_temp.hala_stage152_target(id, new_pos)
  with others as (
    select id,
           row_number() over (
             order by sort_order nulls last, created_at, name, id
           )::integer as pos
    from public.products
    where store_id = p_store_id
      and coalesce(category_name, '') = v_category
      and id <> p_product_id
  )
  select id, case when pos < v_target then pos else pos + 1 end from others
  union all
  select p_product_id, v_target;

  -- Move all rows out of the positive range first so the unique index cannot
  -- collide while positions are shifting.
  update public.products p
  set sort_order = -3000000 - f.new_pos
  from pg_temp.hala_stage152_target f
  where p.id = f.id and p.store_id = p_store_id;

  update public.products p
  set sort_order = f.new_pos
  from pg_temp.hala_stage152_target f
  where p.id = f.id and p.store_id = p_store_id;

  return query
  select p.id, p.sort_order
  from public.products p
  where p.store_id = p_store_id and coalesce(p.category_name, '') = v_category
  order by p.sort_order, p.created_at, p.name, p.id;
end;
$$;

grant execute on function public.store_set_product_position_v2(uuid, uuid, integer) to authenticated;

notify pgrst, 'reload schema';

-- Final diagnostic: duplicate_groups must be 0.
select
  true as product_order_final_fix_ready,
  count(*) as total_products,
  count(*) filter (where sort_order is null) as products_without_order,
  (
    select count(*)
    from (
      select store_id, coalesce(category_name, '') as category_name, sort_order
      from public.products
      where sort_order is not null
      group by store_id, coalesce(category_name, ''), sort_order
      having count(*) > 1
    ) d
  ) as duplicate_groups
from public.products;
