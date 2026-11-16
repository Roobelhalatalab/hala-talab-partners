# NOTE24 — Variant image upload ordering (REVIEW ONLY)

Changed only `lib/screens/dashboard/products_management.dart`.

Before: save product + shift links; reorder; upload variant images; replace variants; save addons. A failed variant upload could leave a partially saved product.

Now: upload/prepare variant images before saving product + shift links. If upload fails, product DB save has not started.

Limitations: new uploaded images can be orphaned on later DB failure; product/reorder/variants/addons are still separate transactions; requires Flutter/device and staging Supabase testing. No live SQL executed.
