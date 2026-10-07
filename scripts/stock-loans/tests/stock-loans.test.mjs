/**
 * Record use and stock lent out (400 + 401): src/lib/stock-loans/stockLoans.ts.
 *
 * Pins the Owner's rules of 6 Oct 2026 as the screens carry them: Record use
 * sends every line at once with a reason; a loan names a customer or a typed
 * name and a return date that is today or later, and asks for no more than is
 * on the shelf; "Out on loan" is what is still out on the open loans; overdue
 * is open and due before today (Singapore); taking back accounts for no more
 * than is out, sends returns to the chosen place (warehouses only for those
 * with the warehouse permission), splits damaged items into back-to-stock and
 * recorded-as-used, and says when the loan will close. Also that both stock
 * pages and the customer's profile use the shared pieces, and that the
 * Record use loop is gone. Every name and number is invented.
 *
 * Run: node --test scripts/stock-loans/tests/stock-loans.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/stock-loans/stockLoans';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
});
const sl = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');

const P1 = '11111111-1111-4111-8111-111111111111';
const P2 = '22222222-2222-4222-8222-222222222222';
const loan = (over = {}) => ({
  id: 'L1', loan_no: 'LOAN-000001', status: 'open', location_type: 'store', location_id: 'S1', location_name: 'Fixture Store',
  customer_id: 'C1', borrower: 'Jane Tan', borrower_phone: '+6591390401', is_affiliate: false, purpose: null,
  lent_at: '2026-10-06T02:00:00Z', lent_by_name: 'Fixture Staff', expected_return_date: '2026-10-10',
  overdue: false, days_overdue: 0, closed_at: null, outstanding: 3, events: [],
  lines: [
    { line_id: 'A', product_id: P1, product_name: 'Fixture Mat', sku: 'T-1', qty_out: 2, qty_returned: 0, qty_used: 0, qty_lost: 0, outstanding: 2 },
    { line_id: 'B', product_id: P2, product_name: 'Fixture Lamp', sku: 'T-2', qty_out: 1, qty_returned: 0, qty_used: 0, qty_lost: 0, outstanding: 1 },
  ],
  ...over,
});

test('product lines: the empty starting row is ignored; anything else is a product with a whole quantity, once', () => {
  assert.deepEqual(sl.checkLines([{ product_id: P1, quantity: 2 }, { product_id: '', quantity: 0 }]),
    { ok: true, value: [{ product_id: P1, quantity: 2 }] });
  assert.equal(sl.checkLines([{ product_id: '', quantity: 0 }]).error, 'Add at least one product with a quantity.');
  assert.equal(sl.checkLines([{ product_id: P1, quantity: 0 }]).error, 'Every product needs a whole quantity greater than zero.');
  assert.equal(sl.checkLines([{ product_id: P1, quantity: 1.5 }]).error, 'Every product needs a whole quantity greater than zero.');
  assert.equal(sl.checkLines([{ product_id: P1, quantity: -1 }]).error, 'Every product needs a whole quantity greater than zero.');
  assert.equal(sl.checkLines([{ product_id: '', quantity: 3 }]).error, 'Pick a product for every quantity.');
  assert.equal(sl.checkLines([{ product_id: P1, quantity: 1 }, { product_id: P1, quantity: 2 }]).error,
    'The same product is listed more than once.');
});

test('Record use: every line at once, with a reason; the note is optional', () => {
  assert.equal(sl.checkRecordUse([{ product_id: P1, quantity: 1 }], '   ', '').error, 'A reason is required.');
  assert.deepEqual(sl.checkRecordUse([{ product_id: P1, quantity: 1 }, { product_id: P2, quantity: 3 }], ' Demo ', '  '), {
    ok: true, value: { p_lines: [{ product_id: P1, quantity: 1 }, { product_id: P2, quantity: 3 }], p_reason: 'Demo', p_note: null },
  });
});

test('a loan: a customer or a typed name, a return date today or later, no more than is on the shelf', () => {
  const base = { lines: [{ product_id: P1, quantity: 2 }], borrowerMode: 'customer', customerId: 'C1', borrowerName: '',
    expectedReturn: '2026-10-08', purpose: ' Home trial ' };
  assert.deepEqual(sl.checkLend(base, '2026-10-06'), { ok: true, value: {
    p_lines: [{ product_id: P1, quantity: 2 }], p_expected_return_date: '2026-10-08',
    p_customer_id: 'C1', p_borrower_name: null, p_purpose: 'Home trial' } });
  assert.equal(sl.checkLend({ ...base, customerId: '' }, '2026-10-06').error, 'Pick the customer who is borrowing it.');
  const typed = sl.checkLend({ ...base, borrowerMode: 'name', customerId: 'C1', borrowerName: '  Roadshow   Fixture ' }, '2026-10-06');
  assert.equal(typed.value.p_borrower_name, 'Roadshow Fixture');
  assert.equal(typed.value.p_customer_id, null, 'a typed name never also sends the customer');
  assert.match(sl.checkLend({ ...base, borrowerMode: 'name', borrowerName: '  ' }, '2026-10-06').error, /^Type who is borrowing it/);
  assert.equal(sl.checkLend({ ...base, expectedReturn: '' }, '2026-10-06').error, 'An expected return date is required.');
  assert.equal(sl.checkLend({ ...base, expectedReturn: '2026-10-05' }, '2026-10-06').error, 'The expected return date cannot be in the past.');
  assert.equal(sl.checkLend({ ...base, expectedReturn: '2026-10-06' }, '2026-10-06').ok, true, 'due back today is allowed');
  assert.equal(sl.checkLend(base, '2026-10-06', { [P1]: 1 }, () => 'Fixture Mat').error,
    'Only 1 of "Fixture Mat" in stock here, so 2 cannot be lent.');
  assert.equal(sl.checkLend(base, '2026-10-06', { [P1]: 2 }).ok, true);
});

test('overdue is open and due before today; "Out on loan" is what is still out on open loans', () => {
  assert.equal(sl.isOverdue(loan(), '2026-10-10'), false, 'due today is not overdue');
  assert.equal(sl.isOverdue(loan(), '2026-10-11'), true);
  assert.equal(sl.daysOverdue(loan(), '2026-10-13'), 3);
  assert.equal(sl.isOverdue(loan({ status: 'closed' }), '2026-12-01'), false);
  const partly = loan({ lines: [{ ...loan().lines[0], qty_returned: 1 }, loan().lines[1]] });
  assert.deepEqual(sl.outByProduct([partly, loan({ status: 'closed' }), loan({ lines: [loan().lines[1]] })]), { [P1]: 1, [P2]: 2 });
  assert.equal(sl.outstanding({ qty_out: 5, qty_returned: 1, qty_used: 1, qty_lost: 1 }), 2);
});

test('taking back: returns go to the chosen place, damaged items to stock or as used, nothing beyond what is out', () => {
  const where = { type: 'store', id: 'S2' };
  const drafts = { A: { returned: 1, damagedToStock: 0, damagedUsed: 0, used: 0, lost: 0 } };
  const part = sl.takeBackEntries(loan(), drafts, where);
  assert.deepEqual(part, { ok: true, value: { closes: false, entries: [
    { line_id: 'A', outcome: 'returned', quantity: 1, condition: 'good', location_type: 'store', location_id: 'S2' }] } });
  const all = sl.takeBackEntries(loan(), {
    A: { returned: 0, damagedToStock: 1, damagedUsed: 1, used: 0, lost: 0 },
    B: { returned: 0, damagedToStock: 0, damagedUsed: 0, used: 0, lost: 1 } }, where);
  assert.equal(all.value.closes, true);
  assert.deepEqual(all.value.entries, [
    { line_id: 'A', outcome: 'returned', quantity: 1, condition: 'damaged', location_type: 'store', location_id: 'S2' },
    { line_id: 'A', outcome: 'used', quantity: 1, condition: 'damaged' },
    { line_id: 'B', outcome: 'lost', quantity: 1 }]);
  assert.equal(sl.takeBackEntries(loan(), { A: { returned: 2, damagedToStock: 0, damagedUsed: 0, used: 1, lost: 0 } }, where).error,
    'Only 2 of "Fixture Mat" are still out, but 3 are entered.');
  assert.equal(sl.takeBackEntries(loan(), drafts, null).error, 'Choose the store or warehouse it came back to.');
  assert.equal(sl.takeBackEntries(loan(), { B: { ...sl.blankTakeBack(), used: 1 } }, null).ok, true,
    'used and lost need no place');
  assert.equal(sl.takeBackEntries(loan(), {}, where).error,
    'Enter what came back, or what was used or lost, for at least one item.');
  assert.match(sl.takeBackEntries(loan(), { A: { ...sl.blankTakeBack(), returned: 0.5 } }, where).error, /whole number/);
  const every = sl.takeBackAll(loan());
  assert.deepEqual(every.A, { returned: 2, damagedToStock: 0, damagedUsed: 0, used: 0, lost: 0 });
  assert.equal(sl.takeBackEntries(loan(), every, where).value.closes, true);
});

test('places to return to: every store; warehouses only with the warehouse permission', () => {
  const st = [{ id: 'S1', name: 'Fixture Store' }], wh = [{ id: 'W1', name: 'Fixture Warehouse' }];
  assert.deepEqual(sl.returnPlaces(st, wh, false).map(p => p.value), ['store:S1']);
  assert.deepEqual(sl.returnPlaces(st, wh, true).map(p => p.label), ['Fixture Store (Store)', 'Fixture Warehouse (Warehouse)']);
});

test('what the screens say', () => {
  assert.equal(sl.eventLabel({ outcome: 'returned', condition: 'good' }), 'Returned');
  assert.equal(sl.eventLabel({ outcome: 'returned', condition: 'damaged' }), 'Returned damaged, back in stock');
  assert.equal(sl.eventLabel({ outcome: 'used', condition: 'damaged' }), 'Came back damaged, recorded as used');
  assert.equal(sl.eventLabel({ outcome: 'used', condition: null }), 'Used / given away');
  assert.equal(sl.eventLabel({ outcome: 'lost', condition: null }), 'Lost / damaged');
  assert.equal(sl.borrowerLabel(loan({ is_affiliate: true })), 'Jane Tan · Affiliate');
  assert.equal(sl.borrowerLabel(loan({ customer_id: null, borrower: 'Roadshow Fixture' })), 'Roadshow Fixture');
  assert.equal(sl.formatDay('2026-10-10'), '10 Oct 2026');
  assert.equal(sl.formatDay(null), '—');
  assert.equal(sl.sgToday(new Date('2026-10-06T16:30:00Z')), '2026-10-07', 'Singapore is 8 hours ahead');
  assert.match(sl.newRequestId(), /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.notEqual(sl.newRequestId(), sl.newRequestId());
  assert.equal(sl.saveFailure({ message: 'Only 1 of "Fixture Mat" in stock.', code: 'P0001' }, 'Press again.'),
    'Only 1 of "Fixture Mat" in stock. Nothing was saved.');
  assert.equal(sl.saveFailure({ message: 'TypeError: Failed to fetch', code: '' }, 'Press again.'),
    'TypeError: Failed to fetch It may or may not have been saved. Press again.');
});

test('a retry after a failed save: only an unanswered save may have saved; the server\'s "already saved" says itself what was kept', () => {
  assert.equal(sl.mayHaveSaved({ message: 'TypeError: Failed to fetch', code: '' }), true);
  assert.equal(sl.mayHaveSaved({ message: 'Gateway timeout' }), true, 'no code at all');
  assert.equal(sl.mayHaveSaved({ message: 'Only 1 in stock', code: 'P0001' }), false);
  const changed = 'This form was already saved as USE-000009 (Fixture Mat ×1), and has been changed since: nothing more was recorded. Close it, and record anything else as a new use.';
  assert.equal(sl.saveFailure({ message: changed, code: 'P0001' }, 'Press again.'), changed, 'no contradicting "Nothing was saved."');
  assert.equal(sl.usesSummary([{ use_no: 'USE-000009', product_id: P1, quantity: 1 }, { use_no: 'USE-000010', product_id: P2, quantity: 3 }],
    id => (id === P1 ? 'Fixture Mat' : 'Fixture Lamp')), 'USE-000009 (Fixture Mat ×1), USE-000010 (Fixture Lamp ×3)');
  assert.equal(sl.loanItemsSummary(loan()), 'Fixture Mat ×2, Fixture Lamp ×1');
  assert.equal(sl.loanItemsSummary(null), '');
});

test('the forms lock after a save that may have saved, so pressing again sends the same details', () => {
  for (const [file, button] of [['RecordUseModal', 'Record Use again'], ['LendModal', 'Lend again'], ['TakeBackModal', 'Save again']]) {
    const src = read(`src/components/stock-loans/${file}.tsx`);
    assert.match(src, /setLocked\(mayHaveSaved\(error\)\)/, `${file}: locks only when the save may have been made`);
    assert.match(src, new RegExp(`locked \\? '${button}'`), `${file}: the button says it is a retry`);
    // Every field: the self-closing ones up to "/>", and a <select> up to its first prop with an arrow.
    const inputs = [...(src.match(/<(input|textarea|SearchSelect|CustomerSearchSelect)\b[\s\S]*?\/>/g) ?? []),
                    ...(src.match(/<select\b[\s\S]*?=>/g) ?? [])];
    assert.ok(inputs.length >= 3, `${file}: has its fields`);
    for (const tag of inputs) assert.match(tag, /disabled=\{locked/, `${file}: ${tag.slice(0, 60)}… is locked too`);
  }
  // A locked Lend is not stopped by checks that change with time or stock.
  assert.match(read('src/components/stock-loans/LendModal.tsx'), /locked \? '' : today, locked \? undefined : available/);
});

test('the On loan list keeps only the latest answer, for the location on screen, and says whether the person may act', () => {
  const hook = read('src/components/stock-loans/useStockLoans.ts');
  assert.match(hook, /const ask = \+\+latest\.current;/);
  assert.match(hook, /if \(ask !== latest\.current\) return;/, 'an older answer is dropped');
  assert.match(hook, /loaded\.key === key \? loaded : null/, 'another location\'s loans are never shown');
  assert.match(hook, /canAct: typeof data\?\.can_act === 'boolean'/);
  const store = read('src/pages/StoreInventoryPage.tsx');
  assert.match(store, /canAct=\{loans\.canAct === true\}/, 'Store: Take back only where the database lets this person act');
  assert.doesNotMatch(store, /\bcanAct onTakeBack/, 'Store: Take back is no longer always offered');
  assert.match(store, /const actHere = loans\.canAct !== false;/);
  assert.equal((store.match(/disabled=\{!selectedStore \|\| !actHere\}/g) ?? []).length, 2, 'Store: Lend and Record Use follow it');
  const wh = read('src/pages/WarehouseInventoryPage.tsx');
  assert.match(wh, /canAct=\{canUseStock && loans\.canAct === true\}/);
  assert.match(read('supabase/401_record_use_and_stock_loans.sql'), /'can_act', public\.stock_loan_access\(p_location_type, p_location_id, true\)/);
});

test('the pages use one call per form, and the shared pieces', () => {
  const store = read('src/pages/StoreInventoryPage.tsx');
  const wh = read('src/pages/WarehouseInventoryPage.tsx');
  const useModal = read('src/components/stock-loans/RecordUseModal.tsx');
  assert.doesNotMatch(store, /rpc\('record_stock_use'/, 'the Store page no longer loops over record_stock_use');
  assert.match(useModal, /rpc\('record_stock_uses'/);
  assert.match(useModal, /p_request_id: requestId/);
  assert.match(read('src/components/stock-loans/LendModal.tsx'), /rpc\('lend_stock'[\s\S]*p_request_id: requestId/);
  assert.match(read('src/components/stock-loans/TakeBackModal.tsx'), /rpc\('return_stock_loan'[\s\S]*p_request_id: requestId/);
  for (const [name, page, type] of [['Store', store, 'store'], ['Warehouse', wh, 'warehouse']]) {
    assert.match(page, new RegExp(`<RecordUseModal locationType="${type}"`), `${name}: Record Use`);
    assert.match(page, new RegExp(`<LendModal locationType="${type}"`), `${name}: Lend`);
    assert.match(page, /<TakeBackModal /, `${name}: Take back`);
    assert.match(page, new RegExp(`useStockLoans\\('${type}'`), `${name}: On loan list`);
    assert.match(page, /Out on loan/, `${name}: Out on loan column`);
  }
  // The warehouse buttons follow the database's permission, and the access
  // check no longer returns before the page's hooks.
  assert.match(wh, /canUseStock && <button[^\n]*Lend/);
  assert.match(wh, /canUseStock && <button[^\n]*Record Use/);
  assert.match(wh, /const canUseStock = canManageWarehouseStock\(profile\?\.role\)/);
  assert.match(wh, /return <WarehouseInventoryView \/>;/);
  assert.match(read('src/pages/CustomersPage.tsx'), /<CustomerLoans customerId=\{profileFor\.id\} \/>/);
  assert.match(read('src/components/stock-loans/CustomerLoans.tsx'), /rpc\('customer_stock_loans'/);
  const types = read('src/types/index.ts');
  for (const t of ['loan_out', 'loan_return', 'exchange_return_in', 'exchange_replacement_out']) {
    assert.match(types, new RegExp(`'${t}'`), `StockMovementType has ${t}`);
  }
  assert.match(types, /loan_out: 'Lent out'/);
  assert.match(types, /loan_return: 'Loan returned'/);
  assert.match(read('supabase/401_record_use_and_stock_loans.sql'), /when ''loan_out'' then ''Lent out'' when ''loan_return'' then ''Loan returned''/);
});
