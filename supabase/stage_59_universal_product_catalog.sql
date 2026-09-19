-- Hala Talab Partners - Stage 59
-- Universal product catalog for restaurants, grocery, beverages, pharmacy, flowers, hookah and other stores.

alter table public.products
  add column if not exists brand text,
  add column if not exists barcode text,
  add column if not exists sku text,
  add column if not exists unit text not null default 'piece',
  add column if not exists track_stock boolean not null default false,
  add column if not exists stock_quantity numeric,
  add column if not exists size_label text,
  add column if not exists weight_value numeric,
  add column if not exists weight_unit text not null default 'g',
  add column if not exists catalog_kind text not null default 'restaurant';

alter table public.products drop constraint if exists products_product_type_valid;
alter table public.products add constraint products_product_type_valid
  check (product_type in ('single','family','drink','product','grocery','pharmacy','flower','hookah'));

alter table public.products drop constraint if exists products_unit_valid;
alter table public.products add constraint products_unit_valid
  check (unit in ('piece','pack','box','bottle','kg','g','l','ml'));

alter table public.products drop constraint if exists products_stock_nonnegative;
alter table public.products add constraint products_stock_nonnegative
  check (stock_quantity is null or stock_quantity >= 0);

create index if not exists products_store_barcode_idx on public.products(store_id, barcode) where barcode is not null;
create index if not exists products_store_sku_idx on public.products(store_id, sku) where sku is not null;

notify pgrst, 'reload schema';
