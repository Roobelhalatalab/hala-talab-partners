-- Hala Talab Partners - Stage 76
-- Store status architecture cleanup: one authoritative open/close path.
-- Run ONCE in Supabase SQL Editor. Safe to run again.

-- Keep approval mirror synchronized with the Admin review.
create or replace function public.sync_store_approval_from_admin_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.stores
     set approval_status = coalesce(new.review_status, 'pending')
   where id = new.store_id
     and approval_status is distinct from coalesce(new.review_status, 'pending');
  return new;
end;
$$;

drop trigger if exists sync_store_approval_from_admin_review_trigger on public.admin_store_reviews;
create trigger sync_store_approval_from_admin_review_trigger
after insert or update of review_status on public.admin_store_reviews
for each row execute function public.sync_store_approval_from_admin_review();

-- Repair existing rows once.
update public.stores s
   set approval_status = r.review_status
  from public.admin_store_reviews r
 where r.store_id = s.id
   and r.review_status is not null
   and s.approval_status is distinct from r.review_status;

-- Protect approval/activation from owner-side edits, but do not second-guess
-- a legitimate is_open change that comes through the dedicated RPC.
create or replace function public.enforce_store_admin_approval_gate()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_review text;
begin
  if tg_op = 'INSERT' then
    if auth.uid() = new.owner_id then
      new.approval_status := 'pending';
      new.is_active := false;
      new.is_open := false;
    end if;
    return new;
  end if;

  if auth.uid() = old.owner_id then
    new.approval_status := old.approval_status;
    new.is_active := old.is_active;
  end if;

  select r.review_status
    into v_review
    from public.admin_store_reviews r
   where r.store_id = new.id
   order by r.reviewed_at desc nulls last
   limit 1;

  v_review := coalesce(v_review, new.approval_status, 'pending');

  if v_review <> 'approved' or coalesce(new.is_active, false) = false then
    new.is_open := false;
  end if;

  return new;
end;
$$;

drop trigger if exists stores_admin_approval_gate on public.stores;
create trigger stores_admin_approval_gate
before insert or update on public.stores
for each row execute function public.enforce_store_admin_approval_gate();

-- Single authoritative RPC for opening/closing the signed-in owner's store.
create or replace function public.set_my_store_open_status(p_is_open boolean)
returns setof public.stores
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_store public.stores%rowtype;
  v_review text;
  v_lifecycle text := 'active';
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select * into v_store
    from public.stores
   where owner_id = v_uid
   order by created_at desc nulls last
   limit 1
   for update;

  if not found then
    raise exception 'Store was not found';
  end if;

  select r.review_status
    into v_review
    from public.admin_store_reviews r
   where r.store_id = v_store.id
   order by r.reviewed_at desc nulls last
   limit 1;

  v_review := coalesce(v_review, v_store.approval_status, 'pending');

  if p_is_open then
    if v_review <> 'approved' then
      raise exception 'Store is not approved by admin (status: %)', v_review;
    end if;
    if coalesce(v_store.is_active, false) = false then
      raise exception 'Store is approved but not activated by admin';
    end if;

    if to_regclass('public.admin_store_controls') is not null then
      execute 'select lifecycle_status from public.admin_store_controls where store_id=$1 order by updated_at desc nulls last limit 1'
        into v_lifecycle using v_store.id;
      v_lifecycle := coalesce(v_lifecycle, 'active');
      if v_lifecycle <> 'active' then
        raise exception 'Store is administratively %', v_lifecycle;
      end if;
    end if;
  end if;

  return query
  update public.stores
     set approval_status = v_review,
         is_open = coalesce(p_is_open, false),
         updated_at = now()
   where id = v_store.id
   returning public.stores.*;
end;
$$;

revoke all on function public.set_my_store_open_status(boolean) from public;
grant execute on function public.set_my_store_open_status(boolean) to authenticated;

