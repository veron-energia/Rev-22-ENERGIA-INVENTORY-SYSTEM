// "Links sent" (security audit L7, 18 Nov 2026): the panel Owners and Managers
// see on an invoice, special sale and rental, and its Withdraw.
// The real src/components/DocumentLinksPanel.tsx is bundled with esbuild and
// mounted in jsdom; only the Supabase client and the auth context are stubbed.
// All names, phones and ids are invented.
//
// Run: node --test scripts/ui/tests/document-links-panel.test.mjs
// Control: DOC_LINKS_CONTROL=1 swaps the panel for an empty one; the main
// tests must then fail.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const CONTROL = process.env.DOC_LINKS_CONTROL === '1';

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://links.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'Element', 'Node', 'Event',
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
    contents: CONTROL
      ? `export const DocumentLinksPanel = () => null; export { createRoot } from 'react-dom/client'; export { act } from 'react'; export { default as React } from 'react';`
      : `export { default as DocumentLinksPanel } from './src/components/DocumentLinksPanel'; export { createRoot } from 'react-dom/client'; export { act } from 'react'; export { default as React } from 'react';`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser', logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { rpc: (...a) => globalThis.__supabase.rpc(...a), storage: { from: (...a) => globalThis.__supabase.storage.from(...a) } };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth;' }));
  } }],
});
const { DocumentLinksPanel, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const ROW = over => ({
  send_id: 'send-1', pdf_path: 'invoice/INV-9001-1.pdf', sent_at: '2026-11-10T02:30:00Z', channel: 'whatsapp',
  sent_to: '+61491570001', sent_by_name: 'Sample Staff', status: 'sent', copy_present: true,
  withdrawn_at: null, withdrawn_by_name: null, ...over,
});

// A stubbed client that records calls in order.
function backend({ list = [ROW()], listError = null, removeError = null, withdrawError = null, removeKeeps = false } = {}) {
  // removeKeeps: the delete answers without error but deletes nothing (as storage
  // does for a copy a login may not delete); otherwise a deleted copy is no longer stored.
  const b = { log: [], list, listError, removeError, withdrawError, removeKeeps };
  globalThis.__supabase = {
    rpc: async (name, args) => {
      b.log.push(['rpc', name, args]);
      if (name === 'document_links') return b.listError ? { data: null, error: { message: b.listError } } : { data: b.list, error: null };
      if (name === 'withdraw_document_link') {
        if (b.withdrawError) return { data: null, error: { message: b.withdrawError } };
        b.list = b.list.map(r => r.pdf_path === args.p_pdf_path
          ? { ...r, copy_present: false, withdrawn_at: '2026-11-18T03:00:00Z', withdrawn_by_name: 'Sample Owner' } : r);
        return { data: { success: true, sends: 1, already: false }, error: null };
      }
      throw new Error('unexpected rpc ' + name);
    },
    storage: { from: bucket => ({ remove: async paths => {
      b.log.push(['remove', bucket, paths]);
      if (b.removeError) return { data: null, error: { message: b.removeError } };
      if (!b.removeKeeps) b.list = b.list.map(r => paths.includes(r.pdf_path) ? { ...r, copy_present: false } : r);
      return { data: [], error: null };
    } }) },
  };
  return b;
}
const flush = async () => { for (let i = 0; i < 6; i++) await act(async () => { await new Promise(r => setImmediate(r)); }); };
async function mount(role, props = {}) {
  globalThis.__auth = { profile: role ? { role } : null };
  const host = document.createElement('div'); document.body.appendChild(host);
  const root = createRoot(host);
  await act(async () => { root.render(React.createElement(DocumentLinksPanel, { docKind: 'invoice', docId: 'doc-1', ...props })); });
  await flush();
  return { host, root, unmount: () => act(async () => { root.unmount(); host.remove(); }) };
}
const withConfirm = (answer, fn) => async () => {
  const asked = []; window.confirm = m => { asked.push(m); return answer; };
  await fn(asked);
};
const click = async el => { await act(async () => { el.dispatchEvent(new window.MouseEvent('click', { bubbles: true })); }); await flush(); };

test('hidden for staff, admin and inventory manager, and nothing is read', async () => {
  for (const role of ['staff', 'admin', 'inventory_manager', null]) {
    const b = backend();
    const m = await mount(role);
    assert.equal(m.host.querySelector('[data-testid="document-links-panel"]'), null, `hidden for ${role}`);
    assert.equal(b.log.length, 0, `no read for ${role}`);
    await m.unmount();
  }
});

test('shown for owner and manager, reading the list for this document', async () => {
  for (const role of ['owner', 'manager']) {
    const b = backend();
    const m = await mount(role, { docKind: 'rental', docId: 'rent-7' });
    assert.ok(m.host.querySelector('[data-testid="document-links-panel"]'), `shown for ${role}`);
    assert.deepEqual(b.log[0], ['rpc', 'document_links', { p_doc_kind: 'rental', p_doc_id: 'rent-7' }]);
    await m.unmount();
  }
});

test('rows say when, how, to whom, by whom and the state', async () => {
  backend({ list: [
    ROW(),
    ROW({ send_id: null, pdf_path: 'old.pdf', channel: null, sent_to: null, sent_by_name: null, copy_present: false }),
    ROW({ send_id: 's3', pdf_path: 'w.pdf', channel: 'email', sent_to: 'a@example.invalid', copy_present: false,
      withdrawn_at: '2026-11-12T01:00:00Z', withdrawn_by_name: 'Sample Owner' }),
    ROW({ send_id: 's4', pdf_path: 'f.pdf', status: 'failed', copy_present: false }),
  ] });
  const m = await mount('owner');
  const rows = [...m.host.querySelectorAll('[data-testid="document-link-row"]')];
  assert.equal(rows.length, 4);
  // A send that failed after its copy was made says so (its copy may still open).
  assert.match(rows[3].textContent, /the send failed \(the copy was made\)/);
  assert.doesNotMatch(rows[0].textContent, /failed/);
  assert.match(rows[0].textContent, /10\/11\/2026, 10:30/);
  assert.match(rows[0].textContent, /WhatsApp.*to \+61491570001.*by Sample Staff/);
  assert.match(rows[0].textContent, /Link open until it expires/);
  assert.match(rows[1].textContent, /Sent before the send log/);
  assert.match(rows[1].textContent, /Copy no longer stored/);
  assert.match(rows[2].textContent, /Email.*a@example\.invalid/);
  assert.match(rows[2].textContent, /Withdrawn 12\/11\/2026.*by Sample Owner/);
  const buttons = [...m.host.querySelectorAll('button')].map(x => x.textContent);
  assert.deepEqual(buttons, ['Withdraw'], 'only the open copy can be withdrawn');
  await m.unmount();
});

test('an empty list says no links were sent', async () => {
  backend({ list: [] });
  const m = await mount('manager');
  assert.match(m.host.textContent, /No links were sent/);
  await m.unmount();
});

test('a failed read is said as a failure, never as "no links"', async () => {
  backend({ listError: 'Your role cannot do this.' });
  const m = await mount('owner');
  assert.match(m.host.querySelector('[data-testid="document-links-error"]').textContent, /could not be read.*Your role cannot do this/);
  assert.doesNotMatch(m.host.textContent, /No links were sent/);
  await m.unmount();
});

test('Withdraw asks, deletes the copy, THEN records it, then reloads the list', withConfirm(true, async asked => {
  const b = backend();
  const m = await mount('owner', { docKind: 'special_sale', docId: 'sale-3' });
  await click(m.host.querySelector('button'));
  assert.equal(asked.length, 1);
  assert.match(asked[0], /stops opening the PDF/); assert.match(asked[0], /already opened or saved stays with them/);
  assert.match(asked[0], /cannot be undone/); assert.match(asked[0], /send the document again/i);
  assert.doesNotMatch(asked[0], /at once/, 'no promise the audit could not test');
  const names = b.log.map(x => x[0] === 'remove' ? 'remove' : x[1]);
  assert.deepEqual(names, ['document_links', 'remove', 'withdraw_document_link', 'document_links']);
  assert.deepEqual(b.log[1], ['remove', 'invoice-pdfs', ['invoice/INV-9001-1.pdf']]);
  assert.deepEqual(b.log[2][2], { p_doc_kind: 'special_sale', p_doc_id: 'sale-3', p_pdf_path: 'invoice/INV-9001-1.pdf' });
  assert.match(m.host.textContent, /Withdrawn 18\/11\/2026.*by Sample Owner/);
  assert.equal(m.host.querySelector('button'), null, 'no Withdraw once withdrawn');
  await m.unmount();
}));

test('a storage error is shown and the withdrawal is NOT recorded', withConfirm(true, async () => {
  const b = backend({ removeError: 'Not allowed to delete' });
  const m = await mount('manager');
  await click(m.host.querySelector('button'));
  assert.match(m.host.querySelector('[data-testid="document-links-action-error"]').textContent, /Not allowed to delete/);
  assert.equal(b.log.filter(x => x[1] === 'withdraw_document_link').length, 0);
  assert.ok(m.host.querySelector('button'), 'Withdraw can be tried again');
  await m.unmount();
}));

test('an error from the server is shown as it says it, and a copy still stored is never called deleted', withConfirm(true, async () => {
  backend({ withdrawError: 'The PDF copy is still there, so its link still opens. Try Withdraw again.', removeKeeps: true });
  const m = await mount('owner');
  await click(m.host.querySelector('button'));
  const err = m.host.querySelector('[data-testid="document-links-action-error"]').textContent;
  assert.equal(err, 'The PDF copy is still there, so its link still opens. Try Withdraw again.');
  assert.doesNotMatch(err, /no longer opens it|\.\./);
  assert.deepEqual([...m.host.querySelectorAll('button')].map(x => x.textContent), ['Withdraw'], 'no "Record the withdrawal"; Withdraw can be tried again');
  await m.unmount();
}));

test('"still there" answered just before the copy turns out gone: only the later reading is said', withConfirm(true, async () => {
  backend({ withdrawError: 'The PDF copy is still there, so its link still opens. Try Withdraw again.' });
  const m = await mount('owner');
  await click(m.host.querySelector('button'));
  const err = m.host.querySelector('[data-testid="document-links-action-error"]').textContent;
  assert.match(err, /^The withdrawal could not be recorded\. The copy is deleted, so the link no longer opens it\./);
  assert.doesNotMatch(err, /still there|still opens/);
  assert.ok([...m.host.querySelectorAll('button')].some(x => x.textContent === 'Record the withdrawal'));
  await m.unmount();
}));

test('a refusal while the copy is still stored is shown alone, whatever it says', withConfirm(true, async () => {
  for (const said of ['Your role cannot do this.', 'This link is not one sent for this document.']) {
    backend({ withdrawError: said, removeKeeps: true });
    const m = await mount('manager');
    await click(m.host.querySelector('button'));
    assert.equal(m.host.querySelector('[data-testid="document-links-action-error"]').textContent, said);
    assert.equal([...m.host.querySelectorAll('button')].some(x => x.textContent === 'Record the withdrawal'), false);
    await m.unmount();
  }
}));

test('a copy deleted but not recorded can be recorded again, without deleting again', withConfirm(true, async () => {
  const b = backend({ withdrawError: 'connection lost' });
  const m = await mount('owner');
  await click(m.host.querySelector('button'));
  const err = m.host.querySelector('[data-testid="document-links-action-error"]');
  assert.match(err.textContent, /could not be recorded: connection lost\. The copy is deleted, so the link no longer opens it/);
  assert.doesNotMatch(err.textContent, /\.\./);
  const again = [...m.host.querySelectorAll('button')].find(x => x.textContent === 'Record the withdrawal');
  assert.ok(again, 'a button to record it again');
  b.withdrawError = null;
  await click(again);
  const names = b.log.map(x => x[0] === 'remove' ? 'remove' : x[1]);
  assert.deepEqual(names, ['document_links', 'remove', 'withdraw_document_link', 'document_links', 'withdraw_document_link', 'document_links'],
    'the list read again after the failure; then recorded again with no second delete, then the list read');
  assert.equal(m.host.querySelector('[data-testid="document-links-action-error"]'), null);
  assert.match(m.host.textContent, /Withdrawn 18\/11\/2026.*by Sample Owner/);
  await m.unmount();
}));

test('a copy stored again under a withdrawn name is shown, with Withdraw', async () => {
  backend({ list: [ROW({ withdrawn_at: '2026-11-12T01:00:00Z', withdrawn_by_name: 'Sample Manager', copy_present: true })] });
  const m = await mount('manager');
  const row = m.host.querySelector('[data-testid="document-link-row"]');
  assert.match(row.textContent, /Withdrawn 12\/11\/2026.*by Sample Manager, but a copy is stored under this name again and the link opens it/);
  assert.deepEqual([...m.host.querySelectorAll('button')].map(x => x.textContent), ['Withdraw']);
  await m.unmount();
});

test('cancelling the question does nothing', withConfirm(false, async asked => {
  const b = backend();
  const m = await mount('owner');
  await click(m.host.querySelector('button'));
  assert.equal(asked.length, 1);
  assert.deepEqual(b.log.map(x => x[1]), ['document_links'], 'nothing but the first read');
  await m.unmount();
}));

test('a new reloadKey reads the list again', async () => {
  const b = backend();
  const m = await mount('owner', { reloadKey: 0 });
  await act(async () => { m.root.render(React.createElement(DocumentLinksPanel, { docKind: 'invoice', docId: 'doc-1', reloadKey: 1 })); });
  await flush();
  assert.equal(b.log.filter(x => x[1] === 'document_links').length, 2);
  await m.unmount();
});

test('the wiring: 30-day links; the panel only for Owners and Managers on the invoice, sale and rental', () => {
  assert.match(read('src/lib/sendDoc.ts'), /const LINK_SECONDS = 60 \* 60 \* 24 \* 30;/);
  assert.match(read('src/lib/sendDoc.ts'), /upsert: false, cacheControl: '0' \}/, 'new copies are stored with caching off');
  const inv = read('src/pages/InvoicesPage.tsx');
  assert.match(inv, /isOwnerOrManager\(profile\?\.role\) && <DocumentLinksPanel key=\{detail\.id\} docKind="invoice" docId=\{detail\.id\} reloadKey=\{linksKey\}/,
    'a new panel for each invoice, so an answer for one never shows on another');
  assert.match(inv, /setLinksKey\(k => k \+ 1\)/, 'a send reloads the list');
  const sp = read('src/pages/SpecialPage.tsx');
  assert.match(sp, /linksFor && isOwnerOrManager\(profile\?\.role\)[\s\S]*?<DocumentLinksPanel key=\{`\$\{linksFor\.kind\}-\$\{linksFor\.id\}`\} docKind=\{linksFor\.kind\}/);
  assert.match(sp, /kind: 'special_sale'/); assert.match(sp, /kind: 'rental'/);
  assert.match(sp, /setLinksKey\(k => k \+ 1\)/);
  assert.match(read('src/components/DocumentLinksPanel.tsx'), /isOwnerOrManager\(profile\?\.role\)/);
});
