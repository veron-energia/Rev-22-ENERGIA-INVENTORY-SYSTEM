# Codebase review and cleanup, before a calendar

**Scope.** A review of the whole application with risk-based priorities, the
fixes that review justified, focused cleanup, regression tests and
documentation. Preparation for a future Google Calendar feature only: no
calendar code, no OAuth, no credentials and no external events were added. The
readiness assessment is in [CALENDAR_READINESS.md](CALENDAR_READINESS.md).

**Applied to production on 2026-09-20.** All seven migrations are live on the
`Energia Inventory System` project, applied between 14:36 and 14:39 SGT after a
pre-flight against the live database and an adversarial review that found and
stopped a real defect first (see "What the pre-flight caught" below). Nothing
was committed or pushed, no edge function was deployed, and no production record
was read or repaired. Invoice and customer counts were identical before and
after: 244 and 12,886.

**What this report does not claim.** The application is not bug-free and this
review did not make it so. What follows is what was examined, what was changed,
and what was verified — including several confirmed defects that were
deliberately left for a decision rather than guessed at.

---

## 1. The headline

Six defects were fixed that could expose another customer's information, bypass
role permissions, or hand out benefits and money twice.

| | Defect | Severity | Fixed by |
| --- | --- | --- | --- |
| 1 | 637 of 794 database functions were callable by anyone holding the publishable key, which ships in the browser bundle | High | migration 339 |
| 2 | Eight owner/manager guards let a caller with no role through, because `NULL not in (…)` is not true | High | migration 340 |
| 3 | A negative voucher quantity bought headroom in a claim, so five could be issued against two | High | migration 341 |
| 4 | Two tables never had row-level security enabled at all, with full read and write granted to signed-out callers | High | migration 342 |
| 5 | An affiliate login could make itself an Owner, rewrite any customer, and read the whole medical and financial record | High | migration 343 |
| 6 | The invoice email function made no authorization decision, so the publishable key could send mail from the company domain | High **latent** — see below | `send-invoice-email` |
| 7 | Any signed-in staff member, of any role, could write off any quantity from any warehouse | High | migration 345 |

Three more that lose money or records quietly:

| | Defect | Severity | Fixed by |
| --- | --- | --- | --- |
| 8 | A settlement file over 1,000 rows confirmed its first 1,000 and silently dropped the rest | High | `TikTokImportPage.tsx` |
| 9 | The invoice Excel export contained 400 of every 1,000 matching invoices | High | `listPage.ts` |
| 10 | A part-paid commission was reported as paid in full | Medium | `ReportsPage.tsx` |

And three hardening changes: a voucher can now only be issued once per invoice
line, staff commission payouts are serialized (344), and the survey QR print
escapes stored text (with the shared escaper widened to cover quotes). Seven
assertions in the test fixtures that could never fail were also repaired.

---

## 2. Baseline

Repository at `main`, with substantial uncommitted work from the previous task
present and preserved. Nothing was reset, stashed or switched. Type checking and
the production build passed before the work started and pass now.

Two disposable local databases were used throughout:

- the integration cluster (`energia_integration_test`), reached only through
  `scripts/invoices/local-sql.sh`, which refuses any other database;
- a local Supabase stack in Docker, which is the fuller replica because it
  carries the platform's own default privileges. Where a conclusion depended on
  grants, it came from there. Neither is production, and that is stated wherever
  it matters below.

The integration cluster is **not** a faithful replica: one function the
application calls, `set_invoice_instalment_label` from migration 326, is absent
there although the Docker replica has it. That drove a design decision — every
migration below computes what it needs from the live catalogue at apply time
rather than from a list written against one database.

**Pre-existing failures, not caused by this work.** Two suites cannot run in
this environment and did not run before the work either:

- `test:phase4` needs a Supabase URL and a service-role key. Not run, because
  the only real key available is production's.
- the `*:db` suites need a second disposable cluster on port 55442. It was not
  running; `scripts/auth-email/bootstrap-local.sh` brought it up and they then
  ran.

---

## 3. Findings register

Classification as asked: **(a)** fixed and verified, **(b)** still present and
fixed during this task, **(c)** not applicable to the current implementation,
**(d)** unresolved, with the reason.

### The fourteen earlier findings

