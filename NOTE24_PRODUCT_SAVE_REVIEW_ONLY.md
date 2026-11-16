# NOTE 24 — Product shift preservation (REVIEW ONLY)

- Source: HALA_TALAB_PARTNERS_NOTE24_LEGACY_SYNC_REVIEW_ONLY.zip.
- Changed only `lib/screens/dashboard/products_management.dart`: product explicit selected/existing shift links take precedence over legacy category `shift_id` when saving. Legacy is fallback only when no explicit selection exists.
- This is **not** an atomic save fix. `saveProduct`, `setProductPosition`, `setProductShifts`, variants and addons remain separate calls. No RPC was deployed or created.
- The UI currently does not expose a full multi-shift selector in this product dialog; `_selectedShiftIds` comes from existing assignments or default shift. Review UI selection behavior before deployment.
- A safe atomic RPC cannot be finalized without verified production/staging `products` column definitions, constraints, triggers, and app save contract.
- No Flutter build, database test, Supabase/GitHub changes, or deployment performed.
