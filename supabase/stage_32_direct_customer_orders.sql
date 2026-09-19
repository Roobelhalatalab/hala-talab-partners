-- Hala Talab Partners - Stage 32
-- Secure direct customer order creation + realtime delivery to the store.
-- Safe to run more than once. Existing data is preserved.

create extension if not exists pgcrypto;

-- Customers can see only their own orders.
drop policy if exists "Customers can view own orders" on public.orders;
create policy "Customers can view own orders"
on public.orders for select
to authenticated
using (customer_id = auth.uid());

-- Customers can see the items of only their own orders.
drop policy if exists "Customers can view own order items" on public.order_items;
create policy "Customers can view own order items"
on public.order_items for select
to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and o.customer_id = auth.uid()
  )
);

-- Secure function used by the customer app. Prices are calculated from the
-- products table; the client cannot submit a forged product price.
create or replace function public.create_customer_order(
  p_store_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_delivery_address text,
  p_payment_method text default 'cash',
  p_notes text default null,
  p_delivery_fee numeric default 0,
  p_discount_amount numeric default 0,
  p_items jsonb default '[]'::jsonb
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_subtotal numeric(12,2) := 0;
  v_item jsonb;
  v_product public.products;
  v_quantity integer;
  v_total numeric(12,2);
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not exists (select 1 from public.stores where id = p_store_id) then
    raise exception 'Store not found';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_quantity := greatest(coalesce((v_item->>'quantity')::integer, 1), 1);
    select * into v_product
    from public.products
    where id = (v_item->>'product_id')::uuid
      and store_id = p_store_id
      and is_available = true;
    if not found then
      raise exception 'Unavailable product: %', v_item->>'product_id';
    end if;
    v_subtotal := v_subtotal + (v_product.price * v_quantity);
  end loop;

  v_total := greatest(v_subtotal + greatest(coalesce(p_delivery_fee, 0), 0)
    - greatest(coalesce(p_discount_amount, 0), 0), 0);

  insert into public.orders (
    customer_id, store_id, status, subtotal, delivery_fee,
    discount_amount, total, payment_method, payment_status,
    customer_name, customer_phone, delivery_address, notes
  ) values (
    auth.uid(), p_store_id, 'pending', v_subtotal,
    greatest(coalesce(p_delivery_fee, 0), 0),
    greatest(coalesce(p_discount_amount, 0), 0), v_total,
    coalesce(nullif(p_payment_method, ''), 'cash'), 'pending',
    nullif(trim(p_customer_name), ''), nullif(trim(p_customer_phone), ''),
    nullif(trim(p_delivery_address), ''), nullif(trim(p_notes), '')
  ) returning * into v_order;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_quantity := greatest(coalesce((v_item->>'quantity')::integer, 1), 1);
    select * into v_product
    from public.products
    where id = (v_item->>'product_id')::uuid
      and store_id = p_store_id
      and is_available = true;

    insert into public.order_items (
      order_id, product_id, product_name, quantity, unit_price, notes
    ) values (
      v_order.id, v_product.id, v_product.name, v_quantity, v_product.price,
      nullif(trim(v_item->>'notes'), '')
    );
  end loop;

  return v_order;
end;
$$;

revoke all on function public.create_customer_order(uuid,text,text,text,text,text,numeric,numeric,jsonb) from public;
grant execute on function public.create_customer_order(uuid,text,text,text,text,text,numeric,numeric,jsonb) to authenticated;

-- Ensure direct order changes are published to Supabase Realtime.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;

notify pgrst, 'reload schema';

select
  to_regclass('public.orders') as orders,
  to_regclass('public.order_items') as order_items,
  to_regprocedure('public.create_customer_order(uuid,text,text,text,text,text,numeric,numeric,jsonb)') as create_customer_order,
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) as orders_realtime_ready;