| # | Finding | Status | Evidence and outcome |
| --- | --- | --- | --- |
| 1 | Authorization around credit granting and voucher revocation | **(a)** | Every entry point is guarded by a positive check (`can_manage_customer_credit`, `is_owner_or_manager`), and the grant, reverse, reassign and revoke functions have no grant to signed-in users at all. Re-verified after 339. |
| 2 | Negative voucher quantities allowing over-issuance | **(b)** | The claim's counting loop added every quantity; the issuing loop skipped non-positive ones. `[{A:5},{B:-3}]` counted as 2 and issued 5. Fixed in 341, with a regression test that reproduces the payload. |
| 3 | Duplicate voucher claims on retries | **(d)** | Confirmed present. `claim_entitlement_vouchers` takes no request id and `voucher_claims` has no idempotency key, so a lost response followed by a retry creates a second claim document. The row lock caps the total, so this cannot over-issue beyond the entitlement. Left unfixed: adding a request id changes a client contract and the house pattern (298) deserves a deliberate design pass. |
| 4 | Missing authorization for invoice email sending | **(b)** | The function had no identity check of any kind, and recipient, subject, body and attachment were all caller-supplied. Now requires a bearer token, a real user, an active staff profile, and store access for the document's store. |
| 5 | Unescaped stored text in survey QR printing | **(b)** | The survey QR print was the only print path that never escaped. Fixed, and the shared `esc` was widened to cover `"`, `'` and `>` because it is also used inside HTML attributes. |
| 6 | Exchange instalment/deposit linkage | **(d)** | Confirmed present, by a different mechanism than the finding described. The database implements linkage correctly; the Exchanges screen offers "Instalment — pay over time" and then sends an empty arrangements list, discarding the terms. Left unfixed: the correct behaviour is a business question about what an exchange instalment means. |
| 7 | Incorrect commission "Paid Out" after partial payouts | **(b)** | The database was right; the Reports page summed `commission_amount` for every commission whose status was `paid`, and a payout marks a commission paid on any slice. Now read from the payout records, the same basis the other two screens use. Regression test included. |
| 8 | Later receipts not linking to instalment arrangements | **(c)** | Migration 326 retired the arrangement model; an instalment is now recorded as the receipt it is. One residual (Low) is recorded in section 7. |
| 9 | Unpaginated queries silently omitting records | **(b)**, partly | Two of the worst fixed: the invoice export (400 of every 1,000) and the TikTok settlement confirm (first 1,000 rows of the file). The class is wider — section 7 lists the rest. |
| 10 | Incomplete voucher-claim documents | **(d)** | Confirmed present and presentation-only: a claim document prints as a zero-line S$0.00 "Tax Invoice" although `voucher_claims.selections` holds what was handed over. Left unfixed: what the customer's copy should say is a business decision. |
| 11 | Missing historical eligibility allowing overly broad claims | **(d)** | Confirmed present. Entitlements predating migration 310 have no eligible-voucher snapshot, and the guard only applies when the snapshot exists, so any active reward voucher can be chosen. A reconciliation function computes a suggested list but nothing writes it back. Left unfixed: backfilling what a customer was sold is exactly the invention this task was told not to make. |
| 12 | Deferred voucher deadlines from unrelated rules | **(d)**, partly | Fixed for premium bundles by migration 323. Still present for credit packages, which derive the deadline from the therapy rule with the lowest qualifying amount — unrelated to the package. Left unfixed: the correct deadline is a business rule. |
| 13 | Ineffective stock regression assertions | **(b)** | Confirmed: `sum(...) <> 9` is NULL when the key is missing, and a NULL condition takes the false branch, so the assertion passes on the regression it guards. Fixed in the fixtures listed in section 5. |
| 14 | Excessively large initial bundles | **(a)** | All 47 routes are lazy; the eager graph is nine modules. Measured in section 8. |

### The eight previously reported fixes

All eight hold. Verified against the installed definitions and the current
client code, not against the reports that claimed them.

| Fix | Status | Evidence |
| --- | --- | --- |
| Customer reassignment affecting unrelated credit lots | **(a)** | Lots are scoped to the invoice's own lot ids and must be untouched and active; no customer-wide scan. |
| Reassigned credit losing spending eligibility | **(a)** | The new lot carries the original restrictions, category and provenance, and policy resolution walks back to the originating lot. |
| "Keep recipients" versus "transfer unused benefits" | **(a)** | The correction refuses without an explicit benefit action, and the screen offers both as radio options. |
| Deferred Premium Bundle voucher selection | **(a)** | No live function still requires an exact selection. One repair tool retains the old wording and says so. |
| Quantity-first voucher collection | **(a)** | Quantity is taken first, capped per voucher, and submission requires the picks to match the total. |
| Existing-customer affiliate signup | **(a)** | Both functions carry their outcome flags and the page branches on those rather than on message text. |
| Invoice date filters | **(a)** | The installed function excludes undated invoices from a range and carries both range guards; covered by an existing test. |
| Paginated invoice-list refresh across users and tabs | **(a)** | Every mutation notes the change then refreshes the current page; live updates are per-user channels plus a cross-tab broadcast, treated as signals with the list re-querying the access-checked function. Verified live in the browser: the list shows its live indicator and re-reads after changes. |

