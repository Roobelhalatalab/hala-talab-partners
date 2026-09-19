-- Hala Talab Partners - Stage 95
-- Private storage for store verification documents.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'store-documents',
  'store-documents',
  false,
  8388608,
  array['application/pdf','image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Store owners can manage only files inside their own store-id folder.
drop policy if exists "store_documents_insert_own" on storage.objects;
create policy "store_documents_insert_own"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'store-documents'
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[1] = s.id::text
  )
);

drop policy if exists "store_documents_select_own" on storage.objects;
create policy "store_documents_select_own"
on storage.objects for select
to authenticated
using (
  bucket_id = 'store-documents'
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[1] = s.id::text
  )
);

drop policy if exists "store_documents_update_own" on storage.objects;
create policy "store_documents_update_own"
on storage.objects for update
to authenticated
using (
  bucket_id = 'store-documents'
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[1] = s.id::text
  )
)
with check (
  bucket_id = 'store-documents'
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[1] = s.id::text
  )
);

drop policy if exists "store_documents_delete_own" on storage.objects;
create policy "store_documents_delete_own"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'store-documents'
  and exists (
    select 1 from public.stores s
    where s.owner_id = auth.uid()
      and (storage.foldername(name))[1] = s.id::text
  )
);

notify pgrst, 'reload schema';

select exists(select 1 from storage.buckets where id = 'store-documents') as store_documents_bucket_ready;
