-- Hala Talab — Partners Stage 186
-- Driver store-scoped ready-order notifications.
-- Safe/idempotent. Keeps Stage 185 assignment rules and existing push pipeline.

begin;

-- A ready order is an OFFER to every active driver who is allowed to serve
-- that store. The actual claim remains atomic in claim_driver_delivery_offer().
create or replace function public.hala_notify_eligible_drivers_ready_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'ready' or new.driver_id is not null then
    return new;
  end if;

  -- Only fan out when the order becomes ready (or its store changes while ready).
  if tg_op = 'UPDATE'
     and old.status is not distinct from new.status
     and old.store_id is not distinct from new.store_id
     and old.driver_id is not distinct from new.driver_id then
    return new;
  end if;

  insert into public.driver_notifications(
    driver_id, order_id, order_number, event_type
  )
  select
    d.driver_id,
    new.id,
    new.order_number::text,
    'available'
  from public.driver_delivery_scope d
  where d.is_active = true
    and (
      d.driver_type = 'hala'
      or (d.driver_type = 'store' and d.store_id = new.store_id)
    )
  on conflict (driver_id, order_id, event_type) do nothing;

  return new;
end;
$$;

revoke all on function public.hala_notify_eligible_drivers_ready_order() from public;

drop trigger if exists hala_orders_ready_driver_fanout on public.orders;
create trigger hala_orders_ready_driver_fanout
after insert or update of status, driver_id, store_id on public.orders
for each row execute function public.hala_notify_eligible_drivers_ready_order();

-- If Admin assigns a driver to a store while ready orders already exist,
-- notify that driver about currently available work without touching orders.
create or replace function public.hala_notify_driver_after_scope_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active is not true then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.is_active is not distinct from new.is_active
     and old.driver_type is not distinct from new.driver_type
     and old.store_id is not distinct from new.store_id then
    return new;
  end if;

  insert into public.driver_notifications(
    driver_id, order_id, order_number, event_type
  )
  select new.driver_id, q.id, q.order_number::text, 'available'
  from (
    select o.id, o.order_number
    from public.orders o
    where o.status = 'ready'
      and o.driver_id is null
      and (
        new.driver_type = 'hala'
        or (new.driver_type = 'store' and o.store_id = new.store_id)
      )
    order by o.ready_at nulls last, o.created_at
    limit 10
  ) q
  on conflict (driver_id, order_id, event_type) do nothing;

  return new;
end;
$$;

revoke all on function public.hala_notify_driver_after_scope_assignment() from public;

drop trigger if exists hala_driver_scope_ready_backfill on public.driver_delivery_scope;
create trigger hala_driver_scope_ready_backfill
after insert or update of driver_type, store_id, is_active on public.driver_delivery_scope
for each row execute function public.hala_notify_driver_after_scope_assignment();

-- Ensure realtime remains active for in-app notification refresh.
alter table public.driver_notifications replica identity full;
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'driver_notifications'
  ) then
    alter publication supabase_realtime add table public.driver_notifications;
  end if;
end
$$;

commit;

notify pgrst, 'reload schema';

select
  to_regprocedure('public.hala_notify_eligible_drivers_ready_order()') is not null as ready_fanout_function_ready,
  exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname='public' and c.relname='orders'
      and t.tgname='hala_orders_ready_driver_fanout' and t.tgenabled <> 'D'
  ) as ready_fanout_trigger_ready,
  exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname='public' and c.relname='driver_delivery_scope'
      and t.tgname='hala_driver_scope_ready_backfill' and t.tgenabled <> 'D'
  ) as assignment_backfill_trigger_ready;