---

## 4. The security fixes, in detail

### Functions were endpoints by default (339)

PostgreSQL grants EXECUTE on a new function to `PUBLIC`. Supabase's `anon` role
inherits that, and the anon key ships inside the browser bundle. So every
function this application ever created was, by default, an endpoint anyone could
call without signing in — 637 of 794 of them.

339 replaces that with an allowlist computed at apply time: five functions the
signed-out pages genuinely need, the functions the client calls (granted to
signed-in users), and everything else granted to nobody but the service role.
Extension-owned functions are excluded, because the migration role cannot revoke
them.

The single most important thing this migration learned: **row-level security
policies are evaluated as the querying role**, so a helper used inside a policy
must stay executable by that role or every policy using it fails and the
application empties for staff. The migration computes that set — policy
expressions, check constraints, column defaults and index expressions — and
keeps those functions reachable.

Verified over HTTP against the local Supabase stack: signed out, the API lists
seven callable functions, being the five endpoints plus two harmless text-search
helpers from an extension. Signed in, 357. None of the 243 functions the
application calls was lost.

`ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE … FROM PUBLIC` does **not** withdraw
this default — verified on PostgreSQL 14 and 17 — so every future migration must
grant explicitly. That is documented in the migration itself, and
`scripts/permissions/tests/function-grants.sql` fails if a new function appears
outside the allowlist.

### A role nobody has is not permission (340)

Eight functions guarded themselves with `if current_user_role() not in
('owner','manager') then raise`. An affiliate has no profiles row, so the
function returns NULL, `NULL not in (…)` is NULL, and PL/pgSQL takes the false
branch. The guard never fired.

Anyone with an affiliate login could delete a TikTok import batch, rewrite the
customer-source options, change status mappings, or reattribute an invoice to a
different member of staff. All eight call sites are staff-only screens, so no
legitimate affiliate workflow changed.

### A signed-in customer is not staff (342, 343)

Most read policies here say "to authenticated using (true)". That was an
accurate way to write "any member of staff" until affiliates began signing in
for themselves. The set of people holding the signed-in role grew; the policies
were never revisited.

- **342** switches on row-level security for `commission_corrections` and
  `credit_package_progress_lots`, the only two tables in the schema that never
  had it. With it off and the platform's default grants in place, both were
  readable *and writable* by a signed-out caller. Neither is named anywhere in
  the application; every legitimate reader is a definer function owned by the
  table owner, so they are now deny-by-default with no policy at all.
- **343** drops the INSERT policy on `profiles` and scopes 45 policies to "has a
  staff role at all".

The profiles policy was the worst of them. The privilege guard on that table is
a BEFORE UPDATE trigger, so it does not fire on INSERT, and the role column is
caller-supplied. **Verified by running it**: an affiliate session inserted its
own profile with role `owner` and immediately read back as an owner. It now has
no INSERT policy; profiles are created by `invite_user_accept`, a definer
function that policies do not apply to.

`customers` was the second worst: update was open to any signed-in session,
including `referred_by`, which is the referral chain commission is calculated
from.

**No staff role lost anything.** `true` became "has a staff role", which is what
the policies meant when they were written; no store scoping was added. Verified
two ways: the regression test asserts an Owner still reads and writes everything
it did, and the running application was driven through the invoice list,
customers, therapy, surveys and reports screens with 53 database requests and
zero failures.

### The email function decided nothing (send-invoice-email)

The handler read the body and posted to Resend. Recipient, subject, body and
attachment were all caller-supplied, so whoever held the publishable key could
send arbitrary mail with arbitrary attachments from the company's verified
domain, and the customer name and document number were interpolated into the
outgoing HTML unescaped.

It now requires a bearer token, resolves it to a real user, requires an active
staff profile, and — when the caller names the document's store — asks the
database whether they may see that store, through the same function the invoice
screens are gated on. The decision lives in `authorize.ts` so it can be tested
without a network or a server, and nine tests drive it.

**A correction to the severity above.** When it came to deploying this, the
function turned out never to have been deployed at all — not on the live project
and not on the paused one. So the hole was never reachable in production: it was
a real defect in code that would have become live the first time anyone deployed
it. It is listed as High because that is what it was worth fixing as, but it was
latent, not exploited and not exploitable. Saying otherwise would overstate it.

