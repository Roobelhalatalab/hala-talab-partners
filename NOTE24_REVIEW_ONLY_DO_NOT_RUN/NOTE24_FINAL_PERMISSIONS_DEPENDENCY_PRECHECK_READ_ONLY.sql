-- NOTE 24 | READ ONLY | Safe to inspect in Supabase SQL editor; no changes.
-- Function existence, signatures, SECURITY DEFINER and effective EXECUTE privileges.
select n.nspname as schema_name, p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       case when p.prosecdef then 'DEFINER' else 'INVOKER' end as security_mode,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_can_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute,
       has_function_privilege('PUBLIC',p.oid,'EXECUTE') as public_can_execute,
       p.proconfig as function_config
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
 'hala_save_complete_product_v1','hala_save_complete_single_shift_product_v1',
 'hala_save_product_with_shifts','hala_replace_product_addons',
 'store_replace_product_variants_v3','store_replace_product_variants_v4',
 'store_set_product_position_v6','hala_save_category_with_shifts','hala_replace_shift_links'
) order by p.proname, arguments;

-- Relevant product_variants schema and constraints for v4 staging compatibility.
select column_name,data_type,is_nullable,column_default
from information_schema.columns
where table_schema='public' and table_name='product_variants'
order by ordinal_position;

select conname, pg_get_constraintdef(oid) as definition
from pg_constraint where conrelid='public.product_variants'::regclass
order by conname;

select indexname,indexdef from pg_indexes
where schemaname='public' and tablename='product_variants'
order by indexname;
