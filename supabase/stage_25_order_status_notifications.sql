-- Hala Talab Partners - Stage 25: Order accepted/cancelled notifications
-- Safe to run more than once. Does not delete existing data.

create extension if not exists pgcrypto;

-- Notifications that will be read by the customer application.
create table if not exists public.customer_notifications (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid references public.orders(id) on delete cascade,
  type text not null default 'order_update',
  title text not null,
  body text,
  data jsonb not null default '{}'::jsonb,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists customer_notifications_customer_created_idx
  on public.customer_notifications(customer_id, created_at desc);
create index if not exists customer_notifications_unread_idx
  on public.customer_notifications(customer_id, is_read)
  where is_read = false;
create index if not exists customer_notifications_order_idx
  on public.customer_notifications(order_id);

alter table public.customer_notifications enable row level security;

drop policy if exists "Customers can view own notifications" on public.customer_notifications;
create policy "Customers can view own notifications"
on public.customer_notifications for select
to authenticated
using (customer_id = auth.uid());

drop policy if exists "Customers can update own notifications" on public.customer_notifications;
create policy "Customers can update own notifications"
on public.customer_notifications for update
to authenticated
using (customer_id = auth.uid())
with check (customer_id = auth.uid());

drop policy if exists "Customers can delete own notifications" on public.customer_notifications;
create policy "Customers can delete own notifications"
on public.customer_notifications for delete
to authenticated
using (customer_id = auth.uid());

-- Create a customer notification whenever the store accepts or rejects an order.
create or replace function public.notify_customer_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  order_label text;
  notification_title text;
  notification_body text;
  notification_type text;
begin
  if old.status is not distinct from new.status then
    return new;
  end if;

  if new.customer_id is null then
    return new;
  end if;

  order_label := coalesce(new.order_number::text, left(new.id::text, 8));

  if new.status = 'accepted' then
    notification_type := 'order_accepted';
    notification_title := 'تم قبول طلبك #' || order_label;
    notification_body := 'وافق المتجر على طلبك وسيبدأ تجهيزه الآن.';
  elsif new.status = 'rejected' then
    notification_type := 'order_rejected';
    notification_title := 'تعذر قبول طلبك #' || order_label;
    notification_body := 'اعتذر المتجر عن قبول الطلب. يمكنك اختيار متجر آخر.';
  elsif new.status = 'cancelled' then
    notification_type := 'order_cancelled';
    notification_title := 'تم إلغاء طلبك #' || order_label;
    notification_body := 'تم إلغاء الطلب بنجاح.';
  else
    return new;
  end if;

  insert into public.customer_notifications(
    customer_id, order_id, type, title, body, data
  ) values (
    new.customer_id,
    new.id,
    notification_type,
    notification_title,
    notification_body,
    jsonb_build_object(
      'order_id', new.id,
      'order_number', new.order_number,
      'store_id', new.store_id,
      'status', new.status
    )
  );

  return new;
end;
$$;

drop trigger if exists orders_notify_customer_status on public.orders;
create trigger orders_notify_customer_status
after update of status on public.orders
for each row execute function public.notify_customer_order_status();

-- Notify the store in real time if a customer cancels an order.
create or replace function public.notify_store_customer_cancelled_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status is distinct from new.status and new.status = 'cancelled' then
    insert into public.store_notifications(store_id, type, title, body, data)
    values (
      new.store_id,
      'order_cancelled',
      'تم إلغاء الطلب #' || coalesce(new.order_number::text, left(new.id::text, 8)),
      'ألغى العميل الطلب. افتح صفحة الطلبات للاطلاع على التفاصيل.',
      jsonb_build_object('order_id', new.id, 'status', new.status)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists orders_notify_store_customer_cancelled on public.orders;
create trigger orders_notify_store_customer_cancelled
after update of status on public.orders
for each row execute function public.notify_store_customer_cancelled_order();

-- Enable realtime for the customer application and keep store notifications live.
alter table public.customer_notifications replica identity full;
alter table public.store_notifications replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'customer_notifications'
  ) then
    alter publication supabase_realtime add table public.customer_notifications;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'store_notifications'
  ) then
    alter publication supabase_realtime add table public.store_notifications;
  end if;
end $$;

notify pgrst, 'reload schema';

select
  to_regclass('public.orders') as orders,
  to_regclass('public.store_notifications') as store_notifications,
  to_regclass('public.customer_notifications') as customer_notifications;
