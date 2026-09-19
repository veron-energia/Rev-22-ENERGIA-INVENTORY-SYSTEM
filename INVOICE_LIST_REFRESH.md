# Invoice list: refresh after changes, and live updates

**Reported:** cancel a paid invoice; the list still says Paid until the browser
is reloaded.

## Root cause (confirmed)

Pagination (324) made the list a page of a server-side query: `loadPage()`
fills `pageRows`, and the table renders `pageRows`. The function every save
called afterwards, `loadAll()`, had been left in place but no longer fetched
invoices — its invoice request was a `Promise.resolve({ data: [] })`
placeholder feeding a `setInvoices()` that nothing read. So after a
cancellation, payment, correction, refund, FOC, fulfilment or affiliate change
the catalogue reloaded and the list did not. The Refresh button called the same
function. Only a filter, sort, page or page-size change — or a reload — ran
`loadPage()` again. Confirmed in code before editing (`InvoicesPage.tsx`,
`loadAll` at the old line 327, callers at 317, 968, 1146, 1281–1307, 1423–1483,
1921, 3115, 3600).

## What changed

### One refresh mechanism

- `loadReferenceData()` (was `loadAll`) loads the catalogue once when the page
  opens: stores, products, prices, methods, promotions, staff, therapy. It
  never touches the list. Its comment says so, and why.
- `refreshList({ afterSave?, changed? })` is what every save calls. It asks the
  server for the current page for the current search, status, date filters,
  sort and page size — count, page count, totals and the page's payment
  labels included — through `loadPage(page, { background: true })`. Nothing is
  patched locally; the server's answer is the list.
  - Calls are coalesced (`createRefreshQueue`): one in flight, at most one
    queued behind it, reading the latest query state when it runs. Every
    caller's promise resolves after a refresh made at or after its call.
  - A background refresh keeps the rows on screen until the answer lands. If
    it fails with rows on screen the failure is reported beside them, not as
    an empty error state.
  - `afterSave` is the sentence to show if the save succeeded but the refresh
    did not: "**The cancellation was saved.** The invoice list could not be
    refreshed and may still show the earlier state. Do not repeat the action.
    [Try again]" — Try again is a read-only refresh. Mutations are never
    replayed to repair the screen.
  - Older responses never overwrite newer ones: page requests keep their
    ticket, and payment-label requests stamp the invoices they will write
    (`createStampedWriter`), so a slow earlier label response cannot overwrite
    a label a later request has claimed. Setters are skipped after unmount.
    The "loading…" indicator belongs to the newest foreground load and clears
    when that load settles, even if a background refresh answered first.
  - If the viewer's page no longer exists after a refresh (the last row left
    it), the viewer moves to the last page that does; an empty result shows
    the empty state on page one. A reversed date range sends no request.
- The Refresh button calls `refreshList()`, shows "Refreshing…", is disabled
  while running, and keeps the rows.

### Every invoice operation refreshes

