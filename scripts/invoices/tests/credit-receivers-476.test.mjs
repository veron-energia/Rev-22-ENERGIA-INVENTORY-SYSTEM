// 476: the Pay dialog (Record Payment) says which customer receives a
// Credit Package's or Premium Bundle's credit when that is not the invoice's
// customer (the Owner's answer E, 27 Oct 2026: "Dialogs name the
// receiver"). After a customer change that kept the benefits with whoever
// holds them ('keep'), what a package paid in part gives later (the credit
// each payment releases, and at full payment the rest of it, its Bonus and
// its vouchers) goes to the customer who holds its benefits; the invoice
// shows its new customer. And on a reopened invoice, the credit the payment
// that settles it reinstates goes to whoever holds the invoice's benefits
// (the Owner, 28 Oct 2026, for the Reopen dialog: "All of the credit"; and
// staff are told what the payment will give).
//
//   * The page reads invoice_credit_receivers for the open invoice while
//     Record Payment can show, and drops an answer read for another invoice
//     or for this invoice's earlier customer (as it does the wallet);
//     without 476 the read fails and nothing shows.
//   * Record Payment shows one note per receiver, naming the lines and the
//     customer, and the credit reinstated once paid in full; nothing when
//     everything goes to the invoice's customer. A package may have no Bonus
//     and no vouchers, so the note says "Any Bonus or vouchers".
// What the server works out is covered by
// scripts/invoices/tests/part-paid-change-same-as-paid-in-full-476.sql.
// Every name, id and amount is invented.
// Run: node --test scripts/invoices/tests/credit-receivers-476.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { creditReceiverNotes } from '../../../src/lib/invoices/creditReceivers.mjs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const inv = { id: 'inv-1', customer_id: 'cust-b' };
const line = (n, who, name) => ({ invoice_item_id: `it-${n}`, label: `Fixture Package ${n}`, customer_id: who, customer_name: name });

test('one line whose credit goes to the buyer: one note naming the line and the buyer', () => {
  const notes = creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [line(1, 'cust-a', 'Ada Fixture')] }, inv);
  assert.deepEqual(notes, ["Credit from Fixture Package 1 goes to Ada Fixture, who holds its benefits, not to this invoice's customer. Any Bonus or vouchers it gives once paid in full go to Ada Fixture too."]);
});

test('the note never says a package has a Bonus or vouchers: a plain package reads true', () => {
  const [note] = creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [line(1, 'cust-a', 'Ada Fixture')] }, inv);
  assert.doesNotMatch(note, /So do its Bonus/);
  assert.match(note, /Any Bonus or vouchers it gives once paid in full/);
});

test('two lines to the same buyer: one note naming both', () => {
  const notes = creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b',
    lines: [line(1, 'cust-a', 'Ada Fixture'), line(2, 'cust-a', 'Ada Fixture')] }, inv);
  assert.deepEqual(notes, ["Credit from Fixture Package 1 and Fixture Package 2 goes to Ada Fixture, who holds their benefits, not to this invoice's customer. Any Bonus or vouchers they give once paid in full go to Ada Fixture too."]);
});

test('lines to two receivers: a note each, in the order the server lists them', () => {
  const notes = creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b',
    lines: [line(1, 'cust-a', 'Ada Fixture'), line(2, 'cust-c', 'Cy Fixture'), line(3, 'cust-a', 'Ada Fixture')] }, inv);
  assert.equal(notes.length, 2);
  assert.match(notes[0], /^Credit from Fixture Package 1 and Fixture Package 3 goes to Ada Fixture,/);
  assert.match(notes[1], /^Credit from Fixture Package 2 goes to Cy Fixture,/);
});

test('nothing to say: no lines, a line for the invoice\'s own customer, no answer', () => {
  assert.deepEqual(creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [] }, inv), []);
  assert.deepEqual(creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [line(1, 'cust-b', 'Bo Fixture')] }, inv), []);
  assert.deepEqual(creditReceiverNotes(null, inv), []);
  assert.deepEqual(creditReceiverNotes(undefined, inv), []);
  assert.deepEqual(creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [line(1, 'cust-a', 'Ada')] }, null), []);
});

