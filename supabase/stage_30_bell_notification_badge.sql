-- Hala Talab partners - Stage 30
-- Bell unread badge + a one-time unread test notification.
-- Safe to run more than once.

create or replace function public.get_my_store_unread_notification_count()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::bigint
  from public.store_notifications n
  join public.stores s on s.id = n.store_id
  where s.owner_id = auth.uid()
    and n.is_read = false;
$$;

grant execute on function public.get_my_store_unread_notification_count() to authenticated;

-- Adds one unread notification to every store only once, so the red badge can
-- be verified immediately. It may be marked read or deleted from the app.
insert into public.store_notifications (store_id, type, title, body, data, is_read)
select
  s.id,
  'system',
  'عداد الإشعارات يعمل',
  'هذا إشعار تجريبي غير مقروء للتأكد من ظهور الرقم فوق جرس الإشعارات.',
  jsonb_build_object('stage', 30, 'kind', 'bell_badge_test'),
  false
from public.stores s
where not exists (
  select 1
  from public.store_notifications n
  where n.store_id = s.id
    and n.data->>'kind' = 'bell_badge_test'
);

notify pgrst, 'reload schema';

select
  to_regclass('public.store_notifications') as store_notifications,
  public.get_my_store_unread_notification_count() as my_unread_count;
