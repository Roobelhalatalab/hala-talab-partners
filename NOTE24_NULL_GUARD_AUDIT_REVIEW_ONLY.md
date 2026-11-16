# NOTE24 — SQL NULL validation hardening (REVIEW ONLY)

Source: HALA_TALAB_PARTNERS_NOTE24_SINGLE_SHIFT_UNIFIED_REVIEW_ONLY.zip

Changed exactly two SQL draft files:
- NOTE24_ATOMIC_PRODUCT_SAVE_REVIEW_ONLY.sql
- NOTE24_SINGLE_SHIFT_UNIFIED_SAVE_REVIEW_ONLY.sql

In both functions, explicit IS NULL checks were added for min_quantity and quantity_step, alongside their positive-value checks. PostgreSQL three-valued boolean logic can otherwise allow NULL through an IF condition. No Dart files were changed.

Important remaining audit issues:
- Existing SQL RPC signatures, grants, triggers, RLS, defaults and actual data must be verified in a staging environment.
- SECURITY DEFINER functions require independent permission review.
- Storage uploads are not part of the SQL transaction.
- End-to-end tests for both shift modes and rollback behavior have not run.

DO NOT RUN SQL ON PRODUCTION. NO DEPLOYMENT.
