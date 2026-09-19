-- Hala Talab Partners - Stage 17: Store products
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  description text,
  category_name text,
  price numeric(12,2) not null default 0 check (price >= 0),
  image_url text,
  is_available boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists products_store_id_idx on public.products(store_id);
create index if not exists products_store_available_idx on public.products(store_id, is_available);

alter table public.products enable row level security;

drop policy if exists "Store owners can view own products" on public.products;
create policy "Store owners can view own products"
on public.products for select
to authenticated
using (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
);

drop policy if exists "Store owners can create own products" on public.products;
create policy "Store owners can create own products"
on public.products for insert
to authenticated
with check (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
);

drop policy if exists "Store owners can update own products" on public.products;
create policy "Store owners can update own products"
on public.products for update
to authenticated
using (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
);

drop policy if exists "Store owners can delete own products" on public.products;
create policy "Store owners can delete own products"
on public.products for delete
to authenticated
using (
  exists (
    select 1 from public.stores
    where stores.id = products.store_id
      and stores.owner_id = auth.uid()
  )
);

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at
before update on public.products
for each row execute function public.set_updated_at();
