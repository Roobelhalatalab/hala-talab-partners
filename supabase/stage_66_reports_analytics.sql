-- Hala Talab Partners - Stage 66
-- Reporting/analytics performance support.
-- Safe to run more than once; no business data is deleted or rewritten.

create index if not exists orders_store_created_status_idx
  on public.orders(store_id, created_at desc, status);

create index if not exists orders_store_delivered_created_idx
  on public.orders(store_id, created_at desc)
  where status = 'delivered';

create index if not exists order_items_order_product_idx
  on public.order_items(order_id, product_id);

create index if not exists store_reviews_store_created_idx
  on public.store_reviews(store_id, created_at desc);

notify pgrst, 'reload schema';

select
  to_regclass('public.orders') as orders,
  to_regclass('public.order_items') as order_items,
  to_regclass('public.store_reviews') as store_reviews,
  true as stage_66_ready;
