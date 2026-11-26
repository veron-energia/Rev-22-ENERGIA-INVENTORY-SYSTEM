# Migrations that were never applied

The files in this folder were written but **never applied to production, and must
not be applied as they stand.** They are kept for reference only.

- `363_a_promotion_refund_closes_its_therapy.sql` is superseded by 417. Its guards
  no longer match production, because later migrations changed the functions it
  rewrites.
- `350_a_package_inside_a_promotion_grants_it.sql` and
  `351_a_promotion_keeps_its_own_money.sql` are parked, unfinished work. They are
  git-ignored (see `.gitignore`), so they stay on this Mac and cannot be committed
  by accident.

The numbers keep their place in the sequence, so the next migration never reuses
one. If this work resumes, write a new, numbered file at the head of the sequence
rather than moving one of these back.
