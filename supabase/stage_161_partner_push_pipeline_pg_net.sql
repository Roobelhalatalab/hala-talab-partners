-- Superseded by stage_163_partner_push_complete.sql. Kept for history.
-- Hala Talab Partners — Stage 161
-- Production push pipeline for Store + Driver notifications using pg_net.
-- Customer push remains untouched and continues through the same send-push Edge Function.
-- Run ONCE after deploying supabase/functions/send-push from Stage 161.
-- Safe to re-run: functions + triggers are replaced idempotently.

begin;

create extension if not exists pg_net;

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
    raise exception 'pg_net is not available. Enable pg_net in Supabase Database > Extensions, then re-run Stage 161 SQL.';
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
      'record', to_jsonb(new), 'old_record', null
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
      'record', to_jsonb(new), 'old_record', null
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
