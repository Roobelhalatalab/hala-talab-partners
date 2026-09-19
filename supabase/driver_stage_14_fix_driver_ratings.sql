-- Hala Talab Partners - Driver Stage 14 FIX
-- Driver ratings foundation + RLS. Safe to run more than once.

create table if not exists public.driver_reviews (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references auth.users(id) on delete cascade,
  customer_id uuid references auth.users(id) on delete set null,
  customer_name text,
  order_id uuid references public.orders(id) on delete set null,
  rating numeric(2,1) not null check (rating >= 1 and rating <= 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (order_id, customer_id)
);

create index if not exists driver_reviews_driver_created_idx
  on public.driver_reviews(driver_id, created_at desc);

alter table public.driver_reviews enable row level security;

drop policy if exists "driver_reviews_select_own_driver" on public.driver_reviews;
create policy "driver_reviews_select_own_driver"
on public.driver_reviews for select
to authenticated
using (driver_id = auth.uid());

-- Customer-side insertion is intentionally constrained to a delivered order
-- that belongs to the signed-in customer and the same assigned driver.
drop policy if exists "driver_reviews_customer_insert_delivered" on public.driver_reviews;
create policy "driver_reviews_customer_insert_delivered"
on public.driver_reviews for insert
to authenticated
with check (
  customer_id = auth.uid()
  and exists (
    select 1
    from public.orders o
    where o.id = order_id
      and o.driver_id = driver_id
      and o.status = 'delivered'
      and o.customer_id = auth.uid()
  )
);

notify pgrst, 'reload schema';

select to_regclass('public.driver_reviews') as driver_reviews_table;
