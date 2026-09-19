-- Hala Talab Partners - Stage 200
-- Shift-scoped categories + exact product/category linkage.
-- General solution for every current and future store.
-- Safe/backward-compatible: single-shift stores and legacy rows continue to work.

create extension if not exists pgcrypto;

-- 1) A category may belong to one shift. NULL means legacy/shared across all shifts.
alter table public.product_categories
  add column if not exists shift_id uuid references public.store_shifts(id) on delete cascade;

create index if not exists product_categories_store_shift_idx
  on public.product_categories(store_id, shift_id, sort_order, created_at);

-- 2) Products get an exact category reference. Keep category_name for old clients/views.
alter table public.products
  add column if not exists category_id uuid references public.product_categories(id) on delete set null;

create index if not exists products_category_id_idx on public.products(category_id);
create index if not exists products_store_category_id_idx on public.products(store_id, category_id);

-- Backfill exact category ids while the old store/name rule is still unambiguous.
with resolved as (
  select p.id as product_id,
         (
           select c.id
           from public.product_categories c
           where c.store_id = p.store_id
             and lower(btrim(c.name)) = lower(btrim(coalesce(p.category_name, '')))
           order by c.created_at, c.id
           limit 1
         ) as category_id
  from public.products p
  where p.category_id is null
)
update public.products p
set category_id = r.category_id
from resolved r
where p.id = r.product_id
  and r.category_id is not null;

-- If Stage 199 already assigned a category to exactly one shift, promote that
-- assignment to the category row itself. Zero/multiple links stay shared (NULL).
with one_shift as (
  select category_id, (array_agg(shift_id order by shift_id))[1] as shift_id
  from public.store_category_shifts
  group by category_id
  having count(*) = 1
)
update public.product_categories c
set shift_id = o.shift_id
from one_shift o
where c.id = o.category_id
  and c.shift_id is null;

-- 3) Same name is allowed in different shifts, but not twice in the same shift.
drop index if exists public.product_categories_store_name_unique;
drop index if exists public.product_categories_store_shared_name_unique;
drop index if exists public.product_categories_store_shift_name_unique;

create unique index product_categories_store_shared_name_unique
  on public.product_categories(store_id, lower(btrim(name)))
  where shift_id is null;

create unique index product_categories_store_shift_name_unique
  on public.product_categories(store_id, shift_id, lower(btrim(name)))
  where shift_id is not null;

-- 4) Validate category/shift store ownership and keep legacy link-table in sync.
create or replace function public.hala_category_shift_guard_sync()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_shift_store uuid;
begin
  if new.shift_id is not null then
    select store_id into v_shift_store from public.store_shifts where id = new.shift_id;
    if v_shift_store is null or v_shift_store <> new.store_id then
      raise exception 'Category and shift must belong to the same store';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_category_shift_guard on public.product_categories;
create trigger trg_category_shift_guard
before insert or update of store_id, shift_id on public.product_categories
for each row execute function public.hala_category_shift_guard_sync();

create or replace function public.hala_sync_category_shift_link()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  delete from public.store_category_shifts where category_id = new.id;
  if new.shift_id is not null then
    insert into public.store_category_shifts(category_id, shift_id)
    values (new.id, new.shift_id)
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_category_shift_link on public.product_categories;
create trigger trg_sync_category_shift_link
after insert or update of shift_id on public.product_categories
for each row execute function public.hala_sync_category_shift_link();

-- Synchronize existing promoted rows now.
insert into public.store_category_shifts(category_id, shift_id)
select c.id, c.shift_id
from public.product_categories c
where c.shift_id is not null
on conflict do nothing;

-- 5) Exact product/category integrity and legacy category_name compatibility.
create or replace function public.hala_sync_product_category()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_cat_store uuid;
  v_cat_name text;
  v_count integer;
  v_id uuid;
begin
  if new.category_id is not null then
    select store_id, name into v_cat_store, v_cat_name
    from public.product_categories
    where id = new.category_id;
    if v_cat_store is null or v_cat_store <> new.store_id then
      raise exception 'Product and category must belong to the same store';
    end if;
    new.category_name := v_cat_name;
    return new;
  end if;

  -- Legacy clients that only send category_name remain supported only when the
  -- name resolves to exactly one category in that store. Duplicate shift names
  -- require the new category_id and therefore cannot be guessed incorrectly.
  if btrim(coalesce(new.category_name, '')) <> '' then
    select count(*), (array_agg(id order by id))[1]
      into v_count, v_id
      from public.product_categories
     where store_id = new.store_id
       and lower(btrim(name)) = lower(btrim(new.category_name));
    if v_count = 1 then
      new.category_id := v_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_product_category on public.products;
create trigger trg_sync_product_category
before insert or update of store_id, category_id, category_name on public.products
for each row execute function public.hala_sync_product_category();

-- 6) Product ordering is now scoped by the exact category id.
drop index if exists public.products_store_category_sort_unique_idx;
drop index if exists public.products_store_category_id_sort_unique_idx;
drop index if exists public.products_store_legacy_category_sort_unique_idx;

