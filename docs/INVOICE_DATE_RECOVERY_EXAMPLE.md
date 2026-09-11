# Synthetic invoice-date recovery preview

**Test data only. No production customer or invoice records were accessed.** Generated on 11 September 2026 from the isolated invoice-date fixture using `preview.sql` and `review.py`. Five concurrency-test invoices plus seven demonstration invoices produced:

| Classification | Count |
| --- | ---: |
| Already valid | 5 |
| Eligible for automatic recovery | 2 |
| Manual review | 5 |
| Total invoice rows | 12 |

The two eligible examples were:

| Invoice | Proposed business date | Source | Expected additional sales |
| --- | --- | --- | ---: |
| DEMO-DATE-1 | 2020-02-01 | Original `2020-01-31T16:00:00Z` creation timestamp, Singapore calendar date | S$150 |
| DEMO-DATE-5 | 2019-10-01 | Explicit original audit business date | S$0 |

DEMO-DATE-1 totals S$300, with a S$150 receipt collected on 1 March. Recovery adds S$150 to 1 February sales; March collections remain unchanged. DEMO-DATE-2's existing, intentionally backdated 1 December 2019 date is preserved.

The manual list contained:

| Invoice / ID | Review issue |
| --- | --- |
| DEMO-DATE-3 / `29000000-0000-4000-8000-000000000103` | Imported invoice without an established original date. Creation suggests 1 February 2020, but it is not confirmed. |
| DEMO-DATE-4 / `29000000-0000-4000-8000-000000000104` | Audit dates 1 and 2 November 2019 disagree without a reliable intentional correction. |
| DEMO-DATE-6 / `29000000-0000-4000-8000-000000000106` | Latest revision intentionally cleared a disputed date. |
| DEMO-DATE-7 / `29000000-0000-4000-8000-000000000107` | Non-finite original timestamp (`infinity`); no reliable date. |
| Retained concurrency-test invoice (random UUID in generated CSV) | New import evidence committed while recovery waited, so the stale preview was skipped. |

The local generated apply file recovered exactly two invoices. Confirmed/pending counts changed from **5/7 to 7/5**. Every operational table hash remained identical, collections were identical, and ledger event identifiers were not duplicated. The generated reversal restored **5/7**, retaining the two recovery and two reversal audit events. These are a demonstration of the procedure, not estimates of production findings.

Private reports are generated under `.invoice-date-test/review/` during this demonstration; they are ignored by Git. Follow `INVOICE_DATE_RECOVERY.md` to produce an actual approved staging/production preview before any recovery.