**It is now deployed, with the fix in place** (2026-09-20, version 1,
`verify_jwt` on). The refusal paths were checked against the live endpoint: a
request with no credentials is refused at the gateway, and the CORS preflight is
answered by this function's own code — which incidentally proved the thing that
could not be tested locally, that both of its imports resolve in the real edge
runtime. The authenticated success path was deliberately **not** exercised,
because doing so sends a real email to a real address.

---

## 5. The correctness fixes, in detail

### The export contained 400 of every 1,000 invoices

`invoice_list_page` clamps its page size to 200 and reports the limit it used.
The export asked for 500 a page and advanced the offset by 500, so it skipped
every row between 200 and 500 on every round. An export of 1,000 matching
invoices contained 400 of them, in the right order, with no error and a
plausible-looking file.

It now pages by what the server returned. The regression test reproduces the
clamp and asserts every matching invoice appears exactly once; run against the
old arithmetic it returns 400 of 1,000.

### A settlement file over 1,000 rows confirmed only its first 1,000

The TikTok import screen read a batch's rows with no paging. PostgREST stops at
1,000 rows and reports no error. Those row ids are exactly what the confirm
sends, so the remainder of the file was never confirmed — silently, and with
money attached.

Fixed for both the order rows and the settlement rows. Four further reads on
that page took the newest 300 rows across all stores and *then* filtered by
store in the browser, so a store's rows could vanish entirely; the filter now
happens in the database and the read is paged. The newest-first order those tabs
are read in is restored after paging, which must read ascending to be correct.

### Assertions that could not fail

`if (select sum(...)) <> 9 then raise` passes when the key is missing: `sum` of
nothing is NULL, `NULL <> 9` is NULL, and PL/pgSQL takes the false branch. The
test passed on exactly the regression it guarded. Confirmed empirically, then
fixed with `coalesce(..., -1)` in `scripts/invoices/regression.sql` (two places),
`scripts/invoices/tests/extended.sql`,
`scripts/invoice-correction/tests/promotion-voucher-ownership.sql` (two places)
and `scripts/credit-policy/tests/requested-flow-audit.sql`.

### Issued once, paid once (344)

Both voucher issuance functions declare themselves idempotent and enforce it
with an unlocked `if exists … then continue`, with no unique index behind it.
Two settlements of the same invoice landing together both read "not there" and
both insert. There is now a partial unique index on the issuance source, and the
migration refuses to install it if duplicates already exist rather than merging
them, because which of a customer's duplicate units is real is not a decision a
migration may make.

Staff commission payouts had none of the protection affiliate commissions have:
`create_staff_commission_payout` read a month's total, inserted a payout and
then allocated, with no lock anywhere. Two concurrent calls both compute the same
total and both insert a payout; the second allocation then updates nothing,
leaving a payout row carrying a full month with no commission attached. A
statement-level advisory-lock trigger now mirrors the affiliate one, and the
function takes the lock before it reads.

---

## 6. Cleanup and refactoring

Deliberately incremental. No architecture was changed and nothing was renamed
for consistency.

- **Route-level code splitting.** All 47 page imports became lazy with one
  Suspense boundary. Staff previously waited for the whole application to open
  the dashboard. Measured in section 8.
- **The export pager was extracted** into a window-addressed helper, so page
  arithmetic on a clamped size cannot recur.
- **The shared escaper was widened** to cover quotes and `>`, because it is used
  inside HTML attributes as well as in text.
- **The TikTok page now uses the shared pager** rather than a hand-rolled limit,
  and filters in the database.

**Not removed, deliberately.** A confirmed-unused module list exists (a customer
picker superseded by the search select, a dead CSV writer, three unused phase-8
components, two superseded send helpers, 36 unused imports). None was deleted
in this pass: they are inert, and deleting them would add noise to a review that
already carries six security migrations. They are recorded in section 7 as a
follow-up. Nothing under `supabase/`, no audit code and no test fixture was
touched, per instruction — including `loadInvoiceList.ts`, which looks unused
and is the documented rollback path for pagination.

---

## 7. What is still open

### Confirmed by a deeper review, not fixed in this pass

These were confirmed against the installed definitions late in the task. Each is
real; none was fixed, because each needs either a business decision or a change
whose blast radius deserves its own pass.

1. **An exclusion constraint's predicate is inverted** (`supabase/53_purchasable_unlimited_therapy.sql:221`).
   `status in (...) = false` parses as `(status in (...)) = false` because `=`
   binds tighter than `and`. So scheduled entitlements — the case the comment
   says the constraint exists for — are *not* covered, while cancelled and
   refunded rows that still carry dates are. Not changed here because tightening
   an exclusion constraint can be rejected by existing production rows, and that
   needs a reconciliation pass first.
