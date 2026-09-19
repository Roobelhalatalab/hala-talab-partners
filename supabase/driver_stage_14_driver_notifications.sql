-- Hala Talab Partners - Driver Stage 14
-- Driver in-app notifications for real delivery lifecycle updates.
-- Safe to run more than once. Existing store notification tables are untouched.

create table if not exists public.driver_notifications (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid references public.orders(id) on delete cascade,
  order_number text,
  event_type text not null,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique (driver_id, order_id, event_type)
);

create index if not exists driver_notifications_driver_created_idx
  on public.driver_notifications(driver_id, created_at desc);

alter table public.driver_notifications enable row level security;

drop policy if exists "driver_notifications_select_own" on public.driver_notifications;
create policy "driver_notifications_select_own"
on public.driver_notifications for select
to authenticated
using (driver_id = auth.uid());

drop policy if exists "driver_notifications_update_own" on public.driver_notifications;
create policy "driver_notifications_update_own"
on public.driver_notifications for update
to authenticated
using (driver_id = auth.uid())
with check (driver_id = auth.uid());

drop policy if exists "driver_notifications_delete_own" on public.driver_notifications;
create policy "driver_notifications_delete_own"
on public.driver_notifications for delete
to authenticated
using (driver_id = auth.uid());

create or replace function public.create_driver_order_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event text;
begin
  if new.driver_id is null then
    return new;
  end if;

  if old.driver_id is distinct from new.driver_id and new.driver_id is not null then
    v_event := 'assigned';
  elsif old.status is distinct from new.status
        and new.status in ('assigned', 'picked_up', 'delivered', 'cancelled', 'canceled') then
    v_event := new.status;
  else
    return new;
  end if;

  insert into public.driver_notifications(driver_id, order_id, order_number, event_type)
  values (new.driver_id, new.id, new.order_number::text, v_event)
  on conflict (driver_id, order_id, event_type) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_driver_order_notification on public.orders;
create trigger trg_driver_order_notification
after update of driver_id, status on public.orders
for each row execute function public.create_driver_order_notification();

create or replace function public.mark_all_my_driver_notifications_read()
returns void
language sql
security definer
set search_path = public
as $$
  update public.driver_notifications
  set is_read = true,
      read_at = coalesce(read_at, now())
  where driver_id = auth.uid()
    and is_read = false;
$$;

revoke all on function public.mark_all_my_driver_notifications_read() from public;
grant execute on function public.mark_all_my_driver_notifications_read() to authenticated;

notify pgrst, 'reload schema';

select
  to_regclass('public.driver_notifications') as driver_notifications_table,
  to_regprocedure('public.mark_all_my_driver_notifications_read()') as mark_all_rpc;
