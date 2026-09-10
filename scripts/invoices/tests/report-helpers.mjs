// Exercise the actual helpers in ReportsPage without a browser or database.
// Run: node --test scripts/invoices/tests/report-helpers.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import ts from 'typescript';

const reportPath = new URL('../../../src/pages/ReportsPage.tsx', import.meta.url);
const sourceText = await readFile(reportPath, 'utf8');
const sourceFile = ts.createSourceFile(reportPath.pathname, sourceText, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
const names = ['fetchReportRows', 'buildLineSales'];
const declarations = names.map(name => {
  const declaration = sourceFile.statements.find(node => ts.isFunctionDeclaration(node) && node.name?.text === name);
  assert.ok(declaration, `ReportsPage must expose its local ${name} helper for this focused check`);
  return declaration.getText(sourceFile);
});
const compiled = ts.transpileModule(declarations.join('\n'), {
  compilerOptions: { target: ts.ScriptTarget.ES2022 },
}).outputText;
const { fetchReportRows, buildLineSales } = new Function(`${compiled}\nreturn { fetchReportRows, buildLineSales };`)();

const event = (event_id, amount, event_kind = 'receipt', invoice_id = 'invoice') => ({
  invoice_id, event_id, amount, event_kind, sales_date: '2026-02-01',
});
const items = [
  { id: 'A', invoice_id: 'invoice', line_total: 100, line_discount: 0 },
  { id: 'B', invoice_id: 'invoice', line_total: 100, line_discount: 0 },
];

test('pagination returns every row beyond 1,000 using stable ordering', async () => {
  const dataset = Array.from({ length: 1505 }, (_, n) => ({ id: String(1505 - n).padStart(4, '0') }));
  let calls = 0;
  const rows = await fetchReportRows(() => {
    const keys = [];
    return {
      order(key, options) { assert.equal(options.ascending, true); keys.push(key); return this; },
      async range(from, to) {
        calls++;
        assert.deepEqual(keys, ['id']);
        return { data: dataset.toSorted((a, b) => a.id.localeCompare(b.id)).slice(from, to + 1), error: null };
      },
    };
  });
  assert.equal(calls, 2);
  assert.equal(rows.length, 1505);
  assert.equal(new Set(rows.map(row => row.id)).size, 1505);
  assert.equal(rows[0].id, '0001');
  assert.equal(rows.at(-1).id, '1505');
});

test('ledger pagination accepts its composite stable order without assuming id', async () => {
  const keys = [];
  await fetchReportRows(() => ({
    order(key) { keys.push(key); return this; },
    async range() { return { data: [], error: null }; },
  }), ['sales_date', 'event_id']);
  assert.deepEqual(keys, ['sales_date', 'event_id']);
});

test('a later page failure rejects the report instead of returning a partial total', async () => {
  let calls = 0;
  await assert.rejects(fetchReportRows(() => ({
    order() { return this; },
    async range() {
      calls++;
      return calls === 1 ? { data: Array.from({ length: 1000 }, (_, id) => ({ id })) }
        : { error: { message: 'Second page unavailable' } };
    },
  })), /Second page unavailable/);
  assert.equal(calls, 2);
});

test('partial receipts use discounted line weights', () => {
  const result = buildLineSales([{ ...items[0], line_discount: 50 }, items[1]], [event('payment', 75)], []);
  assert.deepEqual([...result.byLine], [['A', 25], ['B', 50]]);
  assert.equal(result.unallocated.length, 0);
});

test('a product-specific refund does not reduce another product', () => {
  const refunds = [{ id: 'refund', invoice_id: 'invoice', outcome: { lines: [{ invoice_item_id: 'A', amount: 100 }] } }];
  const result = buildLineSales(items, [event('refund', -100, 'refund')], refunds);
  assert.equal(result.byLine.get('A'), -100);
  assert.equal(result.byLine.has('B'), false);
  assert.equal(result.unallocated.length, 0);
});

test('a mixed-source refund recovers lines stored on the wallet row and allocates only external sales', () => {
  const refunds = [
    { id: 'wallet', invoice_id: 'invoice', request_id: 'request', amount: 60, credit_returned: 60,
      outcome: { lines: [{ invoice_item_id: 'A', amount: 75 }, { invoice_item_id: 'B', amount: 25 }] } },
    { id: 'cash', invoice_id: 'invoice', request_id: 'request', amount: 40, credit_returned: 0, outcome: {} },
  ];
  const result = buildLineSales(items, [event('cash', -40, 'refund')], refunds);
  assert.deepEqual([...result.byLine], [['A', -30], ['B', -10]]);
  assert.equal(result.unallocated.length, 0);
});

test('invoice-level correction refunds remain explicitly unallocated', () => {
  const result = buildLineSales(items, [event('correction', -20, 'refund')], [
    { id: 'correction', invoice_id: 'invoice', outcome: { lines: [{ invoice_item_id: null, amount: 20 }] } },
  ]);
  assert.equal(result.byLine.size, 0);
  assert.equal(result.unallocated[0].amount, -20);
  assert.equal(result.unallocated[0].reason, 'Invoice-level correction refund');
});

test('missing refund evidence is never spread across unrelated lines', () => {
  const result = buildLineSales(items, [event('missing', -15, 'refund')], []);
  assert.equal(result.byLine.size, 0);
  assert.equal(result.unallocated[0].amount, -15);
  assert.equal(result.unallocated[0].reason, 'No recorded line allocation');
});

test('a line belonging to another invoice remains pending review', () => {
  const result = buildLineSales(items, [event('wrong', -8, 'refund', 'other-invoice')], [
    { id: 'wrong', invoice_id: 'other-invoice', outcome: { lines: [{ invoice_item_id: 'A', amount: 8 }] } },
  ]);
  assert.equal(result.byLine.size, 0);
  assert.equal(result.unallocated[0].amount, -8);
  assert.equal(result.unallocated[0].reason, 'Original line is unavailable');
});

test('cent allocations reconcile and reversal entries cancel the original line shares', () => {
  const thirds = ['A', 'B', 'C'].map(id => ({ id, invoice_id: 'invoice', line_total: 1, line_discount: 0 }));
  for (const amount of [0.01, -0.01, 100, -100]) {
    const result = buildLineSales(thirds, [event('rounding', amount)], []);
    const total = [...result.byLine.values()].reduce((sum, value) => sum + value, 0);
    assert.equal(Math.round(total * 100), Math.round(amount * 100));
  }
  const result = buildLineSales(items, [event('payment', 0.01), event('reversal', -0.01, 'correction_reversal')], []);
  assert.deepEqual([...result.byLine.values()], [0, 0]);
});
