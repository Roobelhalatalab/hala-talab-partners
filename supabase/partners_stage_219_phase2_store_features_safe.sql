-- Hala Talab Partners Android - Stage 219 Phase 2
-- Notes 5, 6, 9, 11, 13. Additive/idempotent: no existing rows are deleted.

begin;

-- Note 5 + Note 9: merchant delivery + always-open switch.
alter table public.stores add column if not exists self_delivery boolean not null default false;
alter table public.stores add column if not exists always_open boolean not null default false;

-- Note 6: optional image for merchant offers/coupons.
alter table public.store_promotions add column if not exists image_url text;
alter table public.store_promotions add column if not exists image_path text;
alter table public.coupons add column if not exists image_url text;
alter table public.coupons add column if not exists image_path text;

-- Note 11: quantity meaning is explicit per product.
alter table public.products add column if not exists min_quantity numeric(12,3) not null default 1;
alter table public.products add column if not exists quantity_step numeric(12,3) not null default 1;

-- Avoid destructive constraint replacement; only add validation if it is absent.
do $$
begin
  if not exists (select 1 from pg_constraint where conname='products_min_quantity_positive') then
    alter table public.products add constraint products_min_quantity_positive check (min_quantity > 0) not valid;
    alter table public.products validate constraint products_min_quantity_positive;
  end if;
  if not exists (select 1 from pg_constraint where conname='products_quantity_step_positive') then
    alter table public.products add constraint products_quantity_step_positive check (quantity_step > 0) not valid;
    alter table public.products validate constraint products_quantity_step_positive;
  end if;
end $$;

-- Note 13: one product type can have its own image and package choices.
alter table public.product_variants add column if not exists image_url text;
alter table public.product_variants add column if not exists image_path text;
alter table public.product_variants add column if not exists packages jsonb not null default '[]'::jsonb;

-- Version 3 keeps all Stage 156 validation and additionally persists image/packages.
create or replace function public.store_replace_product_variants_v3(
  p_store_id uuid,
  p_product_id uuid,
  p_variants jsonb
)
returns table(
  variant_id uuid,
  name text,
  price numeric,
  sort_order integer,
  is_available boolean,
  image_url text,
  image_path text,
  packages jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_variants jsonb := coalesce(p_variants, '[]'::jsonb);
begin
  select s.owner_id into v_owner from public.stores s where s.id = p_store_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'Not allowed to edit product variants for this store';
  end if;
  if not exists (select 1 from public.products p where p.id = p_product_id and p.store_id = p_store_id) then
    raise exception 'Product not found';
  end if;
  if jsonb_typeof(v_variants) <> 'array' then raise exception 'Variants must be a JSON array'; end if;
  if jsonb_array_length(v_variants) > 50 then raise exception 'A product cannot have more than 50 variants'; end if;

  if exists (
    select 1
    from jsonb_array_elements(v_variants) v(item)
    where btrim(v.item->>'name') = ''
       or char_length(btrim(v.item->>'name')) > 80
       or nullif(v.item->>'price','') is null
       or (v.item->>'price')::numeric < 0
       or (v.item ? 'packages' and jsonb_typeof(v.item->'packages') <> 'array')
  ) then
    raise exception 'Each type needs valid data';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_variants) v(item)
    group by lower(btrim(v.item->>'name'))
    having count(*) > 1
  ) then
    raise exception 'Variant names must be unique inside a product';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_variants) v(item)
    cross join lateral jsonb_array_elements(coalesce(v.item->'packages','[]'::jsonb)) p(pkg)
    where btrim(p.pkg->>'label') = ''
       or nullif(p.pkg->>'price','') is null
       or (p.pkg->>'price')::numeric < 0
  ) then
    raise exception 'Every package needs a label and non-negative price';
  end if;

  delete from public.product_variants where product_id = p_product_id;

  insert into public.product_variants(
    product_id, name, price, sort_order, is_available, image_url, image_path, packages, updated_at
  )
  select
    p_product_id,
    btrim(v.item->>'name'),
    (v.item->>'price')::numeric(14,2),
    v.ordinality::integer,
    coalesce((v.item->>'is_available')::boolean, true),
    nullif(btrim(v.item->>'image_url'),''),
    nullif(btrim(v.item->>'image_path'),''),
    coalesce(v.item->'packages','[]'::jsonb),
    now()
  from jsonb_array_elements(v_variants) with ordinality as v(item, ordinality);

  return query
  select pv.id, pv.name, pv.price, pv.sort_order, pv.is_available,
         pv.image_url, pv.image_path, pv.packages
  from public.product_variants pv
  where pv.product_id = p_product_id
  order by pv.sort_order;
