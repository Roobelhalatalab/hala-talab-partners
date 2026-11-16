-- REVIEW ONLY / DO NOT RUN IN PRODUCTION
-- Preserve order_items.variant_id by updating existing rows rather than deleting them.
create or replace function public.store_replace_product_variants_v4(
  p_store_id uuid, p_product_id uuid, p_variants jsonb
) returns table(variant_id uuid, name text, price numeric, sort_order integer,
                is_available boolean, image_url text, image_path text, packages jsonb)
language plpgsql security definer set search_path=public as $$
declare
  v jsonb;
  v_id uuid;
  v_ord integer := 0;
  v_seen uuid[] := '{}'::uuid[];
  v_existing integer;
  v_max_sort bigint;
  v_stage_count integer;
  v_hidden_offset integer;
  v_original_names jsonb;
begin
  if auth.uid() is null or not exists (
    select 1 from public.stores s where s.id=p_store_id and s.owner_id=auth.uid()
  ) then raise exception 'Not allowed to edit variants'; end if;
  perform 1 from public.products p
    where p.id=p_product_id and p.store_id=p_store_id for update;
  if not found then raise exception 'Product not found in store'; end if;
  if p_variants is null or jsonb_typeof(p_variants) <> 'array'
     or jsonb_array_length(p_variants)>50 then
    raise exception 'Invalid variant array';
  end if;
  select count(*) into v_existing from public.product_variants where product_id=p_product_id;
  -- Fail closed: an empty payload on an existing product could be caused by
  -- a client load failure. Do not silently hide all historical variants.
  if v_existing > 0 and jsonb_array_length(p_variants) = 0 then
    raise exception 'Refusing to hide all existing variants in one save';
  end if;
  -- Reject malformed IDs and numeric values before staging any rows.
  if exists (
    select 1 from jsonb_array_elements(p_variants) x(item)
    where (x.item ? 'id' and nullif(x.item->>'id','') is not null
           and (x.item->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
       or coalesce(x.item->>'price','') !~ '^[0-9]+(\.[0-9]{1,2})?$'
       or (x.item ? 'is_available' and jsonb_typeof(x.item->'is_available') <> 'boolean')
       or (x.item ? 'packages' and jsonb_typeof(x.item->'packages') <> 'array')
  ) then raise exception 'Invalid variant identifier or field type'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_variants) x(item)
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(x.item->'packages')='array'
           then x.item->'packages' else '[]'::jsonb end
    ) y(pkg)
    where jsonb_typeof(y.pkg)<>'object'
       or coalesce(y.pkg->>'price','') !~ '^[0-9]+(\.[0-9]{1,2})?$'
  ) then raise exception 'Invalid package type or price'; end if;
  -- Prevent older clients from accidentally replacing historical IDs by omission.
  if v_existing>0 and jsonb_array_length(p_variants)>0 and exists (
    select 1 from jsonb_array_elements(p_variants) x(item)
    where nullif(x.item->>'id','') is null
  ) then
    -- Mixed existing/new entries are allowed only when at least one explicit ID is present.
    if not exists (select 1 from jsonb_array_elements(p_variants) x(item)
                   where nullif(x.item->>'id','') is not null) then
      raise exception 'Existing variant IDs required to preserve order history';
    end if;
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_variants) x(item)
    where jsonb_typeof(x.item)<>'object'
       or nullif(btrim(x.item->>'name'),'') is null
       or char_length(btrim(x.item->>'name'))>80
       or nullif(x.item->>'price','') is null
       or (x.item->>'price')::numeric < 0
       or (x.item ? 'packages' and jsonb_typeof(x.item->'packages')<>'array')
  ) then raise exception 'Invalid variant fields'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_variants) x(item)
    group by lower(btrim(x.item->>'name')) having count(*)>1
  ) then raise exception 'Duplicate variant names'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_variants) x(item)
    cross join lateral jsonb_array_elements(coalesce(x.item->'packages','[]'::jsonb)) y(pkg)
    where nullif(btrim(y.pkg->>'label'),'') is null
       or nullif(y.pkg->>'price','') is null
       or (y.pkg->>'price')::numeric<0
  ) then raise exception 'Invalid package'; end if;
  -- Lock existing rows to prevent concurrent edits; keep all IDs.
  perform 1 from public.product_variants where product_id=p_product_id for update;
  -- Unique indexes on (product_id, sort_order) and normalized name are
  -- IMMEDIATE. Temporarily move all existing rows to collision-free positive
  -- positions and unique placeholder names before any swaps/renames.
  -- All of this runs in the same transaction and rolls back on any error.
  select coalesce(max(sort_order),0)::bigint, count(*)::integer
    into v_max_sort, v_stage_count
    from public.product_variants where product_id=p_product_id;
  if v_max_sort + v_stage_count + 100 >= 2147483647 then
    raise exception 'Variant ordering range exhausted';
  end if;
  select coalesce(jsonb_object_agg(id::text,name),'{}'::jsonb) into v_original_names
    from public.product_variants where product_id=p_product_id;
  with staged as (
    select id, row_number() over (order by sort_order,created_at,id)::integer as rn
    from public.product_variants where product_id=p_product_id
  )
  update public.product_variants pv
    set sort_order=(v_max_sort + 100 + st.rn)::integer,
        name='__hala_stage_' || replace(pv.id::text,'-','')
  from staged st where pv.id=st.id;
  -- The original names are retained for omitted historical rows below.
  -- Names of omitted rows must not collide with submitted names.
  for v in select value from jsonb_array_elements(p_variants) loop
    v_ord := v_ord+1;
    v_id := nullif(v->>'id','')::uuid;
    if v_id is not null then
      if v_id=any(v_seen) then raise exception 'Duplicate variant ID'; end if;
      update public.product_variants pv
      set name=btrim(v->>'name'), price=(v->>'price')::numeric(14,2),
          sort_order=v_ord, is_available=coalesce((v->>'is_available')::boolean,true),
          image_url=nullif(btrim(v->>'image_url'),''),
          image_path=nullif(btrim(v->>'image_path'),''),
          packages=coalesce(v->'packages','[]'::jsonb), updated_at=now()
      where pv.id=v_id and pv.product_id=p_product_id;
      if not found then raise exception 'Variant ID does not belong to this product'; end if;
    else
      insert into public.product_variants
        (product_id,name,price,sort_order,is_available,image_url,image_path,packages,updated_at)
      values (p_product_id,btrim(v->>'name'),(v->>'price')::numeric(14,2),v_ord,
        coalesce((v->>'is_available')::boolean,true),
        nullif(btrim(v->>'image_url'),''),nullif(btrim(v->>'image_path'),''),
        coalesce(v->'packages','[]'::jsonb),now()) returning id into v_id;
    end if;
    v_seen := array_append(v_seen,v_id);
  end loop;
  -- Keep historical rows and IDs; move omitted rows after submitted ones.
  -- Reject conflicting names instead of renaming historical variants.
  if exists (
    select 1 from public.product_variants pv
    where pv.product_id=p_product_id and not (pv.id=any(v_seen))
      and exists (
        select 1 from public.product_variants active
        where active.product_id=p_product_id and active.id=any(v_seen)
          and lower(btrim(active.name))=lower(btrim(v_original_names->>pv.id::text))
      )
  ) then raise exception 'Historical variant name conflicts with active variant'; end if;
  -- First move omitted rows to fresh positions; submitted rows already use 1..N.
  -- Restore original names of omitted rows, retaining their historical meaning.
  with omitted as (
    select pv.id, row_number() over (order by pv.sort_order,pv.created_at,pv.id)::integer as rn
    from public.product_variants pv
    where pv.product_id=p_product_id and not (pv.id=any(v_seen))
  )
  update public.product_variants pv
    set sort_order=v_ord + o.rn,
        name=v_original_names->>pv.id::text,
        is_available=false, updated_at=now()
  from omitted o where pv.id=o.id;
  return query select pv.id,pv.name,pv.price,pv.sort_order,pv.is_available,
                      pv.image_url,pv.image_path,pv.packages
               from public.product_variants pv where pv.product_id=p_product_id
               order by pv.sort_order,pv.created_at;
end; $$;
revoke all on function public.store_replace_product_variants_v4(uuid,uuid,jsonb) from public;
revoke all on function public.store_replace_product_variants_v4(uuid,uuid,jsonb) from anon;
grant execute on function public.store_replace_product_variants_v4(uuid,uuid,jsonb) to authenticated;
