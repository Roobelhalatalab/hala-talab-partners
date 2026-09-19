-- Hala Talab Partners - Stage 24: Realtime new-order notifications
-- Safe to run more than once.

alter table if exists public.store_notifications replica identity full;
alter table if exists public.orders replica identity full;

do $$
begin
  if to_regclass('public.store_notifications') is not null
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'store_notifications'
     ) then
    alter publication supabase_realtime add table public.store_notifications;
  end if;

  if to_regclass('public.orders') is not null
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'orders'
     ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;

notify pgrst, 'reload schema';

select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename in ('store_notifications', 'orders')
order by tablename;
