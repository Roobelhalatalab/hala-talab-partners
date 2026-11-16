-- NOTE24 / READ ONLY. Run only if you choose to inspect database permissions.
-- Does not alter data, permissions, or functions.
SELECT n.nspname AS schema_name, p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS signature,
       CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS security_mode,
       p.proowner::regrole::text AS owner_role,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
       p.proconfig AS settings
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN (
 'hala_save_complete_product_v1', 'hala_save_complete_single_shift_product_v1',
 'hala_save_product_with_shifts', 'store_set_product_position_v6',
 'store_replace_product_variants_v3', 'hala_replace_product_addons'
)
ORDER BY p.proname, signature;

-- Check foreign keys referencing product_variants IDs, including outside expected tables.
SELECT c.conrelid::regclass::text AS referencing_table,
       c.conname AS foreign_key_name,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.contype='f' AND c.confrelid='public.product_variants'::regclass
ORDER BY 1, 2;
