/**
 * An instalment is a label on money that has arrived.
 *
 * It used to be a promise: the panel asked for a category (in-house or
 * provider-funded) and two amounts — what the arrangement covered, and what was
 * actually received today — and wrote an invoice_payment_arrangements row for
 * the balance still to collect. This shop is paid in full at the till; the
 * customer's instalment is with their own bank. Recording a promise to collect
 * money that had already arrived left invoices owing balances nobody was
 * waiting for.
 *
 * These assert the shape the panel and its validation now have. 326 carries the
 * database side.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const src = p => readFileSync(new URL(`../../../src/${p}`, import.meta.url), 'utf8');
const panel = src('components/invoices/InstalmentPortionFields.tsx');
const invoices = src('pages/InvoicesPage.tsx');
const exchanges = src('pages/ExchangesPage.tsx');
const editPaid = src('components/invoices/InstalmentFields.tsx');

const compiled = await build({
  stdin: { contents: "export * from './src/lib/invoices/business';", resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
});
const { instalmentText, validateInstalment } = await import(
  'data:text/javascript;base64,' + Buffer.from(compiled.outputFiles[0].text).toString('base64'));

test('the panel asks for one amount, not a covered sum and a deposit', () => {
  assert.doesNotMatch(panel, /Amount covered by this arrangement/,
    'the two-amount split is what made an instalment a promise');
  assert.doesNotMatch(panel, /Amount actually received now/);
  assert.equal((panel.match(/<label>Amount/g) ?? []).length, 1, 'exactly one amount field');
  assert.doesNotMatch(panel, /covered_amount/, 'covered_amount has no meaning once the money is in');
});

test('no screen offers a category any more', () => {
  // Offering it is what changed. The word may still appear in a comment, and
  // business.ts must keep understanding it for rows already saved with it.
  for (const [name, source] of [['panel', panel], ['edit-paid', editPaid]]) {
    assert.doesNotMatch(source, /value="provider_funded"|value='provider_funded'/,
      `${name} still offers provider-funded as a choice`);
    assert.doesNotMatch(source, /<label>Category|Category<select/, `${name} still asks for a category`);
  }
});

test('the amount is required, because it is money that has arrived', async () => {
  const { portionProblem } = await import(
    'data:text/javascript;base64,' + Buffer.from((await build({
      stdin: { contents: "export { portionProblem, emptyPortion } from './src/components/invoices/InstalmentPortionFields';",
               resolveDir: process.cwd(), loader: 'ts' },
      bundle: true, write: false, format: 'esm', jsx: 'automatic', loader: { '.css': 'empty' },
    })).outputFiles[0].text).toString('base64'));

  const ok = { method_id: 'm1', months: 12 };
  assert.equal(portionProblem(ok, 1080), null, 'a complete instalment with money should pass');
  assert.match(portionProblem(ok, 0) ?? '', /amount received/i, 'zero is no longer the normal case');
  assert.match(portionProblem({ method_id: '', months: 12 }, 1080) ?? '', /payment method/i);
  assert.match(portionProblem({ method_id: 'm1', months: 0 }, 1080) ?? '', /months/i);
});

test('neither payment screen writes an arrangement row', () => {
  assert.match(invoices, /arrangements: \[\]/, 'the invoice payment dialog must send no arrangements');
  assert.match(exchanges, /arrangements: \[\]/, 'the exchange dialog must send no arrangements');
  // Reading covered_amount off an arrangement that already exists is how the
  // exchange screen shows historical terms, and must keep working. What must
  // not come back is building one to send.
  for (const [name, source] of [['invoices', invoices], ['exchanges', exchanges]]) {
    assert.doesNotMatch(source, /covered_amount:/, `${name} still builds a coverage figure to send`);
  }
});

test('the terms are stamped on the invoice, so the list can still show them', () => {
  assert.match(invoices, /set_invoice_instalment_label/,
    'the duration has to be recorded somewhere for instalmentText to read');
  assert.equal(instalmentText({ instalment_category: 'in_house', instalment_months: 12, instalment_method_id: 'm1' },
    [{ id: 'm1', name: 'PayNow' }]), 'Instalment · 12 months · PayNow');
  assert.equal(instalmentText({}, []), '', 'an invoice with no instalment says nothing');
});

test('rows saved under the old model keep saying what they were saved as', () => {
  assert.match(instalmentText({ instalment_category: 'provider_funded', instalment_months: 6, instalment_method_id: 'm1' },
    [{ id: 'm1', name: 'Atome' }]), /^Provider-funded instalments · 6 months · Atome$/,
    'history must not be relabelled by a change to how new ones are recorded');
  assert.equal(validateInstalment({ instalment_category: 'provider_funded', instalment_method_id: 'm1', instalment_months: 6 }), null,
    'an existing provider-funded invoice must still validate');
});
