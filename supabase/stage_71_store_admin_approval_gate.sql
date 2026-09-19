-- Hala Talab Partners - Stage 71
-- Admin approval gate for new stores.
-- Safe to run more than once. Existing data is preserved.
--
-- Result:
-- 1) A newly created store is always pending, inactive and closed.
-- 2) The store owner cannot approve/activate their own store.
-- 3) A store cannot be opened before admin approval + activation.
-- 4) Admin/service-role updates remain possible.

create or replace function public.enforce_store_admin_approval_gate()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_jwt_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if tg_op = 'INSERT' then
    if auth.uid() = new.owner_id and v_jwt_role <> 'service_role' then
      new.approval_status := 'pending';
      new.is_active := false;
      new.is_open := false;
    end if;
  elsif tg_op = 'UPDATE' then
    -- Store owners may edit store content/settings, but approval and activation
    -- belong to administration only.
    if auth.uid() = old.owner_id and v_jwt_role <> 'service_role' then
      new.approval_status := old.approval_status;
      new.is_active := old.is_active;
    end if;
  end if;

  -- No store can be open unless it has passed admin review and is active.
  if coalesce(new.approval_status, 'pending') <> 'approved'
     or coalesce(new.is_active, false) = false then
    new.is_open := false;
  end if;

  return new;
end;
$$;

drop trigger if exists stores_admin_approval_gate on public.stores;
create trigger stores_admin_approval_gate
before insert or update on public.stores
for each row execute function public.enforce_store_admin_approval_gate();

-- Repair any old store that is not approved but was accidentally left open/active.
update public.stores
set is_open = false,
    is_active = case when approval_status = 'approved' then is_active else false end
where approval_status is distinct from 'approved'
   or is_active is distinct from true;
