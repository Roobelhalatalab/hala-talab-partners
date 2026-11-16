-- NOTE24 REVIEW ONLY - DO NOT RUN ON PRODUCTION.
-- Staging review required: triggers, RLS, role grants, and Flutter integration.
-- Product fields and explicit shift links are one PostgreSQL transaction.
create or replace function public.hala_save_product_with_shifts(
  p_store_id uuid, p_product_id uuid, p_values jsonb,
  p_selected_shift_ids uuid[], p_all_shift_ids uuid[]
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_row public.products%rowtype;
  v_saved public.products%rowtype;
  v_active uuid[];
  v_selected uuid[];
  v_all uuid[];
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.stores where id = p_store_id and owner_id = auth.uid()) then
    raise exception 'Store not owned by caller';
  end if;
  perform 1 from public.stores where id = p_store_id for update;
  select coalesce(array_agg(id order by id), '{}'::uuid[]) into v_active
    from public.store_shifts where store_id = p_store_id and is_active = true;
  select coalesce(array_agg(distinct x order by x), '{}'::uuid[]) into v_selected
    from unnest(coalesce(p_selected_shift_ids, '{}'::uuid[])) x;
  select coalesce(array_agg(distinct x order by x), '{}'::uuid[]) into v_all
    from unnest(coalesce(p_all_shift_ids, '{}'::uuid[])) x;
  if cardinality(v_active) = 0 or v_all <> v_active or cardinality(v_selected) = 0
     or exists(select 1 from unnest(v_selected) x where not (x = any(v_active))) then
    raise exception 'Shift configuration changed or invalid; reload';
  end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception 'Invalid product payload';
  end if;
  if exists (select 1 from jsonb_object_keys(p_values) k where k not in ('store_id', 'name', 'description', 'category_name', 'price', 'image_url', 'is_available', 'sort_order', 'image_path', 'preparation_time_minutes', 'calories', 'notes', 'tags', 'product_type', 'brand', 'barcode', 'sku', 'unit', 'track_stock', 'stock_quantity', 'size_label', 'weight_value', 'weight_unit', 'catalog_kind', 'category_id', 'min_order_quantity', 'quantity_step', 'min_quantity')) then
    raise exception 'Unsupported product field';
  end if;
  if p_values->>'store_id' is distinct from p_store_id::text then
    raise exception 'Store mismatch';
  end if;
  v_row := jsonb_populate_record(null::public.products, p_values);
  if nullif(btrim(v_row.name),'') is null or v_row.price is null or v_row.price < 0
     or v_row.min_quantity is null or v_row.min_quantity <= 0
     or v_row.quantity_step is null or v_row.quantity_step <= 0 then
    raise exception 'Invalid product fields';
  end if;
  if v_row.category_id is not null and not exists (
    select 1 from public.product_categories where id = v_row.category_id and store_id = p_store_id
  ) then raise exception 'Category not in store'; end if;
  if p_product_id is null then
    insert into public.products (store_id, name, description, category_name, price, image_url, is_available, sort_order, image_path, preparation_time_minutes, calories, notes, tags, product_type, brand, barcode, sku, unit, track_stock, stock_quantity, size_label, weight_value, weight_unit, catalog_kind, category_id, min_order_quantity, quantity_step, min_quantity)
      values (v_row.store_id, v_row.name, v_row.description, v_row.category_name, v_row.price, v_row.image_url, v_row.is_available, v_row.sort_order, v_row.image_path, v_row.preparation_time_minutes, v_row.calories, v_row.notes, v_row.tags, v_row.product_type, v_row.brand, v_row.barcode, v_row.sku, v_row.unit, v_row.track_stock, v_row.stock_quantity, v_row.size_label, v_row.weight_value, v_row.weight_unit, v_row.catalog_kind, v_row.category_id, v_row.min_order_quantity, v_row.quantity_step, v_row.min_quantity) returning * into v_saved;
  else
    update public.products set
      name = v_row.name,
      description = v_row.description,
      category_name = v_row.category_name,
      price = v_row.price,
      image_url = v_row.image_url,
      is_available = v_row.is_available,
      sort_order = v_row.sort_order,
      image_path = v_row.image_path,
      preparation_time_minutes = v_row.preparation_time_minutes,
      calories = v_row.calories,
      notes = v_row.notes,
      tags = v_row.tags,
      product_type = v_row.product_type,
      brand = v_row.brand,
      barcode = v_row.barcode,
      sku = v_row.sku,
      unit = v_row.unit,
      track_stock = v_row.track_stock,
      stock_quantity = v_row.stock_quantity,
      size_label = v_row.size_label,
      weight_value = v_row.weight_value,
      weight_unit = v_row.weight_unit,
      catalog_kind = v_row.catalog_kind,
      category_id = v_row.category_id,
      min_order_quantity = v_row.min_order_quantity,
      quantity_step = v_row.quantity_step,
      min_quantity = v_row.min_quantity
    where id = p_product_id and store_id = p_store_id returning * into v_saved;
    if not found then raise exception 'Product not found in store'; end if;
  end if;
  delete from public.store_product_shifts where product_id = v_saved.id;
  insert into public.store_product_shifts(product_id, shift_id)
    select v_saved.id, unnest(v_selected);
  return to_jsonb(v_saved);
end; $$;
revoke all on function public.hala_save_product_with_shifts(uuid,uuid,jsonb,uuid[],uuid[]) from public;
grant execute on function public.hala_save_product_with_shifts(uuid,uuid,jsonb,uuid[],uuid[]) to authenticated;
