-- Hala Talab Partners - Stage 63
-- Final secure store operations settings: location, delivery/pickup, zones and weekly hours.
-- Run once after the previous stage migrations.

alter table public.stores add column if not exists latitude double precision;
alter table public.stores add column if not exists longitude double precision;
alter table public.stores add column if not exists location_note text;
alter table public.stores add column if not exists pickup_available boolean not null default true;
alter table public.stores add column if not exists delivery_zones jsonb not null default '[]'::jsonb;
alter table public.stores add column if not exists working_hours jsonb not null default '{}'::jsonb;

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
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_key text;
  v_day jsonb;
  v_open text;
  v_close text;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;
  if not exists(select 1 from public.stores where owner_id = v_uid) then
    raise exception 'No store belongs to the signed-in user';
  end if;
  if nullif(btrim(coalesce(p_address_text, '')), '') is null then
    raise exception 'Store address is required';
  end if;
  if p_latitude is not null and (p_latitude < -90 or p_latitude > 90) then
    raise exception 'Latitude must be between -90 and 90';
  end if;
  if p_longitude is not null and (p_longitude < -180 or p_longitude > 180) then
    raise exception 'Longitude must be between -180 and 180';
  end if;
  if not coalesce(p_delivery_available, false) and not coalesce(p_pickup_available, false) then
    raise exception 'Delivery or pickup must be enabled';
  end if;
  if coalesce(p_delivery_fee, 0) < 0 or coalesce(p_minimum_order, 0) < 0 then
    raise exception 'Delivery fee and minimum order cannot be negative';
  end if;
  if p_preparation_minutes is null or p_preparation_minutes < 1 or p_preparation_minutes > 240 then
    raise exception 'Preparation time must be between 1 and 240 minutes';
  end if;
  if jsonb_typeof(coalesce(p_delivery_zones, '[]'::jsonb)) <> 'array' then
    raise exception 'Delivery zones must be a JSON array';
  end if;
  if jsonb_typeof(coalesce(p_working_hours, '{}'::jsonb)) <> 'object' then
    raise exception 'Working hours must be a JSON object';
  end if;

  foreach v_key in array array['saturday','sunday','monday','tuesday','wednesday','thursday','friday'] loop
    v_day := coalesce(p_working_hours -> v_key, '{}'::jsonb);
    if coalesce((v_day ->> 'enabled')::boolean, true) then
      v_open := v_day ->> 'open';
      v_close := v_day ->> 'close';
      if v_open is null or v_open !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'Invalid opening time for %', v_key;
      end if;
      if v_close is null or v_close !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'Invalid closing time for %', v_key;
      end if;
      if v_open = v_close then
        raise exception 'Opening and closing time cannot be equal for %', v_key;
      end if;
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
         is_open = coalesce(p_is_open, false),
         updated_at = now()
   where owner_id = v_uid
   returning public.stores.*;
end;
$$;

revoke all on function public.update_my_store_operations(text,double precision,double precision,text,boolean,boolean,numeric,numeric,integer,jsonb,jsonb,boolean) from public;
grant execute on function public.update_my_store_operations(text,double precision,double precision,text,boolean,boolean,numeric,numeric,integer,jsonb,jsonb,boolean) to authenticated;

notify pgrst, 'reload schema';

select
  to_regprocedure('public.update_my_store_operations(text,double precision,double precision,text,boolean,boolean,numeric,numeric,integer,jsonb,jsonb,boolean)') is not null as operations_rpc_ready;
