-- NOTE 24: Non-destructive replacement for the legacy category-shift trigger.
-- REVIEW ONLY: do not run on production without approval, backup and staging tests.
-- Explicit store_category_shifts links are authoritative. shift_id is fallback
-- ONLY when the category has no explicit links. Never DELETE links here.
create or replace function public.hala_sync_category_shift_link()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.shift_id is not null
     and not exists (
       select 1 from public.store_category_shifts links
       where links.category_id = new.id
     ) then
    insert into public.store_category_shifts(category_id, shift_id)
    values (new.id, new.shift_id)
    on conflict do nothing;
  end if;
  return new;
end;
$$;
