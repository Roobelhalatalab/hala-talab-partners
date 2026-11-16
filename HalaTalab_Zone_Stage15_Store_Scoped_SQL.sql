-- Stage 15. Review/backup first; DO NOT run before stage 1 coverage table exists.
-- The partner app calls hala_get_my_delivery_coverage_v1 and
-- hala_save_my_delivery_coverage_v1. This file is not part of V7 execution.
-- Additive explicit-store RPCs, no changes to legacy order pricing.
BEGIN;
CREATE OR REPLACE FUNCTION public.hala_get_store_delivery_coverage_v2(p_store_id uuid)
RETURNS TABLE(area_id uuid, area_name text, zone_name text, is_enabled boolean, delivery_fee numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.stores s WHERE s.id=p_store_id AND s.owner_id=auth.uid()) THEN
  RAISE EXCEPTION 'Store access denied' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT a.id,a.name::text,z.name::text,COALESCE(c.is_enabled,false),COALESCE(c.delivery_fee,0)
 FROM public.hala_zone_areas a JOIN public.hala_zones z ON z.id=a.zone_id
 LEFT JOIN public.hala_store_delivery_coverage c ON c.area_id=a.id AND c.store_id=p_store_id
 WHERE a.is_active AND z.is_active ORDER BY z.name,a.name;
END;$$;
CREATE OR REPLACE FUNCTION public.hala_save_store_delivery_coverage_v2(
 p_store_id uuid,p_area_id uuid,p_enabled boolean,p_delivery_fee numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.stores s WHERE s.id=p_store_id AND s.owner_id=auth.uid()) THEN
  RAISE EXCEPTION 'Store access denied' USING ERRCODE='42501';
 END IF;
 IF p_enabled IS NULL OR p_delivery_fee IS NULL OR p_delivery_fee < 0 OR p_delivery_fee > 100000000 THEN
  RAISE EXCEPTION 'Invalid delivery settings';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.hala_zone_areas a JOIN public.hala_zones z ON z.id=a.zone_id
                WHERE a.id=p_area_id AND a.is_active AND z.is_active) THEN
  RAISE EXCEPTION 'Area not active';
 END IF;
 -- Same per-store lock as admin move RPC; serializes inserts and updates.
 PERFORM pg_advisory_xact_lock(hashtextextended(p_store_id::text, 19017));
 INSERT INTO public.hala_store_delivery_coverage(store_id,area_id,is_enabled,delivery_fee,updated_at)
 VALUES(p_store_id,p_area_id,p_enabled,p_delivery_fee,now())
 ON CONFLICT(store_id,area_id) DO UPDATE SET is_enabled=EXCLUDED.is_enabled,
 delivery_fee=EXCLUDED.delivery_fee,updated_at=now();
END;$$;
REVOKE ALL ON FUNCTION public.hala_get_store_delivery_coverage_v2(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.hala_save_store_delivery_coverage_v2(uuid,uuid,boolean,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.hala_get_store_delivery_coverage_v2(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hala_save_store_delivery_coverage_v2(uuid,uuid,boolean,numeric) TO authenticated;
COMMIT;
