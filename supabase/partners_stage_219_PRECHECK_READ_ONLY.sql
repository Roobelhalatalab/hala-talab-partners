-- Hala Talab Partners Android - Stage 219 Phase 2
-- READ ONLY precheck. This query changes nothing.
-- Expected: every row = OK before running the migration.
select '1 stores' check_name, case when to_regclass('public.stores') is not null then 'OK' else 'MISSING' end result
union all select '2 products', case when to_regclass('public.products') is not null then 'OK' else 'MISSING' end
union all select '3 product_variants', case when to_regclass('public.product_variants') is not null then 'OK' else 'MISSING' end
union all select '4 store_promotions', case when to_regclass('public.store_promotions') is not null then 'OK' else 'MISSING' end
union all select '5 coupons', case when to_regclass('public.coupons') is not null then 'OK' else 'MISSING' end
union all select '6 orders', case when to_regclass('public.orders') is not null then 'OK' else 'MISSING' end
union all select '7 driver_delivery_scope', case when to_regclass('public.driver_delivery_scope') is not null then 'OK' else 'MISSING' end
union all select '8 driver_notifications', case when to_regclass('public.driver_notifications') is not null then 'OK' else 'MISSING' end
union all select '9 driver_order_rejections', case when to_regclass('public.driver_order_rejections') is not null then 'OK' else 'MISSING' end
union all select '10 driver_can_take_store', case when to_regprocedure('public.driver_can_take_store(uuid,uuid)') is not null then 'OK' else 'MISSING' end
union all select '11 update_my_store_order_status', case when to_regprocedure('public.update_my_store_order_status(uuid,text)') is not null then 'OK' else 'MISSING' end
union all select '12 available_driver_offer', case when to_regprocedure('public.get_available_driver_delivery_offer()') is not null then 'OK' else 'MISSING' end
union all select '13 claim_driver_offer', case when to_regprocedure('public.claim_driver_delivery_offer(uuid)') is not null then 'OK' else 'MISSING' end
union all select '14 ready_driver_notify', case when to_regprocedure('public.hala_notify_eligible_drivers_ready_order()') is not null then 'OK' else 'MISSING' end;
