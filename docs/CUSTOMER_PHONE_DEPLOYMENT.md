# Customer phone policy: deployment, review and rollback

This change is prepared and tested locally. No production database has been read or changed, no legacy cleanup has been applied, and no application has been deployed. A production customer export was not available, so actual pending-review counts are unknown. The example dry-run report uses synthetic fixtures only.

## What changes

- A phone has a global capacity of **three non-deleted customers**, including inactive customers. Soft-deleted customers and phone history consume no capacity.
- New/changed current phone values are validated and stored in E.164. A private atomic counter enforces capacity for table writes, RPCs, imports, phone changes and restoration. The counter is updated in an AFTER trigger, so `INSERT ... ON CONFLICT` cannot leak a reservation. Counter row updates serialize competing writers; serialization/deadlock failures should be retried as whole transactions.
- Existing legacy phone strings are **not rewritten by installation**. The migration snapshots original values and seeds counts from safely normalized numbers. Groups already over three remain intact; additional assignments fail while unrelated edits, deletion and corrective phone changes remain possible. Uncertain rows remain unchanged until reviewed.
- Surveys and referral registration match current normalized phone plus normalized full name (lowercase and collapsed whitespace). No fuzzy match, phone-only first match, history match, merge or automatic reassignment. Two exact matches require explicit staff resolution. Affiliate login additionally requires the existing verified-email safeguards; email alone no longer chooses a customer.
- Customer IDs, invoice owners, referral relationships and survey customer IDs are preserved. Existing customer-to-survey contact synchronization still works. Every actual phone change records the prior value in `customer_phone_history`.

## Country rules

The application and SQL use one generated snapshot of **libphonenumber-js 1.13.12 maximum metadata**, including all supported international numbering plans. `PhoneInput` still uses the existing library for country selection, parsing and formatting. The SQL validator uses the same general/type patterns and possible lengths. Do not edit the generated rules manually or independently update the library without regenerating and testing both sides.

- `+` and `00` introduce explicit international numbers, which must validate. Their country code is preserved. Malformed explicit numbers/extensions are rejected, not rewritten to Singapore.
- Country-coded `65...` and `60...` without a plus are accepted only when they validate.
- Without country evidence, an eight-digit Singapore local number must validate as SG and must not also validate as Malaysian. A valid Malaysian domestic number with its `0` trunk prefix can be recognized. A possible MY number without that evidence remains pending.
- For example, `91234567`, `6591234567` and `+65 9123 4567` normalize to `+6591234567`. `0123456789` normalizes to `+60123456789`. `93234567` is valid under both SG and MY interpretations and stays pending without confirmed phone country.
- The report accepts optional `phone_country` (`SG`/`MY`) **only** with `phone_country_source` equal to `customer_confirmed` or `verified_phone_country`. Nationality, citizenship and store location are never used to infer phone country. Other countries should be supplied in explicit international format.

## Dry run before any cleanup

1. Back up the database and export **all** customer rows, including inactive and deleted records. Do not use the paginated UI export or cast phones to numbers. From a read-only psql session, run `scripts/customer-phones/export.sql`; it writes `customer-phones.csv` on that client. Alternatively export a JSON array with `id`, `full_name`, `phone`, `deleted_at` and `is_active`.
2. Generate the report offline:

   ```sh
   node scripts/customer-phones/report.mjs customer-phones.csv /private/tmp/energia-phone-review
   ```

   This tool has no database connection and cannot change data. It produces `report.md`, `report.json`, `review.csv` and `proposed-plan.json`. Reports include IDs, names, original values, suggested numbers/countries, reasons, input hash and over-capacity groups. Store these files privately; they contain customer information. CSV export escapes spreadsheet formulas.
3. Review every pending row. Confirm country and the full number with the customer or reliable phone-specific evidence. Resolve groups over three without merging, deleting or moving customers arbitrarily. Use a confirmed alternative number through **Customers → Change phone** where appropriate. Uncertain records must be omitted from an approved plan.
4. Review the proposed plan as well: it is a proposal, not approval. It excludes uncertain rows and non-deleted records in over-capacity groups. Re-export after corrections, or remove stale entries. A plan is rejected if any customer phone changed since export.

## Install the policy and application

Test first against a staging copy with the same schema and permissions. Migrations through **160** must already be installed.

1. Back up the database and save the current application release. Record any custom customer-phone constraints, indexes or write triggers.
2. Generate a single-transaction bundle:

   ```sh
   node scripts/customer-phones/bundle-migration.mjs /private/tmp/energia-phone-policy.sql
   ```

   The bundle combines `161_customer_phone_policy.sql`, `162_customer_phone_identity_flows.sql` and `163_customer_phone_review_tools.sql`. Use this bundle for deployment so a failure in any part rolls back the entire installation. It validates function bodies, locks customer writes during initialization, snapshots every original phone, removes only recognized phone uniqueness, seeds capacity counters and replaces identification RPCs. **It does not apply the cleanup plan.** Unexpected phone unique indexes cause an atomic failure for manual investigation rather than a partly installed policy. Large databases need a maintenance window for the customer lock, validation scan and index rebuild.
3. In an approved maintenance window, stop imports/customer writes and apply the reviewed bundle through the project's SQL editor or administrative migration connection. Then deploy the matching application build and reopen writes. Do not continue applying obsolete migrations 32, 139, 155, 157 or 158 afterward; they replace these functions with the old behaviour.
4. Verify customer creation, a shared phone, source survey association and deleted-customer restoration. Owner/Manager can call `customer_phone_review_report()` or `customer_phone_collisions()` for current diagnostics. The mapping and counters are private; authenticated clients cannot alter them.