2. **Commission has no idempotency guard on earning.** 344 serializes the
   payout side, but re-paying or rebasing an invoice can earn a second set of
   commission rows, and nothing in the schema rejects them. The fix needs a
   decision about what uniquely identifies a commission.
3. **Wallet credit is silently unusable for rentals, special products and
   events**, because the purchase-category matrix has no entry for them.
4. **The list's Outstanding column is computed differently from
   `invoice_financial_position`** and the two disagree for cancelled and
   refunded invoices.
5. **Voucher stock is restored on cancellation but not on correction.**
6. **Invoice creation is the only mutation in the area with no request id**, so
   a retried creation can produce two invoices.
7. **The guided refund and cancel flow omits a field the server requires**,
   which dead-ends that workflow.

### Confirmed defects left for a decision

Each is a business rule. The instruction was not to change one by guessing.

1. **Credit-package claim deadlines come from an unrelated rule.** The deadline
   is derived from the therapy package rule with the lowest qualifying amount.
   Premium bundles were fixed (323) by using one year from payment. Whether that
   is also right for credit packages is yours to say.
2. **Entitlements predating migration 310 have no eligible-voucher list**, so
   any active reward voucher may be claimed against them. A reconciliation
   function suggests a list; nothing writes it back. Backfilling what a customer
   was sold cannot be inferred.
3. **A voucher claim prints as a zero-line S$0.00 "Tax Invoice."** What the
   customer's copy should say is a decision.
4. **The Exchanges screen offers an instalment and discards its terms.** The
   database supports the linkage; the screen sends an empty arrangement list.
5. **Voucher-level repeat rules are stored and never evaluated**, although the
   migration that introduced them says the stricter of the two rules should
   decide.
6. **A voucher claim has no request id**, so a retry after a lost response
   creates a second claim document. It cannot exceed the entitlement.
7. **Correcting a payment off the instalment method leaves stale terms** on the
   invoice; nothing calls the clear.

### Recommended, not done

- **Store-scope `invoice_items` and its siblings.** A staff member at one branch
  cannot read another branch's invoice header but can read its lines, prices,
  discounts and refunds. This is a narrowing of staff access, so it was not done
  silently. The shape to copy is the one `invoice_payments` already uses.
- **The remaining unpaginated reads.** The two that lose money or benefits were
  fixed. Still unpaged and worth a sweep: the therapy page sums the whole
  voucher-claims table in the browser (truncation makes claimed quantity
  *under*-count, so used vouchers reappear as available), the audit log page is
  already truncating at 500 and exports that, the referrer list has no range,
  and the invoice export's payment lookup slices 200 ids at a time against a
  1,000-row cap. Six hand-rolled pagers exist alongside the shared one.
- **A stale `create_transfer_request` overload** still exists with an enum
  parameter and never received two later fixes. Revoke it first so any surviving
  caller fails loudly, then drop it in a later release.
- **Missing foreign keys** on `commissions.payout_id` and
  `staff_commissions.payout_id`, added `not valid` so existing rows do not block
  the migration.
- **Fifteen redundant indexes**, each a leading-column prefix of a unique index
  on the same table. The win is write cost, not read speed.
- **`fulfil_from_warehouse` and `guarantee_invoice_stock` depend on trigger
  name ordering** for correctness, and nothing in the schema records that.
  Renaming either breaks stock accounting silently. A comment on the trigger is
  the cheapest guard.
- **`fulfil_from_warehouse` writes no stock movement row**, so the warehouse
  side of a fulfilment appears nowhere in the movement ledger.
- **Dead code removal** (the list in section 6) and turning on the two unused-code
  compiler checks that would have caught the 36 unused imports.

### Dependencies

Ten advisories, of which **one is reachable in production**: `xlsx` 0.18.5 is
used to parse user-uploaded spreadsheets, which is exactly the surface both its
advisories describe. There is no fix on npm — the publisher left, and 0.18.5 is
the last version there — so the fix is to install from their CDN:

```bash
npm install "xlsx@https://cdn.sheetjs.com/xlsx-0.20.3/xlsx-0.20.3.tgz"
```

That changes where a dependency comes from, which is a supply-chain decision, so
it is recommended rather than applied. The other production-tree advisories are
not reachable: the HTML renderer that pulls in the vulnerable sanitiser is never
called, and every route target in this application is a literal string, so the
router's open-redirect advisories have no path. A free patch is still worth
taking:

```bash
npm install react-router-dom@6.30.6
```

The five remaining advisories are build-tooling only and their only offered fix
is a three-major jump of the build tool. Deferred: there is no exploitable
exposure, the dev server is never deployed, and the cost of that upgrade is out
of proportion. The practical impact of deferring is that `npm audit` stays
noisy.

