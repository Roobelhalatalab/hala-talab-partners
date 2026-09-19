-- Hala Talab partners - Stage 31: product images in Supabase Storage
alter table public.products add column if not exists image_url text;
alter table public.products add column if not exists image_path text;

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

-- Each store owner can upload only inside their store-id folder.
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

select
  to_regclass('public.products') as products,
  exists(select 1 from storage.buckets where id = 'product-images') as product_images_bucket_ready;
