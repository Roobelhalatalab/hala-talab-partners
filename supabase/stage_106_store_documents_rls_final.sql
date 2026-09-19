-- Hala Talab Partners - Stage 106
-- Final private Storage policies for optional store verification documents.
-- Each authenticated partner may manage only files inside their own auth UUID folder.

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

-- Remove all earlier variants so there is one unambiguous policy set.
drop policy if exists "store_documents_insert_own" on storage.objects;
drop policy if exists "store_documents_select_own" on storage.objects;
drop policy if exists "store_documents_update_own" on storage.objects;
drop policy if exists "store_documents_delete_own" on storage.objects;
drop policy if exists "store_documents_insert_user_folder" on storage.objects;
drop policy if exists "store_documents_select_user_folder" on storage.objects;
drop policy if exists "store_documents_update_user_folder" on storage.objects;
drop policy if exists "store_documents_delete_user_folder" on storage.objects;

create policy "store_documents_insert_user_folder"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'store-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "store_documents_select_user_folder"
on storage.objects for select
to authenticated
using (
  bucket_id = 'store-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "store_documents_update_user_folder"
on storage.objects for update
to authenticated
using (
  bucket_id = 'store-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'store-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "store_documents_delete_user_folder"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'store-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

notify pgrst, 'reload schema';

select
  exists(select 1 from storage.buckets where id = 'store-documents') as store_documents_bucket_ready,
  exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='store_documents_insert_user_folder') as insert_policy_ready,
  exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='store_documents_select_user_folder') as select_policy_ready,
  exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='store_documents_delete_user_folder') as delete_policy_ready;