end;
$$;
revoke all on function public.store_replace_product_variants_v3(uuid,uuid,jsonb) from public;
grant execute on function public.store_replace_product_variants_v3(uuid,uuid,jsonb) to authenticated;

-- Note 5: store can complete a ready delivery only when self-delivery is enabled
-- and no driver has claimed that order. Normal driver flow remains unchanged.
create or replace function public.update_my_store_order_status(
  p_order_id uuid,
  p_new_status text
)
returns setof public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_store public.stores%rowtype;
  v_allowed boolean := false;
  v_now timestamptz := now();
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select o.* into v_order
  from public.orders o
  join public.stores s on s.id=o.store_id
  where o.id=p_order_id and s.owner_id=auth.uid()
  for update of o;
  if not found then raise exception 'Order not found for this store'; end if;

  select * into v_store from public.stores s where s.id=v_order.store_id;

  v_allowed := case v_order.status
    when 'pending' then p_new_status in ('preparing','rejected')
    when 'accepted' then p_new_status='preparing'
    when 'preparing' then p_new_status='ready'
    when 'ready' then p_new_status='delivered'
                      and coalesce(v_store.self_delivery,false)
                      and v_order.driver_id is null
    else false
  end;
  if not v_allowed then raise exception 'Invalid order transition: % -> %', v_order.status, p_new_status; end if;

  update public.orders
  set status=p_new_status,
      updated_at=v_now,
      accepted_at=case when p_new_status='preparing' and accepted_at is null then v_now else accepted_at end,
      preparing_at=case when p_new_status='preparing' then v_now else preparing_at end,
      ready_at=case when p_new_status='ready' then v_now else ready_at end,
      delivered_at=case when p_new_status='delivered' then v_now else delivered_at end,
      rejected_at=case when p_new_status='rejected' then v_now else rejected_at end
  where id=p_order_id and store_id=v_order.store_id;

  return query select * from public.orders where id=p_order_id;
end;
$$;
revoke all on function public.update_my_store_order_status(uuid,text) from public;
grant execute on function public.update_my_store_order_status(uuid,text) to authenticated;

