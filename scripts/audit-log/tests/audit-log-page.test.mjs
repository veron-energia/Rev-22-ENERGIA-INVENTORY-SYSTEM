// The Audit Log page reads the log a page at a time on the server (428,
// REPORTS-10): every entry can be reached, the filters and search run there,
// times are Singapore time, a failed read is shown as a failure rather than
// "No audit entries" (REPORTS-5), and the export holds every entry of the
// search with When, Action, Table, Module, By, Role, Reason, Record and
// Details.
//
// The actual src/pages/AuditLogPage.tsx is bundled with esbuild and mounted in
// jsdom. Only the Supabase client, the auth context and xlsx are stubbed: the
// client by a small stand-in for audit_log_page, xlsx so an export is
// captured instead of written. Every name and id below is invented.
//
// Run: node --test scripts/audit-log/tests/audit-log-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

// The page must show Singapore time on any computer, so the tests run in UTC:
// on a computer already set to Singapore time a page that used the device's
// zone would pass. Set before the page is bundled or any date is formatted.
process.env.TZ = 'UTC';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://audit.invalid', pretendToBeVisual: true });
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
      export { default as AuditLogPage, auditDetailsText, sgtStamp } from './src/pages/AuditLogPage';
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
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const utils = {
        json_to_sheet: (body, opts) => ({ body, header: opts && opts.header }),
        book_new: () => ({ sheets: [] }),
        book_append_sheet: (wb, ws, name) => { wb.sheets.push({ ws, name }); },
      };
      export const writeFile = (wb, filename) => { globalThis.__exports.push({ filename, sheet: wb.sheets[0] }); };` }));
  } }],
});
const { AuditLogPage, auditDetailsText, sgtStamp, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const OWNER = '00000000-0000-4000-8000-0000000000a1';
const STAFF = '00000000-0000-4000-8000-0000000000a2';
const INVOICE = '00000000-0000-4000-8000-0000000000b1';
const NOW = '2026-10-09T08:00:00.000Z';
// 2,450 entries, one every 10 minutes back from 8 Oct 16:40 UTC, and three
// that show what the page must show.
function makeEntries() {
  const out = [];
  for (let i = 0; i < 2450; i++) {
    out.push({ id: `e-${String(i).padStart(5, '0')}`, created_at: new Date(Date.parse('2026-10-08T16:40:00Z') - i * 600000).toISOString(),
      action: 'stock_in', table_name: 'warehouse_inventory', module: null, module_recorded: false, changed_by: OWNER, actor_name: 'Fixture Owner',
      actor_role: 'owner', reason: null, record_id: null, record_label: null, old_data: null, new_data: { qty: i } });
  }
  out[0] = { id: 'e-special-1', created_at: '2026-10-08T16:50:00Z', action: 'invoice_paid', table_name: 'invoices', module: 'invoices',
    module_recorded: false, changed_by: null, actor_name: 'System', actor_role: null, reason: null, record_id: INVOICE,
    record_label: 'INV-FX-0001', old_data: { status: 'unpaid' }, new_data: { status: 'paid' } };
  out[1] = { id: 'e-special-2', created_at: '2026-10-08T16:30:00Z', action: 'transfer_requested_by_staff', table_name: 'transfer_requests',
    module: 'transfers', module_recorded: true, changed_by: STAFF, actor_name: 'Fixture Staff', actor_role: 'inventory_manager',
    reason: 'Shelf restock', record_id: '00000000-0000-4000-8000-0000000000c1', record_label: null, old_data: null, new_data: { lines: 2 } };
  return out;
}

// ── fake backend: a stand-in for audit_log_page ────────────────────────────
function createBackend() {
  const b = { calls: [], fail: null, held: null, entries: makeEntries() };
  b.hold = () => { let release; b.held = new Promise(r => { release = r; }); return () => release(); };
  const page = a => {
    const asOf = a.p_as_of ?? NOW;
    let rows = b.entries.filter(e => e.created_at <= asOf);
    const sgDay = iso => new Date(Date.parse(iso) + 8 * 3600000).toISOString().slice(0, 10);
    if (a.p_from) rows = rows.filter(e => sgDay(e.created_at) >= a.p_from);
    if (a.p_to) rows = rows.filter(e => sgDay(e.created_at) <= a.p_to);
    if (a.p_module) rows = rows.filter(e => (e.module ?? e.table_name) === a.p_module);
    if (a.p_table) rows = rows.filter(e => e.table_name === a.p_table);
    if (a.p_actor) rows = rows.filter(e => e.changed_by === a.p_actor);
    if (a.p_text) rows = rows.filter(e => JSON.stringify(e).toLowerCase().includes(a.p_text.toLowerCase()));
    rows.sort((x, y) => (x.created_at === y.created_at ? (x.id < y.id ? 1 : -1) : x.created_at < y.created_at ? 1 : -1));
    const count = key => Object.entries(rows.reduce((m, e) => ({ ...m, [key(e)]: (m[key(e)] ?? 0) + 1 }), {}));
    return {
      as_of: asOf, total: rows.length, rows: rows.slice(a.p_offset, a.p_offset + a.p_limit),
      choices: a.p_with_choices ? {
        modules: count(e => e.module ?? e.table_name).map(([value, n]) => ({ value, count: n })).sort((x, y) => x.value.localeCompare(y.value)),
        tables: count(e => e.table_name).map(([value, n]) => ({ value, count: n })).sort((x, y) => x.value.localeCompare(y.value)),
        actors: [{ id: OWNER, name: 'Fixture Owner', count: 2448 }, { id: STAFF, name: 'Fixture Staff', count: 1 }],
      } : null,
    };
  };
  b.client = {
    from: name => { throw new Error(`the page read the table ${name} directly`); },
    rpc: (name, args) => ({
      then(res, rej) {
        return (async () => {
          b.calls.push({ name, args });
          b.onCall?.(name, args);
          if (b.held) { const gate = b.held; b.held = null; await gate; }
          await Promise.resolve();
          if (name !== 'audit_log_page') return { data: null, error: { code: 'PGRST202', message: `unknown rpc ${name}` } };
          if (b.fail) return { data: null, error: { code: '22023', message: b.fail } };
          return { data: page(args), error: null };
        })().then(res, rej);
      },
    }),
  };
  return b;
}

// ── driving the page ───────────────────────────────────────────────────────
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
const wait = ms => act(async () => { await new Promise(r => setTimeout(r, ms)); });
async function mount({ role = 'owner', setup } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend();
  globalThis.__backend = backend; globalThis.__renderErrors = []; globalThis.__exports = [];
  globalThis.__auth = { profile: { id: OWNER, full_name: 'Fixture Owner', role } };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(AuditLogPage))));
  await tick();
  assert.ok(!document.getElementById('crashed'), document.getElementById('crashed')?.textContent);
}
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await tick(); };
const button = label => [...document.querySelectorAll('button')].find(x => x.textContent.trim().startsWith(label));
const calls = () => backend.calls.filter(c => c.name === 'audit_log_page');
const lastArgs = () => calls().at(-1).args;
const text = el => (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
const pager = () => text(document.querySelector('[data-testid="audit-pager"] span'));
const bodyRows = () => [...document.querySelectorAll('tbody tr')];
const cells = tr => [...tr.children].map(td => text(td));
const field = label => document.querySelector(`[aria-label="${label}"]`);
async function setValue(el, value, event) {
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => { Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value); el.dispatchEvent(new dom.window.Event(event ?? (el.tagName === 'SELECT' ? 'change' : 'input'), { bubbles: true })); });
  await tick();
}
const NO_FILTERS = { p_from: null, p_to: null, p_module: null, p_table: null, p_actor: null, p_text: null };
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests ──────────────────────────────────────────────────────────────────
test('only Owners, Admins and Managers see it; others are not sent to the server', async () => {
  for (const role of ['staff', 'inventory_manager']) {
    await mount({ role });
    assert.match(document.body.textContent, /Only Owners, Admins, and Managers can view the audit log\./);
    assert.equal(calls().length, 0, role);
  }
  for (const role of ['owner', 'admin', 'manager']) {
    await mount({ role });
    assert.equal(calls().length, 1, role);
  }
});

test('the first page: 50 entries of all of them, newest first, in Singapore time, with who, the module and the record', async () => {
  await mount();
  assert.deepEqual(lastArgs(), { ...NO_FILTERS, p_limit: 50, p_offset: 0, p_as_of: null, p_with_choices: true });
  assert.equal(bodyRows().length, 50);
  assert.equal(pager(), '1–50 of 2,450 entries');
  const head = [...document.querySelectorAll('thead th')].map(th => th.textContent);
  assert.deepEqual(head, ['When (SGT)', 'Action', 'Table', 'Module', 'By', 'Role', 'Reason', 'Record', 'Details']);
  // 16:50 UTC on 8 Oct is 00:50 on 9 Oct in Singapore.
  const [first, second] = bodyRows().map(cells);
  assert.deepEqual(first.slice(0, 8), ['09 Oct 202600:50', 'invoice paid', 'invoices', 'invoicesfrom table', 'System', '—', '—', 'INV-FX-0001']);
  assert.equal(first[8], '{"status":"paid"}');
  assert.deepEqual(second.slice(0, 8), ['09 Oct 202600:30', 'transfer requested by staff', 'transfer_requests', 'transfers',
    'Fixture Staff', 'inventory manager', 'Shelf restock', '00000000…']);
  assert.doesNotMatch(document.body.textContent, /No audit entries/);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('Older and Newer page through one search at its as-of time; new entries do not shift it', async () => {
  await mount();
  assert.ok(button('Newer').disabled, 'nothing newer than the first page');
  backend.entries.unshift({ ...makeEntries()[5], id: 'e-late', created_at: '2026-10-09T09:00:00Z' });   // after the search's time
  await click(button('Older'));
  assert.deepEqual(lastArgs(), { ...NO_FILTERS, p_limit: 50, p_offset: 50, p_as_of: NOW, p_with_choices: false });
  assert.equal(pager(), '51–100 of 2,450 entries');
  await click(button('Newer'));
  assert.equal(lastArgs().p_offset, 0);
  assert.equal(lastArgs().p_as_of, NOW, 'the same search');
  for (let i = 0; i < 48; i++) await click(button('Older'));
  assert.equal(pager(), '2,401–2,450 of 2,450 entries');
  assert.ok(button('Older').disabled, 'nothing older than the last page');
  // Refresh is a new search: a new as-of time, and the choices again.
  await click(button('Refresh'));
  assert.deepEqual(lastArgs(), { ...NO_FILTERS, p_limit: 50, p_offset: 0, p_as_of: null, p_with_choices: true });
});

test('the filters: dates, module, table, person and text each start a new search on the server', async () => {
  await mount();
  const moduleOptions = [...field('Module').options].map(o => o.textContent);
  assert.deepEqual(moduleOptions, ['All modules', 'invoices (1)', 'transfers (1)', 'warehouse_inventory (2448)']);
  assert.deepEqual([...field('Person').options].map(o => o.textContent), ['Everyone', 'Fixture Owner (2448)', 'Fixture Staff (1)']);

  await click(button('Older'));
  await setValue(field('Module'), 'transfers');
  assert.deepEqual(lastArgs(), { ...NO_FILTERS, p_module: 'transfers', p_limit: 50, p_offset: 0, p_as_of: null, p_with_choices: false });
  assert.equal(pager(), '1–1 of 1 entry');
  await setValue(field('Module'), '');
  await setValue(field('Table'), 'invoices');
  assert.equal(lastArgs().p_table, 'invoices');
  await setValue(field('Table'), '');
  await setValue(field('Person'), STAFF);
  assert.equal(lastArgs().p_actor, STAFF);
  await setValue(field('Person'), '');
  await setValue(field('From'), '2026-10-01');
  await setValue(field('To'), '2026-10-02');
  assert.deepEqual(lastArgs(), { ...NO_FILTERS, p_from: '2026-10-01', p_to: '2026-10-02', p_limit: 50, p_offset: 0, p_as_of: null, p_with_choices: false });

  // Text waits for a pause in typing, then searches once.
  const before = calls().length;
  await setValue(field('Search the audit log'), 'she');
  await setValue(field('Search the audit log'), 'shelf');
  assert.equal(calls().length, before, 'not while typing');
  await wait(400); await tick();
  assert.equal(calls().length, before + 1);
  assert.equal(lastArgs().p_text, 'shelf');
  assert.equal(lastArgs().p_from, '2026-10-01', 'with the other filters');
  assert.match(document.body.textContent, /No audit entries match these filters/);

  await click(button('Clear filters'));
  assert.deepEqual(lastArgs(), { ...NO_FILTERS, p_limit: 50, p_offset: 0, p_as_of: null, p_with_choices: false });
  assert.equal(field('Search the audit log').value, '');
  await wait(400); await tick();
  assert.equal(lastArgs().p_text, null, 'clearing does not search the old text again');
});

test('a failed read is shown as a failure, never as "No audit entries"', async () => {
  await mount({ setup: b => { b.fail = 'JWT expired'; } });
  assert.equal(text(document.querySelector('[role="alert"]')), 'The audit log could not be loaded: JWT expired');
  assert.doesNotMatch(document.body.textContent, /No audit entries/);
  assert.equal(document.querySelector('[data-testid="audit-pager"]'), null);
  assert.ok(button('Export Excel').disabled, 'nothing to export');
  assert.equal(document.querySelector('.spin'), null, 'the spinner stopped');

  // The server's own reason, as for an end date before the start date.
  backend.fail = null;
  await click(button('Refresh'));
  assert.equal(document.querySelector('[role="alert"]'), null);
  backend.fail = 'The end date cannot be before the start date.';
  await setValue(field('From'), '2026-10-05');
  assert.equal(text(document.querySelector('[role="alert"]')), 'The audit log could not be loaded: The end date cannot be before the start date.');
});

test('a slow answer for an earlier search never replaces a later one', async () => {
  await mount();
  const release = backend.hold();
  await setValue(field('Module'), 'invoices');        // held
  backend.held = null;
  await setValue(field('Module'), 'transfers');       // answered at once
  assert.equal(pager(), '1–1 of 1 entry');
  release(); await tick();
  assert.equal(cells(bodyRows()[0])[1], 'transfer requested by staff', 'still the later search');
});

test('the export reads every entry of the search at its as-of time, with By, Role, Module, Record and Details, and no Category', async () => {
  await mount();
  backend.entries.unshift({ ...makeEntries()[5], id: 'e-late', created_at: '2026-10-09T09:00:00Z' });   // after the search's time
  const before = calls().length;
  await click(button('Export Excel'));
  await tick(20);
  const reads = calls().slice(before).map(c => c.args);
  assert.deepEqual(reads.map(a => [a.p_offset, a.p_limit, a.p_as_of]), [[0, 1000, NOW], [1000, 1000, NOW], [2000, 1000, NOW]]);
  assert.equal(globalThis.__exports.length, 1);
  const { sheet } = globalThis.__exports[0];
  assert.deepEqual(sheet.ws.header, ['When (SGT)', 'Action', 'Table', 'Module', 'By', 'Role', 'Reason', 'Record', 'Details']);
  assert.equal(sheet.ws.body.length, 2450, 'every entry, not the page on screen; not the one after the search');
  assert.deepEqual(sheet.ws.body[0], {
    'When (SGT)': '2026-10-09 00:50:00', Action: 'invoice paid', Table: 'invoices', Module: 'invoices (from table)', By: 'System',
    Role: '', Reason: '', Record: 'INV-FX-0001', Details: 'Before: {"status":"unpaid"}\nAfter: {"status":"paid"}' });
  assert.deepEqual(sheet.ws.body[1], {
    'When (SGT)': '2026-10-09 00:30:00', Action: 'transfer requested by staff', Table: 'transfer_requests', Module: 'transfers',
    By: 'Fixture Staff', Role: 'inventory manager', Reason: 'Shelf restock', Record: '00000000-0000-4000-8000-0000000000c1',
    Details: 'After: {"lines":2}' });

  // An entry from a write that began before the search but was saved during
  // the export is dated before the as-of time, so it moves the rest down a
  // place. The export still holds each entry once.
  let late = false;
  backend.onCall = (name, args) => {
    if (args.p_offset === 1000 && !late) {
      late = true;
      backend.entries.unshift({ ...makeEntries()[5], id: 'e-late-writer', created_at: '2026-10-09T07:59:59Z' });
    }
  };
  await click(button('Export Excel'));
  await tick(20);
  backend.onCall = null;
  assert.ok(late, 'the late entry arrived during the export');
  const body = globalThis.__exports.at(-1).sheet.ws.body;
  assert.equal(body.length, 2450, 'no entry twice');
  assert.equal(new Set(body.map(r => `${r['When (SGT)']}|${r.Details}`)).size, 2450, 'each entry once');

  // With a filter: the same filter, all of it.
  await setValue(field('Person'), STAFF);
  const mark = calls().length;
  await click(button('Export Excel'));
  await tick(20);
  assert.deepEqual(calls().slice(mark).map(c => c.args.p_actor), [STAFF]);
  assert.equal(globalThis.__exports.at(-1).sheet.ws.body.length, 1);
});

test('the export helpers: Singapore time, and long details cut to fit an Excel cell', () => {
  assert.equal(sgtStamp('2026-12-31T16:00:00Z'), '2027-01-01 00:00:00');
  assert.equal(sgtStamp('not a date'), '');
  assert.equal(auditDetailsText({ old_data: null, new_data: null }), '');
  const long = auditDetailsText({ old_data: null, new_data: { note: 'x'.repeat(40000) } });
  assert.equal(long.length, 32000 + '… (cut at 32,000 characters)'.length);
  assert.ok(long.endsWith('… (cut at 32,000 characters)'));
});
