# Note 24 — atomic add-on links (REVIEW ONLY)

Based on HALA_TALAB_PARTNERS_NOTE24_ADDON_ERROR_VISIBILITY_REVIEW_ONLY.zip.

Changed only `lib/repositories/products_repository.dart`: `setProductAddons` now calls `hala_replace_product_addons` instead of two client-side delete/insert requests. Added review-only SQL RPC with ownership, same-store product/addon checks, row lock, deduplication and one transaction. Empty array intentionally clears all add-on links; null is rejected. Invalid add-on IDs raise error rather than silently dropping selections.

**Deployment dependency:** The app must not be released before independently approving/deploying the SQL RPC. The SQL is NOT run. Missing RPC will fail visibly, not silently erase links. Confirm product_addons table and roles in staging.

**Not solved:** full product save still consists of multiple transactions (product/shift, sort, variants, add-ons, image storage). This patch makes ONLY the add-on link replacement atomic. Duplicate-product path also uses this RPC. Flutter compile, Supabase staging, concurrency and runtime tests have not been run.

No GitHub, live database or deployed app changed.