-- Prevent self-delivery stores from entering the general driver offer queue.
create or replace function public.get_available_driver_delivery_offer()
returns table(
  order_id uuid, order_number bigint, store_id uuid, store_name text,
  store_address text, customer_name text, customer_phone text,
  delivery_address text, delivery_fee numeric, payment_method text, created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select o.id, o.order_number, o.store_id, s.name, s.address_text,
         o.customer_name, o.customer_phone, o.delivery_address,
         o.delivery_fee, o.payment_method, o.created_at
  from public.orders o
  join public.stores s on s.id=o.store_id
  where auth.uid() is not null
    and not coalesce(s.self_delivery,false)
    and public.driver_can_take_store(auth.uid(),o.store_id)
    and (select count(*) from public.orders ao where ao.driver_id=auth.uid() and ao.status in ('ready','assigned','picked_up')) < 10
    and o.status='ready'
    and o.driver_id is null
    and not exists(select 1 from public.driver_order_rejections r where r.driver_id=auth.uid() and r.order_id=o.id)
  order by o.ready_at nulls last,o.created_at
  limit 1
$$;
revoke all on function public.get_available_driver_delivery_offer() from public;
grant execute on function public.get_available_driver_delivery_offer() to authenticated;

-- Reassert claim with an explicit self-delivery guard.
create or replace function public.claim_driver_delivery_offer(p_order_id uuid)
returns table(
  order_id uuid, order_number bigint, store_id uuid, store_name text,
  store_address text, customer_name text, customer_phone text,
  delivery_address text, delivery_fee numeric, payment_method text, created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_active_count integer;
  v_store_id uuid;
  v_self_delivery boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select o.store_id, coalesce(s.self_delivery,false)
    into v_store_id, v_self_delivery
  from public.orders o join public.stores s on s.id=o.store_id
  where o.id=p_order_id;
  if v_store_id is null or v_self_delivery then raise exception 'Delivery offer is no longer available'; end if;
  if not public.driver_can_take_store(auth.uid(),v_store_id) then raise exception 'This order is not available for this driver'; end if;

  return query
  select o.id,o.order_number,o.store_id,s.name,s.address_text,o.customer_name,o.customer_phone,
         o.delivery_address,o.delivery_fee,o.payment_method,o.created_at
  from public.orders o join public.stores s on s.id=o.store_id
  where o.id=p_order_id and o.driver_id=auth.uid() and o.status in ('ready','assigned','picked_up')
  limit 1;
  if found then return; end if;

  select count(*)::integer into v_active_count
  from public.orders ao where ao.driver_id=auth.uid() and ao.status in ('ready','assigned','picked_up');
  if v_active_count>=10 then raise exception 'Driver active order limit reached'; end if;

  return query
  with claimed as (
    update public.orders o
       set driver_id=auth.uid(), updated_at=now()
      from public.stores s
     where o.id=p_order_id and o.store_id=s.id
       and not coalesce(s.self_delivery,false)
       and o.status='ready' and o.driver_id is null
       and public.driver_can_take_store(auth.uid(),o.store_id)
    returning o.id,o.order_number,o.store_id,o.customer_name,o.customer_phone,o.delivery_address,o.delivery_fee,o.payment_method,o.created_at
  )
  select c.id,c.order_number,c.store_id,s.name,s.address_text,c.customer_name,c.customer_phone,
         c.delivery_address,c.delivery_fee,c.payment_method,c.created_at
  from claimed c join public.stores s on s.id=c.store_id;
  if not found then raise exception 'Delivery offer is no longer available'; end if;
end;
$$;
revoke all on function public.claim_driver_delivery_offer(uuid) from public;
grant execute on function public.claim_driver_delivery_offer(uuid) to authenticated;


-- Self-delivery ready orders must not create general-driver notifications.
create or replace function public.hala_notify_eligible_drivers_ready_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'ready' or new.driver_id is not null then return new; end if;
  if exists(select 1 from public.stores s where s.id=new.store_id and coalesce(s.self_delivery,false)) then
    delete from public.driver_notifications n
    where n.order_id=new.id and n.event_type='available';
    return new;
  end if;
  if tg_op='UPDATE' and old.status is not distinct from new.status
     and old.store_id is not distinct from new.store_id
     and old.driver_id is not distinct from new.driver_id then return new; end if;

  insert into public.driver_notifications(driver_id,order_id,order_number,event_type,is_read,read_at,created_at)
  select d.driver_id,new.id,new.order_number::text,'available',false,null,now()
  from public.driver_delivery_scope d
  where d.is_active=true
    and (d.driver_type='hala' or (d.driver_type='store' and d.store_id=new.store_id))
  on conflict(driver_id,order_id,event_type)
  do update set is_read=false,read_at=null,created_at=excluded.created_at;
  return new;
end;
$$;

create or replace function public.hala_notify_driver_after_scope_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active is not true then return new; end if;
  if tg_op='UPDATE' and old.is_active is not distinct from new.is_active
     and old.driver_type is not distinct from new.driver_type
     and old.store_id is not distinct from new.store_id then return new; end if;
  insert into public.driver_notifications(driver_id,order_id,order_number,event_type,is_read,read_at,created_at)
  select new.driver_id,q.id,q.order_number::text,'available',false,null,now()
  from (
    select o.id,o.order_number
    from public.orders o join public.stores s on s.id=o.store_id
    where o.status='ready' and o.driver_id is null and not coalesce(s.self_delivery,false)
      and (new.driver_type='hala' or (new.driver_type='store' and o.store_id=new.store_id))
    order by o.ready_at nulls last,o.created_at
    limit 10
  ) q
  on conflict(driver_id,order_id,event_type)
  do update set is_read=false,read_at=null,created_at=excluded.created_at;
  return new;
end;
$$;

-- If a merchant enables self delivery while a ready order is waiting, remove
-- only the still-available driver notifications for that store. No order is changed.
create or replace function public.hala_cleanup_driver_offers_for_self_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.self_delivery is true and old.self_delivery is distinct from true then
    delete from public.driver_notifications n
    using public.orders o
    where n.order_id=o.id and o.store_id=new.id and o.status='ready'
      and o.driver_id is null and n.event_type='available';
  end if;
  return new;
end;
$$;
drop trigger if exists hala_store_self_delivery_cleanup on public.stores;
create trigger hala_store_self_delivery_cleanup
after update of self_delivery on public.stores
for each row execute function public.hala_cleanup_driver_offers_for_self_delivery();

notify pgrst, 'reload schema';
commit;
