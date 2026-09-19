-- Hala Talab Partners - Stage 64
-- Store + product ratings, ownership-safe read policies and customer review rules.

create extension if not exists pgcrypto;

-- Keep compatibility with the existing store_reviews table while linking a rating
-- to a delivered order when the client app starts writing real reviews.
alter table public.store_reviews
  add column if not exists order_id uuid references public.orders(id) on delete set null;

create index if not exists store_reviews_store_created_idx
  on public.store_reviews(store_id, created_at desc);
create index if not exists store_reviews_order_id_idx
  on public.store_reviews(order_id);

-- One store review per customer per order. Old rows with NULL order_id remain valid.
create unique index if not exists store_reviews_unique_customer_order
  on public.store_reviews(customer_id, order_id)
  where customer_id is not null and order_id is not null;

create table if not exists public.product_reviews (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  customer_id uuid references auth.users(id) on delete set null,
  customer_name text,
  rating numeric(2,1) not null check (rating >= 1 and rating <= 5),
  comment text,
  created_at timestamptz not null default now()
);

create index if not exists product_reviews_store_created_idx
  on public.product_reviews(store_id, created_at desc);
create index if not exists product_reviews_product_id_idx
  on public.product_reviews(product_id);
create index if not exists product_reviews_order_id_idx
  on public.product_reviews(order_id);
create unique index if not exists product_reviews_unique_customer_order_product
  on public.product_reviews(customer_id, order_id, product_id)
  where customer_id is not null and order_id is not null;

alter table public.store_reviews enable row level security;
alter table public.product_reviews enable row level security;

-- Store owners can only read reviews that belong to their own store.
drop policy if exists "store owners read store reviews" on public.store_reviews;
create policy "store owners read store reviews"
on public.store_reviews for select to authenticated
using (
  exists (
    select 1 from public.stores s
    where s.id = store_id and s.owner_id = auth.uid()
  )
);

drop policy if exists "store owners read product reviews" on public.product_reviews;
create policy "store owners read product reviews"
on public.product_reviews for select to authenticated
using (
  exists (
    select 1 from public.stores s
    where s.id = store_id and s.owner_id = auth.uid()
  )
);

-- Customers may review a store only for their own delivered order and the review
-- must point to the same store as that order.
drop policy if exists "customers create store reviews" on public.store_reviews;
create policy "customers create store reviews"
on public.store_reviews for insert to authenticated
with check (
  customer_id = auth.uid()
  and order_id is not null
  and exists (
    select 1 from public.orders o
    where o.id = order_id
      and o.customer_id = auth.uid()
      and o.store_id = store_id
      and o.status = 'delivered'
  )
);

-- Customers may review a product only if it belongs to the same delivered order.
drop policy if exists "customers create product reviews" on public.product_reviews;
create policy "customers create product reviews"
on public.product_reviews for insert to authenticated
with check (
  customer_id = auth.uid()
  and order_id is not null
  and exists (
    select 1
    from public.orders o
    join public.order_items oi on oi.order_id = o.id
    join public.products p on p.id = product_id
    where o.id = order_id
      and o.customer_id = auth.uid()
      and o.store_id = store_id
      and o.status = 'delivered'
      and oi.product_id = product_id
      and p.store_id = store_id
  )
);

-- Customers can read their own reviews; useful when the client app later displays
-- whether a delivered order has already been rated.
drop policy if exists "customers read own store reviews" on public.store_reviews;
create policy "customers read own store reviews"
on public.store_reviews for select to authenticated
using (customer_id = auth.uid());

drop policy if exists "customers read own product reviews" on public.product_reviews;
create policy "customers read own product reviews"
on public.product_reviews for select to authenticated
using (customer_id = auth.uid());

notify pgrst, 'reload schema';

select
  to_regclass('public.store_reviews') as store_reviews,
  to_regclass('public.product_reviews') as product_reviews;
