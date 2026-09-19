-- Hala Talab Partners — Stage 3
-- Multi-active driver orders (max 10) + robust/idempotent offer claim.
-- Safe to run more than once.

create or replace function public.get_available_driver_delivery_offer()
returns table (
  order_id uuid,
  order_number bigint,
  store_id uuid,
  store_name text,
  store_address text,
  customer_name text,
  customer_phone text,
  delivery_address text,
  delivery_fee numeric,
  payment_method text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    o.id,
    o.order_number,
    o.store_id,
    s.name,
    s.address_text,
    o.customer_name,
    o.customer_phone,
    o.delivery_address,
    o.delivery_fee,
    o.payment_method,
    o.created_at
  from public.orders o
  join public.stores s on s.id = o.store_id
  where auth.uid() is not null
    and (
      select count(*)
      from public.orders active_o
      where active_o.driver_id = auth.uid()
        and active_o.status in ('assigned', 'picked_up')
    ) < 10
    and o.status = 'ready'
    and o.driver_id is null
    and not exists (
      select 1
      from public.driver_order_rejections r
      where r.driver_id = auth.uid()
        and r.order_id = o.id
    )
  order by o.ready_at nulls last, o.created_at
  limit 1;
$$;

create or replace function public.claim_driver_delivery_offer(p_order_id uuid)
returns table (
  order_id uuid,
  order_number bigint,
  store_id uuid,
  store_name text,
  store_address text,
  customer_name text,
  customer_phone text,
  delivery_address text,
  delivery_fee numeric,
  payment_method text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  -- Idempotent retry: if this driver already owns this active order,
  -- return it instead of showing "offer no longer available".
  return query
  select
    o.id, o.order_number, o.store_id, s.name, s.address_text,
    o.customer_name, o.customer_phone, o.delivery_address,
    o.delivery_fee, o.payment_method, o.created_at
  from public.orders o
  join public.stores s on s.id = o.store_id
  where o.id = p_order_id
    and o.driver_id = auth.uid()
    and o.status in ('assigned', 'picked_up')
  limit 1;

  if found then
    return;
  end if;

  select count(*)::integer
    into v_active_count
  from public.orders o
  where o.driver_id = auth.uid()
    and o.status in ('assigned', 'picked_up');

  if v_active_count >= 10 then
    raise exception 'Driver active order limit reached';
  end if;

  return query
  with claimed as (
    update public.orders o
       set driver_id = auth.uid(),
           status = 'assigned',
           updated_at = now()
     where o.id = p_order_id
       and o.status = 'ready'
       and o.driver_id is null
     returning o.*
  )
  select
    c.id, c.order_number, c.store_id, s.name, s.address_text,
    c.customer_name, c.customer_phone, c.delivery_address,
    c.delivery_fee, c.payment_method, c.created_at
  from claimed c
  join public.stores s on s.id = c.store_id;

  if not found then
    raise exception 'Delivery offer is no longer available';
  end if;
end;
$$;

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
      o.updated_at,
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
  ) x;
$$;

revoke all on function public.get_available_driver_delivery_offer() from public;
revoke all on function public.claim_driver_delivery_offer(uuid) from public;
revoke all on function public.get_driver_active_orders() from public;

grant execute on function public.get_available_driver_delivery_offer() to authenticated;
grant execute on function public.claim_driver_delivery_offer(uuid) to authenticated;
grant execute on function public.get_driver_active_orders() to authenticated;

notify pgrst, 'reload schema';
