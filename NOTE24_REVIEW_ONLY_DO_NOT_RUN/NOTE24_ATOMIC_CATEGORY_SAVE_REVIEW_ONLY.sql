-- NOTE24 REVIEW ONLY. DO NOT RUN ON PRODUCTION.
-- Atomic category data + category shift links for two-shift stores.
-- Requires verification of schema, ownership and trigger behavior on staging.
create or replace function public.hala_save_category_with_shifts(
  p_store_id uuid, p_category_id uuid, p_name text, p_is_active boolean,
  p_image_url text, p_image_path text,
  p_selected_shift_ids uuid[], p_all_shift_ids uuid[]
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_store_id uuid;
  v_active uuid[];
  v_selected uuid[];
  v_all uuid[];
  v_category public.product_categories%rowtype;
  v_primary uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if nullif(btrim(p_name),'') is null then raise exception 'Category name required'; end if;
  if p_store_id is null then raise exception 'Store id required'; end if;
  select id into v_store_id from public.stores
    where id = p_store_id and owner_id = auth.uid() for update;
  if v_store_id is null then raise exception 'Store not owned by authenticated user'; end if;
  select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_active
    from public.store_shifts where store_id = v_store_id and is_active = true;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_selected
    from unnest(coalesce(p_selected_shift_ids,'{}'::uuid[])) x;
  select coalesce(array_agg(distinct x order by x),'{}'::uuid[]) into v_all
    from unnest(coalesce(p_all_shift_ids,'{}'::uuid[])) x;
  if cardinality(v_active)=0 or v_all <> v_active then
    raise exception 'Shift list changed; reload and retry';
  end if;
  if cardinality(v_selected)=0 or exists (
    select 1 from unnest(v_selected) x where not (x=any(v_active))
  ) then raise exception 'Invalid selected shifts'; end if;
  -- Preserve legacy shift_id for old screens; explicit links are authoritative.
  -- Suppress legacy trigger only for this atomic save transaction.
  perform set_config('hala.skip_category_shift_sync', 'on', true);
  v_primary := case when v_selected = v_active then null else v_selected[1] end;
  if p_category_id is null then
    insert into public.product_categories
      (store_id,name,is_active,image_url,image_path,shift_id)
    values (v_store_id,btrim(p_name),p_is_active,p_image_url,p_image_path,v_primary)
    returning * into v_category;
  else
    update public.product_categories
      set name=btrim(p_name),is_active=p_is_active,
          image_url=p_image_url,image_path=p_image_path,shift_id=v_primary
      where id=p_category_id and store_id=v_store_id
      returning * into v_category;
    if not found then raise exception 'Category not found in current store'; end if;
  end if;
  -- Write every selected shift explicitly, including shared-all.
  -- Trigger is suppressed during this transaction to prevent unintended link rewrites.
  delete from public.store_category_shifts where category_id=v_category.id;
  insert into public.store_category_shifts(category_id,shift_id)
    select v_category.id, unnest(v_selected);
  return to_jsonb(v_category);
end; $$;
revoke all on function public.hala_save_category_with_shifts(uuid,uuid,text,boolean,text,text,uuid[],uuid[]) from public;
revoke all on function public.hala_save_category_with_shifts(uuid,uuid,text,boolean,text,text,uuid[],uuid[]) from anon;
grant execute on function public.hala_save_category_with_shifts(uuid,uuid,text,boolean,text,text,uuid[],uuid[]) to authenticated;
