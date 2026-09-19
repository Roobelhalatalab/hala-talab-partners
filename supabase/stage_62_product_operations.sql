-- Hala Talab Partners - Stage 62
-- Finalize product/catalog CRUD integrity and ownership safeguards.

-- Prevent duplicate SKU/barcode within the same store while allowing NULL values.
create unique index if not exists products_store_barcode_unique
  on public.products(store_id, barcode)
  where barcode is not null and btrim(barcode) <> '';

create unique index if not exists products_store_sku_unique
  on public.products(store_id, sku)
  where sku is not null and btrim(sku) <> '';

-- Normalize empty identifiers to NULL so the partial unique indexes behave consistently.
update public.products set barcode = null where barcode is not null and btrim(barcode) = '';
update public.products set sku = null where sku is not null and btrim(sku) = '';

-- Category and add-on names should not be duplicated inside the same store.
create unique index if not exists product_categories_store_name_unique
  on public.product_categories(store_id, lower(btrim(name)));

create unique index if not exists product_addons_store_name_unique
  on public.product_addons(store_id, lower(btrim(name)));

-- Keep updated_at current for category/add-on edits.
drop trigger if exists product_categories_set_updated_at on public.product_categories;
create trigger product_categories_set_updated_at
before update on public.product_categories
for each row execute function public.set_updated_at();

drop trigger if exists product_addons_set_updated_at on public.product_addons;
create trigger product_addons_set_updated_at
before update on public.product_addons
for each row execute function public.set_updated_at();

-- Reassert owner-only product policies.
alter table public.products enable row level security;

drop policy if exists "Store owners can view own products" on public.products;
create policy "Store owners can view own products"
on public.products for select to authenticated
using (exists (select 1 from public.stores s where s.id = products.store_id and s.owner_id = auth.uid()));

drop policy if exists "Store owners can create own products" on public.products;
create policy "Store owners can create own products"
on public.products for insert to authenticated
with check (exists (select 1 from public.stores s where s.id = products.store_id and s.owner_id = auth.uid()));

drop policy if exists "Store owners can update own products" on public.products;
create policy "Store owners can update own products"
on public.products for update to authenticated
using (exists (select 1 from public.stores s where s.id = products.store_id and s.owner_id = auth.uid()))
with check (exists (select 1 from public.stores s where s.id = products.store_id and s.owner_id = auth.uid()));

drop policy if exists "Store owners can delete own products" on public.products;
create policy "Store owners can delete own products"
on public.products for delete to authenticated
using (exists (select 1 from public.stores s where s.id = products.store_id and s.owner_id = auth.uid()));

notify pgrst, 'reload schema';
