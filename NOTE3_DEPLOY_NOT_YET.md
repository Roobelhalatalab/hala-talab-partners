NOTE 3 - multi-device ring stop
1. Deploy updated supabase/functions/send-push/index.ts FIRST.
2. Run supabase/NOTE3_MULTI_DEVICE_RING_RESOLUTION.sql AFTER verifying live status strings and that store_notifications insert push trigger is active.
3. Install updated partners app on BOTH Android phones.
4. Test one pending order, accept on phone A; phone B stops. Repeat reject/cancel, two pending orders, locked background phones.
5. SQL rollback: supabase/NOTE3_MULTI_DEVICE_RING_ROLLBACK.sql. Edge Function must be rolled back using prior deployment if necessary.
NOTE: FCM delivery is best-effort, not guaranteed under all Android background/Doze conditions. No live Supabase deployment or two-device test performed here.
