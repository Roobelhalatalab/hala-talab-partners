# NOTE 24 — SQL trigger unification (REVIEW ONLY)

Modified both `supabase/stage_200_shift_scoped_categories.sql` and `NOTE24_REVIEW_ONLY_DO_NOT_RUN/NOTE24_ATOMIC_SHIFT_LINKS_REVIEW_ONLY.sql` to use the **same non-destructive trigger logic**.

- The trigger respects `hala.skip_category_shift_sync` used by atomic category-save RPC.
- Explicit links take priority; `shift_id` is a fallback only when there are no links.
- The old backfill that could insert unintended links into categories with existing explicit links is removed from stage_200.
- No DELETE occurs inside the unified trigger.

**Limitations:** No live DB changes; no PostgreSQL staging test; no Flutter test. Other RPCs can intentionally replace links on explicit saves and still need validation. Historical conflicts remain untouched. SQL execution order and installed DB definitions require verification before deployment. The previous SQL files are draft migrations, not safe to rerun on production wholesale.
