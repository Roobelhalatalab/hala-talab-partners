-- Hala Talab Partners - Stage 75
-- Final store open/close fix.
-- Run ONCE in Supabase SQL Editor. Safe to run again.

-- 1) Keep the store approval mirror synchronized with the Admin review.
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

update public.stores s
   set approval_status = r.review_status
  from public.admin_store_reviews r
 where r.store_id = s.id
   and r.review_status is not null
   and s.approval_status is distinct from r.review_status;

-- 2) Replace the legacy gate with one rule that uses the Admin review as truth.
create or replace function public.enforce_store_admin_approval_gate()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_effective_approval text := coalesce(new.approval_status, 'pending');
begin
  if tg_op = 'INSERT' then
    if auth.uid() = new.owner_id then
      new.approval_status := 'pending';
      new.is_active := false;
      new.is_open := false;
    end if;
  elsif tg_op = 'UPDATE' then
    -- A store owner may open/close and edit content, but cannot approve or
    -- activate the store by changing protected fields directly.
    if auth.uid() = old.owner_id then
      new.approval_status := old.approval_status;
      new.is_active := old.is_active;
    end if;
  end if;

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

-- 3) Dedicated RPC used by the Partner app. It fails loudly instead of
-- silently leaving the switch unchanged.
create or replace function public.set_my_store_open_status(p_is_open boolean)
returns setof public.stores
language plpgsql
security definer
set search_path = public, auth
as $$ 
declare
  v_uid uuid := auth.uid();
  v_store public.stores%rowtype;
  v_review text;
  v_lifecycle text := 'active';
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select * into v_store
    from public.stores
   where owner_id = v_uid
   limit 1
   for update;

  if not found then
    raise exception 'Store was not found';
  end if;

  select r.review_status into v_review
    from public.admin_store_reviews r
   where r.store_id = v_store.id
   limit 1;

  v_review := coalesce(v_review, v_store.approval_status, 'pending');

  if p_is_open then
    if v_review <> 'approved' then
      raise exception 'Store is not approved by admin (status: %)', v_review;
    end if;
    if coalesce(v_store.is_active, false) = false then
      raise exception 'Store is approved but not activated by admin';
    end if;

    if to_regclass('public.admin_store_controls') is not null then
      execute 'select lifecycle_status from public.admin_store_controls where store_id=$1'
        into v_lifecycle using v_store.id;
      v_lifecycle := coalesce(v_lifecycle, 'active');
      if v_lifecycle <> 'active' then
        raise exception 'Store is administratively %', v_lifecycle;
      end if;
    end if;
  end if;

  return query
  update public.stores
     set is_open = coalesce(p_is_open, false),
         updated_at = now()
   where id = v_store.id
   returning public.stores.*;
end;
$$;

revoke all on function public.set_my_store_open_status(boolean) from public;
grant execute on function public.set_my_store_open_status(boolean) to authenticated;

notify pgrst, 'reload schema';

select
  s.id,
  s.name,
  s.approval_status,
  s.is_active,
  s.is_open,
  r.review_status,
  c.lifecycle_status
from public.stores s
left join public.admin_store_reviews r on r.store_id=s.id
left join public.admin_store_controls c on c.store_id=s.id
order by s.created_at desc nulls last;
