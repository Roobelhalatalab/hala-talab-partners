-- Hala Talab Partners - Stage 127
-- Store menu category ordering + customer-visible order.
-- Idempotent and safe to run once after Stage 126.

alter table public.product_categories
  add column if not exists sort_order integer;

-- Normalize every store's existing categories to 1..N, preserving the old
-- visible order as much as possible (existing sort_order first, then creation).
with ranked as (
  select
    id,
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

alter table public.product_categories
  alter column sort_order set default 1;

create index if not exists product_categories_store_sort_idx
  on public.product_categories(store_id, sort_order, created_at);

-- Customer catalog must expose the exact order chosen by the store owner.
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
  select
    c.id,
    c.store_id,
    c.name,
    c.is_active,
    coalesce(c.sort_order, 999999) as sort_order
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
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'product_categories'
      and column_name = 'sort_order'
  ) as menu_category_order_ready,
  (select count(*) from public.product_categories) as total_menu_categories;
