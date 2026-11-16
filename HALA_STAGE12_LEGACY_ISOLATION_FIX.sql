-- Hala drivers must never be eligible for automatic legacy delivery claiming.
-- Existing store drivers retain their existing scope and behavior.
BEGIN;
CREATE OR REPLACE FUNCTION public.driver_can_take_store(p_driver_id uuid,p_store_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT COALESCE((SELECT d.is_active AND d.driver_type='store' AND d.store_id=p_store_id
 FROM public.driver_delivery_scope d WHERE d.driver_id=p_driver_id),false)
$$;
REVOKE ALL ON FUNCTION public.driver_can_take_store(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.driver_can_take_store(uuid,uuid) TO authenticated;
COMMIT;
