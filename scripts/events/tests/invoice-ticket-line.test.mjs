/**
 * An event ticket on the invoice form sends what 370 checks.
 *
 * The server (event_ticket_line_check, event_sync_ticket_line) takes a ticket
 * line as { kind: 'event_ticket', event_ticket_option_id, quantity,
 * event_days, attendees: [{ guest_id?, name, phone, customer_id }] } and keeps
 * a person's guest record by guest_id. These assertions pin the form to that
 * contract; scripts/events/tests/events.sql exercises the server side, and
 * vite.event-invoices-preview.config.mts renders the form against a stub.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const page = read('src/pages/InvoicesPage.tsx');

test('a ticket line is sent with its option, days and a name for every person', () => {
  const start = page.indexOf("      : l.kind === 'event_ticket'\n      ? { kind: 'event_ticket'");
  assert.ok(start > 0, 'validLines has an event_ticket branch');
  const branch = page.slice(start, start + 600);
  assert.match(branch, /event_ticket_option_id: l\.event_ticket_option_id/);
  assert.match(branch, /quantity: \(l\.attendees \?\? \[\]\)\.length/, 'the quantity is the number of people named');
  assert.match(branch, /event_days: \[\.\.\.\(l\.event_days \?\? \[\]\)\]\.sort\(\)/);
  assert.match(branch, /guest_id: a\.guest_id/, 'a saved person keeps their guest record');
  assert.match(branch, /name: a\.name\.trim\(\)/);
  assert.match(branch, /\.\.\.ovr\(l\), \.\.\.disc\(l\)/, 'a saved line sends its id and price back, and its one discount (FOC or another) travels as on any line');
});

test('the form refuses a ticket without its days or without every name, before the server does', () => {
  assert.match(page, /l\.kind === 'event_ticket' \? l\.event_ticket_option_id/, 'a chosen ticket counts as a line');
  assert.match(page, /choose \$\{o\.days_count\} day/);
  assert.match(page, /give the name of every person/);
});

test('a ticket is priced from the options on sale for the business date', () => {
  assert.match(page, /rpc\('event_ticket_options_for_sale',\s*\{ p_store_id: activeStore, p_business_date: cBusinessDate \}\)/);
  assert.match(page, /l\.kind === 'event_ticket' \? \(ticketOptions\.find\(o => o\.option_id === l\.event_ticket_option_id\)\?\.unit_price \?\? null\)/);
  // The totals must recompute when the options (and so the prices) change.
  // Every line's money, and so every total, comes from one memo (linePreview).
  const deps = page.match(/creditPkgs, creditBundles, ticketOptions\]\)/g) ?? [];
  assert.equal(deps.length, 1, 'the memoised line money depends on the ticket options');
  assert.match(page, /const linePreview: LineMoney\[\] = useMemo\(/, 'the totals are worked out from the memoised line money');
});

test('editing an invoice brings back each person on its tickets by guest id', () => {
  const start = page.indexOf("} else if (it.line_kind === 'event_ticket') {");
  assert.ok(start > 0, 'openEdit rebuilds ticket lines');
  const branch = page.slice(start, start + 900);
  assert.match(branch, /detailEvent\?\.lines/);
  assert.match(branch, /guest_id: g\.guest_id/);
  assert.match(page, /rpc\('invoice_event_guests', \{ p_invoice_id: inv\.id \}\)/, 'the detail loads the people with the lines');
});

test('a full day warns and never blocks the sale', () => {
  assert.match(page, /Over capacity: .*You can still sell the ticket\./);
  assert.doesNotMatch(page, /setCErr\([^)]*capacity/i, 'capacity never stops the save');
});

test('the invoice shows its event, and staff can mark or unmark it', () => {
  assert.match(page, /rpc\('invoice_events', \{ p_invoice_ids: wanted \}\)/);
  assert.match(page, /rpc\('set_invoice_event'/);
  assert.match(page, /rpc\('clear_invoice_event'/);
  assert.match(page, /event_ticket: 'Event ticket'/, 'printed and shared documents name the kind');
});
