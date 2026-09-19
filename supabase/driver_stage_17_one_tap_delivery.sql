-- Hala Talab Driver Stage 17 — one-tap delivery completion
-- Removes code/photo requirement from the active driver flow without dropping legacy columns.
create or replace function public.driver_complete_order_one_tap(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_order public.orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_order from public.orders where id=p_order_id and driver_id=auth.uid() and status='picked_up' for update;
  if v_order.id is null then raise exception 'Order is not available for delivery completion'; end if;
  update public.orders set status='delivered', delivered_at=coalesce(delivered_at,now()), updated_at=now() where id=p_order_id returning * into v_order;
  return jsonb_build_object('order_id',v_order.id,'order_number',v_order.order_number,'status',v_order.status,'delivered_at',v_order.delivered_at);
end; $$;
revoke all on function public.driver_complete_order_one_tap(uuid) from public;
grant execute on function public.driver_complete_order_one_tap(uuid) to authenticated;
notify pgrst,'reload schema';
select to_regprocedure('public.driver_complete_order_one_tap(uuid)') as one_tap_delivery_rpc;
