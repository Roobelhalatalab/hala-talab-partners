# NOTE24 — single-shift unified save (REVIEW ONLY)

- Built on RPC_COMPATIBILITY_GUARD ZIP, not a new project.
- Single-shift product save now calls `hala_save_complete_single_shift_product_v1` for product + ordering + variants/packages + add-on links within one PostgreSQL transaction.
- SQL checks `auth.uid()` store ownership and `shift_mode=1`, verifies category ownership and product fields, and leaves `store_product_shifts` untouched for legacy compatibility.
- Shift-mode 2 continues to call `hala_save_complete_product_v1`.
- Both modes depend on separately reviewed `store_set_product_position_v6`, `store_replace_product_variants_v3`, `hala_replace_product_addons`.
- **NOT READY TO DEPLOY**: no PostgreSQL compilation, staging, Flutter analysis or runtime testing. `SECURITY DEFINER` requires independent permissions/RLS audit. Existing RPC signature/return semantics must be verified. SQL execution requires separate user approval.
- Storage uploads are outside the transaction. Product duplication and other screens not unified.