Deployment was deliberately **not** performed in this task.

## Apply only a reviewed cleanup plan later

After explicit approval of a concrete plan, convert it to SQL without executing it:

```sh
node scripts/customer-phones/plan-sql.mjs reviewed-plan.json /private/tmp/apply-reviewed-phone-plan.sql OWNER_PROFILE_UUID
```

The generated transaction sets the auditing identity to an actual Owner/Manager and calls `apply_customer_phone_review`. Run only from a trusted administrative SQL connection. The RPC itself checks the role, current original values, unique customer IDs, valid E.164 targets, reasons and capacity. A stale or invalid row rolls back **the entire call**. Original values are retained in the private mapping and phone history, with the applied phone, actor, time and reason. An unresolved overfull group cannot be silently normalized by a cleanup batch.

For large batches, review separate plans per batch and re-export between batches. Each call is atomic; separate calls are separate transactions. A batch may need ordering into corrective steps if capacity must be released first; do not bypass the trigger or change counters manually.

## Restoring and resolving ambiguous identities

- **Customers → Deleted Customers → Review restoration** shows the existing ID and phone. An Owner/Manager can restore on that number if capacity is available, or enter another valid number and a reason. Changing the phone and restoring happen together; an error leaves the customer deleted and allows correction in the same dialog. Old phones/invoices remain intact.
- **Health Surveys**: when a public submission reports multiple exact matches, staff verify the person, search the name/phone and explicitly open/start the survey for the correct customer ID. The public form deliberately accepts no customer-ID override. Do not merge the records to clear the error.
- **Affiliates → Pending Account Claims → Resolve**: review the entered name, phone and verified email, explicitly select the correct customer, and record a verification note. Existing claim-resolution permissions remain in force.
- Customer imports use normal table INSERTs (the database enforces normalization/capacity) or the appropriate checked signup flow. Do **not** upsert or resolve ownership by phone; it is no longer unique. An import that identifies existing people must use phone plus name and stop for multiple exact matches. There was no customer-import UI in this repository; the existing TikTok importer handles orders/stock and does not identify customers by phone.

## Rollback

Prefer rolling forward after shared numbers are in use. Reinstalling phone-only matching or raw uniqueness at that point is unsafe.

- A failed bundled install or cleanup call automatically rolls back that transaction.
- Before reopening writes, or if the guards permit, `scripts/customer-phones/rollback-policy.sql` restores the captured pre-policy functions and old uniqueness under a table lock. It refuses if raw duplicates (including deleted records), normalized shared numbers, or an incomplete function backup would make the old rules unsafe. It does not delete customers, rewrite phones, erase mapping/history or relink invoices. Deploy the old application only after a successful guarded database rollback.
- After real sharing or legacy conflicts exist, leave the database protections installed and fix forward. Do not delete/merge records just to satisfy rollback guards. A full backup restore is a separate operational recovery decision and would lose subsequent writes unless those are reconciled.
- To undo an approved phone correction, use a new reviewed corrective plan with the **current** phone as `original_phone` and a confirmed valid E.164 target. The normal capacity checks and audit trail still apply. Do not automatically restore ambiguous/non-E.164 legacy strings; the original remains in history/mapping for investigation.

## Tests

```sh
npm run test:customer-phones
npm run build
```

For SQL integration tests, use a disposable PostgreSQL database named `energia_phone_test` on a local `/tmp/energia-*` Unix socket. Never point this harness at production:

```sh
node scripts/customer-phones/tests/bootstrap.mjs /private/tmp/phone-test-bootstrap.sql
# Create an EMPTY energia_phone_test database first; set PGHOST, PGPORT and PGUSER.
PGDATABASE=energia_phone_test psql -X -v ON_ERROR_STOP=1 -f /private/tmp/phone-test-bootstrap.sql
node scripts/customer-phones/bundle-migration.mjs /private/tmp/phone-test-policy.sql
PGDATABASE=energia_phone_test psql -X -v ON_ERROR_STOP=1 -f /private/tmp/phone-test-policy.sql
PGDATABASE=energia_phone_test node scripts/customer-phones/tests/database.mjs
```

The bootstrap composes the relevant real repository table/RPC/trigger definitions, with local Supabase Auth plumbing. It is not a full production clone. Tests cover limits, inactive/deleted/history behaviour, release on phone changes, restore with replacement, normalization, review reporting, legacy conflicts, upserts, atomic failures, preserved associations, exact and ambiguous identity matching, SQL/JavaScript parity, eight concurrent inserts, duplicate concurrent surveys, and the phone-input country/invalid/paste/partial-entry interactions. Stage against the complete deployed schema/RLS before production rollout.

### Validation performed in this task

- Nine normalization/report/metadata/phone-input tests passed.
- 57 PostgreSQL/JavaScript normalization parity cases passed.
- Database integration checks passed with the existing name and customer-to-survey synchronization triggers, including invoice/referral ownership preservation, fourth referral rejection, pending-identity handling, audited cleanup and atomic stale-plan failure.
- Eight simultaneous inserts: three committed, five rejected; capacity counter matched the customer rows.
- Two simultaneous identical public surveys: one customer and one survey.
- The migration bundle installed and reran successfully with an existing four-customer normalized conflict.
- Rollback refused an unsafe shared-number state; the successful rollback path was tested inside a rolled-back local transaction.
- TypeScript/Vite production build passed. Vite reported a bundle larger than 500 kB; this is a size warning, not a build failure.

No production customer data was used for these checks.
