-- Hala Talab Client Stage 52
-- Expose merchant product notes + selling unit/size/weight to the customer catalog.
-- Safe to run after the existing customer catalog stages.

begin;

drop function if exists public.customer_catalog_products(uuid, uuid);

create function public.customer_catalog_products(
  p_store_id uuid default null,
  p_product_id uuid default null
)
returns table (
  id uuid,
  store_id uuid,
  category_id text,
  category_name text,
  name text,
  description text,
  price numeric,
  image_url text,
  is_available boolean,
  sort_order integer,
  notes text,
  unit text,
  size_label text,
  weight_value numeric,
  weight_unit text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_store_id is null and p_product_id is null then
    raise exception 'Store id or product id is required';
  end if;

  return query
  select
    p.id,
    p.store_id,
    coalesce(c.id::text, 'category:' || lower(btrim(coalesce(p.category_name, 'other')))) as category_id,
    coalesce(p.category_name, ''),
    p.name,
    coalesce(p.description, ''),
    p.price,
    p.image_url,
    p.is_available,
    p.sort_order,
    p.notes,
    coalesce(p.unit, 'piece'),
    p.size_label,
    p.weight_value,
    p.weight_unit
  from public.products p
  join public.stores s on s.id = p.store_id
  left join lateral (
    select pc.id
    from public.product_categories pc
    where pc.store_id = p.store_id
      and pc.is_active = true
      and lower(btrim(pc.name)) = lower(btrim(coalesce(p.category_name, '')))
    order by pc.sort_order nulls last, pc.created_at
    limit 1
  ) c on true
  where (p_store_id is null or p.store_id = p_store_id)
    and (p_product_id is null or p.id = p_product_id)
    and p.is_available = true
    and (coalesce(p.track_stock, false) = false or coalesce(p.stock_quantity, 0) > 0)
    and s.approval_status = 'approved'
    and s.is_active = true
  order by p.sort_order nulls last, p.created_at, p.name;
end;
$$;

revoke all on function public.customer_catalog_products(uuid, uuid) from public;
grant execute on function public.customer_catalog_products(uuid, uuid) to anon, authenticated;

commit;

select
  to_regprocedure('public.customer_catalog_products(uuid,uuid)') is not null as product_notes_units_ready;
