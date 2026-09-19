-- Hala Talab Partners - Stage 201
-- Independent weekly schedules for morning/evening shifts.
-- Backward compatible: single-shift stores keep using stores.working_hours.

alter table public.store_shifts
  add column if not exists weekly_hours jsonb not null default '{}'::jsonb;

comment on column public.store_shifts.weekly_hours is
  'Per-day schedule for this shift. Keys: saturday..friday; values: {enabled, open, close}. Empty object falls back to start_time/end_time.';

-- Keep the public helper as the single source of truth for whether a shift is
-- open now. It understands per-day schedules and overnight shifts.
create or replace function public.hala_shift_is_open(
  p_shift_id uuid,
  p_at timestamptz default now()
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_shift public.store_shifts%rowtype;
  v_tz text;
  v_local timestamp;
  v_time time;
  v_dow int;
  v_day_key text;
  v_prev_key text;
  v_today jsonb;
  v_prev jsonb;
  v_today_enabled boolean;
  v_prev_enabled boolean;
  v_today_start time;
  v_today_end time;
  v_prev_start time;
  v_prev_end time;
  v_has_weekly boolean;
begin
  select sh.*
    into v_shift
    from public.store_shifts sh
   where sh.id = p_shift_id
   limit 1;

  if v_shift.id is not null then
    select coalesce(nullif(s.store_timezone, ''), 'Asia/Baghdad')
      into v_tz
      from public.stores s
     where s.id = v_shift.store_id
     limit 1;
  else
    v_tz := 'Asia/Baghdad';
  end if;

  if v_shift.id is null or not v_shift.is_active then
    return false;
  end if;

  v_local := p_at at time zone v_tz;
  v_time := v_local::time;
  v_dow := extract(dow from v_local)::int; -- 0=Sunday ... 6=Saturday

  v_day_key := case v_dow
    when 0 then 'sunday' when 1 then 'monday' when 2 then 'tuesday'
    when 3 then 'wednesday' when 4 then 'thursday' when 5 then 'friday'
    else 'saturday' end;

  v_prev_key := case v_dow
    when 0 then 'saturday' when 1 then 'sunday' when 2 then 'monday'
    when 3 then 'tuesday' when 4 then 'wednesday' when 5 then 'thursday'
    else 'friday' end;

  v_has_weekly := v_shift.weekly_hours is not null
                  and jsonb_typeof(v_shift.weekly_hours) = 'object'
                  and v_shift.weekly_hours <> '{}'::jsonb;

  if not v_has_weekly then
    if v_shift.start_time = v_shift.end_time then return true; end if;
    if v_shift.start_time < v_shift.end_time then
      return v_time >= v_shift.start_time and v_time < v_shift.end_time;
    end if;
    return v_time >= v_shift.start_time or v_time < v_shift.end_time;
  end if;

  v_today := coalesce(v_shift.weekly_hours -> v_day_key, '{}'::jsonb);
  v_prev := coalesce(v_shift.weekly_hours -> v_prev_key, '{}'::jsonb);

  v_today_enabled := coalesce((v_today ->> 'enabled')::boolean, false);
  v_prev_enabled := coalesce((v_prev ->> 'enabled')::boolean, false);

  v_today_start := coalesce(nullif(v_today ->> 'open', '')::time, v_shift.start_time);
  v_today_end := coalesce(nullif(v_today ->> 'close', '')::time, v_shift.end_time);
  v_prev_start := coalesce(nullif(v_prev ->> 'open', '')::time, v_shift.start_time);
  v_prev_end := coalesce(nullif(v_prev ->> 'close', '')::time, v_shift.end_time);

  -- Portion belonging to today's configured shift.
  if v_today_enabled then
    if v_today_start = v_today_end then
      return true;
    elsif v_today_start < v_today_end then
      if v_time >= v_today_start and v_time < v_today_end then return true; end if;
    else
      -- Overnight shift: today's late-night portion.
      if v_time >= v_today_start then return true; end if;
    end if;
  end if;

  -- After-midnight continuation of yesterday's overnight shift.
  if v_prev_enabled and v_prev_start > v_prev_end and v_time < v_prev_end then
    return true;
  end if;

  return false;
end;
$$;

notify pgrst, 'reload schema';

select
  exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='store_shifts' and column_name='weekly_hours'
  ) as shift_weekly_hours_ready,
  to_regprocedure('public.hala_shift_is_open(uuid,timestamptz)') is not null as shift_open_helper_ready;
