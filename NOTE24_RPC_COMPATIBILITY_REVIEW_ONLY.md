# NOTE24 — RPC compatibility review (REVIEW ONLY)

- Base: HALA_TALAB_PARTNERS_NOTE24_UNIFIED_SAVE_REVIEW_ONLY.zip; full original project preserved.
- Found: missing Note24 RPC was incorrectly presented as Stage 200 issue because error classifier matched `schema cache`.
- Changed only lib/screens/dashboard/products_management.dart to surface a distinct, actionable error and avoid instructing unreviewed SQL execution.
- Verified in source: shift_mode=2 calls hala_save_complete_product_v1; shift_mode=1 still saves product, position, variants and add-ons separately. The single-shift path is NOT atomic.
- Unified SQL calls four functions: hala_save_product_with_shifts, store_set_product_position_v6, store_replace_product_variants_v3, hala_replace_product_addons. Their signatures/permissions and trigger behavior require actual database verification.
- Risk: uploading images occurs before database save, and uploaded files may be orphaned if the RPC fails.
- No SQL run, no Supabase/GitHub changes, no Flutter/device tests. Not deployable.
