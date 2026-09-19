-- Hala Talab Phase B: device push token registry
create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'customer',
  platform text not null,
  token text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists device_push_tokens_user_idx on public.device_push_tokens(user_id, role);
alter table public.device_push_tokens enable row level security;
drop policy if exists device_push_tokens_own_select on public.device_push_tokens;
create policy device_push_tokens_own_select on public.device_push_tokens for select using (auth.uid() = user_id);
drop policy if exists device_push_tokens_own_insert on public.device_push_tokens;
create policy device_push_tokens_own_insert on public.device_push_tokens for insert with check (auth.uid() = user_id);
drop policy if exists device_push_tokens_own_update on public.device_push_tokens;
create policy device_push_tokens_own_update on public.device_push_tokens for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists device_push_tokens_own_delete on public.device_push_tokens;
create policy device_push_tokens_own_delete on public.device_push_tokens for delete using (auth.uid() = user_id);
select true as phase_b_push_tokens_ready;
