/**
 * 507 (the Owner, 17 Nov 2026): only an Owner or Manager makes a credit
 * package, premium bundle, voucher or therapy line free of charge. The
 * database refuses anyone else (supabase/507_...); the Invoices page does not
 * offer it to them: the New Invoice and Edit Invoice Discount choices leave
 * FOC off a voucher or therapy line, Save says why when a changed one is still
 * free, and the invoice view shows "Owner or Manager only" instead of Make FOC.
 *   node --test scripts/invoices/tests/foc-owner-manager-507.test.mjs
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `
    export { canGiveFoc, canGiveFocOn, FOC_OWNER_OR_MANAGER_KINDS } from './src/lib/invoices/business';
    export { discountChoicesFor } from './src/lib/invoices/lineDiscounts';`,
    resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm', platform: 'node',
});
const lib = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');

test('who may make which line FOC', () => {
  const kinds = ['credit_package', 'premium_bundle', 'voucher', 'therapy'];
  assert.deepEqual([...lib.FOC_OWNER_OR_MANAGER_KINDS], kinds);
  for (const kind of kinds) {
    assert.equal(lib.canGiveFocOn('owner', kind), true, `owner: ${kind}`);
    assert.equal(lib.canGiveFocOn('manager', kind), true, `manager: ${kind}`);
    assert.equal(lib.canGiveFocOn('staff', kind), false, `staff: ${kind}`);
    assert.equal(lib.canGiveFocOn('admin', kind), false, `admin: ${kind} (the database asks for an Owner or Manager)`);
    assert.equal(lib.canGiveFocOn('inventory_manager', kind), false);
  }
  for (const kind of ['product', 'promotion', 'special_product', 'rental', 'event_ticket']) {
    assert.equal(lib.canGiveFocOn('staff', kind), true, `staff still make a ${kind} line free`);
    assert.equal(lib.canGiveFocOn('inventory_manager', kind), false, 'an Inventory Manager gives no FOC, as before');
  }
  assert.equal(lib.canGiveFocOn(null, 'product'), false);
});

test('the Discount choices leave FOC off a voucher or therapy line for anyone else', () => {
  for (const kind of ['voucher', 'therapy']) {
    assert.deepEqual(lib.discountChoicesFor(kind, { notOwnerOrManager: true }), ['', 'manual', 'percentage'], kind);
    assert.deepEqual(lib.discountChoicesFor(kind, { notOwnerOrManager: false }), ['', 'foc', 'manual', 'percentage'], kind);
  }
  assert.deepEqual(lib.discountChoicesFor('product', { notOwnerOrManager: true, thirdParty: true }), ['', 'foc', 'manual', 'percentage'],
    'a product line keeps FOC for Staff');
  assert.deepEqual(lib.discountChoicesFor('promotion', { notOwnerOrManager: true }), ['', 'foc', 'manual', 'percentage']);
  assert.deepEqual(lib.discountChoicesFor('credit_package', { notOwnerOrManager: true }), []);
});

test('the page wires both in', () => {
  assert.match(page, /notOwnerOrManager: !isOwnerOrManager\(profile\?\.role\)/, 'the Discount choices know who is invoicing');
  assert.match(page, /l\.discount === 'foc' && !unchangedDraft\(l\) && !canGiveFocOn\(profile\?\.role, l\.kind\)/,
    'Save says why a changed free voucher or therapy line is refused');
  assert.match(page, /only an Owner or Manager can make a voucher or therapy line free of charge/);
  assert.match(page, /canGiveFocOn\(profile\?\.role, it\.line_kind\) \? \(/, 'Make FOC is shown by the line\'s kind');
  assert.match(page, /FOC on this line: Owner or Manager only/);
});
