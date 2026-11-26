# supabase/

The database migrations (numbered `.sql` files), the Edge Functions and the
function settings. What production has actually run is recorded in
`applied/production-applied.tsv`; files that were never applied are in
`not-applied/` (read its README).

## Rules

1. **An applied migration file is never edited.** A correction is a new file with
   the next number. Editing a file production already ran makes the repository say
   something production never did.
2. **From the baseline on, numbers follow applied order.** The next file gets the
   next number, and goes in the order it is applied, so reading the numbers in
   order replays production.
3. A file that is written but not applied goes in `not-applied/`, not here.
4. Edge Function settings (`verify_jwt`) are in `config.toml`; every tracked
   function folder needs a section there. `npm run live:check-edge-functions`
   compares names and those settings with the hosted project (it only reads).

## Known exceptions

The repository and production do not agree byte for byte in these places. They are
recorded here rather than rewritten, because rewriting history would hide them.

| What | State | What to do |
| --- | --- | --- |
| Nine files edited after production ran them. The revision production ran is given. | `UPGRADE_to_current.sql` 1b1a9cc, `61` e17fb05, `66` cde18e9, `83` 5b15b31, `92` ffa6560, `130` 39216f5, `243` d6d319c, `339` dd52942, `357` 46ecdbb | Leave their bytes alone. `61`, `66`, `83`, `92`, `130` and `243` have no row in production's history, so "the revision production ran" for them rests on comparing the functions production has, not on the history. |
| `339` | Production's row is code-identical to `dd52942` apart from its `begin;`, `notify pgrst` and `commit;` lines, which is why the list marks it "differs". | Nothing. |
| `346`, `347` and `352` | Match no tracked revision exactly; one or two lines differ. | Nothing; the table in `applied/` marks them. |
| `trg_invoice_manual_discount_reason()` | Production holds `335`'s logic with different whitespace (production md5 `bfed9e779a89ed9b149b6be80217775a`). `481` pins it. | Nothing. |
| `user_has_store_access` | Production has the `00_complete_setup.sql` version, not file `24`'s. | Nothing. |
| `DIAGNOSE_survey_name_edit.sql` | Production ran it. It created `diagnose_survey_name_edit(text)`, which clients cannot call. | Nothing. |
| Note on `243` | The revision production ran patched nothing in `upsert_credit_package` or `upsert_premium_bundle`: its signature list was out of date since `94` and `96`. The two CHECK constraints `credit_packages_third_party_commission` and `premium_bundles_third_party_commission` keep every package third-party, so the only effect is a refused save. `502` and `535` pin today's text, so no migration is needed. | Fold the clean-up into the next change to those functions. |
| The TikTok ads engine (16 tables, 4 views, 64 functions) | Its source is only in production's migration history, deliberately not exported. 48 rows of `applied/production-applied.tsv` are marked "ads engine, source not here". | It joins the baseline once the repository is private. |
| Order of files from `403` on | Files went in in commit order, so `432` and `433` come before `418`, and `449` before `446`. | Nothing; do not renumber. |

## Files here

- `applied/production-applied.tsv`: one row per row of production's migration
  history (version, name, size, md5, the file and git revision it matches, and how
  well it matches), then the numbered files with no row.
- `not-applied/`: files that were never applied, and must not be.
- `config.toml`: Edge Function settings only.
- `functions/`: the Edge Functions, `_shared/` holding what they share.
