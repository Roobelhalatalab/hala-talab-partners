-- Stage 107: align driver assignment and pickup confirmation states.
-- Safe to run more than once.

create or replace function public.driver_confirm_order_pickup(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.orders o
     set status = 'picked_up',
         picked_up_at = coalesce(o.picked_up_at, now()),
         updated_at = now()
   where o.id = p_order_id
     and o.driver_id = auth.uid()
     and o.status in ('assigned', 'ready')
  returning o.* into v_order;

  if v_order.id is null then
    raise exception 'Order is not available for pickup confirmation';
  end if;

  return public.get_current_driver_assigned_order();
end;
$$;

revoke all on function public.driver_confirm_order_pickup(uuid) from public;
grant execute on function public.driver_confirm_order_pickup(uuid) to authenticated;

notify pgrst, 'reload schema';
