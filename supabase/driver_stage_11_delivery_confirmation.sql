-- Hala Talab Partners - Driver Stage 11
-- Secure final delivery confirmation with either a 4-digit handoff code
-- or a delivery proof photo. Safe to run more than once.

alter table public.orders add column if not exists delivery_confirmation_code text;
alter table public.orders add column if not exists delivery_proof_path text;
alter table public.orders add column if not exists delivery_proof_method text;

-- Create a private bucket for delivery proof photos.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'driver-delivery-proofs',
  'driver-delivery-proofs',
  false,
  10485760,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Generate a 4-digit code for active driver trips that do not already have one.
update public.orders
set delivery_confirmation_code = lpad((floor(random() * 9000) + 1000)::int::text, 4, '0')
where status in ('assigned', 'picked_up')
  and delivery_confirmation_code is null;

-- Automatically prepare a code when a driver trip becomes assigned/picked_up.
create or replace function public.ensure_order_delivery_confirmation_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('assigned', 'picked_up')
     and new.driver_id is not null
     and new.delivery_confirmation_code is null then
    new.delivery_confirmation_code := lpad((floor(random() * 9000) + 1000)::int::text, 4, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_delivery_confirmation_code on public.orders;
create trigger trg_orders_delivery_confirmation_code
before insert or update of status, driver_id on public.orders
for each row execute function public.ensure_order_delivery_confirmation_code();

-- Driver can upload only into their own folder: <uid>/<order-id>/file.ext
-- The final RPC below verifies that the uploaded path belongs to the authenticated driver.
drop policy if exists "driver_delivery_proofs_insert_own" on storage.objects;
create policy "driver_delivery_proofs_insert_own"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'driver-delivery-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "driver_delivery_proofs_update_own" on storage.objects;
create policy "driver_delivery_proofs_update_own"
on storage.objects for update
to authenticated
using (
  bucket_id = 'driver-delivery-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'driver-delivery-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "driver_delivery_proofs_select_own" on storage.objects;
create policy "driver_delivery_proofs_select_own"
on storage.objects for select
to authenticated
using (
  bucket_id = 'driver-delivery-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create or replace function public.driver_confirm_order_delivery(
  p_order_id uuid,
  p_code text default null,
  p_proof_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_method text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
    and driver_id = auth.uid()
    and status = 'picked_up'
  for update;

  if v_order.id is null then
    raise exception 'Order is not available for delivery confirmation';
  end if;

  if p_code is not null and btrim(p_code) <> '' then
    if v_order.delivery_confirmation_code is null
       or btrim(p_code) <> v_order.delivery_confirmation_code then
      raise exception using message = 'Invalid delivery confirmation code', errcode = '22023';
    end if;
    v_method := 'code';
  elsif p_proof_path is not null and btrim(p_proof_path) <> '' then
    if p_proof_path not like auth.uid()::text || '/' || p_order_id::text || '/%' then
      raise exception 'Invalid delivery proof path';
    end if;
    if not exists (
      select 1 from storage.objects so
      where so.bucket_id = 'driver-delivery-proofs'
        and so.name = p_proof_path
    ) then
      raise exception 'Delivery proof photo was not found';
    end if;
    v_method := 'photo';
  else
    raise exception 'A valid delivery code or proof photo is required';
  end if;

  update public.orders
     set status = 'delivered',
         delivered_at = coalesce(delivered_at, now()),
         delivery_proof_method = v_method,
         delivery_proof_path = case when v_method = 'photo' then p_proof_path else delivery_proof_path end,
         updated_at = now()
   where id = p_order_id
  returning * into v_order;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'delivered_at', v_order.delivered_at,
    'proof_method', v_order.delivery_proof_method
  );
end;
$$;

revoke all on function public.driver_confirm_order_delivery(uuid, text, text) from public;
grant execute on function public.driver_confirm_order_delivery(uuid, text, text) to authenticated;

-- Keep the driver's active trip RPC limited to non-completed trips.
create or replace function public.get_current_driver_assigned_order()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select to_jsonb(x)
  from (
    select
      o.id as order_id,
      o.order_number,
      o.status,
      o.store_id,
      s.name as store_name,
      s.address_text as store_address,
      s.phone as store_phone,
      o.customer_name,
      o.customer_phone,
      o.delivery_address,
      o.notes,
      o.subtotal,
      o.delivery_fee,
      o.discount_amount,
      o.total,
      o.payment_method,
      o.payment_status,
      o.created_at,
      o.picked_up_at,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', oi.id,
              'product_name', oi.product_name,
              'quantity', oi.quantity,
              'unit_price', oi.unit_price,
              'total_price', oi.total_price,
              'notes', oi.notes
            ) order by oi.created_at
          )
          from public.order_items oi
          where oi.order_id = o.id
        ),
        '[]'::jsonb
      ) as items
    from public.orders o
    join public.stores s on s.id = o.store_id
    where auth.uid() is not null
      and o.driver_id = auth.uid()
      and o.status in ('assigned', 'picked_up')
    order by o.updated_at desc
    limit 1
  ) x;
$$;

revoke all on function public.get_current_driver_assigned_order() from public;
grant execute on function public.get_current_driver_assigned_order() to authenticated;

notify pgrst, 'reload schema';

select
  to_regprocedure('public.driver_confirm_order_delivery(uuid,text,text)') as confirm_delivery_rpc,
  to_regprocedure('public.get_current_driver_assigned_order()') as active_trip_rpc;
