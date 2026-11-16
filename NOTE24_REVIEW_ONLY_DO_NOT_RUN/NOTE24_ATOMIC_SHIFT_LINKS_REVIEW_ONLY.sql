-- REVIEW ONLY: DO NOT EXECUTE ON PRODUCTION.
-- Prerequisites: public.stores.owner_id, store_category_shifts, store_product_shifts,
-- store_shifts and auth.uid() ownership semantics must be verified on staging.
-- Atomic replacement: explicitly store every selected shift, including all shifts.
-- Legacy empty-link convention remains readable, but new saves never create ambiguity.
create or replace function public.hala_replace_shift_links(
  p_entity text,
  p_entity_id uuid,
  p_selected_shift_ids uuid[],
  p_all_shift_ids uuid[]
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_store_id uuid;
  v_active uuid[];
  v_selected uuid[];
  v_all uuid[];
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_entity not in ('category', 'product') then raise exception 'Unsupported entity'; end if;
  if p_entity = 'category' then
    select store_id into v_store_id from public.product_categories where id = p_entity_id;
  else
    select store_id into v_store_id from public.products where id = p_entity_id;
  end if;
  if v_store_id is null or not exists (
    select 1 from public.stores where id = v_store_id and owner_id = auth.uid()
  ) then raise exception 'Entity not owned by current store'; end if;

  -- Lock the parent store to serialize concurrent updates to its shift configuration.
  perform 1 from public.stores where id = v_store_id for update;
  select coalesce(array_agg(id order by id), '{}'::uuid[]) into v_active
  from public.store_shifts where store_id = v_store_id and is_active = true;
  select coalesce(array_agg(distinct x order by x), '{}'::uuid[]) into v_selected
  from unnest(coalesce(p_selected_shift_ids, '{}'::uuid[])) as x;
  select coalesce(array_agg(distinct x order by x), '{}'::uuid[]) into v_all
  from unnest(coalesce(p_all_shift_ids, '{}'::uuid[])) as x;

  if v_all <> v_active then raise exception 'Shift list changed; reload and retry'; end if;
  if exists (select 1 from unnest(v_selected) x where not (x = any(v_active))) then
    raise exception 'Selected shift is not active in this store';
  end if;
  if cardinality(v_selected) = 0 and cardinality(v_active) > 0 then
    raise exception 'Choose at least one shift or explicitly select all';
  end if;
  -- Keep explicit links for all selected shifts; avoid ambiguous empty-link writes.
  if p_entity = 'category' then
    -- Keep the legacy field consistent with explicit links. A shared/all-shifts
    -- category has no single legacy shift, so use NULL (not an arbitrary shift).
    -- Suppress the fallback trigger for this transaction.
    perform set_config('hala.skip_category_shift_sync', 'on', true);
    update public.product_categories
      set shift_id = case when v_selected = v_active then null else v_selected[1] end
      where id = p_entity_id and store_id = v_store_id;
    if not found then raise exception 'Category disappeared during save'; end if;
    delete from public.store_category_shifts where category_id = p_entity_id;
    insert into public.store_category_shifts(category_id, shift_id)
      select p_entity_id, unnest(v_selected);
  else
    delete from public.store_product_shifts where product_id = p_entity_id;
    insert into public.store_product_shifts(product_id, shift_id)
      select p_entity_id, unnest(v_selected);
  end if;
end; $$;
revoke all on function public.hala_replace_shift_links(text,uuid,uuid[],uuid[]) from public;
revoke all on function public.hala_replace_shift_links(text,uuid,uuid[],uuid[]) from anon;
grant execute on function public.hala_replace_shift_links(text,uuid,uuid[],uuid[]) to authenticated;

-- NOTE 24: unified non-destructive legacy fallback. Explicit links are authoritative.
-- The category-save RPC controls links atomically; skip its trigger-side fallback.
create or replace function public.hala_sync_category_shift_link()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_setting('hala.skip_category_shift_sync', true) = 'on' then
    return new;
  end if;
  if new.shift_id is not null and not exists (
    select 1 from public.store_category_shifts l where l.category_id = new.id
  ) then
    insert into public.store_category_shifts(category_id, shift_id)
    values (new.id, new.shift_id) on conflict do nothing;
  end if;
  return new;
end; $$;
