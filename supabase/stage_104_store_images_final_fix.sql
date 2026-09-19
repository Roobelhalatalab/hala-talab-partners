-- Hala Talab Partners - Stage 104
-- Dedicated store logo/cover storage with owner-only writes and public reads.
-- Run this ONCE in Supabase SQL Editor before testing store logo/cover upload.

alter table public.stores add column if not exists logo_url text;
alter table public.stores add column if not exists cover_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'store-images',
  'store-images',
  true,
  10485760,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Object paths are: <auth.uid>/<store_id>/<logo-or-cover>-<timestamp>.<ext>
-- Using auth.uid as the first folder makes ownership checks stable even if
-- store ids use a different database type.
drop policy if exists "Store owners upload store images" on storage.objects;
create policy "Store owners upload store images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'store-images'
  and (storage.foldername(name))[1] = auth.uid()::text
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[2] = s.id::text
  )
);

drop policy if exists "Public can view store images" on storage.objects;
create policy "Public can view store images"
on storage.objects for select to public
using (bucket_id = 'store-images');

drop policy if exists "Store owners update store images" on storage.objects;
create policy "Store owners update store images"
on storage.objects for update to authenticated
using (
  bucket_id = 'store-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'store-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Store owners delete store images" on storage.objects;
create policy "Store owners delete store images"
on storage.objects for delete to authenticated
using (
  bucket_id = 'store-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Re-assert the store update policy used to persist logo_url / cover_url.
alter table public.stores enable row level security;
drop policy if exists "Store owners can update own store" on public.stores;
create policy "Store owners can update own store"
on public.stores for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

notify pgrst, 'reload schema';

select
  exists(select 1 from storage.buckets where id = 'store-images') as store_images_bucket_ready,
  exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='stores' and column_name='logo_url'
  ) as logo_url_ready,
  exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='stores' and column_name='cover_url'
  ) as cover_url_ready;
