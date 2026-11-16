# NOTE24 — Historical variant editor clarity (REVIEW ONLY)

Source: HALA_TALAB_PARTNERS_NOTE24_VARIANT_REORDER_SAFE_REVIEW_ONLY.zip.

Changed only lib/screens/dashboard/products_management.dart.

- Existing variant removal confirmation now explains that the v4 SQL will hide the row, not delete its historical ID.
- New unsaved variant removal has a separate confirmation.
- Existing unavailable variants display a visible “Hidden — can restore” label.
- Availability toggle clarifies that enabling restores an existing hidden variant.

IMPORTANT: This UX change assumes the proposed v4 SQL is reviewed, installed and used. No migration was run. The unresolved case of a new variant reusing a historical hidden name is still rejected by v4 SQL; do not silently repurpose old IDs. No Flutter build, device, or Supabase staging test performed.
