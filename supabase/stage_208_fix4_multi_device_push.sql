-- Hala Talab Partners — Stage 208 Fix 4
-- One Store/Driver account may be active on multiple phones/tablets at once.
-- Guarantees one independent push registration per app installation and keeps
-- ALL valid installations for the same account. Safe to re-run.

begin;

alter table public.device_push_tokens
  add column if not exists installation_id text null;

-- Older experimental schemas may have accidentally added a UNIQUE constraint
-- on (user_id, role), which would force the newest phone to replace the older
-- phone. Remove ONLY such two-column uniqueness if it exists. Normal indexes,
-- the primary key, and the required UNIQUE(token) constraint are preserved.
do $$
declare r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'device_push_tokens'
      and c.contype = 'u'
      and (
        select array_agg(a.attname::text order by u.ord)
        from unnest(c.conkey) with ordinality u(attnum, ord)
        join pg_attribute a on a.attrelid = t.oid and a.attnum = u.attnum
      ) = array['user_id','role']::text[]
  loop
    execute format('alter table public.device_push_tokens drop constraint %I', r.conname);
  end loop;
end $$;

-- Drop an accidental UNIQUE INDEX on (user_id, role) when it is not owned by a
-- constraint. Do not touch non-unique lookup indexes.
do $$
declare r record;
begin
  for r in
    select indexname
    from pg_indexes
    where schemaname='public'
      and tablename='device_push_tokens'
      and indexdef ilike 'create unique index%'
      and regexp_replace(indexdef, '\\s+', ' ', 'g') ~* '\\(user_id, role\\)'
  loop
    begin
      execute format('drop index if exists public.%I', r.indexname);
    exception when dependent_objects_still_exist then
      null;
    end;
  end loop;
end $$;

create index if not exists device_push_tokens_user_role_updated_idx
  on public.device_push_tokens(user_id, role, updated_at desc);

-- This is the key multi-device invariant: one row per installation, not one row
-- per account. NULL legacy rows are allowed until each device re-registers.
create unique index if not exists device_push_tokens_installation_unique_idx
  on public.device_push_tokens(user_id, role, installation_id)
  where installation_id is not null;

create or replace function public.register_device_push_token(
  p_role text,
  p_platform text,
  p_token text,
  p_installation_id text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_role text := lower(trim(coalesce(p_role,'')));
  v_platform text := lower(trim(coalesce(p_platform,'')));
  v_token text := trim(coalesce(p_token,''));
  v_installation text := trim(coalesce(p_installation_id,''));
begin
  if v_user is null then raise exception 'Not authenticated'; end if;
  if v_role not in ('customer','business','driver') then raise exception 'Invalid role'; end if;
  if v_token = '' then raise exception 'Push token is required'; end if;
  if v_installation = '' then raise exception 'Installation id is required'; end if;

  -- Token rotation must replace only the row for this one installation.
  delete from public.device_push_tokens
   where user_id = v_user
     and role = v_role
     and installation_id = v_installation
     and token <> v_token;

  -- An FCM token belongs to one current app installation. If Android/iOS reuses
  -- a token after account changes, safely attach it to the currently signed-in
  -- account instead of leaving a stale recipient behind.
  insert into public.device_push_tokens(
    user_id, role, platform, token, installation_id, created_at, updated_at
  ) values (
    v_user, v_role, v_platform, v_token, v_installation, now(), now()
  )
  on conflict (token) do update set
    user_id = excluded.user_id,
    role = excluded.role,
    platform = excluded.platform,
    installation_id = excluded.installation_id,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.register_device_push_token(text,text,text,text) from public;
grant execute on function public.register_device_push_token(text,text,text,text) to authenticated;

commit;

-- Verification: after signing the SAME store into two devices and opening the
-- app once on both, token_count should be >= 2 for that business user.
select user_id, role, count(*) as token_count,
       count(distinct installation_id) filter (where installation_id is not null) as installation_count
from public.device_push_tokens
group by user_id, role
order by token_count desc, user_id;
