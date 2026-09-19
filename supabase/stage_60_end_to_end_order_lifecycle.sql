-- Hala Talab Partners - Stage 60
-- End-to-end order lifecycle audit + customer notifications.
-- Safe to run more than once. Existing orders are preserved.

create extension if not exists pgcrypto;

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  customer_id uuid references auth.users(id) on delete set null,
  old_status text,
  new_status text not null,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists order_status_history_order_idx
  on public.order_status_history(order_id, created_at);
create index if not exists order_status_history_store_idx
  on public.order_status_history(store_id, created_at desc);

alter table public.order_status_history enable row level security;

drop policy if exists "Store owners can view own order status history" on public.order_status_history;
create policy "Store owners can view own order status history"
on public.order_status_history for select
to authenticated
using (
  exists (
    select 1 from public.stores s
    where s.id = order_status_history.store_id
      and s.owner_id = auth.uid()
  )
);

drop policy if exists "Customers can view own order status history" on public.order_status_history;
create policy "Customers can view own order status history"
on public.order_status_history for select
to authenticated
using (customer_id = auth.uid());

create or replace function public.record_order_status_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status is distinct from new.status then
    insert into public.order_status_history(
      order_id, store_id, customer_id, old_status, new_status, changed_by
    ) values (
      new.id, new.store_id, new.customer_id, old.status, new.status, auth.uid()
    );
  end if;
  return new;
end;
$$;

drop trigger if exists orders_record_status_history on public.orders;
create trigger orders_record_status_history
after update of status on public.orders
for each row execute function public.record_order_status_history();

-- Full customer-facing lifecycle notifications.
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
      notification_body := 'وافق المتجر على طلبك.';
    when 'preparing' then
      notification_type := 'order_preparing';
      notification_title := 'طلبك قيد التحضير #' || order_label;
      notification_body := 'بدأ المتجر بتجهيز طلبك.';
    when 'ready' then
      notification_type := 'order_ready';
      notification_title := 'طلبك جاهز #' || order_label;
      notification_body := 'أصبح طلبك جاهزًا للاستلام أو التسليم للسائق.';
    when 'assigned' then
      notification_type := 'driver_assigned';
      notification_title := 'تم تعيين سائق لطلبك #' || order_label;
      notification_body := 'سيتم استلام الطلب من المتجر قريبًا.';
    when 'picked_up' then
      notification_type := 'order_picked_up';
      notification_title := 'طلبك في الطريق #' || order_label;
      notification_body := 'استلم السائق طلبك من المتجر.';
    when 'delivered' then
      notification_type := 'order_delivered';
      notification_title := 'تم تسليم طلبك #' || order_label;
      notification_body := 'تم تسليم الطلب بنجاح. شكرًا لاستخدام هلا طلب.';
    when 'rejected' then
      notification_type := 'order_rejected';
      notification_title := 'تعذر قبول طلبك #' || order_label;
      notification_body := 'اعتذر المتجر عن قبول الطلب.';
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

alter table public.orders replica identity full;
alter table public.order_status_history replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'order_status_history'
  ) then
    alter publication supabase_realtime add table public.order_status_history;
  end if;
end $$;

notify pgrst, 'reload schema';

select
  to_regclass('public.orders') as orders,
  to_regclass('public.order_items') as order_items,
  to_regclass('public.order_status_history') as order_status_history,
  to_regclass('public.customer_notifications') as customer_notifications;
