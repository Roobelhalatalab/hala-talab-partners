-- Additive V6/V7 compatible: only adds a new AFTER UPDATE trigger.
-- Existing order functions and existing cancellation notifications stay untouched.
create or replace function public.hala_notify_merchant_ring_resolved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status is distinct from new.status
     and old.status = 'pending'
     and new.status is distinct from 'pending' then
    insert into public.store_notifications(store_id, type, title, body, data)
    values (
      new.store_id,
      'merchant_order_resolved',
      'تحديث حالة الطلب',
      'تم تحديث حالة الطلب',
      jsonb_build_object('order_id', new.id::text, 'status', new.status)
    );
  end if;
  return new;
end;
$$;

revoke all on function public.hala_notify_merchant_ring_resolved() from public;

drop trigger if exists hala_merchant_ring_resolved on public.orders;
create trigger hala_merchant_ring_resolved
  after update of status on public.orders
  for each row execute function public.hala_notify_merchant_ring_resolved();