Three packages sit in the wrong place (`jsdom` and two type-only packages are
production dependencies but used only by tests), and one, `jszip`, is entirely
unused. No dependency was added or removed during this task and the lockfile is
untouched.

---

## 8. Measurements

Same machine, same production build command, same dataset.

| | Before | After |
| --- | --- | --- |
| Initial JavaScript | 2,760.47 kB | 422.05 kB |
| Initial JavaScript, gzipped | 757.50 kB | 120.83 kB |
| Chunks | 1 large entry | 99 |

The spreadsheet library, 424 kB on its own, is now in a chunk loaded only when
someone exports. Verified in the browser: the loading screen appears and the
page then renders, on desktop and at a phone viewport, with no console errors
from the application. The only failing request on any page is a Google Fonts
stylesheet, which this sandbox blocks; it is not an application fault.

The export defect was quantified rather than described: against a clamp of 200,
the old loop returned **400 of 1,000** matching invoices.

---

## 9. Tests

New, all of which fail against the code they guard — each was run against the
defect as well as against the fix:

| Test | What it proves |
| --- | --- |
| `scripts/permissions/tests/function-grants.sql` | Only the five signed-out endpoints are callable by anon; 355 functions remain callable by staff; named privileged internals are callable by neither; every function the database evaluates as the caller stays reachable |
| `scripts/permissions/tests/role-guards.sql` | Eight functions refuse a signed-in caller with no staff role, **for the role reason and not by accident**, and none of them refuses an Owner |
| `scripts/permissions/tests/rls-policies.sql` | An affiliate session reaches none of fourteen protected tables, cannot create its own Owner profile, cannot rewrite a customer; an Owner still reads and writes everything |
| `scripts/permissions/client-rpcs-are-granted.mjs` | Every function the application calls is callable by a signed-in user. Reads the call sites, not the allowlist |
| `scripts/voucher-claims/tests/negative-quantity.sql` | A claim carrying a quantity below one is refused whole, nothing moves, and an honest claim still settles |
| `scripts/voucher-claims/tests/issued-once.sql` | An invoice line issues each voucher once; a replay is refused and the customer keeps exactly what was bought |
| `scripts/permissions/tests/warehouse-stock-use.sql` | A staff member cannot write off warehouse stock, keeps their own store work, and a manager keeps the warehouse |
| `scripts/commissions/tests/partial-payout-totals.sql` | A part payment of S$30 marks S$150 of commission paid, and the report shows S$30 |
| `scripts/ui/tests/print-escaping.test.mjs` | Stored text cannot carry markup into a printed document, in an attribute or in text, and the survey QR print escapes both its values |
| `scripts/invoices/tests/invoice-export-paging.test.mjs` | The export returns every matching invoice exactly once, paged by the limit the database applied |
| `supabase/functions/send-invoice-email/tests/authorize.test.ts` | Who may email a document: no token, no user, no staff profile, a deactivated account, and a store the caller cannot see are all refused |

The role-guard test is worth a note. Its first version passed for the wrong
reason: one call was refused because of a bad argument, not because of the
guard. It now asserts the **reason** for each refusal, and separately that an
Owner is never refused by a role guard.

Registered under `npm run test:permissions`, `check:permissions`,
`test:voucher-claims`, `test:commission-totals`, `test:invoices` and
`test:invoice-email:edge`.

Full results are in section 11.

---

## 10. What the pre-flight caught

The migrations were **not** applied as written. Checking them against the live
database first changed them twice, and both changes mattered.

**Production is not what the repository describes.** It carries an entire
`ads` leads, appointments and calendar subsystem — including a live Google
Calendar integration, which is why CALENDAR_READINESS.md needed correcting — — 12 tables and 34 functions,
19 migrations applied over the two days before this work — that exists in no
local database and in no file in this repository. That is why production had
1,013 functions against 1,000 locally. All 34 are SECURITY INVOKER, so 339 keeps
them reachable by staff, and the only external caller in 24 hours of API logs is
Pabbly Connect authenticating with a secret key, which 339 grants. It was
unaffected. **It was also never tested against**, which is worth saying plainly.

**339 would have broken staff invitations.** Three functions an administrator
calls as themselves — `invite_user_begin`, `invite_user_prepare_resend` and
`invite_user_cancel` — were missing from the allowlist, so 339 would have
revoked them and Invite, Resend and Cancel would all have failed. The automated
pre-flight missed it because those calls are spelled `callerRpc('...')` inside a
shared edge-function module rather than `supabase.rpc('...')`, and the scan
matched only the latter. Its clean result was an artefact of the pattern, not
evidence of safety. Three independent reviewers found it; the check now covers
both spellings and distinguishes caller-side calls from service-role ones.

