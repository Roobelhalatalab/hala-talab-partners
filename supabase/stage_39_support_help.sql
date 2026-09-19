-- Hala Talab Partners - Stage 39
-- Adds a dedicated support-ticket table without modifying existing store/order integrations.

create table if not exists public.partner_support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  store_id uuid references public.stores(id) on delete set null,
  category text not null default 'general',
  message text not null,
  status text not null default 'open' check (status in ('open','in_progress','resolved','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists partner_support_tickets_user_id_idx
  on public.partner_support_tickets(user_id, created_at desc);
create index if not exists partner_support_tickets_store_id_idx
  on public.partner_support_tickets(store_id, created_at desc);

alter table public.partner_support_tickets enable row level security;

drop policy if exists "partners can create own support tickets" on public.partner_support_tickets;
create policy "partners can create own support tickets"
on public.partner_support_tickets
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "partners can read own support tickets" on public.partner_support_tickets;
create policy "partners can read own support tickets"
on public.partner_support_tickets
for select
to authenticated
using (auth.uid() = user_id);

-- Keep updated_at current on edits performed later by the admin/support panel.
create or replace function public.set_partner_support_ticket_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists partner_support_ticket_updated_at on public.partner_support_tickets;
create trigger partner_support_ticket_updated_at
before update on public.partner_support_tickets
for each row execute function public.set_partner_support_ticket_updated_at();

notify pgrst, 'reload schema';

select
  to_regclass('public.partner_support_tickets') as partner_support_tickets,
  true as support_ready;
