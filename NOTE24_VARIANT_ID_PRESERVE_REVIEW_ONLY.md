# Note 24 — preserving variant IDs (review only)

Changes: product edit UI retains variant `id` in drafts and sends it to unified save; copied/new variants do not reuse IDs. Unified single/two-shift SQL now calls `store_replace_product_variants_v4`; repository direct variant replacement also calls v4. New SQL updates existing variants, inserts new, and soft-hides omitted variants; it never deletes variants.

**Not production-ready:** Current `getProductVariants` returns hidden rows too, so the merchant UI needs an explicit hidden-variant policy. The legacy packages-only special variant must retain its ID on edits (not yet done). The v4 function has not been run on staging, and temporary uniqueness collisions on sort_order/name when reordering need testing and likely additional handling. It also needs confirmation that all JSON package values conform to live schema. Do not deploy or run any SQL yet.