**339 would also have opened something.** `invite_user_accept` was *in* the
allowlist, but migrations 230 and 231 had deliberately revoked it from signed-in
users. It takes a user id and an email as arguments instead of reading
`auth.uid()`, so granting it back would have let any signed-in user accept
somebody else's invitation and activate their profile. It was removed from the
list. The migration as originally written would have introduced a privilege
escalation while fixing others.

339 also gained a `notify pgrst, 'reload schema'`, which it lacked: it changes
only grants, and without it the API could have kept answering from its cached
view of who may call what.

## 11. Applied to production

In this order, each verified before the next.

| Migration | Effect on production, measured |
| --- | --- |
| 339 | Functions callable without signing in: **637 → 5**, and exactly the five intended endpoints |
| 340 | Guards that let a role-less caller through: **8 → 0** |
| 341 | The voucher claim now refuses a quantity below one |
| 342 | Tables with no row-level security: **1 → 0** |
| 343 | The profiles INSERT policy is gone; **45 policies** now require a staff role |
| 344 | The issued-once index and the payout serialization trigger are in place, and the payout function takes the lock before it reads |
| 345 | A warehouse write-off now requires the warehouse permission |

Checked afterwards: all 243 functions the application calls are still callable
by a signed-in user; the three invitation functions are callable and
`invite_user_accept` is not; all 34 ads functions keep staff and service-role
access, the one exception being a trigger function, which PostgreSQL checks at
trigger-creation rather than at fire time; and in the API logs the only non-2xx
response is a 400 from the ads workstream's own iteration 24 minutes *before*
the first migration landed. Nothing has failed since.

## 11b. An incident this work caused, and how it was found

**339 broke transfer requests for about fifteen hours.** Creating one failed with
HTTP 300 from the moment 339 was applied at 14:39 on 2026-09-20 until 348 fixed
it at about 05:30 the next morning. Six attempts were refused at 02:26, all
before reaching the database.

`create_transfer_request` has two overloads with identical parameter names: the
current `(text, text, …)` form, and a stale `(text, location_type, …)` form left
behind because `create or replace function` with different parameter types
creates a new function rather than replacing one. PostgREST resolves an overload
by the set of parameter names and refuses outright when two match, answering
PGRST203.

339 caused it directly. Its allowlist matches on the function **name**, so
granting `create_transfer_request` granted **both** overloads and put a second
candidate in front of PostgREST where there had been one. The earlier database
review had flagged this exact overload as a risk and recommended revoking the
stale one; the recommendation was recorded in section 7 and not acted on, and
339 then made it live.

**How it was found matters.** Not by a test, not by a user report, and not by
the post-apply verification, which only checked that every function the client
calls is *callable* — never that exactly one candidate answers. It surfaced
because I happened to read the API error log while applying an unrelated
migration. Nobody told us.

**348** revokes the stale overload, which removes it from PostgREST's candidate
set, and marks it DEPRECATED. It is not dropped: this codebase patches function
bodies by matching installed text, and a hard drop could strand such a patch.

**339 was amended twice** so this cannot repeat. It now skips any function whose
comment begins DEPRECATED, and it carries a new self-check that fails if any
name the application calls has more than one callable overload with the same
parameter names. That check would have caught this at apply time.

**What this says about the rest of the work.** Every other verification in this
report asked "does this still work", never "is there now more than one way for
it to work". That is the class of mistake to look for if anything else surfaces.

## 12. Still to do

1. ~~Apply the migrations~~ — done, above.
   All seven are idempotent — each was applied twice to both local databases and the
   second run reports nothing to do. Each computes what it needs from the live
   catalogue, so none assumes production matches a local database.
2. **The pre-flight, for any future database:**
   ```bash
   ENERGIA_PERMISSIONS_DSN=<local dsn> node scripts/permissions/client-rpcs-are-granted.mjs
   ```
   It reads every `supabase.rpc(...)` call in the application and asks the
   database whether a signed-in user may execute each one. Run it again
   afterwards; it must still report every one callable. This is the check that
   would catch a function present in production but missing from the allowlist —
   the one risk this migration carries.
3. **Watch for these after 343**, which is the change most likely to surprise:
   any screen that reads a table directly and is used by someone without a
   profiles row. The application was driven through its main screens against the
   local stack with zero failed requests, but production may have screens or
   integrations this environment does not exercise.
