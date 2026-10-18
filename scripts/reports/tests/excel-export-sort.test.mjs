// Sorting the shared Excel export by a column (427, REPORTS-M2).
//
// The Customers Special Export writes Date of Birth and Created as day-first
// text ("12/08/2026"); sorting by them read the text as month first (8 Dec), so
// the sheet came out scrambled. src/lib/excelSort.mjs reads a day-first date
// day first, and a column may give the raw value to sort by (sortValue). The
// component, src/components/ExcelExport.tsx, is bundled and mounted in jsdom
// with xlsx stubbed, to check it sorts with them. Every value is invented.
//
// Run: node --test scripts/reports/tests/excel-export-sort.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import { sortExportRows, dayFirstTime, compareExportValues } from '../../../src/lib/excelSort.mjs';

// Six dates of birth where reading the text month first scrambles the order.
const BIRTHS = ['12/08/1990', '03/11/1985', '25/01/1990', '01/12/1985', '07/05/2001', '30/06/1978'];

test('day-first dates sort as dates, both ways, blanks last', () => {
  const rows = [...BIRTHS, '', null].map((dob, i) => ({ i, dob }));
  assert.deepEqual(sortExportRows(rows, r => r.dob, 'asc').map(r => r.dob),
    ['30/06/1978', '03/11/1985', '01/12/1985', '25/01/1990', '12/08/1990', '07/05/2001', '', null]);
  assert.deepEqual(sortExportRows(rows, r => r.dob, 'desc').map(r => r.dob),
    ['07/05/2001', '12/08/1990', '25/01/1990', '01/12/1985', '03/11/1985', '30/06/1978', '', null]);
});

test('a day-first date is read day first, with a time too; an impossible one is not a date', () => {
  assert.equal(dayFirstTime('12/08/2026'), Date.UTC(2026, 7, 12));
  assert.equal(dayFirstTime('12/08/2026, 14:05:09'), Date.UTC(2026, 7, 12, 14, 5, 9));
  assert.equal(dayFirstTime('31/02/2026'), null);
  assert.equal(dayFirstTime('2026-08-12'), null);
});

test('numbers sort as numbers, text by its words and numbers, ISO dates as dates; equal rows keep their order', () => {
  assert.deepEqual(sortExportRows([{ v: '10' }, { v: '9' }, { v: '1,200' }, { v: -3 }], r => r.v).map(r => r.v), [-3, '9', '10', '1,200']);
  assert.deepEqual(sortExportRows([{ v: 'Item 10' }, { v: 'item 2' }, { v: 'Item 1' }], r => r.v).map(r => r.v), ['Item 1', 'item 2', 'Item 10']);
  assert.deepEqual(sortExportRows([{ v: '2026-08-12' }, { v: '2025-12-01' }], r => r.v).map(r => r.v), ['2025-12-01', '2026-08-12']);
  const same = [{ v: 'b', n: 1 }, { v: 'a', n: 2 }, { v: 'b', n: 3 }];
  assert.deepEqual(sortExportRows(same, r => r.v).map(r => r.n), [2, 1, 3]);
  assert.deepEqual(sortExportRows(same, r => r.v, 'desc').map(r => r.n), [1, 3, 2]);
  assert.ok(compareExportValues('12/08/2026', '08/12/2026') < 0, '12 Aug before 8 Dec');
});

// ── the component ──────────────────────────────────────────────────────────
const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://export.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'Element', 'Node', 'Event',
  'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.MessageChannel = class {
  constructor() {
    const port = () => ({ onmessage: null, close() {} });
    this.port1 = port(); this.port2 = port();
    this.port1.postMessage = data => setImmediate(() => this.port2.onmessage?.({ data }));
    this.port2.postMessage = data => setImmediate(() => this.port1.onmessage?.({ data }));
  }
};
const consoleError = console.error;
console.error = (...a) => { if (!String(a[0]).includes('not wrapped in act')) consoleError(...a); };
const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { ExcelExportButton } from './src/components/ExcelExport';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    // The shared ui module reaches the Supabase client; nothing here calls it.
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = new Proxy({}, { get() { throw new Error("no backend in this test"); } }); export const fetchCustomersByIds = async () => []; export const mergeCustomers = (a) => a;' }));
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const utils = {
        json_to_sheet: (body, opts) => ({ body, header: opts && opts.header }),
        book_new: () => ({ sheets: [] }),
        book_append_sheet: (wb, ws, name) => { wb.sheets.push({ ws, name }); },
      };
      export const writeFile = (wb, filename) => { globalThis.__exports.push({ filename, sheet: wb.sheets[0] }); };` }));
  } }],
});
const { ExcelExportButton, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

let root = null;
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); };
const button = label => [...document.querySelectorAll('button')].find(b => b.textContent.trim().startsWith(label));
async function choose(select, value) {
  const setter = Object.getOwnPropertyDescriptor(dom.window.HTMLSelectElement.prototype, 'value').set;
  await act(async () => { setter.call(select, value); select.dispatchEvent(new dom.window.Event('change', { bubbles: true })); });
}
async function exportSortedBy(columns, rows, header, dir = 'asc') {
  globalThis.__exports = [];
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ExcelExportButton, { rows, columns, filename: 'fixture', selectableColumns: true, label: 'Special Export' })));
  await click(button('Special Export'));
  const [sortBy, sortDir] = document.querySelectorAll('select');
  await choose(sortBy, header);
  await choose(sortDir, dir);
  await click([...document.querySelectorAll('button')].find(b => b.textContent.trim().startsWith('Export ')));
  await act(async () => { await new Promise(r => setTimeout(r, 0)); });
  return globalThis.__exports.at(-1);
}
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

const people = BIRTHS.map((dob, i) => ({ name: `Customer ${i + 1}`, dob: dob.split('/').reverse().join('-'),
  created: `2026-0${(i % 9) + 1}-1${i}T10:00:00Z` }));
const asText = iso => iso ? iso.slice(0, 10).split('-').reverse().join('/') : '';

test('the export sorts a day-first date column as dates', async () => {
  const exported = await exportSortedBy([
    { header: 'Name', value: r => r.name },
    { header: 'Date of Birth', value: r => asText(r.dob) },
  ], people, 'Date of Birth');
  assert.deepEqual(exported.sheet.ws.body.map(r => r['Date of Birth']),
    ['30/06/1978', '03/11/1985', '01/12/1985', '25/01/1990', '12/08/1990', '07/05/2001']);
});

test('a column with sortValue is sorted by it, not by its text', async () => {
  const exported = await exportSortedBy([
    { header: 'Name', value: r => r.name },
    // Shown as a label, sorted by the raw date behind it.
    { header: 'Born', value: r => `Born ${asText(r.dob)}`, sortValue: r => r.dob },
  ], people, 'Born', 'desc');
  assert.deepEqual(exported.sheet.ws.body.map(r => r.Name),
    ['Customer 5', 'Customer 1', 'Customer 3', 'Customer 4', 'Customer 2', 'Customer 6']);
});