-- IMPORTANT: normal operations/settings saves no longer own the open/close
-- state. Preserve current is_open there, so opening has one write path only.
create or replace function public.update_my_store_operations(
  p_address_text text,
  p_latitude double precision,
  p_longitude double precision,
  p_location_note text,
  p_delivery_available boolean,
  p_pickup_available boolean,
  p_delivery_fee numeric,
  p_minimum_order numeric,
  p_preparation_minutes integer,
  p_delivery_zones jsonb,
  p_working_hours jsonb,
  p_is_open boolean
)
returns setof public.stores
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_key text;
  v_day jsonb;
  v_open text;
  v_close text;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.stores where owner_id = v_uid) then raise exception 'No store belongs to the signed-in user'; end if;
  if nullif(btrim(coalesce(p_address_text, '')), '') is null then raise exception 'Store address is required'; end if;
  if p_latitude is not null and (p_latitude < -90 or p_latitude > 90) then raise exception 'Latitude must be between -90 and 90'; end if;
  if p_longitude is not null and (p_longitude < -180 or p_longitude > 180) then raise exception 'Longitude must be between -180 and 180'; end if;
  if not coalesce(p_delivery_available, false) and not coalesce(p_pickup_available, false) then raise exception 'Delivery or pickup must be enabled'; end if;
  if coalesce(p_delivery_fee, 0) < 0 or coalesce(p_minimum_order, 0) < 0 then raise exception 'Delivery fee and minimum order cannot be negative'; end if;
  if p_preparation_minutes is null or p_preparation_minutes < 1 or p_preparation_minutes > 240 then raise exception 'Preparation time must be between 1 and 240 minutes'; end if;
  if jsonb_typeof(coalesce(p_delivery_zones, '[]'::jsonb)) <> 'array' then raise exception 'Delivery zones must be a JSON array'; end if;
  if jsonb_typeof(coalesce(p_working_hours, '{}'::jsonb)) <> 'object' then raise exception 'Working hours must be a JSON object'; end if;

  foreach v_key in array array['saturday','sunday','monday','tuesday','wednesday','thursday','friday'] loop
    v_day := coalesce(p_working_hours -> v_key, '{}'::jsonb);
    if coalesce((v_day ->> 'enabled')::boolean, true) then
      v_open := v_day ->> 'open';
      v_close := v_day ->> 'close';
      if v_open is null or v_open !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid opening time for %', v_key; end if;
      if v_close is null or v_close !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Invalid closing time for %', v_key; end if;
      if v_open = v_close then raise exception 'Opening and closing time cannot be equal for %', v_key; end if;
    end if;
  end loop;

  return query
  update public.stores
     set address_text = btrim(p_address_text),
         latitude = p_latitude,
         longitude = p_longitude,
         location_note = nullif(btrim(coalesce(p_location_note, '')), ''),
         delivery_available = coalesce(p_delivery_available, false),
         pickup_available = coalesce(p_pickup_available, false),
         delivery_fee = coalesce(p_delivery_fee, 0),
         minimum_order = coalesce(p_minimum_order, 0),
         preparation_minutes = p_preparation_minutes,
         delivery_zones = coalesce((select jsonb_agg(z order by z) from (select distinct btrim(value) as z from jsonb_array_elements_text(coalesce(p_delivery_zones, '[]'::jsonb)) where btrim(value) <> '') q), '[]'::jsonb),
         working_hours = p_working_hours,
         updated_at = now()
   where owner_id = v_uid
   returning public.stores.*;
end;
$$;

revoke all on function public.update_my_store_operations(text,double precision,double precision,text,boolean,boolean,numeric,numeric,integer,jsonb,jsonb,boolean) from public;
grant execute on function public.update_my_store_operations(text,double precision,double precision,text,boolean,boolean,numeric,numeric,integer,jsonb,jsonb,boolean) to authenticated;

notify pgrst, 'reload schema';
