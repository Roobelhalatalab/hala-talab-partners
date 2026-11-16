-- NOTE24 REVIEW ONLY — DO NOT EXECUTE without independent approval.
-- Atomic replacement of product add-on links; does not change product, variants,
-- image files, or shift links. Requires staging validation of schema and RLS.
create or replace function public.hala_replace_product_addons(
  p_store_id uuid,
  p_product_id uuid,
  p_addon_ids uuid[]
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_addon_ids uuid[];
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_store_id is null or p_product_id is null or p_addon_ids is null then
    raise exception 'Store, product and addon selection are required';
  end if;
  if not exists (
    select 1 from public.stores
    where id = p_store_id and owner_id = auth.uid()
  ) then
    raise exception 'Store not owned by caller';
  end if;

  -- Serialize saves to the same product and reject cross-store updates.
  perform 1 from public.products
  where id = p_product_id and store_id = p_store_id
  for update;
  if not found then
    raise exception 'Product not in store';
  end if;

  select coalesce(array_agg(distinct a order by a), '{}'::uuid[])
    into v_addon_ids
  from unnest(p_addon_ids) as a;
  if exists (select 1 from unnest(v_addon_ids) as a where a is null) then
    raise exception 'Null addon ID';
  end if;
  if exists (
    select 1 from unnest(v_addon_ids) as a
    where not exists (
      select 1 from public.product_addons
      where id = a and store_id = p_store_id
    )
  ) then
    raise exception 'Addon not in store';
  end if;

  delete from public.product_addon_links where product_id = p_product_id;
  insert into public.product_addon_links (product_id, addon_id)
  select p_product_id, a from unnest(v_addon_ids) as a;
  -- An exception in either statement rolls back BOTH within this RPC call.
end;
$$;

-- Grants must be audited against actual roles and default EXECUTE privileges.
-- Ownership checks remain mandatory even if EXECUTE is restricted.
revoke all on function public.hala_replace_product_addons(uuid, uuid, uuid[]) from public;
revoke all on function public.hala_replace_product_addons(uuid, uuid, uuid[]) from anon;
grant execute on function public.hala_replace_product_addons(uuid, uuid, uuid[]) to authenticated;
