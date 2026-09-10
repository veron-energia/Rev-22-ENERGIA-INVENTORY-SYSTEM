# Stock History verification — 10 September 2026

All writes were confined to the exclusive local `energia_stock_history_test` PostgreSQL database at socket `/tmp`, port `55443`. Test fixtures were rolled back. No production connection, deployment, stock repair, commit or push was performed.

| Check | Result |
| --- | --- |
| Complete effective schema, including new migrations 270–272 | **197 migration files applied; zero failures** on a fresh isolated schema. |
| New database access/search tests | **Passed.** Actual authenticated staff role, multiple assignments, other actors, no assignment, counterpart names without balances, raw table/API restrictions, management roles, all supported search fields, exact counts and stable full pagination across more than 5,100 rows. |
| New lifecycle/report tests | **Passed.** Split source quantities and notes; SG midnight; dispatch before receipt; cross-period opening/closing and transit; OR/AND filters; actual balances unaffected by person/text/type filtering; missing evidence and unmatched effects flagged. |
| Real invoice/stock writers feeding reports | **Passed.** Sale, sellable/damaged/not-returned refunds, cancellation, stock use, positive/negative adjustments; drift suppresses exact balances without repairing stock. |
| Shared note history | **Passed.** Request visible before approval; dispatch visible to recipient; original receipt discrepancy remains after resolution; edit/rejection reasons and original request retained; duplicate audit/field entries removed; missing attribution remains unknown. |
| Existing phase 57 transfer review tests | **Passed.** Deferred demand, manual lines, changed approval quantities, store/warehouse sourcing, dispatch/receipt timing, availability, atomic insufficient-stock failure and competing approvals. |
| Existing invoice lifecycle regression | **Passed.** Financial/stock retries, corrections, refunds, cancellation, reopening, damaged/not-returned exclusion, saved historical prices, credit and therapy entitlement rules. |
| Existing phase 54 allocation tests | **Passed.** Lowered/excluded quantities and exact source allocations. |
| Existing phase 56 in-transit tests | **Passed.** Approved quantities, excluded lines and multi-source receiving. |
| Existing phase 55 ship-from-store test | Original fixture **fails before its stock checks** because it inserts invalid phone `+65SFS1`, rejected by the existing customer-phone validation. An otherwise identical temporary copy using valid synthetic phone `+6591237768` **passes all eight checks**. Original file unchanged. |
| Export helper tests | **9 passed.** Full 6,005-row collection, fixed cutoff and filter forwarding, both report endpoints, failed/missing/duplicate/changed/revoked pages, formula-like text and SG default dates. |
| Offline browser verification | **Passed at 1280, 320 and 390 pixels.** Real page/components, multi-select/chips, clear-search vs clear-filters, tab persistence, keyboard tab switching/Escape/focus, shared notes, loading failures, export failures, no assignment and no page-width overflow. |
| Downloaded Excel files | **Passed for both tabs at all three widths.** Actual workbooks were opened and checked for context/timezone, movement values, filtered totals, actual balance labels and historical warnings. |
| Existing customer-phone tests | **9 passed.** |
| Existing survey tests | **26 passed.** |
| Type checking and application build | **Passed.** Vite reports the large-bundle advisory; it does not fail the build. |
| Read-only diagnostic | **Executed successfully.** Missing-history, inventory/evidence, gross/net movement, discrepancy and duplicate/unlinked queries compile and run. Empty results after fixture rollback do not certify production data. |
| Diff whitespace check | **Passed.** |

The new database tests also verify that a later entry with an old document date does not alter a captured report cutoff, while a fresh report places its stock effect on the actual record date. Source-only staff cannot use older whole-transfer report APIs to recover unrelated source legs. Legacy authorized sourced-request edits remain usable, with private balance validation and a non-disclosing failure message.

## Existing issue distinguished from this change

The migration-159 transfer integrity report had untyped NULLs in a UNION that PostgreSQL inferred as text before encountering a UUID location column. Migration 272 supplies explicit casts, preserving the intended report shape. The effective report now executes and the phase 57 regression passes.

The phase 55 failure above belongs to its obsolete sample phone, not Stock History. To reproduce the compatibility check without altering that existing test:

```sh
python3 - <<'PY'
from pathlib import Path
source = Path('supabase/tests/phase55_ship_from_store_tests.sql').read_text()
assert source.count("'+65SFS1'") == 1
Path('.stock-history-test/phase55-valid-fixture.sql').write_text(
    source.replace("'+65SFS1'", "'+6591237768'"))
PY
scripts/stock-history/local-sql.sh -f .stock-history-test/phase55-valid-fixture.sql
```

## Remaining verification and manual review

- No live/staging Supabase data or actual user sessions were accessed. Database tests exercise PostgreSQL roles/functions; browser tests use an offline API fixture. Perform the end-to-end staging checks in the deployment guide before release.
- Browser interaction was checked in Chrome at desktop and mobile viewport sizes, not on physical iOS/Android devices or with a screen reader.
- Production-scale query latency, very large exports, concurrent edits to existing records during exports, and the complete range of legacy data anomalies remain staging review items. Captured cutoffs and row/count checks protect normal paging; exports are not permanent transaction snapshots.
- No verified pre-migration historical baseline was supplied. Older exact balances remain Unknown; unlinked or duplicate old transfer effects, unresolved discrepancies and evidence gaps require operator review. No automatic history linking, merging, quantity correction or historical backfill was performed.

Run commands, access rules, balance definitions, changed files, migration order and rollback guidance are in [STOCK_HISTORY_DEPLOYMENT.md](STOCK_HISTORY_DEPLOYMENT.md). Local logs, screenshots and sample workbooks are under `.stock-history-test/`, which is ignored. The files in that folder are evidence from synthetic fixtures, not company reports.
