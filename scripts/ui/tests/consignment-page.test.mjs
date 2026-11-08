// The Consignment page in the app (the user, 8 Nov 2026: a page of its own,
// where it was a tab of Special & Rentals). App.tsx opens it at /consignment
// behind the staff login; the menu has it right under Special & Rentals, for
// Owners and Managers only, as Special & Rentals is; and the menu goes between
// the two pages, each listing its own products. The real login guard, menu and
// pages, against a fake backend; every name is made up.
//
// Run: node --test scripts/ui/tests/consignment-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { REPO, setupDom, bundle, fakeSupabase, driver } from '../page-harness.mjs';

const dom = setupDom('https://energia.invalid/consignment');
dom.window.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {} });
const mod = await bundle(`
  import React from 'react';
  export { AuthProvider } from './src/context/AuthContext';
  export { Protected } from './src/components/RouteGuards';
  export { default as SpecialPage } from './src/pages/SpecialPage';
  export { default as ConsignmentPage } from './src/pages/ConsignmentPage';
  export { BrowserRouter, Routes, Route } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`);
const { React, AuthProvider, Protected, SpecialPage, ConsignmentPage, BrowserRouter, Routes, Route } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });
const h = React.createElement;

// The two routes as App.tsx has them; the last test reads App.tsx for them.
const app = () => h(AuthProvider, null, h(BrowserRouter, null, h(Routes, null,
  h(Route, { path: '/special', element: h(Protected, null, h(SpecialPage)) }),
  h(Route, { path: '/consignment', element: h(Protected, null, h(ConsignmentPage)) }))));

const SESSION = { access_token: 'x.y.z', user: { id: 'u-1', email: 'olive@cons.invalid' } };
const SP = { description: null, rate_day: 0, rate_week: 0, rate_month: 0, rate_year: 0, late_fee_per_day: 0, is_active: true, deleted_at: null };
function signIn(role) {
  const sb = fakeSupabase({
    tables: {
      profiles: [{ id: 'u-1', full_name: 'Olive Test', role, is_active: true, email: 'olive@cons.invalid', invitation_status: 'accepted', deleted_at: null }],
      user_store_assignments: [],
      special_products: [
        { ...SP, id: 'sp-1', product_id: 'p-1', name: 'Fixture Chair', sku: 'FX-CH', sale_price: 300, rate_day: 20, is_consignment: false },
        { ...SP, id: 'sp-2', product_id: 'p-2', name: 'Fixture Bed', sku: 'FX-BD', sale_price: 900, is_consignment: true },
      ],
      suppliers: [{ id: 'sup-1', name: 'Fixture Supplier', phone: null, is_active: true, deleted_at: null }],
      product_suppliers: [{ product_id: 'p-2', supplier_id: 'sup-1' }],
    },
    rpc: { special_docs_awaiting_fulfilment: () => [], products_available_as_special: () => [] },
  });
  sb.auth.session = SESSION;
  globalThis.__supabase = sb;
}
async function open(path, role) {
  signIn(role);
  history.replaceState(null, '', path);
  await d.mount(app());
}
// The account and the page's lists are read after it opens: wait for them.
async function until(ok, what) {
  for (let i = 0; i < 40 && !ok(); i++) await d.tick(2);
  assert.ok(ok(), `${what}: ${d.text().slice(0, 300)}`);
}
const heading = () => document.querySelector('h2')?.textContent ?? '';
const products = () => [...document.querySelectorAll('tbody tr strong')].map(s => s.textContent);
const menu = () => [...document.querySelectorAll('#app-sidebar a')];
const link = name => menu().find(a => a.textContent.trim() === name);

test('an Owner at /consignment: the page, lit in the menu right under Special & Rentals; the menu goes between the two', async () => {
  await open('/consignment', 'owner');
  await until(() => heading() === 'Consignment Products' && products().length > 0, 'the Consignment page');
  assert.deepEqual(products(), ['Fixture Bed'], 'the ticked product alone');
  const names = menu().map(a => a.textContent.trim());
  const at = names.indexOf('Special & Rentals');
  assert.ok(at >= 0, names.join(','));
  assert.equal(names[at + 1], 'Consignment', 'right under Special & Rentals');
  assert.equal(link('Consignment').getAttribute('href'), '/consignment');
  assert.equal(link('Consignment').getAttribute('aria-current'), 'page', 'lit while open');
  assert.equal(link('Special & Rentals').getAttribute('aria-current'), null);

  await d.click(link('Special & Rentals'));
  await until(() => heading() === 'Special Products & Rentals' && products().length > 0, 'Special & Rentals');
  assert.equal(location.pathname, '/special');
  assert.deepEqual(products(), ['Fixture Chair'], 'the Catalog keeps the products not ticked');
  assert.equal(d.button('Consignment'), undefined, 'no Consignment tab');
  assert.ok(d.button('Catalog') && d.button('Sales') && d.button('Rentals'));

  await d.click(link('Consignment'));
  await until(() => heading() === 'Consignment Products' && products().length > 0, 'back on the Consignment page');
  assert.equal(location.pathname, '/consignment');
  assert.deepEqual(products(), ['Fixture Bed']);
});

test('a Manager has it too; an Admin, Staff and an Inventory Manager have neither page in the menu and are told who may', async () => {
  await open('/consignment', 'manager');
  await until(() => heading() === 'Consignment Products', 'a Manager');
  assert.ok(link('Consignment') && link('Special & Rentals'));
  for (const role of ['admin', 'staff', 'inventory_manager']) {
    await open('/consignment', role);
    await until(() => d.text().includes('Only Owners and Managers can manage consignment products.'), role);
    assert.ok(menu().length > 0, `${role}: the menu is there`);
    assert.equal(link('Consignment'), undefined, role);
    assert.equal(link('Special & Rentals'), undefined, role);
    assert.equal(document.querySelector('table'), null, `${role}: no list`);
  }
});

test('App.tsx opens the two pages at these addresses, each behind the staff login, as the tests above do', () => {
  const src = readFileSync(join(REPO, 'src/App.tsx'), 'utf8');
  assert.match(src, /const ConsignmentPage = lazyPage\(\(\) => import\('\.\/pages\/ConsignmentPage'\)\);/);
  assert.match(src, /<Route path="\/consignment" element=\{<Protected><ConsignmentPage \/><\/Protected>\} \/>/);
  assert.match(src, /<Route path="\/special" element=\{<Protected><SpecialPage \/><\/Protected>\} \/>/);
});
