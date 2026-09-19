-- Hala Talab Partners - Stage 125
-- Simplified store workflow: New -> Preparing (one accept tap) -> Ready for pickup.
-- Driver owns the workflow after Ready. Safe to run more than once.

alter table public.orders add column if not exists preparing_at timestamptz;
alter table public.orders add column if not exists rejected_at timestamptz;
alter table public.orders add column if not exists accepted_at timestamptz;
alter table public.orders add column if not exists ready_at timestamptz;
alter table public.orders add column if not exists updated_at timestamptz default now();

create or replace function public.update_my_store_order_status(
  p_order_id uuid,
  p_new_status text
)
returns setof public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_store_id uuid;
  v_allowed boolean := false;
  v_now timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select o.* into v_order
  from public.orders o
  join public.stores s on s.id = o.store_id
  where o.id = p_order_id
    and s.owner_id = auth.uid()
  for update of o;

  if not found then
    raise exception 'Order not found for this store';
  end if;

  v_store_id := v_order.store_id;

  -- Store only has two operational actions:
  -- pending -> preparing (Accept order also starts preparation)
  -- preparing -> ready (Ready for pickup)
  v_allowed := case v_order.status
    when 'pending' then p_new_status in ('preparing', 'rejected')
    when 'accepted' then p_new_status = 'preparing' -- compatibility for older in-flight orders
    when 'preparing' then p_new_status = 'ready'
    else false
  end;

  if not v_allowed then
    raise exception 'Invalid order transition: % -> %', v_order.status, p_new_status;
  end if;

  update public.orders
  set
    status = p_new_status,
    updated_at = v_now,
    -- Direct acceptance into preparing records both acceptance and preparation time.
    accepted_at = case
      when p_new_status = 'preparing' and accepted_at is null then v_now
      else accepted_at
    end,
    preparing_at = case when p_new_status = 'preparing' then v_now else preparing_at end,
    ready_at = case when p_new_status = 'ready' then v_now else ready_at end,
    rejected_at = case when p_new_status = 'rejected' then v_now else rejected_at end
  where id = p_order_id
    and store_id = v_store_id;

  return query
  select * from public.orders where id = p_order_id;
end;
$$;

revoke all on function public.update_my_store_order_status(uuid, text) from public;
grant execute on function public.update_my_store_order_status(uuid, text) to authenticated;

notify pgrst, 'reload schema';

select
  to_regprocedure('public.update_my_store_order_status(uuid,text)') is not null as store_order_rpc_ready,
  true as stage_125_ready;
