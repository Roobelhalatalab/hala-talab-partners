-- REVIEW ONLY: run only after staging validation and explicit approval.
-- Non-destructive fallback; preserve explicit multi-shift links.
create or replace function public.hala_sync_category_shift_link()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_setting('hala.skip_category_shift_sync', true) = 'on' then return new; end if;
  if new.shift_id is not null and not exists (
    select 1 from public.store_category_shifts l where l.category_id = new.id
  ) then
    insert into public.store_category_shifts(category_id,shift_id)
    values(new.id,new.shift_id) on conflict do nothing;
  end if;
  return new;
end; $$;
