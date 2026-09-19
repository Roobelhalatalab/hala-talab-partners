-- Hala Talab - Shared Stage 182 / Client Stage 81
-- New-store order pipeline: authoritative readiness + atomic order/location.
-- Safe to re-run. Does not delete user/order/store data.

begin;

-- Keep nullable operational fields deterministic for new/legacy stores without
-- overriding an owner's deliberate delivery on/off choice.
create or replace function public.normalize_store_order_defaults()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.delivery_fee := coalesce(new.delivery_fee, 0);
  new.minimum_order := coalesce(new.minimum_order, 0);
  new.preparation_minutes := coalesce(new.preparation_minutes, 30);
  if new.preparation_minutes < 1 then new.preparation_minutes := 30; end if;
  return new;
end;
$$;

drop trigger if exists normalize_store_order_defaults_trigger on public.stores;
create trigger normalize_store_order_defaults_trigger
before insert or update on public.stores
for each row execute function public.normalize_store_order_defaults();

-- One authoritative readiness check used by checkout. It reconciles the store
-- approval mirror with the latest Admin review before deciding.
create or replace function public.customer_store_order_readiness(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store public.stores%rowtype;
  v_review text;
  v_effective_review text;
  v_lifecycle text := 'active';
begin
  select * into v_store from public.stores where id=p_store_id for update;
  if not found then
    return jsonb_build_object('ready',false,'code','STORE_NOT_FOUND');
  end if;

  if to_regclass('public.admin_store_reviews') is not null then
    select r.review_status into v_review
      from public.admin_store_reviews r
     where r.store_id=p_store_id
     order by r.reviewed_at desc nulls last
     limit 1;
  end if;

  v_effective_review := coalesce(v_review, v_store.approval_status, 'pending');
  if v_store.approval_status is distinct from v_effective_review then
    update public.stores set approval_status=v_effective_review, updated_at=now() where id=p_store_id;
    v_store.approval_status := v_effective_review;
  end if;

  if to_regclass('public.admin_store_controls') is not null then
    execute 'select lifecycle_status from public.admin_store_controls where store_id=$1 order by updated_at desc nulls last limit 1'
      into v_lifecycle using p_store_id;
    v_lifecycle := coalesce(v_lifecycle,'active');
  end if;

  if v_effective_review <> 'approved' then
    return jsonb_build_object('ready',false,'code','STORE_NOT_APPROVED','approval_status',v_effective_review);
  end if;
  if coalesce(v_store.is_active,false)=false then
    return jsonb_build_object('ready',false,'code','STORE_NOT_ACTIVE');
  end if;
  if v_lifecycle <> 'active' then
    return jsonb_build_object('ready',false,'code','STORE_SUSPENDED','lifecycle_status',v_lifecycle);
  end if;
  if coalesce(v_store.is_open,false)=false then
    return jsonb_build_object('ready',false,'code','STORE_CLOSED');
  end if;
  if coalesce(v_store.delivery_available,false)=false then
    return jsonb_build_object('ready',false,'code','DELIVERY_UNAVAILABLE');
  end if;
  if v_store.latitude is null or v_store.longitude is null then
    return jsonb_build_object('ready',false,'code','STORE_LOCATION_REQUIRED');
  end if;

  return jsonb_build_object(
    'ready',true,
    'code','READY',
    'store_id',v_store.id,
    'delivery_fee',coalesce(v_store.delivery_fee,0),
    'minimum_order',coalesce(v_store.minimum_order,0),
    'preparation_minutes',coalesce(v_store.preparation_minutes,30)
  );
end;
$$;

revoke all on function public.customer_store_order_readiness(uuid) from public;
grant execute on function public.customer_store_order_readiness(uuid) to authenticated;

-- Atomic checkout: validates customer/store/location first, then creates the
-- order and stores delivery coordinates in the SAME database transaction.
-- Any failure rolls the whole order back, preventing phantom/half-created orders.
create or replace function public.create_customer_order_v6(
  p_store_id uuid,
  p_customer_name text default null,
  p_customer_phone text default null,
  p_delivery_address text default null,
  p_payment_method text default 'cash',
  p_notes text default null,
  p_coupon_code text default null,
  p_items jsonb default '[]'::jsonb,
  p_delivery_latitude double precision default null,
  p_delivery_longitude double precision default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ready jsonb;
  v_code text;
  v_result jsonb;
  v_order_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_delivery_latitude is null or p_delivery_latitude < -90 or p_delivery_latitude > 90 then
    raise exception 'INVALID_LATITUDE';
  end if;
  if p_delivery_longitude is null or p_delivery_longitude < -180 or p_delivery_longitude > 180 then
    raise exception 'INVALID_LONGITUDE';
  end if;

  v_ready := public.customer_store_order_readiness(p_store_id);
  if coalesce((v_ready->>'ready')::boolean,false)=false then
    v_code := coalesce(v_ready->>'code','STORE_UNAVAILABLE');
    raise exception '%', v_code;
  end if;

  v_result := public.create_customer_order_v5(
    p_store_id,p_customer_name,p_customer_phone,p_delivery_address,p_payment_method,
    p_notes,p_coupon_code,p_items
  );
  v_order_id := (v_result->>'id')::uuid;

  update public.orders
     set delivery_latitude=p_delivery_latitude,
         delivery_longitude=p_delivery_longitude,
         updated_at=now()
   where id=v_order_id and customer_id=auth.uid();
  if not found then raise exception 'ORDER_LOCATION_WRITE_FAILED'; end if;

  return v_result;
end;
$$;

revoke all on function public.create_customer_order_v6(uuid,text,text,text,text,text,text,jsonb,double precision,double precision) from public;
grant execute on function public.create_customer_order_v6(uuid,text,text,text,text,text,text,jsonb,double precision,double precision) to authenticated;

-- Repair only safe null operational defaults on existing rows.
update public.stores
   set delivery_fee=coalesce(delivery_fee,0),
       minimum_order=coalesce(minimum_order,0),
       preparation_minutes=case when preparation_minutes is null or preparation_minutes<1 then 30 else preparation_minutes end
 where delivery_fee is null or minimum_order is null or preparation_minutes is null or preparation_minutes<1;

notify pgrst, 'reload schema';
commit;

select
  to_regprocedure('public.customer_store_order_readiness(uuid)') is not null as readiness_ready,
  to_regprocedure('public.create_customer_order_v6(uuid,text,text,text,text,text,text,jsonb,double precision,double precision)') is not null as create_order_v6_ready;
