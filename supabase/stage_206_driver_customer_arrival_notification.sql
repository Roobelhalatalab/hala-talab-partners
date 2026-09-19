-- Hala Talab Partners — Stage 206
-- Driver "I have arrived" notification to customer.
-- General solution for all current/future stores, drivers and orders.
-- Safe/idempotent. Does not change shift, pricing, routing or delivery completion logic.

begin;

alter table public.orders
  add column if not exists driver_arrived_at timestamptz;

comment on column public.orders.driver_arrived_at is
  'Time the assigned driver explicitly notified the customer that the driver arrived.';

create or replace function public.driver_notify_customer_arrival(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_now timestamptz := now();
  v_order_label text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
    into v_order
  from public.orders o
  where o.id = p_order_id
    and o.driver_id = auth.uid()
  for update;

  if not found then
    raise exception 'Order is not assigned to this driver';
  end if;

  if v_order.status <> 'picked_up' then
    raise exception 'Customer can only be notified while order is out for delivery';
  end if;

  if v_order.customer_id is null then
    raise exception 'Order has no customer account to notify';
  end if;

  if v_order.driver_arrived_at is not null then
    return jsonb_build_object(
      'ok', true,
      'already_notified', true,
      'order_id', v_order.id,
      'notified_at', v_order.driver_arrived_at
    );
  end if;

  update public.orders
     set driver_arrived_at = v_now
   where id = v_order.id;

  v_order_label := coalesce(v_order.order_number::text, left(v_order.id::text, 8));

  insert into public.customer_notifications(
    customer_id,
    order_id,
    type,
    title,
    body,
    data
  ) values (
    v_order.customer_id,
    v_order.id,
    'driver_arrived',
    'سائق هلا طلب وصل إليك',
    'السائق وصل إلى موقعك. يمكنك التواصل معه إذا احتجت.',
    jsonb_build_object(
      'order_id', v_order.id,
      'order_number', v_order.order_number,
      'store_id', v_order.store_id,
      'driver_id', auth.uid(),
      'status', v_order.status,
      'event', 'driver_arrived',
      'notified_at', v_now
    )
  );

  return jsonb_build_object(
    'ok', true,
    'already_notified', false,
    'order_id', v_order.id,
    'order_number', v_order_label,
    'notified_at', v_now
  );
end;
$$;

revoke all on function public.driver_notify_customer_arrival(uuid) from public;
grant execute on function public.driver_notify_customer_arrival(uuid) to authenticated;

-- Keep the current Driver payloads, adding only driver_arrived_at so the UI
-- remains idempotent after refresh/reopen.
create or replace function public.get_driver_active_orders()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc), '[]'::jsonb)
  from (
    select
      o.id as order_id,
      o.order_number,
      o.status,
      o.store_id,
      s.name as store_name,
      s.address_text as store_address,
      s.phone as store_phone,
      s.latitude as store_latitude,
      s.longitude as store_longitude,
      o.customer_name,
      o.customer_phone,
      o.delivery_address,
      o.delivery_latitude,
      o.delivery_longitude,
      o.notes,
      o.subtotal,
      o.delivery_fee,
      o.discount_amount,
      o.total,
      o.payment_method,
      o.payment_status,
      o.created_at,
      o.updated_at,
      o.picked_up_at,
      o.driver_arrived_at,
      coalesce((
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
      ), '[]'::jsonb) as items
    from public.orders o
    join public.stores s on s.id = o.store_id
    where auth.uid() is not null
      and o.driver_id = auth.uid()
      and o.status in ('ready','assigned','picked_up')
  ) x
$$;

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
      s.latitude as store_latitude,
      s.longitude as store_longitude,
      o.customer_name,
      o.customer_phone,
      o.delivery_address,
      o.delivery_latitude,
      o.delivery_longitude,
      o.notes,
      o.subtotal,
      o.delivery_fee,
      o.discount_amount,
      o.total,
      o.payment_method,
      o.payment_status,
      o.created_at,
      o.updated_at,
      o.picked_up_at,
      o.driver_arrived_at
    from public.orders o
    join public.stores s on s.id = o.store_id
    where auth.uid() is not null
      and o.driver_id = auth.uid()
      and o.status in ('ready','assigned','picked_up')
    order by o.updated_at desc
    limit 1
  ) x
$$;

revoke all on function public.get_driver_active_orders() from public;
revoke all on function public.get_current_driver_assigned_order() from public;
grant execute on function public.get_driver_active_orders() to authenticated;
grant execute on function public.get_current_driver_assigned_order() to authenticated;

commit;
notify pgrst, 'reload schema';

select
  to_regprocedure('public.driver_notify_customer_arrival(uuid)') is not null as arrival_rpc_ready,
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='orders' and column_name='driver_arrived_at'
  ) as arrival_column_ready,
  to_regprocedure('public.get_driver_active_orders()') is not null as active_orders_rpc_ready;
