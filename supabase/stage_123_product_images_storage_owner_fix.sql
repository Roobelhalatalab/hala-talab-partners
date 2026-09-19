-- Hala Talab Partners - Stage 123
-- Definitive product image Storage RLS repair for newly-created stores.
-- Safe to run after Stage 122.

-- Resolve the current merchant's store through a SECURITY DEFINER helper.
-- This avoids nested RLS on public.stores while evaluating storage.objects policies.
create or replace function public.current_owned_store_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select s.id
  from public.stores s
  where s.owner_id = auth.uid()
  limit 1
$$;

revoke all on function public.current_owned_store_id() from public;
grant execute on function public.current_owned_store_id() to authenticated;

-- Keep the bucket deterministic.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images', 'product-images', true, 5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Replace every Hala Talab product-image policy with owner-folder policies that
-- do not depend on public.stores RLS while Storage is evaluating the request.
drop policy if exists "Store owners upload product images" on storage.objects;
drop policy if exists "Store owners update product images" on storage.objects;
drop policy if exists "Store owners delete product images" on storage.objects;
drop policy if exists "Public can view product images" on storage.objects;
drop policy if exists "Hala Talab product image insert" on storage.objects;
drop policy if exists "Hala Talab product image update" on storage.objects;
drop policy if exists "Hala Talab product image delete" on storage.objects;
drop policy if exists "Hala Talab product image select" on storage.objects;

create policy "Hala Talab product image insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and public.current_owned_store_id() is not null
  and (storage.foldername(name))[1] = public.current_owned_store_id()::text
);

create policy "Hala Talab product image update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'product-images'
  and public.current_owned_store_id() is not null
  and (storage.foldername(name))[1] = public.current_owned_store_id()::text
)
with check (
  bucket_id = 'product-images'
  and public.current_owned_store_id() is not null
  and (storage.foldername(name))[1] = public.current_owned_store_id()::text
);

create policy "Hala Talab product image delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'product-images'
  and public.current_owned_store_id() is not null
  and (storage.foldername(name))[1] = public.current_owned_store_id()::text
);

create policy "Hala Talab product image select"
on storage.objects
for select
to public
using (bucket_id = 'product-images');

notify pgrst, 'reload schema';

-- Diagnostic result: when run in SQL Editor this confirms setup objects exist.
select
  exists(select 1 from storage.buckets where id = 'product-images') as product_images_bucket_ready,
  to_regprocedure('public.current_owned_store_id()') is not null as owner_helper_ready;
