-- Hala Talab Partners - Stage 72
-- Allow a store owner to read only the admin review of their own store.
-- The Partner app merges admin_store_reviews.review_status into approval_status
-- so it displays the exact same review decision as the Admin dashboard.

alter table public.admin_store_reviews enable row level security;

drop policy if exists "partner read own store review" on public.admin_store_reviews;
create policy "partner read own store review"
on public.admin_store_reviews
for select
to authenticated
using (
  exists (
    select 1
    from public.stores s
    where s.id = admin_store_reviews.store_id
      and s.owner_id = auth.uid()
  )
);