test('an answer read for another invoice, or for this invoice\'s earlier customer, is never shown', () => {
  const r = { invoice_id: 'inv-1', customer_id: 'cust-b', lines: [line(1, 'cust-a', 'Ada Fixture')] };
  assert.deepEqual(creditReceiverNotes(r, { id: 'inv-2', customer_id: 'cust-b' }), []);
  assert.deepEqual(creditReceiverNotes(r, { id: 'inv-1', customer_id: 'cust-z' }), []);
});

test('a line with no name or label still reads', () => {
  const notes = creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b',
    lines: [{ invoice_item_id: 'it-9', label: null, customer_id: 'cust-a', customer_name: null }] }, inv);
  assert.deepEqual(notes, ["Credit from this package goes to another customer, who holds its benefits, not to this invoice's customer. Any Bonus or vouchers it gives once paid in full go to another customer too."]);
});

test('a reopened invoice: the credit its settling payment reinstates, named with its receiver', () => {
  const notes = creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [],
    reinstated: [{ customer_id: 'cust-a', customer_name: 'Ada Fixture', amount: 100 }] }, inv);
  assert.deepEqual(notes, ["S$100.00 of credit reinstated once this invoice is paid in full goes to Ada Fixture, who holds the benefits, not to this invoice's customer."]);
});

test('the same receiver for a line and for credit reinstated: one note with both', () => {
  const notes = creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [line(1, 'cust-a', 'Ada Fixture')],
    reinstated: [{ customer_id: 'cust-a', customer_name: 'Ada Fixture', amount: '20.00' }, { customer_id: 'cust-c', customer_name: 'Cy Fixture', amount: '5.5' }] }, inv);
  assert.deepEqual(notes, [
    "Credit from Fixture Package 1 goes to Ada Fixture, who holds its benefits, not to this invoice's customer. Any Bonus or vouchers it gives once paid in full go to Ada Fixture too. So does the S$20.00 of credit reinstated once this invoice is paid in full.",
    "S$5.50 of credit reinstated once this invoice is paid in full goes to Cy Fixture, who holds the benefits, not to this invoice's customer."]);
});

test('credit reinstated for the invoice\'s own customer, or nothing, says nothing', () => {
  assert.deepEqual(creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [],
    reinstated: [{ customer_id: 'cust-b', customer_name: 'Bo Fixture', amount: 100 }] }, inv), []);
  assert.deepEqual(creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [],
    reinstated: [{ customer_id: 'cust-a', customer_name: 'Ada Fixture', amount: 0 }] }, inv), []);
  assert.deepEqual(creditReceiverNotes({ invoice_id: 'inv-1', customer_id: 'cust-b', lines: [] }, inv), []);
});

const page = read('src/pages/InvoicesPage.tsx');

test('the invoice page reads who receives the credit, for this invoice and its customer only, while Record Payment can show', () => {
  assert.match(page, /import \{ creditReceiverNotes, type CreditReceivers \} from '\.\.\/lib\/invoices\/creditReceivers\.mjs';/);
  assert.match(page, /setPayReceivers\(prev => \(prev\?\.invoice_id === inv\.id && prev\?\.customer_id === inv\.customer_id \? prev : null\)\)/,
    'an answer for this invoice\'s earlier customer is dropped at once, as the wallet is');
  assert.match(page, /if \(inv\.customer_id && !\['paid', 'cancelled', 'refunded', 'completed_foc'\]\.includes\(inv\.status\)\) \{\s*supabase\.rpc\('invoice_credit_receivers', \{ p_invoice_id: inv\.id \}\)[\s\S]{0,80}if \(!superseded\(\)\) setPayReceivers\(error \? null : /,
    'a slow answer for the invoice opened before is ignored, and an error (before 476) shows nothing');
});

test('Record Payment shows each note under the Wallet Credit note', () => {
  const start = page.indexOf('<label>Record Payment');
  const end = page.indexOf('Split Payment', start);
  assert.ok(start > 0 && end > start, 'the Record Payment section is where it was');
  const section = page.slice(start, end);
  assert.match(section, /Wallet Credit cannot be used to purchase a Credit Package or Premium Bundle\.[\s\S]*creditReceiverNotes\(payReceivers, detail\)\.map\(note => \(/);
  assert.match(section, /data-testid="credit-receiver-note"/);
});
