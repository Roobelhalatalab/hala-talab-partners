-- Hala Talab Partners - Stage 208 Fix7: safe partner account deletion
-- Purpose: allow a store-owner auth account to be deleted without cascading
-- and destroying historical orders. Existing active stores are unchanged.
-- Safe to run more than once.

begin;

alter table public.stores
  drop constraint if exists stores_owner_id_fkey;

alter table public.stores
  alter column owner_id drop not null;

alter table public.stores
  add constraint stores_owner_id_fkey
  foreign key (owner_id) references auth.users(id) on delete set null;

commit;

select
  is_nullable,
  delete_rule
from information_schema.columns c
left join information_schema.referential_constraints r
  on r.constraint_schema='public' and r.constraint_name='stores_owner_id_fkey'
where c.table_schema='public' and c.table_name='stores' and c.column_name='owner_id';
