-- Hala Talab Partners - Stage 130 (built from stable Stage 127)
-- Numeric menu category positioning for store owners.
-- Safe/idempotent. Keeps customer display ordered by sort_order without showing numbers.

alter table public.product_categories
  add column if not exists sort_order integer;

-- Normalize current rows first.
with ranked as (
  select id,
         row_number() over (
           partition by store_id
           order by sort_order nulls last, created_at, name, id
         )::integer as new_order
  from public.product_categories
)
update public.product_categories pc
set sort_order = ranked.new_order
from ranked
where pc.id = ranked.id
  and pc.sort_order is distinct from ranked.new_order;

create index if not exists product_categories_store_sort_idx
  on public.product_categories(store_id, sort_order, created_at);

create or replace function public.store_set_menu_category_position(
  p_store_id uuid,
  p_category_id uuid,
  p_position integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
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
    raise exception 'Not allowed to reorder this store';
  end if;

  if not exists (
    select 1 from public.product_categories c
    where c.id = p_category_id and c.store_id = p_store_id
  ) then
    raise exception 'Category not found';
  end if;

  select count(*) into v_count
  from public.product_categories
  where store_id = p_store_id;

  v_target := least(greatest(p_position, 1), greatest(v_count, 1));

  -- Rebuild the full list with the selected category placed exactly at v_target.
  with ordered as (
    select id,
           row_number() over (order by sort_order nulls last, created_at, name, id)::integer as old_pos
    from public.product_categories
    where store_id = p_store_id and id <> p_category_id
  ), final_positions as (
    select id,
           case when old_pos < v_target then old_pos else old_pos + 1 end as new_pos
    from ordered
    union all
    select p_category_id, v_target
  )
  update public.product_categories pc
  set sort_order = -1000000 - fp.new_pos
  from final_positions fp
  where pc.id = fp.id and pc.store_id = p_store_id;

  update public.product_categories
  set sort_order = abs(sort_order + 1000000)
  where store_id = p_store_id and sort_order < 0;
end;
$$;

grant execute on function public.store_set_menu_category_position(uuid, uuid, integer) to authenticated;

-- Keep customer view ordered only; numeric values are not exposed in UI by this change.
create or replace function public.customer_catalog_categories(p_store_id uuid)
returns table (
  id uuid,
  store_id uuid,
  name text,
  is_active boolean,
  sort_order integer
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.store_id, c.name, c.is_active, coalesce(c.sort_order, 999999)
  from public.product_categories c
  join public.stores s on s.id = c.store_id
  where c.store_id = p_store_id
    and c.is_active = true
    and s.approval_status = 'approved'
    and s.is_active = true
  order by coalesce(c.sort_order, 999999), c.created_at, c.name;
$$;

grant execute on function public.customer_catalog_categories(uuid) to anon, authenticated;

notify pgrst, 'reload schema';

select
  true as numeric_menu_position_ready,
  (select count(*) from public.product_categories) as total_menu_categories;
