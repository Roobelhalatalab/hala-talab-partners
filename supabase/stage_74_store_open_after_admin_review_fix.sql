-- Hala Talab Partners - Stage 74
-- Fix opening an admin-approved store when stores.approval_status is stale.
-- Safe to run more than once.

-- Keep stores.approval_status synchronized with the authoritative admin review.
create or replace function public.sync_store_approval_from_admin_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.stores
     set approval_status = coalesce(new.review_status, 'pending')
   where id = new.store_id
     and approval_status is distinct from coalesce(new.review_status, 'pending');
  return new;
end;
$$;

drop trigger if exists sync_store_approval_from_admin_review_trigger on public.admin_store_reviews;
create trigger sync_store_approval_from_admin_review_trigger
after insert or update of review_status on public.admin_store_reviews
for each row execute function public.sync_store_approval_from_admin_review();

-- Repair existing stores from their current admin review decision.
update public.stores s
   set approval_status = r.review_status
  from public.admin_store_reviews r
 where r.store_id = s.id
   and r.review_status is not null
   and s.approval_status is distinct from r.review_status;

-- Approval gate: owner still cannot approve/activate themselves, but opening is
-- validated against the authoritative admin review if the legacy store field is stale.
create or replace function public.enforce_store_admin_approval_gate()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_jwt_role text := coalesce(auth.jwt() ->> 'role', '');
  v_effective_approval text;
begin
  if tg_op = 'INSERT' then
    if auth.uid() = new.owner_id and v_jwt_role <> 'service_role' then
      new.approval_status := 'pending';
      new.is_active := false;
      new.is_open := false;
    end if;
  elsif tg_op = 'UPDATE' then
    -- Store owners may change open/closed and content, but cannot self-approve
    -- or self-activate.
    if auth.uid() = old.owner_id and v_jwt_role <> 'service_role' then
      new.approval_status := old.approval_status;
      new.is_active := old.is_active;
    end if;
  end if;

  v_effective_approval := coalesce(new.approval_status, 'pending');

  -- The admin review table is authoritative. This also covers old stores whose
  -- stores.approval_status was left as pending before Stage 74.
  select coalesce(r.review_status, v_effective_approval)
    into v_effective_approval
    from public.admin_store_reviews r
   where r.store_id = new.id
   limit 1;

  if coalesce(v_effective_approval, 'pending') <> 'approved'
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