-- Normalize existing positions separately per exact category.
with ranked as (
  select p.id,
         row_number() over (
           partition by p.store_id,
             case when p.category_id is not null then 'id:' || p.category_id::text
                  else 'name:' || lower(btrim(coalesce(p.category_name, ''))) end
           order by p.sort_order nulls last, p.created_at, p.name, p.id
         )::integer as new_pos
  from public.products p
)
update public.products p
set sort_order = -4000000 - r.new_pos
from ranked r
where p.id = r.id;

with ranked as (
  select p.id,
         row_number() over (
           partition by p.store_id,
             case when p.category_id is not null then 'id:' || p.category_id::text
                  else 'name:' || lower(btrim(coalesce(p.category_name, ''))) end
           order by abs(coalesce(p.sort_order, 9999999)), p.created_at, p.name, p.id
         )::integer as new_pos
  from public.products p
)
update public.products p
set sort_order = r.new_pos
from ranked r
where p.id = r.id;

create unique index products_store_category_id_sort_unique_idx
  on public.products(store_id, category_id, sort_order)
  where category_id is not null and sort_order is not null;

create unique index products_store_legacy_category_sort_unique_idx
  on public.products(store_id, lower(btrim(coalesce(category_name, ''))), sort_order)
  where category_id is null and sort_order is not null;

