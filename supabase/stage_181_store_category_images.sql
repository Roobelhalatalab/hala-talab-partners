-- Hala Talab Partners - Stage 181
-- Store product-category images.
-- Safe migration: adds nullable image metadata only; no existing data is removed.

alter table public.product_categories
  add column if not exists image_url text,
  add column if not exists image_path text;

-- Product-images is already the public store-owned image bucket used by the app.
-- Re-assert its public/read and owner-write policies so category images saved
-- under <store_id>/categories/... follow the same secure ownership rules.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Existing Stage 31 policies already validate the first folder as store_id,
-- therefore <store_id>/categories/file.png is automatically covered.

notify pgrst, 'reload schema';

select
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='product_categories' and column_name='image_url'
  ) as category_image_url_ready,
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='product_categories' and column_name='image_path'
  ) as category_image_path_ready,
  exists(select 1 from storage.buckets where id='product-images') as image_bucket_ready;
