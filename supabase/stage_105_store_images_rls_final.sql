-- Hala Talab Partners - Stage 105
-- FINAL store logo/cover Storage RLS fix.
-- Run ONCE in Supabase SQL Editor after Stage 104.
--
-- Why Stage 104 could still return 403:
-- its INSERT policy checked public.stores from inside a storage.objects policy.
-- That extra cross-table RLS dependency is unnecessary and can reject a valid
-- authenticated upload. Stage 105 uses the authenticated user's UUID as the
-- only writable root folder and keeps store-row ownership enforced separately.

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

-- New object paths:
--   <auth.uid()>/<logo|cover>/<logo|cover>-<timestamp>.<ext>
-- A signed-in user can write only below their own UUID folder.

drop policy if exists "Store owners upload store images" on storage.objects;
drop policy if exists "Store owners update store images" on storage.objects;
drop policy if exists "Store owners delete store images" on storage.objects;
drop policy if exists "Public can view store images" on storage.objects;

create policy "Store owners upload store images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'store-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Store owners update store images"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'store-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'store-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Store owners delete store images"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'store-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Public can view store images"
on storage.objects
for select
to public
using (bucket_id = 'store-images');

-- Persisting logo_url / cover_url remains owner-protected at the store row.
alter table public.stores enable row level security;
drop policy if exists "Store owners can update own store" on public.stores;
create policy "Store owners can update own store"
on public.stores
for update
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

notify pgrst, 'reload schema';

-- Setup verification only. auth.uid() is expected to be NULL in SQL Editor;
-- this query intentionally does not use it as an app-session test.
select
  exists(select 1 from storage.buckets where id = 'store-images') as store_images_bucket_ready,
  exists(
    select 1 from pg_policies
    where schemaname='storage'
      and tablename='objects'
      and policyname='Store owners upload store images'
  ) as upload_policy_ready,
  exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='stores' and column_name='logo_url'
  ) as logo_url_ready,
  exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='stores' and column_name='cover_url'
  ) as cover_url_ready;
