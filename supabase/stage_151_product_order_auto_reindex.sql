-- Hala Talab Partners - Stage 151
-- Guarantees unique, gap-free product ordering inside each store/category.
-- Choosing an occupied position shifts the other products automatically.
-- Safe to run more than once.

alter table public.products
  add column if not exists sort_order integer;

-- First repair all existing duplicate / missing positions to 1..N per category.
with ranked as (
  select id,
         row_number() over (
           partition by store_id, coalesce(category_name, '')
           order by sort_order nulls last, created_at, name, id
         )::integer as new_order
  from public.products
)
update public.products p
set sort_order = ranked.new_order
from ranked
where p.id = ranked.id
  and p.sort_order is distinct from ranked.new_order;

-- One product position may appear only once inside the same store/category.
create unique index if not exists products_store_category_sort_unique_idx
  on public.products (store_id, (coalesce(category_name, '')), sort_order)
  where sort_order is not null;

create or replace function public.store_normalize_product_positions(
  p_store_id uuid,
  p_category_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select s.owner_id into v_owner
  from public.stores s
  where s.id = p_store_id;

  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not allowed to reorder products for this store';
  end if;

  create temporary table if not exists pg_temp.hala_product_order_fix (
    id uuid primary key,
    new_pos integer not null unique
  ) on commit drop;
  truncate pg_temp.hala_product_order_fix;

  insert into pg_temp.hala_product_order_fix(id, new_pos)
  select id,
         row_number() over (
           order by sort_order nulls last, created_at, name, id
         )::integer
  from public.products
  where store_id = p_store_id
    and coalesce(category_name, '') = coalesce(trim(p_category_name), '');

  -- Temporary unique negative values avoid collisions with the unique index.
  update public.products p
  set sort_order = -1000000 - f.new_pos
  from pg_temp.hala_product_order_fix f
  where p.id = f.id
    and p.store_id = p_store_id;

  update public.products p
  set sort_order = f.new_pos
  from pg_temp.hala_product_order_fix f
  where p.id = f.id
    and p.store_id = p_store_id;
end;
$$;

grant execute on function public.store_normalize_product_positions(uuid, text) to authenticated;

create or replace function public.store_set_product_position(
  p_store_id uuid,
  p_product_id uuid,
  p_position integer
)
returns void
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

  select s.owner_id into v_owner
  from public.stores s
  where s.id = p_store_id;

  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not allowed to reorder products for this store';
  end if;

  select coalesce(p.category_name, '') into v_category
  from public.products p
  where p.id = p_product_id
    and p.store_id = p_store_id;

  if not found then
    raise exception 'Product not found';
  end if;

  -- Serialize reordering inside this store to avoid concurrent duplicates.
  perform pg_advisory_xact_lock(hashtext(p_store_id::text));

  select count(*) into v_count
  from public.products
  where store_id = p_store_id
    and coalesce(category_name, '') = v_category;

  v_target := least(greatest(p_position, 1), greatest(v_count, 1));

  create temporary table if not exists pg_temp.hala_product_order_target (
    id uuid primary key,
    new_pos integer not null unique
  ) on commit drop;
  truncate pg_temp.hala_product_order_target;

  -- Build the final order in memory: remove the selected product, then insert
  -- it at the requested position. Everyone after it shifts by one.
  insert into pg_temp.hala_product_order_target(id, new_pos)
  with others as (
    select id,
           row_number() over (
             order by sort_order nulls last, created_at, name, id
           )::integer as old_pos
    from public.products
    where store_id = p_store_id
      and coalesce(category_name, '') = v_category
      and id <> p_product_id
  )
  select id,
         case when old_pos < v_target then old_pos else old_pos + 1 end
  from others
  union all
  select p_product_id, v_target;

  -- Move every row to a unique temporary negative position first, then commit
  -- the final 1..N values. This remains valid even with the unique index above.
  update public.products p
  set sort_order = -1000000 - f.new_pos
  from pg_temp.hala_product_order_target f
  where p.id = f.id
    and p.store_id = p_store_id;

  update public.products p
  set sort_order = f.new_pos
  from pg_temp.hala_product_order_target f
  where p.id = f.id
    and p.store_id = p_store_id;
end;
$$;

grant execute on function public.store_set_product_position(uuid, uuid, integer) to authenticated;

notify pgrst, 'reload schema';

select
  true as product_order_auto_reindex_ready,
  count(*) as total_products,
  count(*) filter (where sort_order is null) as products_without_order
from public.products;
