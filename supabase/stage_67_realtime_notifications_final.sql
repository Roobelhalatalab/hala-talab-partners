-- Hala Talab Partners - Stage 67
-- Final store notifications + Realtime + unread badge repair.
-- Safe to run more than once. Does not delete existing notifications or orders.

create extension if not exists pgcrypto;

create table if not exists public.store_notifications (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  type text not null default 'system',
  title text not null,
  body text,
  data jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists store_notifications_store_created_idx
  on public.store_notifications(store_id, created_at desc);
create index if not exists store_notifications_unread_idx
  on public.store_notifications(store_id, created_at desc) where is_read = false;

alter table public.store_notifications enable row level security;

drop policy if exists "Store owners can view notifications" on public.store_notifications;
create policy "Store owners can view notifications" on public.store_notifications
for select to authenticated using (exists (
  select 1 from public.stores s where s.id = store_notifications.store_id and s.owner_id = auth.uid()
));
drop policy if exists "Store owners can update notifications" on public.store_notifications;
create policy "Store owners can update notifications" on public.store_notifications
for update to authenticated using (exists (
  select 1 from public.stores s where s.id = store_notifications.store_id and s.owner_id = auth.uid()
)) with check (exists (
  select 1 from public.stores s where s.id = store_notifications.store_id and s.owner_id = auth.uid()
));
drop policy if exists "Store owners can delete notifications" on public.store_notifications;
create policy "Store owners can delete notifications" on public.store_notifications
for delete to authenticated using (exists (
  select 1 from public.stores s where s.id = store_notifications.store_id and s.owner_id = auth.uid()
));

create or replace function public.get_my_store_unread_notification_count()
returns bigint language sql stable security definer set search_path = public as $$
  select count(*)::bigint from public.store_notifications n
  join public.stores s on s.id=n.store_id
  where s.owner_id=auth.uid() and n.is_read=false;
$$;

create or replace function public.mark_all_my_store_notifications_read()
returns integer language plpgsql security definer set search_path=public as $$
declare affected integer;
begin
  update public.store_notifications n set is_read=true, read_at=now()
  from public.stores s
  where s.id=n.store_id and s.owner_id=auth.uid() and n.is_read=false;
  get diagnostics affected = row_count;
  return affected;
end; $$;

grant execute on function public.get_my_store_unread_notification_count() to authenticated;
grant execute on function public.mark_all_my_store_notifications_read() to authenticated;

-- IMPORTANT: previous notification SQL used orders.total_amount, while the live
-- orders schema uses orders.total. This replacement makes new-order insertion safe.
create or replace function public.notify_store_new_order()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.store_notifications(store_id,type,title,body,data,is_read)
  values (
    new.store_id,
    'new_order',
    'طلب جديد #' || coalesce(new.order_number::text,left(new.id::text,8)),
    'وصل طلب جديد بقيمة ' || coalesce(new.total,0)::text || ' د.ع',
    jsonb_build_object('order_id',new.id,'order_number',new.order_number,'status',new.status,'total',new.total),
    false
  );
  return new;
end; $$;

drop trigger if exists orders_create_store_notification on public.orders;
create trigger orders_create_store_notification after insert on public.orders
for each row execute function public.notify_store_new_order();

-- Ensure the two tables used by the apps are included in the Realtime publication.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='store_notifications') then
    alter publication supabase_realtime add table public.store_notifications;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='orders') then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;

notify pgrst, 'reload schema';
select to_regclass('public.store_notifications') as store_notifications,
       to_regprocedure('public.get_my_store_unread_notification_count()') as unread_rpc,
       to_regprocedure('public.notify_store_new_order()') as new_order_trigger_function,
       true as stage_67_ready;