4. ~~Deploy `send-invoice-email`~~ — deployed, then **removed at the owner's
   request**: this shop does not use Resend, and its auth email already goes
   through Pabbly. The function, its secrets and its source are gone; staff keep
   the share-sheet and link routes they were already using. The rest of this
   item is kept only as the record of what was needed had it stayed.

   ~~**Two things remain, and they are yours because I cannot see or set project secrets:**
   set `RESEND_API_KEY` and `INVOICE_FROM`, then send one invoice from a staff
   session to an address you control. Until those secrets are set the function
   returns 503 and the application falls back to the device share sheet, which
   is exactly what it does today, so nothing changes. **Once they are set the
   behaviour changes for staff**: the Email button stops opening their mail app
   and instead sends straight from the server to the address stored on the
   customer. A stale address on a customer record would send that invoice to
   whoever now owns it. `VITE_INVOICE_EMAIL=off` in the frontend disables the
   attempt instantly, and deleting the function restores today's behaviour.
   Optionally set `INVOICE_ALLOWED_ORIGINS` to restrict which sites may call it.~~

   **What actually happened.** The provider was never questioned when the
   finding was written: Resend came with the function, from commit `ffa6560`,
   long before this review. Auth email runs on Pabbly. Pushing the owner toward
   a Resend account to satisfy a function nobody had chosen was the wrong call,
   and the fix was to remove it rather than configure it. If server-side sending
   is wanted later, `git show fe33aa5:supabase/functions/send-invoice-email/authorize.ts`
   recovers the authorization logic and its nine tests, which are provider-agnostic.
5. **Confirm a TikTok settlement file of more than 1,000 rows** now confirms
   every row. The local data does not reach that size.
6. **Check the Excel export row count** against the list's own count for a
   filter matching more than 200 invoices.

### Rolling back

- **343** is the only one that could lock somebody out. To reverse a single
  policy: `alter policy "<name>" on public.<table> using (true);`. To reverse it
  wholesale, set the listed policies back to `true` and recreate the profiles
  INSERT policy — but note that doing so restores the escalation.
- **342**: `alter table public.<table> disable row level security;`
- **344**: `drop index public.customer_reward_vouchers_issued_once;` and
  `drop trigger staff_commission_serialization on public.staff_commissions;`
- **345** rewrites one function body; reversing it means re-running the
  migration that last defined `record_stock_use`.
- **339 and 340 and 341** rewrite grants and function bodies. Reversing them
  means re-running the migration that last defined each function. There is no
  one-line undo, which is why the pre-flight in step 2 matters.

### Historical reconciliation still needed

None of this was touched, per instruction. Each needs a query against
production:

- vouchers held with no recorded therapy rights (`therapy_vouchers_without_rights()`);
- voucher lines sold before migration 254, which issued nothing and were
  deliberately not backfilled (`invoice_untracked_voucher_lines()`);
- customers sharing a phone number (`customer_phone_collisions()` reports four
  or more; a stricter sweep is needed for appointments);
- active entitlements with no holiday country, which get no closure extension;
- duplicate voucher issuance rows, which **must** be checked before 344 will
  install its index — the migration refuses rather than merging them.

---

## 13. Test results

Every suite in `package.json` was run after the changes.

**43 of 45 pass. Two do not run in this environment, and neither ran before this
work either.**

| Suite | Result |
| --- | --- |
| `test:phase4` | **Not run.** Needs a Supabase URL and a service-role key; the only real one available is production's. |
| `test:commission-reinstall` | **Not run.** Needs its own disposable cluster, which is not provisioned and has no bootstrap wired to the script. |
| Everything else — 43 suites | Pass, including all permission, invoice, payment, correction, exchange, therapy, voucher, credit-policy, TikTok, Xero, survey, auth-email and concurrency suites. |

Two environments that were not running were brought up during this task so their
suites could actually run rather than be reported as skipped:

- the auth-email cluster, through its own bootstrap script, which let
  `test:auth-email:db`, `test:tiktok:db`, `test:therapy:db`, `test:users:db` and
  `test:therapy-services:db` run. All pass.
- a phone-policy cluster, following the manual steps in
  `docs/CUSTOMER_PHONE_DEPLOYMENT.md`, which let `test:customer-phones:db` run.
  It passes, including 57 SQL-versus-JavaScript parity cases, eight simultaneous
  inserts and duplicate concurrent survey submissions.

Type checking passes. The production build passes.

### One result worth reading twice

`test:permissions` failed after migration 344 was applied — and it was right to.
344 created two functions, and PostgreSQL had granted EXECUTE on both to
everyone, so they became callable without signing in. That is exactly the trap
339 documents and it caught its own author on the first attempt. 344 now grants
explicitly and carries its own assertion that it did. It is the clearest
evidence that the guard works, so it is recorded here rather than tidied away.

