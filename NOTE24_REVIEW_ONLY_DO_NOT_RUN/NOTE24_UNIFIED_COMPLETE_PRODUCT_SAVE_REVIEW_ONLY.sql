-- NOTE24 REVIEW ONLY — DO NOT RUN ON PRODUCTION.
-- Requires staged/verified definitions of:
--   hala_save_product_with_shifts, store_set_product_position_v6,
--   store_replace_product_variants_v4, hala_replace_product_addons.
-- SECURITY DEFINER wrapper: explicit caller ownership and shift-mode checks below.
-- Dependency functions also enforce ownership; use restricted EXECUTE grants.
-- PostgreSQL function calls share one transaction; any exception rolls back all.
-- Do NOT deploy until permissions, triggers, SQL signatures and staging tests pass.
create or replace function public.hala_save_complete_product_v1(
  p_store_id uuid,
  p_product_id uuid,
  p_values jsonb,
  p_selected_shift_ids uuid[],
  p_all_shift_ids uuid[],
  p_position integer,
  p_variants jsonb,
  p_addon_ids uuid[]
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_saved jsonb;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  perform 1 from public.stores
    where id = p_store_id and owner_id = auth.uid() and shift_mode = 2
    for update;
  if not found then
    raise exception 'Store not owned or shift mode changed';
  end if;
  if p_position is null or p_position < 1 then
    raise exception 'Invalid product position';
  end if;
  if p_variants is null or jsonb_typeof(p_variants) <> 'array' then
    raise exception 'Invalid variants payload';
  end if;
  if p_addon_ids is null then
    raise exception 'Missing add-on selection';
  end if;

  v_saved := public.hala_save_product_with_shifts(
    p_store_id, p_product_id, p_values, p_selected_shift_ids, p_all_shift_ids
  );
  v_id := (v_saved->>'id')::uuid;
  perform public.store_set_product_position_v6(p_store_id, v_id, p_position);
  perform public.store_replace_product_variants_v4(p_store_id, v_id, p_variants);
  perform public.hala_replace_product_addons(p_store_id, v_id, p_addon_ids);
  return (select to_jsonb(p) from public.products p where p.id = v_id and p.store_id = p_store_id);
end;
$$;
-- Review-only permissions. Do not execute on production without approval.
revoke all on function public.hala_save_complete_product_v1(uuid,uuid,jsonb,uuid[],uuid[],integer,jsonb,uuid[]) from public;
revoke all on function public.hala_save_complete_product_v1(uuid,uuid,jsonb,uuid[],uuid[],integer,jsonb,uuid[]) from anon;
grant execute on function public.hala_save_complete_product_v1(uuid,uuid,jsonb,uuid[],uuid[],integer,jsonb,uuid[]) to authenticated;
