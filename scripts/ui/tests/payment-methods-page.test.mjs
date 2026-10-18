// Payment Methods, rendered for real against a fake backend (429:
// ADMIN-AUTH-10, -11).
//
//   * the five Wallet credit types carry a System badge, have no Delete and
//     keep their name; they are never switched off (the Owner, 10 Oct 2026):
//     one that is on has no Edit, one found off can only be switched on;
//   * a method the website orders use says so, and switching it off or
//     deleting it names the channel and asks first;
//   * renaming a method the till's QR pop-up finds by name asks first;
//   * a deleted method's name offers Restore; a live name is refused before
//     anything is sent;
//   * a failed read, save or delete says so (a refused delete looked as if it
//     had worked).
// Every name is made up.
//
// Run: node --test scripts/ui/tests/payment-methods-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver } from '../page-harness.mjs';

const dom = setupDom();
const mod = await bundle(`
  import React from 'react';
  export { default as PaymentMethodsPage } from './src/pages/PaymentMethodsPage';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`, { stubAuth: true });
const { PaymentMethodsPage, React } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });

const methods = () => [
  { id: 'pm-cash', name: 'Cash', is_active: true, deleted_at: null, created_at: '2026-01-01', is_wallet_credit: false, is_system: false },
  { id: 'pm-paynow', name: 'PayNow', is_active: true, deleted_at: null, created_at: '2026-01-02', is_wallet_credit: false, is_system: false },
  { id: 'pm-stripe', name: 'Stripe (online)', is_active: true, deleted_at: null, created_at: '2026-01-03', is_wallet_credit: false, is_system: false },
  { id: 'pm-wallet', name: 'Wallet — Paid Credit', is_active: true, deleted_at: null, created_at: '2026-01-04',
    is_wallet_credit: true, wallet_category: 'paid', is_system: true },
  { id: 'pm-bonus', name: 'Wallet — Bonus Credit', is_active: false, deleted_at: null, created_at: '2026-01-06',
    is_wallet_credit: true, wallet_category: 'bonus', is_system: true },
  { id: 'pm-old', name: 'Atome 6 months plan', is_active: false, deleted_at: '2026-05-01T00:00:00Z', created_at: '2026-01-05',
    is_wallet_credit: false, is_system: false },
];
const asked = [];
dom.window.confirm = m => { asked.push(m); return globalThis.__answer ?? true; };

async function open(over = {}) {
  globalThis.__supabase = fakeSupabase({
    tables: { payment_methods: methods() },
    rpc: { payment_method_web_uses: () => [
      { payment_method_id: 'pm-stripe', channel_key: 'test-channel', channel_mode: 'live', used_for: 'website orders' },
    ], ...over.rpc },
    fail: over.fail ?? {},
  });
  globalThis.__auth = { profile: { id: 'u-own', full_name: 'Olive Test', role: 'owner', is_active: true } };
  await d.mount(React.createElement(PaymentMethodsPage));
  return globalThis.__supabase;
}
const rowOf = name => [...document.querySelectorAll('tr')].find(tr => tr.querySelector('strong')?.textContent === name);
const updates = sb => sb.calls.filter(c => c.table === 'payment_methods' && c.op === 'update');

test('a system wallet method has a System badge, no Delete and no Edit: it keeps its name and stays on', async () => {
  await open();
  const row = rowOf('Wallet — Paid Credit');
  assert.ok(row.textContent.includes('System'));
  assert.ok(row.querySelector('.badge[title]').getAttribute('title').includes('always on'));
  assert.equal(row.querySelector('button[aria-label^="Delete"]'), null, 'no Delete');
  assert.equal(row.querySelector('button[aria-label^="Edit"]'), null, 'no Edit: nothing on it can change');
  assert.ok(rowOf('Cash').querySelector('button[aria-label="Delete Cash"]'), 'ordinary methods keep Delete');
  assert.ok(rowOf('Cash').querySelector('button[aria-label="Edit Cash"]'), 'and Edit');
});

test('a wallet credit type found off can be switched on, and is never offered off', async () => {
  const sb = await open();
  await d.click(rowOf('Wallet — Bonus Credit').querySelector('button[aria-label^="Edit"]'));
  assert.equal(document.getElementById('pm-name').disabled, true, 'the name cannot be edited');
  assert.ok(d.text().includes('Its name stays as it is, and once on it stays on.'));
  assert.ok(d.text().includes('Once switched on, it stays on.'));
  const box = document.querySelector('.modal input[type="checkbox"]');
  assert.equal(box.checked, false);
  await d.toggle(box);
  asked.length = 0;
  await d.click(d.button('Save', document.querySelector('.modal')));
  assert.equal(asked.length, 0, 'switching on asks nothing');
  assert.deepEqual(updates(sb)[0].payload, { is_active: true }, 'only Active is sent for a system method');
});

