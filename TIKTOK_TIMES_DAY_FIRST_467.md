# TikTok order times read day first (467): report

24 Oct 2026. **467 is LIVE in production** (applied 24 Oct 2026 by the MCP's apply_migration, version 20261024045047;
the stored statement md5 equals the file's, `9c6b9ff9bb39f67b1afd4328139dc629`). The repair is not run: it needs its own
go-ahead. Every production figure below came from read-only queries and is a count; no order, customer or SKU is named.

| Piece | File | State |
|---|---|---|
| Parser fix (migration) | `supabase/467_tiktok_times_read_day_first.sql` | **LIVE** 24 Oct 2026 (20261024045047) |
| Repair of the stored times | `scripts/tiktok/repair/467-restore-tiktok-order-times.sql` | draft; needs its own go-ahead, after 467 |
| Repair preview (read only) | `scripts/tiktok/repair/467-restore-tiktok-order-times-preview.sql` | safe to run any time |
| Local test | `scripts/tiktok/tests/times-day-first-467.sql` | **156/156 PASS** on Docker `energia_events`, rolled back |

## 1. The bug

`tiktok_parse_time` (64) first tried a cast, `replace(v,'/','-')::timestamp`. A cast follows the server's DateStyle, and
production's is `ISO, MDY`. So when TikTok's `DD/MM/YYYY HH24:MI:SS` text had a day of 12 or less, it was read month
first: 11 October became 10 November. Only days of 13 and later made the cast fail, which let the day-first reading run.

What production holds (24 Oct 2026, after 465):

- **tiktok_order_rows**: 181 rows from 17 files (csv and xlsx). Every raw time is `DD/MM/YYYY HH24:MI:SS`: the second
  number is never above 12, and the first is above 12 in 352 of the 809 times.
  **421 of the 809 stored times are swapped, on 111 rows.** 73 of those rows are confirmed. 285 of the swapped times sit
  on confirmed rows and 136 on rows of deleted files.

  | column | swapped |
  |---|---|
  | created_time | 101 |
  | paid_time | 98 |
  | rts_time | 92 |
  | shipped_time | 74 |
  | delivered_time | 49 |
  | cancelled_time | 7 |

  Every swapped time lands in the wrong month, and 131 of them are in the future. Every one of the 1,086 stored values
  (nulls included) is exactly what the old function gives for the row's raw text. So the old reading explains every
  difference, and nothing else wrote these columns.
- **tiktok_settlement_rows** (305 rows): `order_created_time` and `settled_time` come as `YYYY/MM/DD`. A cast always reads
  a year-first date as year, month, day, so all 305 are right.
- **tiktok_balance_records** (withdrawal records, 375): `request_date` and `success_date` also come as `YYYY/MM/DD`. All
  16 bank payouts fall on a Wednesday, 7 of them on days of 12 or less, so these are right too.

## 2. Who reads the affected times, and what moves

Found from production's own catalogue: every function in every schema whose body names one of the columns or the
parser. The repository's `src/` and edge functions were checked as well.

| Column(s) | Written by | Read by | Wrong now? |
|---|---|---|---|
| tiktok_order_rows: rts / created / paid / shipped / delivered / cancelled_time | `stage_tiktok_orders` (through the parser) | **nobody.** No function, view or edge function reads them. The Import page fetches whole rows (`select *`, Items tab and preview) but shows none of the six. 465's `tiktok_row_shows_shipped` reads the *raw* text, for this reason. | yes (421) |
| tiktok_settlement_rows: settled_time, order_created_time | `stage_tiktok_settlement`, `stage_tiktok_settlement_file` | `report_tiktok_settlement` (+ `_by_store`, `_daily`, `_summary`), `report_sales_reconciliation`, `tiktok_settlement_totals`, `tiktok_settlement_daily`, `tiktok_settlement_eligible`, `tiktok_settlement_diagnostic`, `tiktok_left_out_settlement`, `tiktok_settlement_left_out_rows`, `include_tiktok_settlement_rows`, `confirm_tiktok_settlement_batch`, `trg_tiktok_settlement_immutable`, `tiktok_reporting_month` / the settlement periods, `tiktok_xero_payouts`, `tiktok_bank_payouts` | no |
| tiktok_balance_records: request_date, success_date | `stage_tiktok_settlement_file` | `tiktok_bank_payouts` (the Xero export) | no |

The places named in the brief:

- **report_tiktok_qty_sold** and **report_tiktok_stock_activity** filter by `confirmed_at`. **report_tiktok_imports**
  filters by the file's `uploaded_at`. None of them reads an order time.
- **tiktok_reporting_month** receives `settled_time`, or generated days in `tiktok_bank_payouts`. Both are right.
- **The Import page's month filters**: the settlement reporting month uses the settled date. The lists sort by
  `confirmed_at`, `updated_at` or `created_at`.
- **The Xero export** (`TikTokXeroExport.tsx`) uses `tiktok_bank_payouts` and `tiktok_xero_payouts`, which read settled
  times and withdrawal dates. Both are right.
- **The Dashboard tiles**: `dashboard_alerts_summary` (order state and settlement matching) and
  `tiktok_negative_stock_alerts` (stock). Neither reads an order time.

**What moves when the dates are corrected: no figure in the app, now or after the repair.** Two other things are wrong
today:

- any raw SQL or ad hoc look at TikTok orders by `created_time` or `shipped_time`, such as "orders placed in October" (465's
  diagnosis read the raw text for this reason);
- any future feature that would date orders by these columns.

So the fix is about keeping stored data correct before something starts reading it. Nothing in the app needs to be
recomputed.

## 3. The parser fix: migration 467 (LIVE)

The rule:

- A time that starts with a day and a month (`D/M/YYYY`, with `/`, `.` or `-` between) is read **day first, always**,
  by its parts. There is no cast, so DateStyle no longer matters. Accepted: the day alone, `HH24:MI` or `HH24:MI:SS`
  (with fractions), or an AM/PM hour.
- A value that is not a real date or time (31/02, a 13th month, 25:00) is null, as an unreadable time already was.
- Year-first text (`YYYY/MM/DD` from the settlement and withdrawal sheets, or ISO) is read exactly as before.
- Two short numbers first (`01/07/26`) is null rather than a guess, and so is text with no digit (a cast used to read
  `now` as the current moment).

The function also gets `SET search_path TO 'public'`, like the other TikTok helpers. It stays IMMUTABLE plpgsql,
without security definer, and keeps its grants (signed-in staff and the service role; never anon). Its three callers
are unchanged.

It is written in the house style of 464/465:

- one DO block behind a 5 s lock timeout;
- md5 guards of `pg_get_functiondef` with search_path public: the BEFORE `d7b6de34…` is replaced, the AFTER is left
  alone, and anything else is refused;
- pins on what the self-test relies on: `stage_tiktok_orders` and the 7-argument `tiktok_evaluate` as 465 left them,
  `tiktok_access_check`, `write_audit_ex`;
- the grants are compared as sets after installing;
- a self-test that always undoes itself (it raises P0467). It reads 19 examples under `ISO, MDY` and `ISO, DMY`, then a
  made-up Owner and store stage a two-row file through `stage_tiktok_orders` and the six stored times must come out day
  first. No row is left and no sequence is used.

| | md5 / fingerprint |
|---|---|
| tiktok_parse_time BEFORE (production, as at 64) | `d7b6de34d5f955479a4f97ea9df38b0c` |
| tiktok_parse_time AFTER | `9ab3b68b4fc30013d6bc75294d68bc66` |
| public fingerprint, production now (465 in) | `0b8580cda1e2c697a1e9219f95ed3046` (1380) |
| public fingerprint after 467 (worked out read-only from production's md5 list) | `732a3805a2fafa035c5a46068026c81f` (1380, one replaced) |

Go-live, each step with the Owner's go-ahead:

1. Re-check `schema_migrations` and `origin/main`. 467 is claimed in the shared notes. 462/463 (invoices) and 466
   (affiliate sign-up, which claimed 466 first) belong to other sessions, and none of their files is touched here. The
   fingerprint must still be `0b8580cd… 1380`. If 466 (or 462/463) went first, work the before and after fingerprints
   out again from production's md5 list; the md5s this file checks do not change.
2. Run `apply_migration` with the file text verbatim, then check the AFTER md5 and the fingerprint `732a3805… 1380`.
3. No page change. Files staged from then on store their times right.

Applied 24 Oct 2026, after checking that the fingerprint was still `0b8580cd… 1380`, that the last migration was 465,
and that the parser and all four pinned functions were as pinned. The checks after applying:
- the stored statement md5 equals the file's;
- the parser is `9ab3b68b…` and the fingerprint `732a3805… 1380`, as worked out beforehand;
- the grants are as before, and the function is IMMUTABLE with `search_path=public`;
- every public and auth sequence is unchanged, and the self-test left no user, store or row;
- `11/10/2026 19:02:31` reads as 11 October and `2026/09/07` as before;
- 421 stored times are still swapped, as expected, until the repair.

What it does not cover: a shop whose export is month first (a US-locale TikTok shop) would now be read day first, or
null for days above 12. This shop's 17 files are all day first.

## 4. The repair of the stored times (draft, separately owner-gated)

`467-restore-tiktok-order-times.sql` is one DO block, run as the database owner after 467 is in:

- It refuses unless `tiktok_parse_time` is 467's AFTER and `trg_tiktok_row_immutable` (`e4b60289…`) and
  `write_audit_ex` are as read. The table's only trigger of its own must be `tiktok_row_immutable`, switched on, with
  its definition as read, and the columns must have their types.
- For every row and each of the six columns, it compares the stored time with 467's reading of the raw text. When they
  differ, the stored time must equal the **old reading**: the 64 body is reproduced word for word under `ISO, MDY`,
  whatever the session's DateStyle. If a stored time matches neither reading, the repair refuses and names the row and
  column: something other than the import wrote it.
- **Preview**: run it without `repair467.go`, or run the separate preview select (the MCP does not show notices). It
  prints the counts and changes nothing. Run on production on 24 Oct 2026, after 467: **421 times on 111 rows (73
  confirmed, 38 of deleted files), every one a month off, 131 of them in the future, none that 467 cannot read.** So
  `repair467.expect` = 421 unless a file is imported in between.
- **Go**: `repair467.actor` must be an active Owner's profile id, `repair467.go = 'yes'`, and `repair467.expect` must
  equal the count the preview printed. If the count has changed since, it refuses.
- **The immutability trigger.** Confirmed rows refuse every update, and that stays the rule everywhere else. Inside
  this one statement only, the repair:
  - takes a SHARE ROW EXCLUSIVE lock on the table, so every other writer waits;
  - writes one audit row per row (`tiktok_order_times_restored`, holding the times as they were and as they become),
    under the Owner;
  - runs `alter table … disable trigger tiktok_row_immutable`, updates the six times on exactly the counted rows to 467's
    reading, and runs `enable trigger`;
  - then checks four things: the trigger is on as it was, every row's six times equal 467's reading of its raw text,
    nothing else of any row changed (md5 of every row minus the six columns), and the audit rows are there.

  Because DDL is transactional, any failure undoes all of it, the switch-off included. The test proves this by forcing
  the update to fail after the switch-off. A second run finds nothing to do.
- **Undo**: each audit row's `old_data` holds the times as they were, by row id.

The decision for the Owner: since nothing reads these columns, leaving them is possible. Repairing them is recommended,
so the stored data is true before anything starts reading it. It adds 111 rows to the audit log.

## 5. Local test

`scripts/tiktok/tests/times-day-first-467.sql` (`begin … rollback`; no file it runs contains a commit):

```
psql -X -v ON_ERROR_STOP=1 postgresql://postgres:postgres@127.0.0.1:54322/energia_events -f scripts/tiktok/tests/times-day-first-467.sql
```

Run on 24 Oct 2026: **All 156 467 checks passed.** The local function fingerprint was the same before and after
(`de75b0bd… 1053`), and the table was still empty.

The local database is older than production. Inside the transaction, the suite therefore installs production's
helper bodies (the same block as the 465 suite) and 465 itself, and stages the fixtures with the old parser. It covers:

- **P**: the bug reproduced. One file is confirmed (its rows immutable), one is staged, and one is staged then deleted.
- **M**: 467 twice. The first run changes `tiktok_parse_time` alone and the second nothing. The suite checks: no row
  left, no sequence used, no stored time changed, DateStyle as it was, the AFTER md5, and the grants.
- **G**: 34 inputs under three DateStyles: leap days, AM/PM, separators, fractions, impossible dates, ISO, `now`, empty.
- **N**: a file staged after 467 stores its times day first. A settlement file's `YYYY/MM/DD` times are read as before.
- **V**: the preview's counts.
- **R**: the repair.
  - Each refusal changes nothing: no go-ahead, no or wrong actor, a Manager, no count, a wrong count.
  - A hand-edited time is refused and named.
  - A failure after the switch-off is undone completely.
  - The real run puts right exactly 11 times on 5 rows and changes nothing else. It writes 5 audit rows by the
    Owner, the trigger is on again, and a confirmed row still refuses an update.
  - No stock, state or other row is touched and no sequence is used.
  - A second run does nothing.

Fixtures only (`T467`, `@example.com`, invented order ids and times).
