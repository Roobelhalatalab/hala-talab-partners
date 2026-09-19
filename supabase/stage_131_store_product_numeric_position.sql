-- Hala Talab Partners - Stage 131
-- Numeric ordering for products inside each store menu category.
-- Store owner controls the numeric position; customers only see the resulting order.
-- Safe/idempotent and compatible with Stage 130 category ordering.

alter table public.products
  add column if not exists sort_order integer;

-- Normalize existing products to 1..N inside each store/category.
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

create index if not exists products_store_category_sort_idx
  on public.products(store_id, category_name, sort_order, created_at);

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

  with ranked as (
    select id,
           row_number() over (
             order by sort_order nulls last, created_at, name, id
           )::integer as new_order
    from public.products
    where store_id = p_store_id
      and coalesce(category_name, '') = coalesce(trim(p_category_name), '')
  )
  update public.products p
  set sort_order = ranked.new_order
  from ranked
  where p.id = ranked.id;
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

  -- Normalize every category first. This also closes gaps in an old category
  -- when an edited product was moved to another category before this RPC runs.
  with ranked as (
    select id,
           row_number() over (
             partition by coalesce(category_name, '')
             order by sort_order nulls last, created_at, name, id
           )::integer as new_order
    from public.products
    where store_id = p_store_id
  )
  update public.products p
  set sort_order = ranked.new_order
  from ranked
  where p.id = ranked.id;

  select count(*) into v_count
  from public.products
  where store_id = p_store_id
    and coalesce(category_name, '') = v_category;

  v_target := least(greatest(p_position, 1), greatest(v_count, 1));

  -- Rebuild only this category with the selected product at the requested slot.
  with ordered as (
    select id,
           row_number() over (
             order by sort_order nulls last, created_at, name, id
           )::integer as old_pos
    from public.products
    where store_id = p_store_id
      and coalesce(category_name, '') = v_category
      and id <> p_product_id
  ), final_positions as (
    select id,
           case when old_pos < v_target then old_pos else old_pos + 1 end as new_pos
    from ordered
    union all
    select p_product_id, v_target
  )
  update public.products p
  set sort_order = -1000000 - fp.new_pos
  from final_positions fp
  where p.id = fp.id
    and p.store_id = p_store_id;

  update public.products
  set sort_order = abs(sort_order + 1000000)
  where store_id = p_store_id
    and coalesce(category_name, '') = v_category
    and sort_order < 0;
end;
$$;

grant execute on function public.store_set_product_position(uuid, uuid, integer) to authenticated;

notify pgrst, 'reload schema';

select
  true as product_numeric_order_ready,
  (select count(*) from public.products) as total_products;
