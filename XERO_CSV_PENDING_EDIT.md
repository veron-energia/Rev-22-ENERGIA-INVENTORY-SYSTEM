# Xero export — the accountant's feedback, and the change that answers it

**Status: prepared, not applied.** `src/components/XeroExport.tsx` has uncommitted
changes from agent one (they are moving it from `created_at` to `business_date`).
The three edits below are held until that lands, so the two pieces of work do not
entangle in one file. Everything else is done and tested.

---

## What is actually wrong

The export already carries **every mandatory Xero field** — all nine starred
columns, one row per invoice line, discounts netted into the unit amount, an
invoice-level discount as its own negative line, and a rounding line so the
totals reconcile to the cent. `*Description` has a fallback on every branch and
`*ContactName` falls back to "Walk-in customer", so no mandatory cell is ever
blank.

So "description, quantity, account code and GST/tax code" were all present. Two
things were not:

**1. The file is `.xlsx`, and Xero's importer only takes `.csv`.**
This is the whole blocker. The upload is rejected on file type, before a single
column is read — which explains why the feedback described what Xero needs in
general terms rather than auditing what was in the file. Nobody got as far as the
columns.

**2. It emitted 18 of the template's 29 columns.**
Every missing one is optional — `POAddressLine2/3/4`, `PORegion`, `Total`,
`Discount`, the four `Tracking*` columns and `BrandingTheme`. Xero would accept
the file without them, but held against the template it reads as incomplete.
Emitting them empty costs nothing and makes it a column-for-column match.

Confirmed with you: Energia is **not GST-registered**, so `*TaxType` stays `NONE`
and `TaxAmount` stays `0`. Nothing about the tax handling changes.

---

## Done already (no conflict with agent one)

* `src/lib/xero/salesInvoiceTemplate.mjs` + `.d.mts` — the template's 29 columns
  in Xero's own order, CSV serialisation with proper escaping, and a pre-flight
  check for empty mandatory cells.
* `scripts/xero/tests/template.test.mjs` — 8 tests. The header row is asserted
  **verbatim against Xero's template file**, so if Xero changes it the test says
  so instead of the import failing quietly. Run with `npm run test:xero`.

---

## The three edits to `XeroExport.tsx`, once agent one has committed

### 1. Import the module

```ts
import {
  XERO_SALES_INVOICE_HEADERS, toXeroCsv, findMissingMandatory, xeroCsvFilename,
} from '../lib/xero/salesInvoiceTemplate.mjs';
```

`import * as XLSX from 'xlsx'` can go: nothing else in this file uses it.

### 2. Replace the local `HEADERS` constant

Delete the 18-entry `const HEADERS = [...]` (currently around line 179) and use
the shared list, so there is one definition of the template rather than two:

```ts
const HEADERS = XERO_SALES_INVOICE_HEADERS;
```

Nothing else changes. The row objects are keyed by column name, so the eleven
new columns simply come out empty.

### 3. Write CSV instead of a workbook

Replace the final block (currently around lines 295–300):

```ts
    const ws = XLSX.utils.json_to_sheet(body, { header: HEADERS });
    ws['!cols'] = HEADERS.map(h => ({ wch: Math.max(12, Math.min(h.length + 4, 28)) }));
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Xero Invoices');
    const scope = storeId ? (stores.find(s => s.id === storeId)?.name ?? 'store') : 'all-stores';
    XLSX.writeFile(wb, `xero-invoices-${scope}-${from}-to-${to}.xlsx`.replace(/\s+/g, '-'));
```

with:

```ts
    // Xero's importer takes a CSV. An .xlsx is refused on file type before any
    // column is read, which is what made the last file unusable.
    const missing = findMissingMandatory(body);
    if (missing.length > 0) {
      const first = missing[0];
      setErr(`Row ${first.row} has no ${first.field}. Xero rejects a row with an empty `
           + `mandatory field, so nothing was downloaded. ${missing.length} row(s) affected.`);
      setBusy(false);
      return;
    }

    const scope = storeId ? (stores.find(s => s.id === storeId)?.name ?? 'store') : 'all-stores';
    const blob = new Blob([toXeroCsv(body, HEADERS)], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = xeroCsvFilename(scope, from, to);
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
```

Check the surrounding `setBusy(false)` / `setNote(...)` handling still reads
correctly after the early return — the exact shape depends on how agent one
leaves the function.

---

## Two traps worth not falling into

**Do not populate `Discount` as well as netting it into `*UnitAmount`.** The
export already subtracts a line's discount from its unit amount. Filling the
`Discount` column too would make Xero apply it a second time, and every invoice
would import short. The column stays empty on purpose.

**Do not populate `Total`.** Xero computes the invoice total from the lines. A
`Total` that disagrees — by a cent, after the rounding line — is an argument you
do not need. Leave it to Xero.

---

## What to tell the accountant

The file they were sent was the right report in the wrong format. The next one
will be a `.csv` matching their template column for column, with one row per
invoice line, and `*TaxType` = `NONE` throughout because Energia is not
GST-registered — that is correct rather than missing, and worth saying so they do
not chase it.

One thing to confirm with them: **`*AccountCode` defaults to `200`.** It is
settable in the export dialog, but 200 is only a convention for sales revenue.
They should confirm the right code in Energia's Xero chart of accounts, and
whether different product types should post to different codes — at the moment
every line on every invoice uses the one code.
