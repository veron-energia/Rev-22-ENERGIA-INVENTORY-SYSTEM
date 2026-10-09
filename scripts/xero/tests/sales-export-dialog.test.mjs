// The invoice page's "Xero Export" dialog (411), mounted in jsdom: what it
// says, what it asks the server, what it records and what it downloads.
//
// The actual src/components/XeroExport.tsx is bundled with esbuild, as in
// scripts/tiktok/tests/xero-export.test.mjs. Only the Supabase client and the
// auth context are stubbed. Every name, number and amount below is invented.
//
// Run: node --test scripts/xero/tests/sales-export-dialog.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const singaporeToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore' }).format(new Date());

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://sales.invalid', pretendToBeVisual: true });
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
      export { XeroExportButton } from './src/components/XeroExport';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };
      export class ErrorBoundary extends React.Component {
        constructor(p) { super(p); this.state = { error: null }; }
        static getDerivedStateFromError(error) { return { error }; }
        componentDidCatch(error) { globalThis.__renderErrors.push(String(error && error.stack || error)); }
        render() { return this.state.error ? React.createElement('div', { id: 'crashed' }, String(this.state.error.message)) : this.props.children; }
      }`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$|^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => ({ profile: { id: "u-1", role: "owner" } }); export const AuthProvider = ({ children }) => children;' }));
  } }],
});
const { XeroExportButton, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const STORES = [{ id: 'st-a', name: 'North Store' }, { id: 'st-b', name: 'South Store' }];
const PREFIX = { receipt: 'PAY', correction_replacement: 'ADJ', correction_reversal: 'REV', refund: 'REF' };
const ev = (id, amount, document_date, extra = {}) => {
  const e = { event_kind: 'receipt', event_id: id, invoice_id: `i-${id}`, invoice_no: `INV-2026-${id}`, store_id: 'st-a',
    document_date, amount, recorded_at: `${document_date}T02:00:00Z`, customer_id: 'c-1', contact_name: 'Tan Mei',
    contact_email: 'mei@sig.invalid', contact_address: '1 Fixture Road', ...extra };
  e.document_number = PREFIX[e.event_kind] ? `${e.invoice_no}-${PREFIX[e.event_kind]}-${id}` : null;
  return e;
};
const noHistory = { recorded_since: null, exports: [], downloads: [], vanished: [], missed: [] };
// Recording began before the dates these tests export, and nothing of them was downloaded since.
const recorded = { ...noHistory, recorded_since: '2026-08-01T02:00:00Z' };
const dl = (e, extra = {}) => ({ event_kind: e.event_kind, event_id: e.event_id, document_number: e.document_number,
  document_date: e.document_date, amount: e.amount, exported_at: '2026-09-01T02:00:00Z', times: 1, ...extra });

function createBackend({ events = [], review = recorded } = {}) {
  const b = { calls: [], failures: new Map(), events, review, recordedAt: '2026-10-09T03:00:00Z', downloadsAtRecord: [] };
  class Query {
    constructor(name, args) { Object.assign(this, { name, args, orders: [], rangeV: null }); }
    order(col) { this.orders.push(col); return this; }
    range(a, z) { this.rangeV = [a, z]; return this; }
    async exec() {
      b.calls.push({ name: this.name, args: this.args });
      if (this.name === 'record_xero_sales_export') b.downloadsAtRecord.push(downloads.length);
      await Promise.resolve();
      const failure = b.failures.get(this.name);
      if (failure) {
        if (failure.once) b.failures.delete(this.name);
        return { data: null, error: { message: failure.message, ...(failure.code !== undefined ? { code: failure.code } : {}) } };
      }
      if (this.name === 'xero_sales_events') {
        const rows = b.events.filter(e => e.document_date >= this.args.p_from && e.document_date <= this.args.p_to
          && (!this.args.p_store_id || e.store_id === this.args.p_store_id));
        return { data: this.rangeV ? rows.slice(this.rangeV[0], this.rangeV[1] + 1) : rows, error: null };
      }
      if (this.name === 'xero_sales_export_review') return { data: b.review, error: null };
      if (this.name === 'record_xero_sales_export') {
        return { data: { export_id: 'x-new', exported_at: b.recordedAt, document_count: this.args.p_documents.length, net_total: 0 }, error: null };
      }
      return { data: null, error: { message: `unknown rpc ${this.name}` } };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { rpc: (name, args) => new Query(name, args), from: name => { throw new Error(`no table read expected (${name})`); } };
  return b;
}

// ── driving the dialog ─────────────────────────────────────────────────────
let root = null;
let backend = null;
let downloads = [];
URL.createObjectURL = blob => { downloads.push({ blob }); return 'blob:xero-sales'; };
URL.revokeObjectURL = () => {};
dom.window.HTMLAnchorElement.prototype.click = function () { const d = downloads.at(-1); if (d) d.name = this.download; };
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = setup ?? createBackend();
  globalThis.__backend = backend; globalThis.__renderErrors = [];
  downloads = [];
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(XeroExportButton, { stores: STORES }))));
  await tick();
}
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await tick(); };
const button = (label, scope = document) => [...scope.querySelectorAll('button')].find(x => x.textContent.trim().startsWith(label));
const footer = () => document.querySelector('.modal-footer');
const field = id => document.getElementById(id);
const callsOf = name => backend.calls.filter(c => c.name === name);
async function setValue(el, value, event = 'input') {
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => { Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value); el.dispatchEvent(new dom.window.Event(event, { bubbles: true })); });
  await tick();
}
async function open(setup, from = '2026-09-01', to = '2026-09-30') {
  await mount(setup);
  await click(button('Xero Export'));
  await setValue(field('xero-sales-from'), from);
  await setValue(field('xero-sales-to'), to);
}
const csvOf = async d => (await d.blob.text()).split('\r\n').filter(Boolean);
const alertText = () => document.querySelector('[role="alert"]')?.textContent ?? '';
const statusText = () => document.querySelector('[role="status"]')?.textContent ?? '';
const reviewText = () => document.querySelector('[data-testid="xero-sales-review"]')?.textContent ?? '';
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests ──────────────────────────────────────────────────────────────────
// Presence is asserted as a boolean, never by handing a jsdom node to assert:
// inspecting one for a failure message can exhaust memory.
test('the dialog states the rules: own dates, refunds as credit notes, and none of the old promises', async () => {
  await mount();
  await click(button('Xero Export'));
  const today = singaporeToday();
  assert.equal(field('xero-sales-from').value, `${today.slice(0, 7)}-01`);
  assert.equal(field('xero-sales-to').value, today);
  const text = document.querySelector('[data-testid="xero-sales"]').textContent;
  for (const said of ['Every payment is exported on the day it was received, even if the invoice is cancelled or refunded later.',
    'Refunds, including those made when an invoice is cancelled, are credit notes on the day the refund is recorded in the app',
    'a payment correction is dated the day it was made', 'So dates you have downloaded do not change afterwards.',
    'A cancellation alone returns no money', 'Payments with wallet credit are left out',
    'These totals can differ from the Sales report', 'Each download is recorded',
    'downloads made before this version were not recorded, so check Xero for those']) {
    assert.ok(text.includes(said), `says: ${said}`);
  }
  for (const wrong of ['Money still held on cancelled invoices remains included', 'invoice business date',
    'These rows match the Sales report', 'pending review', 'the day the money went back']) {
    assert.ok(!text.includes(wrong), `no longer says: ${wrong}`);
  }
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('with no download recorded yet: Xero is checked first, then it records the documents and downloads them', async () => {
  const events = [ev('0001', 100, '2026-09-02'), ev('0002', -40, '2026-09-05', { event_kind: 'refund', invoice_no: 'INV-2026-0001' }),
    ev('0003', 300, '2026-09-03', { event_kind: 'legacy_refund_left_out', invoice_no: 'INV-2026-0003' }),
    ev('0004', 50, '2026-09-04', { customer_id: null, contact_name: null, contact_email: null, contact_address: null })];
  await open(createBackend({ events, review: noHistory }));
  await click(button('Export CSV', footer()));
  // The old export may have put these dates in Xero with the same numbers.
  assert.equal(downloads.length, 0, 'nothing downloads before the person confirms');
  assert.equal(callsOf('record_xero_sales_export').length, 0);
  const text = reviewText();
  assert.ok(text.includes('Check Xero first: earlier downloads of these dates may not be recorded'), text);
  assert.ok(text.includes('No download is recorded yet: downloads made before this version of the app were not recorded.'), text);
  assert.ok(text.includes('importing them again would duplicate them'), text);
  assert.ok(!text.includes('Some of these dates were downloaded before'), text);
  assert.equal(field('xero-sales-checked-old').checked, false);
  assert.equal(button('Download', footer()).textContent.trim(), 'Download 3 documents');
  assert.equal(button('Download', footer()).disabled, true, 'not until Xero is checked');
  await click(field('xero-sales-checked-old'));
  assert.equal(button('Download', footer()).disabled, false);
  await click(button('Download', footer()));
  assert.equal(callsOf('xero_sales_events').length, 1, 'not read again to download');
  assert.deepEqual(callsOf('xero_sales_events').map(c => c.args), [{ p_from: '2026-09-01', p_to: '2026-09-30', p_store_id: null }]);
  assert.deepEqual(callsOf('xero_sales_export_review').map(c => c.args), [{ p_from: '2026-09-01', p_to: '2026-09-30', p_store_id: null }]);
  const [record] = callsOf('record_xero_sales_export');
  assert.ok(record, 'the download was recorded');
  assert.deepEqual(backend.downloadsAtRecord, [0], 'recorded before the file was handed over');
  assert.deepEqual(record.args.p_documents.map(d => d.event_id), ['0001', '0004', '0002'], 'the left-out payment is not recorded');
  assert.ok(record.args.p_documents.every(d => !('redownload' in d)), 'nothing is asked for again');
  assert.match(record.args.p_request_id, /^[0-9a-f-]{36}$/);
  assert.equal(downloads.length, 1);
  assert.equal(downloads[0].name, 'xero-invoices-all-stores-2026-09-01-to-2026-09-30.csv');
  const csv = await csvOf(downloads[0]);
  assert.equal(csv.length, 4, 'the header and three documents');
  assert.ok(csv[1].startsWith('Tan Mei,mei@sig.invalid,1 Fixture Road,,,,,,,,INV-2026-0001-PAY-0001,INV-2026-0001,02/09/2026,02/09/2026,'), csv[1]);
  assert.ok(csv[2].startsWith('Walk-in customer,'), csv[2]);
  assert.ok(csv[3].includes('INV-2026-0001-REF-0002,INV-2026-0001,05/09/2026,05/09/2026') && csv[3].includes(',-40.00,'), csv[3]);
  const note = statusText();
  assert.ok(note.includes('Downloaded 3 documents, including 1 credit note. Net: S$110.00.'), note);
  assert.ok(note.includes('Left out: 1 payment (S$300.00) on INV-2026-0003, refunded before refunds were recorded.'), note);
  assert.ok(note.includes('This is the first download the app has recorded; downloads made before this version were not recorded'), note);
  assert.ok(!document.querySelector('[data-testid="xero-sales-review"]'), 'the review closes once downloaded');
});

test('dates starting on or before the first recorded download are checked in Xero first; later dates are not', async () => {
  // First recorded download: 10 Sep 2026, 09:00 in Singapore.
  const review = { ...noHistory, recorded_since: '2026-09-10T01:00:00Z' };
  await open(createBackend({ events: [ev('0001', 100, '2026-09-12')], review }), '2026-09-10', '2026-09-30');
  await click(button('Export CSV', footer()));
  assert.ok(reviewText().includes('Downloads before 10 Sep 2026, 09:00 were not recorded, and these dates start on or before that day.'), reviewText());
  assert.equal(button('Download', footer()).disabled, true);
  assert.equal(downloads.length, 0);
  // A tick is for the dates it was given on: other dates ask again.
  await click(field('xero-sales-checked-old'));
  assert.equal(button('Download', footer()).disabled, false);
  await setValue(field('xero-sales-to'), '2026-09-29');
  await click(button('Export CSV', footer()));
  assert.equal(field('xero-sales-checked-old').checked, false);
  assert.equal(button('Download', footer()).disabled, true);
  assert.equal(downloads.length, 0);
  await open(createBackend({ events: [ev('0001', 100, '2026-09-12')], review }), '2026-09-11', '2026-09-30');
  await click(button('Export CSV', footer()));
  assert.ok(!document.querySelector('[data-testid="xero-sales-review"]'), 'dates after the first recorded download need no check');
  assert.equal(downloads.length, 1);
});

test('a store sends its id, and the file is named after it', async () => {
  await open(createBackend({ events: [ev('0001', 100, '2026-09-02'), ev('0009', 9, '2026-09-02', { store_id: 'st-b' })] }));
  await setValue(field('xero-sales-store'), 'st-b', 'change');
  await click(button('Export CSV', footer()));
  assert.ok(backend.calls.every(c => c.args.p_store_id === 'st-b'));
  assert.equal(downloads[0].name, 'xero-invoices-South-Store-2026-09-01-to-2026-09-30.csv');
  assert.deepEqual(callsOf('record_xero_sales_export')[0].args.p_documents.map(d => d.event_id), ['0009']);
});

test('when the record gets no answer nothing is downloaded, and a retry sends the same request and documents', async () => {
  const b = createBackend({ events: [ev('0001', 100, '2026-09-02')] });
  b.failures.set('record_xero_sales_export', { message: 'FetchError: Network request failed', code: '', once: true });
  await open(b);
  await click(button('Export CSV', footer()));
  assert.equal(downloads.length, 0);
  assert.ok(alertText().includes('Network request failed'), alertText());
  await click(button('Export CSV', footer()));
  assert.equal(downloads.length, 1);
  assert.equal(callsOf('xero_sales_events').length, 1,
    'the retry does not read the dates again: a record made but not answered would now count as downloaded');
  const ids = callsOf('record_xero_sales_export').map(c => c.args.p_request_id);
  assert.equal(ids.length, 2);
  assert.equal(ids[0], ids[1], 'the same download is recorded once, whether or not the first answer was lost');
  assert.deepEqual(callsOf('record_xero_sales_export')[1].args.p_documents, callsOf('record_xero_sales_export')[0].args.p_documents);
  // A later, different download gets a new request.
  backend.events = [ev('0001', 100, '2026-09-02'), ev('0002', 5, '2026-09-03')];
  await click(button('Export CSV', footer()));
  const third = callsOf('record_xero_sales_export')[2];
  assert.notEqual(third.args.p_request_id, ids[0]);
});

test('dates downloaded before: a review first, then a file without the documents already downloaded', async () => {
  const a = ev('0001', 100, '2026-09-02'), late = ev('0002', 70, '2026-09-03');
  const changedNow = ev('0005', 90, '2026-09-04');
  const missed = ev('0006', 20, '2026-08-25');
  const review = {
    recorded_since: '2026-08-01T02:00:00Z',
    exports: [{ id: 'x-1', exported_at: '2026-09-04T02:00:00Z', exported_by: 'Test Owner', from_date: '2026-09-01', to_date: '2026-09-04',
      store_id: null, covered_store_ids: ['st-a', 'st-b'], document_count: 2, net_total: 200 }],
    downloads: [dl(a), dl(changedNow, { amount: 100 })],
    vanished: [{ event_kind: 'receipt', event_id: '0007', document_number: 'INV-2026-0007-PAY-0007', document_date: '2026-09-01',
      amount: 15, exported_at: '2026-09-04T02:00:00Z', now_date: null, now_amount: null }],
    missed: [missed],
  };
  await open(createBackend({ events: [a, late, changedNow, ev('0008', 8, '2026-09-20')], review }));
  await click(button('Export CSV', footer()));
  assert.equal(downloads.length, 0, 'nothing downloads before the review is read');
  assert.equal(callsOf('record_xero_sales_export').length, 0);
  const text = reviewText();
  assert.ok(text.includes('Downloaded 4 Sep 2026, 10:00 by Test Owner: 1 Sep 2026 – 4 Sep 2026, all stores (2 documents of the stores chosen here).'), text);
  assert.ok(!document.querySelector('[data-testid="xero-sales-unrecorded"]'), 'recording began before these dates');
  assert.ok(text.includes('1 document is new in dates already downloaded (entered afterwards, so not in Xero yet) and is in this file: INV-2026-0002-PAY-0002 (3 Sep 2026, S$70.00)'), text);
  assert.ok(text.includes('1 downloaded document now has another date or amount and is left out of this file. Correct it in Xero by hand: INV-2026-0005-PAY-0005: S$100.00 on 4 Sep 2026 then, S$90.00 on 4 Sep 2026 now'), text);
  assert.ok(text.includes('1 downloaded document is no longer listed for these dates'), text);
  assert.ok(text.includes('INV-2026-0007-PAY-0007 (1 Sep 2026, S$15.00), gone'), text);
  assert.ok(text.includes('Leave out the 1 document already downloaded (S$100.00). Importing them again would duplicate them in Xero; untick only to download them again on purpose.'), text);
  assert.ok(text.includes('Add 1 document dated outside these dates, entered after its own dates were downloaded (not in Xero yet): INV-2026-0006-PAY-0006 (25 Aug 2026, S$20.00)'), text);
  assert.equal(field('xero-sales-skip').checked, true);
  assert.equal(field('xero-sales-missed').checked, true);
  // late + new + missed; not the downloaded one, not the changed one.
  assert.equal(button('Download', footer()).textContent.trim(), 'Download 3 documents');
  await click(field('xero-sales-skip'));
  assert.equal(button('Download', footer()).textContent.trim(), 'Download 4 documents');
  await click(field('xero-sales-missed'));
  assert.equal(button('Download', footer()).textContent.trim(), 'Download 3 documents');
  await click(field('xero-sales-skip'));
  await click(field('xero-sales-missed'));
  await click(button('Download', footer()));
  assert.equal(downloads.length, 1);
  assert.deepEqual(callsOf('xero_sales_events').length, 1, 'the review is not read again to download');
  const sent = callsOf('record_xero_sales_export')[0].args.p_documents.map(d => d.event_id);
  assert.deepEqual(sent, ['0006', '0002', '0008'], 'missed, late and new, by date; never the changed one');
  assert.ok(callsOf('record_xero_sales_export')[0].args.p_documents.every(d => !('redownload' in d)), 'none is a download again');
  const csv = await csvOf(downloads[0]);
  assert.deepEqual(csv.slice(1).map(l => l.split(',')[10]), ['INV-2026-0006-PAY-0006', 'INV-2026-0002-PAY-0002', 'INV-2026-0008-PAY-0008']);
  assert.ok(!document.querySelector('[data-testid="xero-sales-review"]'), 'the review closes once downloaded');
  assert.ok(statusText().startsWith('Downloaded 3 documents'), statusText());
  assert.ok(!statusText().includes('not recorded'), 'an earlier download of these dates is recorded');
});

test('everything already downloaded: nothing to download until asked for again', async () => {
  const a = ev('0001', 100, '2026-09-02');
  const review = { recorded_since: '2026-08-01T02:00:00Z', downloads: [dl(a)], vanished: [], missed: [],
    exports: [{ id: 'x-1', exported_at: '2026-09-04T02:00:00Z', exported_by: 'Test Owner', from_date: '2026-09-01', to_date: '2026-09-30',
      store_id: 'st-a', covered_store_ids: ['st-a'], document_count: 1, net_total: 100 }] };
  await open(createBackend({ events: [a], review }));
  await click(button('Export CSV', footer()));
  assert.ok(reviewText().includes('North Store'), 'the earlier download names its store');
  assert.ok(document.querySelector('[data-testid="xero-sales-nothing"]'));
  assert.equal(button('Download', footer()).disabled, true);
  await click(field('xero-sales-skip'));
  assert.equal(button('Download', footer()).disabled, false);
  await click(button('Download', footer()));
  assert.equal(downloads.length, 1);
  assert.deepEqual(callsOf('record_xero_sales_export')[0].args.p_documents.map(d => [d.event_id, d.redownload]), [['0001', true]],
    'a document asked for again is marked, so the server records it again');
});

test('a refused record drops the review: the next click reads the dates again', async () => {
  const a = ev('0001', 100, '2026-09-02'), b0 = ev('0002', 70, '2026-09-03');
  const review = { recorded_since: '2026-08-01T02:00:00Z', downloads: [dl(a)], vanished: [], missed: [],
    exports: [{ id: 'x-1', exported_at: '2026-09-04T02:00:00Z', exported_by: 'Test Owner', from_date: '2026-09-01', to_date: '2026-09-30',
      store_id: null, covered_store_ids: ['st-a'], document_count: 1, net_total: 100 }] };
  const back = createBackend({ events: [a, b0], review });
  back.failures.set('record_xero_sales_export', { once: true, code: 'P0001',
    message: '1 document(s) in this file were downloaded already (the latest: INV-2026-0002-PAY-0002, by Test Manager on 9 Oct 2026, 10:00). Nothing was recorded or downloaded. Export again to see what is new.' });
  await open(back);
  await click(button('Export CSV', footer()));
  await click(button('Download', footer()));
  assert.equal(downloads.length, 0);
  assert.ok(alertText().includes('were downloaded already'), alertText());
  assert.ok(!document.querySelector('[data-testid="xero-sales-review"]'), 'the stale review is gone');
  assert.equal(button('Export CSV', footer()).textContent.trim(), 'Export CSV');
  // Someone else downloaded 0002 meanwhile: read again, it is now already downloaded.
  back.review = { ...review, downloads: [dl(a), dl(b0)] };
  await click(button('Export CSV', footer()));
  assert.equal(callsOf('xero_sales_events').length, 2, 'read again');
  assert.ok(document.querySelector('[data-testid="xero-sales-nothing"]'), 'nothing new to download now');
  assert.equal(downloads.length, 0);
});

test('a review whose record gets no answer keeps the review, and the retry sends the same request', async () => {
  const a = ev('0001', 100, '2026-09-02'), b0 = ev('0002', 70, '2026-09-03');
  const review = { recorded_since: '2026-08-01T02:00:00Z', downloads: [dl(a)], vanished: [], missed: [],
    exports: [{ id: 'x-1', exported_at: '2026-09-04T02:00:00Z', exported_by: 'Test Owner', from_date: '2026-09-01', to_date: '2026-09-30',
      store_id: null, covered_store_ids: ['st-a'], document_count: 1, net_total: 100 }] };
  const back = createBackend({ events: [a, b0], review });
  back.failures.set('record_xero_sales_export', { once: true, message: '<html>502 Bad Gateway</html>' });
  await open(back);
  await click(button('Export CSV', footer()));
  await click(button('Download', footer()));
  assert.equal(downloads.length, 0);
  assert.ok(document.querySelector('[data-testid="xero-sales-review"]'), 'kept: the record may have been made');
  await click(button('Download', footer()));
  assert.equal(downloads.length, 1);
  const ids = callsOf('record_xero_sales_export').map(c => c.args.p_request_id);
  assert.equal(ids.length, 2);
  assert.equal(ids[0], ids[1]);
  assert.equal(callsOf('xero_sales_events').length, 1);
});

test('documents downloaded before their invoice moved to another store are shown as moved, and not downloaded again', async () => {
  const review = { recorded_since: '2026-08-01T02:00:00Z', downloads: [], missed: [],
    exports: [{ id: 'x-1', exported_at: '2026-09-04T02:00:00Z', exported_by: 'Test Owner', from_date: '2026-09-01', to_date: '2026-09-30',
      store_id: 'st-a', covered_store_ids: ['st-a'], document_count: 2, net_total: 150 }],
    vanished: [
      { event_kind: 'receipt', event_id: '0007', document_number: 'INV-2026-0007-PAY-0007', document_date: '2026-09-05', amount: 100,
        exported_at: '2026-09-04T02:00:00Z', now_date: '2026-09-05', now_amount: 100, moved: true, now_store_id: 'st-b' },
      { event_kind: 'receipt', event_id: '0008', document_number: 'INV-2026-0008-PAY-0008', document_date: '2026-09-06', amount: 50,
        exported_at: '2026-09-04T02:00:00Z', now_date: '2026-09-06', now_amount: 50, moved: true, now_store_id: null }] };
  await open(createBackend({ events: [ev('0001', 10, '2026-09-20')], review }));
  await setValue(field('xero-sales-store'), 'st-a', 'change');
  await click(button('Export CSV', footer()));
  const text = reviewText();
  assert.ok(text.includes('2 downloaded documents are now on invoices of another store (moved after the download). They are in Xero already'), text);
  assert.ok(text.includes('INV-2026-0007-PAY-0007 (5 Sep 2026, S$100.00), now South Store; INV-2026-0008-PAY-0008 (6 Sep 2026, S$50.00), now another store'), text);
  assert.ok(!document.querySelector('[data-testid="xero-sales-vanished"]'), 'moved is not "no longer listed"');
  assert.equal(button('Download', footer()).textContent.trim(), 'Download 1 document');
  await click(button('Download', footer()));
  assert.deepEqual(callsOf('record_xero_sales_export')[0].args.p_documents.map(d => d.event_id), ['0001']);
});

test('changing the dates after a review drops it, and the next export reads again', async () => {
  const a = ev('0001', 100, '2026-09-02');
  const review = { recorded_since: '2026-08-01T02:00:00Z', downloads: [dl(a)], vanished: [], missed: [],
    exports: [{ id: 'x-1', exported_at: '2026-09-04T02:00:00Z', exported_by: 'Test Owner', from_date: '2026-09-01', to_date: '2026-09-30',
      store_id: null, covered_store_ids: ['st-a'], document_count: 1, net_total: 100 }] };
  await open(createBackend({ events: [a], review }));
  await click(button('Export CSV', footer()));
  assert.ok(document.querySelector('[data-testid="xero-sales-review"]'));
  await setValue(field('xero-sales-to'), '2026-09-29');
  assert.ok(!document.querySelector('[data-testid="xero-sales-review"]'));
  assert.equal(button('Export CSV', footer()).textContent.trim(), 'Export CSV');
  // Going back to the same dates does not bring the old answer back.
  await setValue(field('xero-sales-to'), '2026-09-30');
  assert.ok(!document.querySelector('[data-testid="xero-sales-review"]'));
  assert.equal(button('Export CSV', footer()).textContent.trim(), 'Export CSV');
  await click(button('Export CSV', footer()));
  assert.equal(callsOf('xero_sales_events').length, 2);
  assert.ok(document.querySelector('[data-testid="xero-sales-review"]'), 'read again, reviewed again');
});

test('a refund with no payment source stops the export of those dates; nothing is recorded or downloaded', async () => {
  await open(createBackend({ events: [ev('0001', 100, '2026-09-02'),
    ev('0002', -40, '2026-09-06', { event_kind: 'refund_unsourced', invoice_no: 'INV-2026-0009' })] }));
  await click(button('Export CSV', footer()));
  assert.match(alertText(), /A refund on invoice INV-2026-0009 on 6 Sep 2026 was recorded without the payment it returned/);
  assert.equal(downloads.length, 0);
  assert.equal(callsOf('record_xero_sales_export').length, 0);
});

test('a document that cannot be exported is reported before any review is shown', async () => {
  const a = ev('0001', 100, '2026-09-02');
  const review = { recorded_since: '2026-08-01T02:00:00Z', downloads: [dl(a)], vanished: [], missed: [],
    exports: [{ id: 'x-1', exported_at: '2026-09-04T02:00:00Z', exported_by: 'Test Owner', from_date: '2026-09-01', to_date: '2026-09-30',
      store_id: null, covered_store_ids: ['st-a'], document_count: 1, net_total: 100 }] };
  await open(createBackend({ review, events: [a, ev('0002', -40, '2026-09-06', { event_kind: 'refund_unsourced' })] }));
  await click(button('Export CSV', footer()));
  assert.match(alertText(), /was recorded without the payment it returned/);
  assert.ok(!document.querySelector('[data-testid="xero-sales-review"]'));
  // ...even one already downloaded, which the file would leave out.
  await open(createBackend({ review, events: [{ ...a, document_number: 'INV-OTHER' }] }));
  await click(button('Export CSV', footer()));
  assert.match(alertText(), /The Xero number for invoice INV-2026-0001 is not the expected one/);
  assert.ok(!document.querySelector('[data-testid="xero-sales-review"]'));
  assert.equal(downloads.length, 0);
});

test('only left-out payments between the dates: nothing downloads, and it says why', async () => {
  await open(createBackend({ events: [ev('0003', 300, '2026-09-03', { event_kind: 'legacy_refund_left_out' })] }));
  await click(button('Export CSV', footer()));
  assert.match(alertText(), /No payments, corrections or refunds to export between these dates\. Left out: 1 payment \(S\$300\.00\) on INV-2026-0003/);
  assert.equal(downloads.length, 0);
  assert.equal(callsOf('record_xero_sales_export').length, 0);
});

test('a double click records and downloads once', async () => {
  await open(createBackend({ events: [ev('0001', 100, '2026-09-02')] }));
  const exportButton = button('Export CSV', footer());
  await act(async () => {
    exportButton.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
    exportButton.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  });
  await tick();
  assert.equal(callsOf('record_xero_sales_export').length, 1);
  assert.equal(downloads.length, 1);
});

test('the dates and the account details are checked before anything is asked', async () => {
  await open(createBackend());
  await setValue(field('xero-sales-code'), '');
  await click(button('Export CSV', footer()));
  assert.ok(alertText().includes('Enter the Xero account code and tax rate.'));
  await setValue(field('xero-sales-code'), '1011');
  await setValue(field('xero-sales-from'), '2026-09-30');
  await setValue(field('xero-sales-to'), '2026-09-01');
  await click(button('Export CSV', footer()));
  assert.ok(alertText().includes('The end date cannot be before the start date.'));
  assert.equal(backend.calls.length, 0);
});
