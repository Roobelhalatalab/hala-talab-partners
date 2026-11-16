# NOTE24 — Atomic product save (REVIEW ONLY)

Changes: products_repository.dart now optionally calls `hala_save_product_with_shifts` when two-shift UI supplies shift IDs. The product screen calculates selections **before** saving and no longer performs a second `setProductShifts` call. SQL verifies owner, store, category, active shifts, field whitelist, then writes product and links in one PostgreSQL transaction.

**Not included in the transaction:** product sort position, variants, packages, addons, image storage. These still save in later calls and can partially fail. The UI fallback to legacy category shift_id remains if no explicit product shifts; it must be reviewed separately for shared categories. Single-shift flow remains on original saveProduct path. No staging test or deployment performed.

**Predeployment:** inspect actual triggers/RLS, review SECURITY DEFINER grant and permissions, run staging migrations in order, compile Flutter, test both shifts and rollback on errors. Never execute on production without explicit approval.
