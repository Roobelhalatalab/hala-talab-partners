-- Hala Talab Partners - Stage 55
-- Meal management redesign: preparation details, tags and product/add-on links.

alter table public.products
  add column if not exists preparation_time_minutes integer,
  add column if not exists calories integer,
  add column if not exists notes text,
  add column if not exists tags text[] not null default '{}',
  add column if not exists product_type text not null default 'single';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'products_preparation_time_nonnegative'
  ) then
    alter table public.products
      add constraint products_preparation_time_nonnegative
      check (preparation_time_minutes is null or preparation_time_minutes >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'products_calories_nonnegative'
  ) then
    alter table public.products
      add constraint products_calories_nonnegative
      check (calories is null or calories >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'products_product_type_valid'
  ) then
    alter table public.products
      add constraint products_product_type_valid
      check (product_type in ('single','family','drink'));
  end if;
end $$;

create table if not exists public.product_addon_links (
  product_id uuid not null references public.products(id) on delete cascade,
  addon_id uuid not null references public.product_addons(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (product_id, addon_id)
);

create index if not exists product_addon_links_addon_id_idx on public.product_addon_links(addon_id);

alter table public.product_addon_links enable row level security;

drop policy if exists "store owners manage product addon links" on public.product_addon_links;
create policy "store owners manage product addon links"
on public.product_addon_links for all to authenticated
using (
  exists (
    select 1
    from public.products p
    join public.stores s on s.id = p.store_id
    where p.id = product_id and s.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.products p
    join public.stores s on s.id = p.store_id
    where p.id = product_id and s.owner_id = auth.uid()
  )
  and exists (
    select 1
    from public.product_addons a
    join public.stores s on s.id = a.store_id
    where a.id = addon_id and s.owner_id = auth.uid()
  )
);

notify pgrst, 'reload schema';