test('a method the website orders use says so, and switching it off names the channel and asks', async () => {
  const sb = await open();
  assert.ok(rowOf('Stripe (online)').textContent.includes('Used by website orders (test-channel)'));
  await d.click(rowOf('Stripe (online)').querySelector('button[aria-label^="Edit"]'));
  await d.toggle(document.querySelector('.modal input[type="checkbox"]'));
  asked.length = 0;
  globalThis.__answer = false;
  await d.click(d.button('Save', document.querySelector('.modal')));
  globalThis.__answer = undefined;
  assert.ok(asked.some(q => q.includes('the website channel "test-channel"') && q.includes('cannot be turned into invoices')), asked.join('|'));
  assert.equal(updates(sb).length, 0);
});

test('deleting a method the website uses names the channel; a refused delete says so', async () => {
  const sb = await open();
  asked.length = 0;
  // The database's rules refuse: no error, no row back.
  sb.tables.payment_methods = sb.tables.payment_methods.filter(m => m.id !== 'pm-stripe');
  await d.click(rowOf('Stripe (online)').querySelector('button[aria-label^="Delete"]'));
  assert.ok(asked.some(q => q.startsWith('Delete "Stripe (online)"?') && q.includes('test-channel')), asked.join('|'));
  const alert = [...document.querySelectorAll('[role="alert"]')].find(a => a.textContent.includes('was not deleted'));
  assert.ok(alert, 'the refusal shows (before 429 the page looked as if it had worked)');
});

test('renaming a method the till finds its QR code by asks first', async () => {
  const sb = await open();
  await d.click(rowOf('PayNow').querySelector('button[aria-label^="Edit"]'));
  await d.setValue(document.getElementById('pm-name'), 'Bank QR');
  asked.length = 0;
  globalThis.__answer = false;
  await d.click(d.button('Save', document.querySelector('.modal')));
  globalThis.__answer = undefined;
  assert.ok(asked.some(q => q.includes('PayNow QR code')), asked.join('|'));
  assert.equal(updates(sb).length, 0);
  // Keeping the word keeps the QR code: nothing to ask.
  await d.setValue(document.getElementById('pm-name'), 'PayNow (shop)');
  asked.length = 0;
  await d.click(d.button('Save', document.querySelector('.modal')));
  assert.equal(asked.length, 0);
  assert.equal(updates(sb)[0].payload.name, 'PayNow (shop)');
});

test('a deleted method\'s name offers Restore; a live name is refused before anything is sent', async () => {
  const sb = await open();
  await d.click(d.button('Add Method'));
  await d.setValue(document.getElementById('pm-name'), '  atome 6 MONTHS plan ');
  assert.ok(d.text().includes('A deleted method is called "Atome 6 months plan"'));
  assert.ok(d.button('Add a new one', document.querySelector('.modal')), 'adding a new one stays possible');
  await d.click(d.button('Restore "Atome 6 months plan"'));
  const restore = updates(sb)[0];
  assert.deepEqual(restore.payload, { deleted_at: null, is_active: true });
  assert.deepEqual(restore.filters, [{ c: 'id', v: 'pm-old' }]);
  assert.ok(d.text().includes('"Atome 6 months plan" was restored.'));

  await d.click(d.button('Add Method'));
  await d.setValue(document.getElementById('pm-name'), ' cash ');
  await d.click(d.button('Save', document.querySelector('.modal')));
  assert.ok(document.querySelector('.modal [role="alert"]')?.textContent.includes('That payment method already exists'));
  assert.equal(sb.calls.filter(c => c.table === 'payment_methods' && c.op === 'insert').length, 0);
});

test('a list that cannot be read says so, with Retry; a website check that fails warns', async () => {
  const sb = await open({ fail: { payment_methods: 'permission denied for table payment_methods', payment_method_web_uses: 'Only active Energia staff can do this.' } });
  assert.ok([...document.querySelectorAll('[role="alert"]')].some(a => a.textContent.includes('Could not load payment methods: permission denied')));
  assert.ok(!d.text().includes('No payment methods yet'));
  sb.fail.payment_methods = undefined;
  await d.click(d.button('Retry'));
  assert.ok(rowOf('Cash'));
  assert.ok([...document.querySelectorAll('[role="alert"]')].some(a => a.textContent.includes('Could not check which methods the website orders use')));
});