create or replace function public.store_set_product_position_v6(
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
  v_category_id uuid;
  v_category_name text;
  v_count integer;
  v_target integer;
begin
  if p_position is null or p_position < 1 then
    raise exception 'Position must be 1 or greater';
  end if;
  select owner_id into v_owner from public.stores where id = p_store_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not allowed to reorder products for this store';
  end if;

  select category_id, coalesce(category_name, '')
    into v_category_id, v_category_name
    from public.products
   where id = p_product_id and store_id = p_store_id;
  if not found then raise exception 'Product not found'; end if;

  perform pg_advisory_xact_lock(hashtext('hala-product-order-v6:' || p_store_id::text || ':' || coalesce(v_category_id::text, lower(btrim(v_category_name)))));

  select count(*) into v_count
  from public.products p
  where p.store_id = p_store_id
    and ((v_category_id is not null and p.category_id = v_category_id)
      or (v_category_id is null and p.category_id is null and lower(btrim(coalesce(p.category_name,''))) = lower(btrim(v_category_name))));

  v_target := least(greatest(p_position, 1), greatest(v_count, 1));

  create temporary table if not exists pg_temp.hala_stage200_product_order(
    id uuid primary key,
    new_pos integer not null unique
  ) on commit drop;
  truncate pg_temp.hala_stage200_product_order;

  insert into pg_temp.hala_stage200_product_order(id, new_pos)
  with others as (
    select p.id,
           row_number() over(order by p.sort_order nulls last, p.created_at, p.name, p.id)::integer as pos
    from public.products p
    where p.store_id = p_store_id
      and p.id <> p_product_id
      and ((v_category_id is not null and p.category_id = v_category_id)
        or (v_category_id is null and p.category_id is null and lower(btrim(coalesce(p.category_name,''))) = lower(btrim(v_category_name))))
  )
  select id, case when pos < v_target then pos else pos + 1 end from others
  union all select p_product_id, v_target;

  update public.products p
     set sort_order = -5000000 - x.new_pos
    from pg_temp.hala_stage200_product_order x
   where p.id = x.id;
  update public.products p
     set sort_order = x.new_pos
    from pg_temp.hala_stage200_product_order x
   where p.id = x.id;
end;
$$;

grant execute on function public.store_set_product_position_v6(uuid,uuid,integer) to authenticated;

create or replace function public.store_normalize_product_positions_v2(
  p_store_id uuid,
  p_category_id uuid default null,
  p_category_name text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select owner_id into v_owner from public.stores where id = p_store_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not allowed';
  end if;

  with ranked as (
    select p.id,
           row_number() over(order by p.sort_order nulls last, p.created_at, p.name, p.id)::integer as new_pos
    from public.products p
    where p.store_id = p_store_id
      and ((p_category_id is not null and p.category_id = p_category_id)
        or (p_category_id is null and p.category_id is null and lower(btrim(coalesce(p.category_name,''))) = lower(btrim(coalesce(p_category_name,'')))))
  )
  update public.products p
     set sort_order = -6000000 - r.new_pos
    from ranked r where p.id = r.id;

  with ranked as (
    select p.id,
           row_number() over(order by abs(coalesce(p.sort_order,9999999)), p.created_at, p.name, p.id)::integer as new_pos
    from public.products p
    where p.store_id = p_store_id
      and ((p_category_id is not null and p.category_id = p_category_id)
        or (p_category_id is null and p.category_id is null and lower(btrim(coalesce(p.category_name,''))) = lower(btrim(coalesce(p_category_name,'')))))
  )
  update public.products p set sort_order = r.new_pos from ranked r where p.id = r.id;
end;
$$;

grant execute on function public.store_normalize_product_positions_v2(uuid,uuid,text) to authenticated;

-- 7) Category ordering is scoped by shift (NULL/shared is its own scope).
create or replace function public.store_set_menu_category_position_v2(
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
  v_shift_id uuid;
  v_count integer;
  v_target integer;
begin
  if p_position is null or p_position < 1 then raise exception 'Position must be 1 or greater'; end if;
  select owner_id into v_owner from public.stores where id = p_store_id;
  if v_owner is null or v_owner <> auth.uid() then raise exception 'Not allowed'; end if;
  select shift_id into v_shift_id from public.product_categories where id = p_category_id and store_id = p_store_id;
  if not found then raise exception 'Category not found'; end if;

  select count(*) into v_count from public.product_categories c
  where c.store_id = p_store_id and c.shift_id is not distinct from v_shift_id;
  v_target := least(greatest(p_position,1), greatest(v_count,1));

  create temporary table if not exists pg_temp.hala_stage200_category_order(id uuid primary key,new_pos integer not null unique) on commit drop;
  truncate pg_temp.hala_stage200_category_order;
  insert into pg_temp.hala_stage200_category_order(id,new_pos)
  with others as (
    select c.id,row_number() over(order by c.sort_order nulls last,c.created_at,c.name,c.id)::integer as pos
    from public.product_categories c
    where c.store_id=p_store_id and c.shift_id is not distinct from v_shift_id and c.id<>p_category_id
  )
  select id,case when pos<v_target then pos else pos+1 end from others
  union all select p_category_id,v_target;

  update public.product_categories c set sort_order=-7000000-x.new_pos from pg_temp.hala_stage200_category_order x where c.id=x.id;
  update public.product_categories c set sort_order=x.new_pos from pg_temp.hala_stage200_category_order x where c.id=x.id;
end;
$$;

grant execute on function public.store_set_menu_category_position_v2(uuid,uuid,integer) to authenticated;

-- 8) Checkout validator: prefer exact products.category_id; name fallback is only
-- for legacy rows that still have no category_id.
create or replace function public.customer_validate_shift_products(
  p_store_id uuid,
  p_product_ids uuid[]
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_mode smallint := 1;
  v_shift_id uuid;
  v_product_id uuid;
  v_product_exists boolean;
  v_category_id uuid;
begin
  select coalesce(s.shift_mode,1) into v_mode from public.stores s where s.id=p_store_id;
  if not found then return jsonb_build_object('ready',false,'code','STORE_NOT_FOUND'); end if;
  if v_mode<>2 then return jsonb_build_object('ready',true,'code','READY'); end if;

  select sh.id into v_shift_id
  from public.store_shifts sh
  where sh.store_id=p_store_id and sh.is_active=true and public.hala_shift_is_open(sh.id,now())
  order by sh.sort_order,sh.start_time limit 1;
  if v_shift_id is null then return jsonb_build_object('ready',false,'code','SHIFT_CLOSED'); end if;

  foreach v_product_id in array coalesce(p_product_ids,array[]::uuid[]) loop
    v_product_exists:=false; v_category_id:=null;
    select true,
           coalesce(p.category_id,(
             select c.id from public.product_categories c
             where c.store_id=p.store_id
               and lower(btrim(c.name))=lower(btrim(coalesce(p.category_name,'')))
             order by (c.shift_id=v_shift_id) desc nulls last,c.created_at,c.id limit 1
           ))
    into v_product_exists,v_category_id
    from public.products p
    where p.id=v_product_id and p.store_id=p_store_id
    limit 1;

    if coalesce(v_product_exists,false)=false then return jsonb_build_object('ready',false,'code','PRODUCT_UNAVAILABLE'); end if;
    if exists(select 1 from public.store_product_shifts ps where ps.product_id=v_product_id)
       and not exists(select 1 from public.store_product_shifts ps where ps.product_id=v_product_id and ps.shift_id=v_shift_id)
    then return jsonb_build_object('ready',false,'code','SHIFT_PRODUCT_CLOSED'); end if;
    if v_category_id is not null
       and exists(select 1 from public.store_category_shifts cs where cs.category_id=v_category_id)
       and not exists(select 1 from public.store_category_shifts cs where cs.category_id=v_category_id and cs.shift_id=v_shift_id)
    then return jsonb_build_object('ready',false,'code','SHIFT_CATEGORY_CLOSED'); end if;
  end loop;
  return jsonb_build_object('ready',true,'code','READY','shift_id',v_shift_id);
end;
$$;

revoke all on function public.customer_validate_shift_products(uuid,uuid[]) from public;
grant execute on function public.customer_validate_shift_products(uuid,uuid[]) to authenticated;

notify pgrst, 'reload schema';

select
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='product_categories' and column_name='shift_id') as category_shift_ready,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='category_id') as product_category_id_ready,
  to_regprocedure('public.store_set_product_position_v6(uuid,uuid,integer)') is not null as product_order_v6_ready,
  to_regprocedure('public.store_set_menu_category_position_v2(uuid,uuid,integer)') is not null as category_order_v2_ready,
  to_regprocedure('public.customer_validate_shift_products(uuid,uuid[])') is not null as checkout_validator_ready;
