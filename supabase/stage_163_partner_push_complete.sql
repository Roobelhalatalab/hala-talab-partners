-- Hala Talab Partners — Stage 163
-- Complete Store + Driver push pipeline.
-- Android + iOS/iPadOS register FCM tokens. Windows keeps in-app realtime.
-- Safe to re-run: tables/policies/functions/triggers are idempotent.

begin;

create extension if not exists pg_net;

create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  platform text not null,
  token text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists device_push_tokens_user_idx
  on public.device_push_tokens(user_id, role);

alter table public.device_push_tokens enable row level security;

drop policy if exists device_push_tokens_own_select on public.device_push_tokens;
create policy device_push_tokens_own_select
  on public.device_push_tokens for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists device_push_tokens_own_insert on public.device_push_tokens;
create policy device_push_tokens_own_insert
  on public.device_push_tokens for insert to authenticated
  with check (
    auth.uid() = user_id
    and role in ('customer', 'business', 'driver')
  );

drop policy if exists device_push_tokens_own_update on public.device_push_tokens;
create policy device_push_tokens_own_update
  on public.device_push_tokens for update to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and role in ('customer', 'business', 'driver')
  );

drop policy if exists device_push_tokens_own_delete on public.device_push_tokens;
create policy device_push_tokens_own_delete
  on public.device_push_tokens for delete to authenticated
  using (auth.uid() = user_id);

do $$
begin
  if to_regclass('public.store_notifications') is null then
    raise exception 'Required table public.store_notifications does not exist';
  end if;
  if to_regclass('public.driver_notifications') is null then
    raise exception 'Required table public.driver_notifications does not exist';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'net' and p.proname = 'http_post'
  ) then
    raise exception 'pg_net is not available';
  end if;
end
$$;

create or replace function public.hala_enqueue_store_notification_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, net
as $$
declare queued_request_id bigint;
begin
  select net.http_post(
    url := 'https://czoqxshblhgwanwsrudk.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'type', 'INSERT', 'table', 'store_notifications', 'schema', 'public',
      'record', jsonb_build_object('id', new.id), 'old_record', null
    ),
    headers := jsonb_build_object('Content-Type', 'application/json'),
    timeout_milliseconds := 5000
  ) into queued_request_id;
  return new;
exception when others then
  raise warning 'Hala Talab store push enqueue failed for notification %: %', new.id, sqlerrm;
  return new;
end;
$$;

create or replace function public.hala_enqueue_driver_notification_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, net
as $$
declare queued_request_id bigint;
begin
  select net.http_post(
    url := 'https://czoqxshblhgwanwsrudk.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'type', 'INSERT', 'table', 'driver_notifications', 'schema', 'public',
      'record', jsonb_build_object('id', new.id), 'old_record', null
    ),
    headers := jsonb_build_object('Content-Type', 'application/json'),
    timeout_milliseconds := 5000
  ) into queued_request_id;
  return new;
exception when others then
  raise warning 'Hala Talab driver push enqueue failed for notification %: %', new.id, sqlerrm;
  return new;
end;
$$;

revoke all on function public.hala_enqueue_store_notification_push() from public;
revoke all on function public.hala_enqueue_driver_notification_push() from public;

drop trigger if exists hala_store_notifications_push on public.store_notifications;
create trigger hala_store_notifications_push
after insert on public.store_notifications
for each row execute function public.hala_enqueue_store_notification_push();

drop trigger if exists hala_driver_notifications_push on public.driver_notifications;
create trigger hala_driver_notifications_push
after insert on public.driver_notifications
for each row execute function public.hala_enqueue_driver_notification_push();

commit;

select
  exists (select 1 from pg_extension where extname='pg_net') as pg_net_ready,
  to_regclass('public.device_push_tokens') is not null as push_tokens_ready,
  to_regprocedure('public.hala_enqueue_store_notification_push()') is not null as store_push_function_ready,
  to_regprocedure('public.hala_enqueue_driver_notification_push()') is not null as driver_push_function_ready,
  exists (
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname='public' and c.relname='store_notifications'
      and t.tgname='hala_store_notifications_push' and t.tgenabled <> 'D'
  ) as store_push_trigger_ready,
  exists (
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname='public' and c.relname='driver_notifications'
      and t.tgname='hala_driver_notifications_push' and t.tgenabled <> 'D'
  ) as driver_push_trigger_ready;
