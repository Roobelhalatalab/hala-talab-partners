-- Remove only the newly added status notification trigger/function.
drop trigger if exists hala_merchant_ring_resolved on public.orders;
drop function if exists public.hala_notify_merchant_ring_resolved();
