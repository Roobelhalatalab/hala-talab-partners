-- Hala Talab Partners - Stage 122
-- Product save repair for newly-created/approved stores.
-- Safe to run once after Stage 121.

alter table public.products
  add column if not exists image_url text,
  add column if not exists image_path text,
  add column if not exists preparation_time_minutes integer,
  add column if not exists calories integer,
  add column if not exists notes text,
  add column if not exists tags text[] not null default '{}',
  add column if not exists product_type text not null default 'single',
  add column if not exists brand text,
  add column if not exists barcode text,
  add column if not exists sku text,
  add column if not exists unit text not null default 'piece',
  add column if not exists track_stock boolean not null default false,
  add column if not exists stock_quantity numeric,
  add column if not exists size_label text,
  add column if not exists weight_value numeric,
  add column if not exists weight_unit text not null default 'g',
  add column if not exists catalog_kind text not null default 'restaurant';

alter table public.products enable row level security;

drop policy if exists "Store owners can view own products" on public.products;
create policy "Store owners can view own products"
on public.products for select to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = products.store_id and s.owner_id = auth.uid()
));

drop policy if exists "Store owners can create own products" on public.products;
create policy "Store owners can create own products"
on public.products for insert to authenticated
with check (exists (
  select 1 from public.stores s
  where s.id = products.store_id and s.owner_id = auth.uid()
));

drop policy if exists "Store owners can update own products" on public.products;
create policy "Store owners can update own products"
on public.products for update to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = products.store_id and s.owner_id = auth.uid()
))
with check (exists (
  select 1 from public.stores s
  where s.id = products.store_id and s.owner_id = auth.uid()
));

drop policy if exists "Store owners can delete own products" on public.products;
create policy "Store owners can delete own products"
on public.products for delete to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = products.store_id and s.owner_id = auth.uid()
));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images', 'product-images', true, 5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Store owners upload product images" on storage.objects;
create policy "Store owners upload product images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[1] = s.id::text
  )
);

drop policy if exists "Public can view product images" on storage.objects;
create policy "Public can view product images"
on storage.objects for select to public
using (bucket_id = 'product-images');

drop policy if exists "Store owners update product images" on storage.objects;
create policy "Store owners update product images"
on storage.objects for update to authenticated
using (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[1] = s.id::text
  )
)
with check (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[1] = s.id::text
  )
);

drop policy if exists "Store owners delete product images" on storage.objects;
create policy "Store owners delete product images"
on storage.objects for delete to authenticated
using (
  bucket_id = 'product-images'
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[1] = s.id::text
  )
);

notify pgrst, 'reload schema';
