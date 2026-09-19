-- Hala Talab Partners - Stage 28
-- Unified Supabase connection for all store/customer notifications.
-- Safe to run more than once. Existing notifications are preserved.

create extension if not exists pgcrypto;

-- Store notifications -------------------------------------------------------
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

alter table public.store_notifications
  add column if not exists type text not null default 'system',
  add column if not exists title text,
  add column if not exists body text,
  add column if not exists data jsonb not null default '{}'::jsonb,
  add column if not exists is_read boolean not null default false,
  add column if not exists read_at timestamptz,
  add column if not exists created_at timestamptz not null default now();

update public.store_notifications
set title = coalesce(title, 'إشعار هلا طلب')
where title is null;

alter table public.store_notifications alter column title set not null;

create index if not exists store_notifications_store_created_idx
  on public.store_notifications(store_id, created_at desc);
create index if not exists store_notifications_unread_idx
  on public.store_notifications(store_id, created_at desc)
  where is_read = false;
create index if not exists store_notifications_order_idx
  on public.store_notifications((data->>'order_id'));

alter table public.store_notifications enable row level security;

drop policy if exists "Store owners can view notifications" on public.store_notifications;
create policy "Store owners can view notifications"
on public.store_notifications for select to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = store_notifications.store_id and s.owner_id = auth.uid()
));

drop policy if exists "Store owners can update notifications" on public.store_notifications;
create policy "Store owners can update notifications"
on public.store_notifications for update to authenticated
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
on public.store_notifications for delete to authenticated
using (exists (
  select 1 from public.stores s
  where s.id = store_notifications.store_id and s.owner_id = auth.uid()
));

-- Customer notifications ----------------------------------------------------
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
  on public.customer_notifications(customer_id, created_at desc)
  where is_read = false;
create index if not exists customer_notifications_order_idx
  on public.customer_notifications(order_id);

alter table public.customer_notifications enable row level security;

drop policy if exists "Customers can view own notifications" on public.customer_notifications;
create policy "Customers can view own notifications"
on public.customer_notifications for select to authenticated
using (customer_id = auth.uid());

drop policy if exists "Customers can update own notifications" on public.customer_notifications;
create policy "Customers can update own notifications"
on public.customer_notifications for update to authenticated
using (customer_id = auth.uid())
with check (customer_id = auth.uid());

drop policy if exists "Customers can delete own notifications" on public.customer_notifications;
create policy "Customers can delete own notifications"
on public.customer_notifications for delete to authenticated
using (customer_id = auth.uid());

-- Atomic RPCs used by the Flutter app ---------------------------------------
create or replace function public.get_my_store_unread_notification_count()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)
  from public.store_notifications n
  join public.stores s on s.id = n.store_id
  where s.owner_id = auth.uid() and n.is_read = false;
$$;

grant execute on function public.get_my_store_unread_notification_count() to authenticated;

create or replace function public.mark_all_my_store_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  update public.store_notifications n
  set is_read = true, read_at = now()
  from public.stores s
  where s.id = n.store_id
    and s.owner_id = auth.uid()
    and n.is_read = false;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

grant execute on function public.mark_all_my_store_notifications_read() to authenticated;

-- Trigger: a new order immediately notifies the store ----------------------
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
    'طلب جديد #' || coalesce(new.order_number::text, left(new.id::text, 8)),
    'وصل طلب جديد بقيمة ' || coalesce(new.total_amount, 0)::text || ' د.ع',
    jsonb_build_object(
      'order_id', new.id,
      'order_number', new.order_number,
      'status', new.status,
      'total_amount', new.total_amount
    )
  );
  return new;
end;
$$;

drop trigger if exists orders_create_store_notification on public.orders;
create trigger orders_create_store_notification
after insert on public.orders
for each row execute function public.notify_store_new_order();

-- Trigger: status changes notify the customer ------------------------------
create or replace function public.notify_customer_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  order_label text := coalesce(new.order_number::text, left(new.id::text, 8));
  notification_title text;
  notification_body text;
  notification_type text;
begin
  if old.status is not distinct from new.status or new.customer_id is null then
    return new;
  end if;

  case new.status
    when 'accepted' then
      notification_type := 'order_accepted';
      notification_title := 'تم قبول طلبك #' || order_label;
      notification_body := 'وافق المتجر على طلبك وسيبدأ تجهيزه الآن.';
    when 'preparing' then
      notification_type := 'order_preparing';
      notification_title := 'طلبك قيد التحضير #' || order_label;
      notification_body := 'بدأ المتجر بتحضير طلبك.';
    when 'ready' then
      notification_type := 'order_ready';
      notification_title := 'طلبك جاهز #' || order_label;
      notification_body := 'أصبح طلبك جاهزًا للاستلام أو التسليم للسائق.';
    when 'completed' then
      notification_type := 'order_completed';
      notification_title := 'اكتمل طلبك #' || order_label;
      notification_body := 'تم إكمال الطلب بنجاح. شكرًا لاستخدام هلا طلب.';
    when 'rejected' then
      notification_type := 'order_rejected';
      notification_title := 'تعذر قبول طلبك #' || order_label;
      notification_body := 'اعتذر المتجر عن قبول الطلب. يمكنك اختيار متجر آخر.';
    when 'cancelled' then
      notification_type := 'order_cancelled';
      notification_title := 'تم إلغاء طلبك #' || order_label;
      notification_body := 'تم إلغاء الطلب.';
    else
      return new;
  end case;

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

-- Trigger: customer cancellation immediately notifies the store ------------
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
      jsonb_build_object(
        'order_id', new.id,
        'order_number', new.order_number,
        'status', new.status
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists orders_notify_store_customer_cancelled on public.orders;
create trigger orders_notify_store_customer_cancelled
after update of status on public.orders
for each row execute function public.notify_store_customer_cancelled_order();

-- Welcome notification (one per store) -------------------------------------
insert into public.store_notifications(store_id, type, title, body)
select s.id, 'system', 'مرحباً بك في إشعارات هلا طلب',
       'ستصلك هنا تنبيهات الطلبات الجديدة والتحديثات المهمة الخاصة بمتجرك.'
from public.stores s
where not exists (
  select 1 from public.store_notifications n
  where n.store_id = s.id and n.type = 'system'
);

-- Realtime -----------------------------------------------------------------
alter table public.store_notifications replica identity full;
alter table public.customer_notifications replica identity full;
alter table public.orders replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'store_notifications'
  ) then
    alter publication supabase_realtime add table public.store_notifications;
  end if;

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
      and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;

notify pgrst, 'reload schema';

select
  to_regclass('public.store_notifications') as store_notifications,
  to_regclass('public.customer_notifications') as customer_notifications,
  to_regclass('public.orders') as orders,
  public.get_my_store_unread_notification_count() as my_unread_count;
