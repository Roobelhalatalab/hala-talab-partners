# Note 24 — historical variant name guard (REVIEW ONLY)

- Captures the ID/name pairs returned by the successful initial variant read.
- Before any storage upload or DB write, rejects a submitted variant name matching an omitted historical variant ID.
- Shows a merchant-facing explanation in Arabic, Kurdish, and English.
- Retains the SQL v4's strict name collision protection; no silent reactivation, rename or deletion of historical variants.
- This is a client-side UX preflight, **not** a concurrency or database integrity guarantee. The SQL check remains authoritative.
- No live SQL, Supabase, GitHub, Flutter build, or device testing was performed. All SQL files remain DO NOT RUN.
- Outstanding: validate v4 against the live schema on a separate staging DB; review permission grants and all call sites; test editing, deletion, restoration, and both shift modes.
