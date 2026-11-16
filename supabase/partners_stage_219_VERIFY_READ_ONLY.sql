-- Hala Talab Partners Android - Stage 219 Phase 2
-- READ ONLY verification after the migration. Expected: every row = OK.
select '1 self_delivery' check_name, case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='self_delivery') then 'OK' else 'MISSING' end result
union all select '2 always_open', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='stores' and column_name='always_open') then 'OK' else 'MISSING' end
union all select '3 promotion image', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='store_promotions' and column_name='image_url') then 'OK' else 'MISSING' end
union all select '4 promotion image path', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='store_promotions' and column_name='image_path') then 'OK' else 'MISSING' end
union all select '5 coupon image', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='coupons' and column_name='image_url') then 'OK' else 'MISSING' end
union all select '6 coupon image path', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='coupons' and column_name='image_path') then 'OK' else 'MISSING' end
union all select '7 min_quantity', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='min_quantity') then 'OK' else 'MISSING' end
union all select '8 quantity_step', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='quantity_step') then 'OK' else 'MISSING' end
union all select '9 variant image', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='product_variants' and column_name='image_url') then 'OK' else 'MISSING' end
union all select '10 variant image path', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='product_variants' and column_name='image_path') then 'OK' else 'MISSING' end
union all select '11 variant packages', case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='product_variants' and column_name='packages') then 'OK' else 'MISSING' end
union all select '12 variants v3 rpc', case when to_regprocedure('public.store_replace_product_variants_v3(uuid,uuid,jsonb)') is not null then 'OK' else 'MISSING' end
union all select '13 store status rpc', case when to_regprocedure('public.update_my_store_order_status(uuid,text)') is not null then 'OK' else 'MISSING' end
union all select '14 available driver offer rpc', case when to_regprocedure('public.get_available_driver_delivery_offer()') is not null then 'OK' else 'MISSING' end
union all select '15 claim driver offer rpc', case when to_regprocedure('public.claim_driver_delivery_offer(uuid)') is not null then 'OK' else 'MISSING' end
union all select '16 ready notify function', case when to_regprocedure('public.hala_notify_eligible_drivers_ready_order()') is not null then 'OK' else 'MISSING' end
union all select '17 assignment notify function', case when to_regprocedure('public.hala_notify_driver_after_scope_assignment()') is not null then 'OK' else 'MISSING' end
union all select '18 self delivery cleanup trigger', case when exists(select 1 from pg_trigger where tgname='hala_store_self_delivery_cleanup' and not tgisinternal) then 'OK' else 'MISSING' end;