| Operation | Where | Refresh |
| --- | --- | --- |
| Create; unpaid edit; audited correction (lines, customer, store, date, discount, affiliate, raised-by, payment method/amount/date/split/removal) | `handleCreate` incl. `CorrectionPreview.onConfirm` | `refreshList({ afterSave, changed })` after the create → open-detail flow |
| Payment (incl. price review confirm) | `handlePay` | both branches, incl. the "recorded but could not reload" branch |
| Payment amount/date correction, method-only change, refund, reopen, benefit transfer, benefit evidence review | `InvoiceFinancePanel.onChanged` | detail reload (failure reported as a display problem, not a failed action) + `refreshList` |
| Guided cancel / full / partial refund, approval, rejection, rental return | `InvoiceGuidedAction.onDone` | `refreshList` first (it does not wait on the invoice re-read), then `refreshDetail` (the dialog's own retry stays) |
| Legacy request refund/cancel | `submitAction` | `refreshList` |
| FOC confirm, line FOC apply/remove | three handlers | `refreshList` |
| Fulfilment warehouse | `setFulfilment` | `refreshList` |
| Affiliate (unpaid) | `changeInvoiceAffiliate` | `refreshList` |
| Delete | `handleDelete` | `refreshList` |
| Split invoices (credit package / premium bundle) | `handleSplitCreated` | `refreshList` with every new id |

Operations elsewhere (exchanges, therapy sessions, voucher claims, approvals
page, special sales, transfers) do not navigate to the list; the list picks
them up through live updates or on its next open.

### Live updates (`useInvoiceLiveUpdates`)

Every source is a *signal*: the list answers by re-running the same
access-checked query. No row data is read from an event.

- **Realtime** — `postgres_changes` on `public.invoices` and
  `public.invoice_payments`, on a channel per user. Realtime evaluates each
  subscriber's row-level security with their own JWT (`read accessible
  invoices` / `read invoice payments`), so a staff member hears only about
  stores they can already read. Bursts are collected for 400 ms into one
  signal.
- **Other tabs of the same browser** — the tab that saved posts a
  `BroadcastChannel('energia:invoices')` message; other tabs refresh. Works
  with realtime down.
- **Coming back** — the tab becoming visible, the browser coming back online,
  and the channel re-subscribing after a drop each refresh once (visibility
  is ignored if a refresh ran in the last five seconds).
- **Fallback polling** — only while realtime is not subscribed *and* the tab is
  visible: once a minute. A hidden tab makes no requests. While live, no
  polling.
- **Duplicates** — the same change arrives more than once (this tab's save
  and then its realtime echo; another tab's message and then its realtime
  event). A save is noted the moment it succeeds — before the invoice is
  re-read — and announced to the other tabs once. A signal from a *different*
  source about the same invoices within three seconds is that same change:
  the open invoice and an open edit are not told again, and if the refresh
  for it is still on its way the queue covers it. Independently of source,
  a realtime signal whose every announced invoice row equals the row the
  list already shows (status, paid, total, customer, store, date, deleted,
  affiliate) is not news and is dropped — the echo of a change already on
  screen, or the second event of the same transaction. Anything not
  comparable — a payment-row event, an invoice not on this page — refreshes.
  The announced row is compared, never shown.
- **Cleanup** — channel, BroadcastChannel, listeners and timer are removed on
  unmount and whenever the signed-in user changes or signs out
  (`userId` dependency).
- A small badge beside Refresh says **Live**, **Updates paused** (polling) or
  **Connecting…**.

### Drafts and open dialogs

A background refresh only writes list state. It never touches the new-invoice
form, a correction draft, allocations, selections, discount reasons, payment
entries or any open dialog.

- **Open invoice changed elsewhere:** if nothing is being entered (payment
  entry untouched, no refund/correction/transfer in progress in the finance
  panel — it now reports `onActiveChange` — no dialog open), the invoice is
  reloaded quietly with a note "Updated just now — this invoice was changed by
  another user or tab." Otherwise a banner says it changed, keeps the entries,
  and offers **Reload invoice**. Closing the invoice forgets it: a later
  signal about it, or a slow open still in flight, never reopens it.
- **Invoice being edited changed elsewhere:** a banner in the form says so
  and keeps the entries. Saving is refused until **Review the current
  invoice** is opened — it shows *when you opened it* vs *now* for status,
  totals, paid, customer, store, date, affiliate, discount, notes and edit
  count — and either **I have reviewed it — keep my entries** (the save then
  carries the current `edit_count`) or **Discard my entries and reopen**. The
  server's own refusal of a stale save (`expected_edit_count`, 172) maps to
  the same review, so a change that arrived without a signal is caught too.
  A further change after a review asks for the review again (and clears a
  correction preview computed before it); "Discard my entries and reopen"
  stays available throughout.
- The detail view never reopens an invoice the user closed, and an older
  detail load never replaces a newer one (existing tickets).

### Backend

`supabase/338_invoices_in_realtime_publication.sql` adds `public.invoices` and
`public.invoice_payments` to the `supabase_realtime` publication (creating the
publication first on a plain Postgres), and refuses to commit if either table
lacks a SELECT policy or has RLS off. It grants nothing and changes no replica
identity. Applied to the local Docker stack and the integration cluster;
**not applied to production**.

## Tests

- `npm run test:invoice-list-refresh`
  - `scripts/invoices/tests/list-refresh.test.mjs` — the refresh queue, label
    stamps, id extraction, burst collection, coverage check, page landing (9).
  - `scripts/invoices/tests/list-refresh-browser.mjs` — the real page in
    Chromium (Playwright) against an in-memory database shared between tabs
    through `localStorage`, at 1280 px and 375 px: **135 checks**. Paid
    cancelled → Cancelled under All without reload; leaves the Paid filter with
    search, status and page size intact and the count from the server; full
    and part payment (status, outstanding, method label); partial and full
    refund reflect the server; creation opens the invoice and the list gains
    the row; a correction updates customer, date and method label; Refresh
    reloads without emptying the rows; last row leaving page 2 lands on page 1;
    save succeeded but refresh failed → saved-state notice, no repeat, Try
    again; a slow older answer never overwrites a filter change or a
    cancellation; another user's realtime event (a burst of six → one
    refresh); another tab's cancellation reaches this tab; drafts survive a
    background refresh; an open invoice with entries is told, not reset, and
    reloads on request; an untouched one updates quietly; concurrent edit →
    review required, save blocked until reviewed, then carries the current
    version; a stale save refused by the server opens the same review; a
    staff member never sees the other store's invoice even when signalled;
    realtime unavailable → "Updates paused", polls at 60 s, not before, not
    while hidden; coming back refreshes; re-subscription refreshes once; live
    → no polling. Each mutation RPC is counted: none is sent twice. From the
    review: a closed invoice is not reopened by a signal; this tab's own echo
    arriving mid-reload is neither reported nor refreshed twice; the loading
    indicator clears when a background refresh overtakes a page change; the
    guided cancel still refreshes the list when the invoice re-read fails
    (and its Reload only re-reads); Refresh mid-flight keeps rows, shows
    "Refreshing…", disabled, one request; another tab's save plus its
    realtime echo cost one request; a second change after "I have reviewed
    it" asks again, entries kept, save blocked, Discard available; a payment
    correction being entered survives a change elsewhere and then refreshes
    the list; reopen, delete and an affiliate change refresh the list; a
    reversed date range sends nothing from Refresh or a signal; an empty
    result stays a clear empty state; unmount stops the poll and removes the
    channel.
- `npm run test:invoice-live` — `scripts/invoice-live/tests/publication.sql`:
  both tables published, RLS on, and a staff member of one store can neither
  read nor list another store's invoice or payment (passes on PG 14 and PG 17).
- Existing: `tsc` clean; `npm run build` passes; `scripts/invoices/tests/browser.mjs`
  and `invoice-actions-browser.mjs` had been failing since 324 because their
  mocks never answered `invoice_list_page` (verified identical on HEAD in a
  temporary worktree); they now get a paged answer and run further, and stop
  at two pre-existing assertions (the 326 instalment section and a 320 px
  overflow) that are unrelated to this change.

## Review

An adversarial review (four lenses, each finding re-checked by a skeptic)
found five real defects in the first version, all fixed and each now covered
by a browser check: a closed invoice reopened by the next live signal about
it; the "loading…" indicator stuck when a background refresh overtook a page
change; the guided cancel/refund skipping the list refresh when the invoice
re-read failed; this tab's own realtime echo, arriving while the invoice was
still being re-read, reported as another user's change and refreshed twice;
and a second concurrent edit after "I have reviewed it" leaving the form
unsaveable.

## Verified against the local stack (Docker Supabase, real realtime)

- Owner signed in, `/invoices`: badge shows **Live**; the list loads (152
  invoices, 25 per page).
- **Cross-user:** a manager (separate session, REST with their own JWT)
  recorded S$100 on INV-2026-0009 → the owner's tab showed
  *Partially Paid · S$895.00 · Cash* within a second, with exactly one list
  request.
- **Cross-tab:** a second tab of the owner's session recorded S$50, then S$10,
  on the same invoice through the UI → the first tab showed S$845.00, then
  S$835.00 outstanding; the second save cost the first tab exactly one list
  request (the tab announcement and the realtime event were recognised as
  one change).
- **Changed underneath an entry:** with INV-2026-0010 open in tab A and an
  amount typed, the manager recorded S$25 via REST → tab A showed the
  "changed by another user or tab" banner with the typed amount kept;
  **Reload invoice** brought the current figures.
- Mobile (375 px) and desktop layouts checked in the browser suite and the
  live stack.
- StrictMode: the development double-mount was leaving the mounted flag false
  (found on the live stack, fixed: the flag is set on mount as well).
- After the review fixes, repeated on the live stack: a colleague's payment on
  an invoice the owner had just opened and closed → one list request
  (+814 ms), the list updated, the closed invoice stayed closed.
- Local test data left on the Docker stack: `manager@local.test` (deactivated;
  its fixture payments reference it) and the test payments on INV-2026-0009 /
  INV-2026-0010. Nothing was touched on production.

## Request volume

One save → one list request (+ one label request for the page) plus the
detail reload the save already did. Realtime echo of the same save: none.
Another user's burst of events: one request. Another tab's save: one request
(its realtime event is recognised as the same change). Idle, live: zero
requests. Idle, realtime unavailable, visible: one per minute. Hidden: zero.
Reference data: once per page open.

## Deployment

1. Apply `supabase/338_invoices_in_realtime_publication.sql` to production
   (psql, as the other migrations). Realtime is on for the project by default;
   the Dashboard's Realtime page will then list both tables.
2. Deploy the frontend.
3. Until 338 is applied the page works as before plus the refresh-after-save
   fix; the badge shows "Live" (the channel subscribes) but no events arrive,
   so other users' changes appear on focus, on the minute poll (only when the
   channel is not subscribed — so in that state, on focus and on other tabs'
   announcements), or on Refresh. Apply 338 for the cross-user path.

**Post-deployment verification needed:** the cross-user path against
production's Realtime service (the local stack's Realtime is the same image,
but the hosted service's RLS evaluation and quotas are the ones that matter);
the size of the realtime connection count under normal staffing.

## Rollback

- Frontend: redeploy the previous build; nothing in the database depends on it.
- 338: `alter publication supabase_realtime drop table public.invoices, public.invoice_payments;`
  — the page then falls back to focus/poll/other-tab signals as above.

## Limitations

- "Same change by another route" is a three-second, same-invoices,
  different-source rule. A colleague's further change to the same invoice
  inside that window is still caught when the event carries the invoice row
  (the row is compared with the list) or when it is a payment-row event that
  arrives after this tab's refresh has landed; a payment-row event arriving
  while that refresh is still in flight is folded into it, and one arriving
  within the window for an invoice not on the current page is refreshed by
  the next signal, the next focus, or Refresh — late, not lost.
- The open-invoice auto-reload treats the payment entry as touched from the
  first keystroke; a reload then needs the user's click.
- Polling when realtime is unavailable is once a minute; a change by another
  user can take up to a minute to appear in that state (focus or Refresh is
  immediate).
- Changes made on other pages (exchanges, therapy, approvals) reach the list
  through realtime or on the next open of the page; those pages were not
  changed.
