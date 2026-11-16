# NOTE24 — Variant compatibility follow-up (REVIEW ONLY / DO NOT DEPLOY)

Based on the preceding variant-ID-preservation ZIP, not a new project.

## Changed
- Retain the ID of the special `__hala_packages_only__` row when editing a packages-only product.
- Recognize a packages-only product even when other historical variants are hidden.
- Change the remaining direct repository variant-replacement call from destructive v3 to ID-preserving v4.

## Critical remaining blockers
- The v4 SQL currently updates `sort_order` and `name` directly under unique indexes. Swapping two existing variants may violate uniqueness midway through the transaction. **Do not run or deploy v4 until a collision-safe reordering/name-swap strategy is implemented and tested.**
- v4 hides omitted rows with `is_available=false`; the merchant editor still loads hidden variants and needs explicit UX/policy for restoration and removal.
- In packages-only mode, hidden historical variants are omitted and retained as hidden; verify the live client filters these correctly.
- v4 and unified save RPCs have not been tested against staging, RLS, live schema, or Flutter builds.
- Image uploads are outside database transactions.
- No SQL executed, no GitHub/Supabase modifications.
