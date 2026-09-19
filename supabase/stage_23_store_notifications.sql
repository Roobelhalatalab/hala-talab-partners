-- Hala Talab Partners - Stage 23: Store notifications
-- Safe to run more than once.

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
  on public.store_notifications(store_id, is_read) where is_read = false;

alter table public.store_notifications enable row level security;

drop policy if exists "Store owners can view notifications" on public.store_notifications;
create policy "Store owners can view notifications"
on public.store_notifications for select
to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = store_notifications.store_id and s.owner_id = auth.uid()
));

drop policy if exists "Store owners can update notifications" on public.store_notifications;
create policy "Store owners can update notifications"
on public.store_notifications for update
to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = store_notifications.store_id and s.owner_id = auth.uid()
))
with check (exists (
  select 1 from public.stores s
  where s.id = store_notifications.store_id and s.owner_id = auth.uid()
));

drop policy if exists "Store owners can delete notifications" on public.store_notifications;
create policy "Store owners can delete notifications"
on public.store_notifications for delete
to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = store_notifications.store_id and s.owner_id = auth.uid()
));

create or replace function public.notify_store_new_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.store_notifications(store_id, type, title, body, data)
  values (
    new.store_id,
    'new_order',
    'طلب جديد #' || coalesce(new.order_number, left(new.id::text, 8)),
    'وصل طلب جديد بقيمة ' || coalesce(new.total_amount, 0)::text || ' د.ع',
    jsonb_build_object('order_id', new.id, 'status', new.status)
  );
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.orders') is not null then
    execute 'drop trigger if exists orders_create_store_notification on public.orders';
    execute 'create trigger orders_create_store_notification after insert on public.orders for each row execute function public.notify_store_new_order()';
  end if;
end $$;

-- Add one welcome notification for stores that do not have any notification yet.
insert into public.store_notifications(store_id, type, title, body)
select s.id, 'system', 'مرحباً بك في إشعارات هلا طلب',
       'ستصلك هنا تنبيهات الطلبات الجديدة والتحديثات المهمة الخاصة بمتجرك.'
from public.stores s
where not exists (
  select 1 from public.store_notifications n where n.store_id = s.id
);

notify pgrst, 'reload schema';

select to_regclass('public.store_notifications') as store_notifications;
