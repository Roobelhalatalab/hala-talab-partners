# NOTE24 — collision-safe variant ordering review (DO NOT RUN)

Built from the previous VARIANT_COMPAT_FIX ZIP. Changed only the proposed v4 SQL plus this report.

## Fix
- Stage all existing variant names under unique temporary names and their sort orders above the current maximum before editing.
- Preserve a JSON snapshot of old names; update/insert submitted variants at 1..N while preserving existing IDs.
- Move omitted historical variants after the active list, restore their original names, mark them unavailable; never delete their rows.
- Reject a collision between an omitted historical name and a submitted name rather than silently renaming history.
- Protect against integer overflow and rely on transaction rollback for failed validations.

## Remaining review blockers
- Verify exact deployed unique indexes and schema, especially packages-only behavior.
- Existing hidden variants are returned to editor; UX for restoration/removal needs review.
- If the submitted variant name equals an omitted historical name, save deliberately fails until an explicit naming policy is chosen.
- New uploads are outside the DB transaction. No Flutter/staging tests.
- SQL is REVIEW ONLY. Nothing executed on Supabase/GitHub.
