# NOTE24 — Add-on save error visibility (REVIEW ONLY)

Base: HALA_TALAB_PARTNERS_NOTE24_ATOMIC_PRODUCT_REVIEW_ONLY.zip.

Changed: lib/screens/dashboard/products_management.dart only.

Previous behavior: setProductAddons failure was caught and logged, then the product editor closed as if fully saved.
New behavior: propagate the failure to the existing error handler and keep the editor open. This does NOT roll back prior product, ordering, or variant writes.

Outstanding critical issue: setProductAddons deletes old links then inserts replacements in separate requests; if insertion fails, existing links may already be lost. Do not deploy before an atomic server-side add-on replacement and staging tests. Variant replacement and position update are also separate RPC calls. Image storage changes cannot be rolled back by a database transaction.

No Supabase SQL run; no GitHub modifications; no Flutter build or runtime test.
