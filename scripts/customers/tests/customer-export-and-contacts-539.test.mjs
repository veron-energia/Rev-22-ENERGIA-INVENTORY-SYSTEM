// The customer export and colleagues' contact details after 539 (security audit of 17 Nov 2026,
// M13; the user, 25 Nov 2026), rendered for real against a fake backend:
// src/pages/CustomersPage.tsx (bundled with esbuild, mounted in jsdom; the Supabase client, the
// auth context and xlsx are stubbed) and the helpers in src/lib/permissions/customers.ts.
//   * only an Owner or a Manager sees Export and Special Export (Staff, an Admin and an Inventory
//     Manager see neither);
//   * an export is one call to export_customers, with the page's search and filters, the kind and
//     the created dates chosen in the window, and the file holds the rows it gave; no paging
//     through search_customers;
//   * a refusal is shown in the server's words, and no file is written;
//   * an Inventory Manager's list shows the server's sentence;
//   * no page or Edge Function asks public.profiles for select('*'), a bare select() or the three
//     hidden columns, and the pages that read profiles name PROFILE_COLUMNS; the sign-in takes the
//     login email from the session (so the pages work before and after 539);
//   * without export_customers the export fails plainly and makes no file (the page-by-page
//     fallback, which wrote no Audit Log entry, is gone now that 539 is live);
//   * an Inventory Manager is offered no Customers page.
// Every id and name is invented. Run: node --test scripts/customers/tests/customer-export-and-contacts-539.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://customers539.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.confirm = () => true;
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
console.error = (...a) => { if (!/not wrapped in act|\(fixture\)/.test(String(a[0]))) consoleError(...a); };

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { default as CustomersPage } from './src/pages/CustomersPage';
      export * as perms from './src/lib/permissions/customers';
      export { MemoryRouter } from 'react-router-dom';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };`,
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
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.from(...a), rpc: (...a) => globalThis.__backend.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const utils = {
        json_to_sheet: (body, opts) => ({ body, header: opts && opts.header }),
        book_new: () => ({ sheets: [] }),
        book_append_sheet: (wb, ws, name) => { wb.sheets.push({ ws, name }); },
      };
      export const writeFile = (wb, filename) => { globalThis.__files.push({ filename, sheet: wb.sheets[0] }); };` }));
  } }],
});
const { CustomersPage, perms, MemoryRouter, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const customer = n => ({
  id: `c-${n}`, full_name: `Made Up ${n}`, first_name: 'Made', last_name: `Up ${n}`, phone: `+61491570${String(n).padStart(3, '0')}`,
  email: `c${n}@example.invalid`, address: null, notes: null, is_active: true, created_at: '2026-07-01T00:00:00Z',
  referred_by: null, is_referrer: false, date_of_birth: null, gender: null, gender_other: null, occupation: null,
  source_label: null, first_visit_on: null, total_count: 3 });
const LIST = [customer(1), customer(2), customer(3)];
const ALL = Array.from({ length: 120 }, (_, i) => customer(i + 1));

function backend({ refuse = {}, missing = [] } = {}) {
  const b = { calls: [] };
  const answer = (name, args) => {
    if (refuse[name]) return { data: null, error: { ...refuse[name] } };
    if (missing.includes(name)) return { data: null, error: { code: 'PGRST202', message: `Could not find the function public.${name} (fixture)` } };
    if (name === 'search_customers') {
      // As the database pages it (the list's order), for the export's fallback.
      const all = ALL.map(r => ({ ...r, total_count: ALL.length }));
      if (Number(args?.p_limit) > 50) return { data: all.slice(args.p_offset, args.p_offset + args.p_limit), error: null };
      return { data: structuredClone(LIST), error: null };
    }
    if (name === 'active_customer_source_options') return { data: [], error: null };
    if (name === 'export_customers') {
      const rows = ALL.map(({ total_count, ...r }) => r);
      return { data: { customers: rows.length, rows }, error: null };
    }
    return { data: null, error: { message: `unknown rpc ${name} (fixture)` } };
  };
  b.rpc = (name, args) => { b.calls.push({ rpc: name, args }); return Promise.resolve(answer(name, args)); };
  b.from = table => {
    const q = { select: () => q, eq: () => q, is: () => q, in: () => q, order: () => q, limit: () => q, maybeSingle: () => q, or: () => q,
      then: (res, rej) => { b.calls.push({ table }); return Promise.resolve({ data: [], error: null }).then(res, rej); } };
    return q;
  };
  return b;
}

const USERS = {
  owner: { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true },
  manager: { id: 'u-mgr', full_name: 'Manager One', role: 'manager', is_active: true },
  staff: { id: 'u-staff', full_name: 'Staff One', role: 'staff', is_active: true },
  admin: { id: 'u-adm', full_name: 'Admin One', role: 'admin', is_active: true },
  invman: { id: 'u-inv', full_name: 'Inventory One', role: 'inventory_manager', is_active: true },
};
let root = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
const wait = async ms => { await act(async () => { await new Promise(r => setTimeout(r, ms)); }); await tick(); };
async function mount(role, opts) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  globalThis.__backend = backend(opts);
  globalThis.__files = [];
  globalThis.__auth = { profile: USERS[role], signOut: async () => {} };
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(MemoryRouter, null, React.createElement(CustomersPage))));
  await tick();
  await wait(320);
  return globalThis.__backend;
}
after(async () => { if (root) await act(async () => root.unmount()); });
const buttons = () => [...document.querySelectorAll('button')];
const byText = t => buttons().find(b => b.textContent.trim() === t || b.textContent.trim().endsWith(t));
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const setInput = async (el, value) => {
  const setter = Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value').set;
  await act(async () => { setter.call(el, value); el.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
  await tick();
};
const modalExport = () => [...document.querySelectorAll('.btn-primary')].find(b => b.textContent.trim() === 'Export');

// ── the rules ──────────────────────────────────────────────────────────────
test('539: who may export, who reads colleagues\' contacts, and the sentences', () => {
  for (const r of ['owner', 'manager']) { assert.equal(perms.canExportCustomers(r), true, r); assert.equal(perms.canSeeStaffContacts(r), true, r); }
  for (const r of ['admin', 'staff', 'inventory_manager', null, undefined, '']) {
    assert.equal(perms.canExportCustomers(r), false, String(r)); assert.equal(perms.canSeeStaffContacts(r), false, String(r));
  }
  assert.equal(perms.SEARCH_CAP, 50);
  assert.equal(perms.CUSTOMER_LIST_MESSAGES.searchCap, 'A search returns at most 50 customers at a time.');
  assert.equal(perms.CUSTOMER_LIST_MESSAGES.exportOwnerOrManager, 'Only an Owner or a Manager can export the customer list.');
  assert.equal(perms.CUSTOMER_LIST_MESSAGES.inventoryManager, 'An Inventory Manager does not see the customer list.');
  assert.equal(perms.CUSTOMER_LIST_MESSAGES.exportKind, 'An export is the standard export or the Special Export.');
  for (const r of ['owner', 'admin', 'manager', 'staff']) assert.equal(perms.canSeeCustomerList(r), true, r);
  for (const r of ['inventory_manager', null, undefined, '']) assert.equal(perms.canSeeCustomerList(r), false, String(r));
  assert.equal(perms.exportFunctionMissing({ code: 'PGRST202' }), true);
  assert.equal(perms.exportFunctionMissing({ code: '42883' }), true);
  assert.equal(perms.exportFunctionMissing({ code: '42501' }), false);
  // The sentences are the database's, word for word.
  const sql = readFileSync(join(REPO, 'supabase/539_customer_export_and_staff_contacts_for_owners_and_managers.sql'), 'utf8');
  for (const m of Object.values(perms.CUSTOMER_LIST_MESSAGES)) assert.ok(sql.includes(`'${m}'`), m);
  const cols = perms.PROFILE_COLUMNS.split(',').map(s => s.trim());
  assert.deepEqual(cols, ['id', 'full_name', 'role', 'is_active', 'deleted_at', 'created_at', 'updated_at', 'work_phone', 'invitation_status']);
  assert.match(sql, /c_prof_read constant text\[\] := array\['id', 'full_name', 'role', 'is_active', 'deleted_at', 'created_at', 'updated_at', 'work_phone', 'invitation_status'\];/);
  assert.deepEqual(perms.withContacts({ id: 'x' }, null), { id: 'x', email: '', personal_phone: null, personal_email: null });
  assert.deepEqual(perms.withContacts({ id: 'x' }, { email: 'a@example.invalid', personal_phone: '+61491570001', personal_email: null }),
    { id: 'x', email: 'a@example.invalid', personal_phone: '+61491570001', personal_email: null });
  assert.deepEqual(perms.customerExportArgs('special', { search: '  Ada ', source: '', visitArgs: { p_visited: 'visited', p_visit_from: '2026-01-01' } }, { from: '2026-02-01', to: '' }),
    { p_export: 'special', p_query: 'Ada', p_source: null, p_visited: 'visited', p_visit_from: '2026-01-01', p_visit_to: null,
      p_created_from: '2026-02-01', p_created_to: null });
});

test('only an Owner or a Manager sees Export and Special Export', async () => {
  for (const role of ['owner', 'manager']) {
    await mount(role);
    assert.ok(byText('Export Excel'), `${role}: Export`);
    assert.ok(byText('Special Export'), `${role}: Special Export`);
  }
  for (const role of ['staff', 'admin', 'invman']) {
    await mount(role);
    assert.equal(byText('Export Excel'), undefined, `${role}: no Export`);
    assert.equal(byText('Special Export'), undefined, `${role}: no Special Export`);
    assert.ok(byText('Refresh'), `${role}: the page itself is there`);
  }
});

test('an Owner\'s export is one call to export_customers, with the filters and the dates, and the file holds its rows', async () => {
  const b = await mount('owner');
  const search = document.querySelector('input[placeholder^="Search name"]');
  await setInput(search, 'Made Up');
  await wait(400);
  const pageDates = new Set(document.querySelectorAll('input[type="date"]'));
  await click(byText('Export Excel'));
  // The window's created dates: the date boxes the page did not have before it opened.
  const dates = [...document.querySelectorAll('input[type="date"]')].filter(d => !pageDates.has(d));
  assert.equal(dates.length, 2, 'the window offers the created dates');
  await setInput(dates[0], '2026-06-01'); await setInput(dates[1], '2026-12-31');
  await click(modalExport());
  await wait(50);
  const exports = b.calls.filter(c => c.rpc === 'export_customers');
  assert.equal(exports.length, 1, 'one call');
  assert.equal(exports[0].args.p_export, 'standard');
  assert.equal(exports[0].args.p_query, 'Made Up');
  assert.equal(exports[0].args.p_created_from, '2026-06-01');
  assert.equal(exports[0].args.p_created_to, '2026-12-31');
  assert.equal(b.calls.filter(c => c.rpc === 'search_customers' && Number(c.args?.p_limit) > 50).length, 0, 'no paging through search_customers');
  assert.equal(globalThis.__files.length, 1, 'one file');
  // The page still keeps only rows made in the chosen dates (all of the fixture's are 1 Jul 2026).
  assert.equal(globalThis.__files[0].sheet.ws.body.length, 120, 'every row the server gave, within the dates');
  assert.equal(globalThis.__files[0].sheet.ws.body[0].Name, 'Made Up 1');
});

test('a Manager\'s Special Export says special', async () => {
  const b = await mount('manager');
  await click(byText('Special Export'));
  await click(modalExport());
  await wait(50);
  const exports = b.calls.filter(c => c.rpc === 'export_customers');
  assert.equal(exports.length, 1);
  assert.equal(exports[0].args.p_export, 'special');
  assert.equal(globalThis.__files.length, 1);
});

test('a refused export shows the server\'s sentence and writes no file', async () => {
  await mount('owner', { refuse: { export_customers: { message: 'Only an Owner or a Manager can export the customer list.', code: '42501' } } });
  await click(byText('Export Excel'));
  await click(modalExport());
  await wait(50);
  assert.match(document.body.textContent, /Export failed: Only an Owner or a Manager can export the customer list\./);
  assert.equal(globalThis.__files.length, 0);
});

test('without export_customers the export fails plainly and reads nothing else (the fallback is gone)', async () => {
  // M13 follow-up: the page-by-page fallback wrote no Audit Log entry, so with 539 live it is removed.
  const b = await mount('owner', { missing: ['export_customers'] });
  await click(byText('Export Excel'));
  await click(modalExport());
  await wait(50);
  assert.equal(b.calls.filter(c => c.rpc === 'export_customers').length, 1, 'export_customers is asked');
  const pages = b.calls.filter(c => c.rpc === 'search_customers' && Number(c.args?.p_limit) === 1000);
  assert.equal(pages.length, 0, 'no paging read through search_customers');
  assert.equal(globalThis.__files.length, 0, 'no file');
  assert.match(document.body.textContent, /Export failed/);
});

test('an Inventory Manager\'s list shows the server\'s sentence', async () => {
  await mount('invman', { refuse: { search_customers: { message: 'An Inventory Manager does not see the customer list.', code: '42501' } } });
  assert.match(document.body.textContent, /An Inventory Manager does not see the customer list\./);
});

// ── every read of public.profiles names readable columns ─────────────────────
function walk(dir, out = []) {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) { if (n !== 'node_modules' && n !== 'tests') walk(p, out); }
    else if (/\.(tsx?|mjs|js)$/.test(n)) out.push(p);
  }
  return out;
}
test('no page or Edge Function reads profiles with select(\'*\') or asks for a hidden column', () => {
  const files = [...walk(join(REPO, 'src')), ...walk(join(REPO, 'supabase/functions'))];
  const reads = [];
  for (const f of files) {
    const s = readFileSync(f, 'utf8');
    for (const m of s.matchAll(/from\(['"]profiles['"]\)([\s\S]{0,400}?)(?:;|\n\s*\n)/g)) reads.push({ f: f.slice(REPO.length), chain: m[1] });
  }
  assert.ok(reads.length >= 15, `found the reads (${reads.length})`);
  for (const r of reads) {
    if (r.f.startsWith('supabase/functions/') && /^\s*\.?select\(/.test(r.chain) && /admin|db\b/.test(r.f)) { /* the secret key's own reads */ }
    assert.ok(!/select\(\s*['"`]\s*\*\s*['"`]\s*\)/.test(r.chain), `${r.f}: select('*') on profiles`);
    assert.ok(!/select\(\s*\)/.test(r.chain), `${r.f}: a bare select() (every column) on profiles`);
    for (const cols of r.chain.matchAll(/select\(\s*['"`]([^'"`]*)['"`]/g)) {
      assert.ok(!/\*|\b(email|personal_phone|personal_email)\b/.test(cols[1]), `${r.f}: asks profiles for a hidden column: ${cols[1]}`);
    }
  }
  // A profiles update kept in a variable and asked back later names its columns too.
  for (const f of files.filter(f => f.includes('/src/'))) {
    const s = readFileSync(f, 'utf8');
    for (const m of s.matchAll(/(?:let|const)\s+(\w+)\s*=\s*supabase\.from\(['"]profiles['"]\)/g)) {
      for (const sel of s.matchAll(new RegExp(`\\b${m[1]}\\.select\\(([^)]*)\\)`, 'g'))) {
        assert.ok(sel[1].trim() && !/\*|email|personal_/.test(sel[1]), `${f.slice(REPO.length)}: ${m[1]}.select(${sel[1]})`);
      }
    }
  }
  for (const f of ['src/context/AuthContext.tsx', 'src/pages/UsersPage.tsx', 'src/pages/StoresPage.tsx']) {
    assert.match(readFileSync(join(REPO, f), 'utf8'), /from\('profiles'\)\.select\(PROFILE_COLUMNS\)/, f);
  }
  const users = readFileSync(join(REPO, 'src/pages/UsersPage.tsx'), 'utf8');
  assert.match(users, /await update\.select\('id, is_active'\)/, 'the Users page asks for back only id and is_active');
  const auth = readFileSync(join(REPO, 'src/context/AuthContext.tsx'), 'utf8');
  assert.match(auth, /supabase\.auth\.getSession\(\)/, 'the sign-in takes the login email from the session');
  assert.ok(!/profile\?\.email/.test(readFileSync(join(REPO, 'src/pages/AffiliateVerifyPage.tsx'), 'utf8')), 'the verify page labels by the session email');
  assert.match(readFileSync(join(REPO, 'src/pages/AffiliateVerifyPage.tsx'), 'utf8'), /session\?\.user\?\.email/);
});

test('an Inventory Manager is offered no customer list', () => {
  const layout = readFileSync(join(REPO, 'src/components/AppLayout.tsx'), 'utf8');
  assert.match(layout, /to: '\/customers'[^\n]*show: canSeeCustomerList\(role\)/);
});
