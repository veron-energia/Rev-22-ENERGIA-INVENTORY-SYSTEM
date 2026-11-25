// 540 (security audit of 17 Nov 2026, M13; the user, 25 Nov 2026: "Stock only", "No lending by IM"):
// what the pages offer an Inventory Manager, and the sentences the database refuses them with.
//   * the role rules in src/lib/permissions/customers.ts;
//   * the sentences are the migration's, word for word;
//   * the menu hides Invoices, Exchanges, Therapy, Affiliates and Customers from an Inventory
//     Manager and keeps their stock pages;
//   * New Invoice, and Lend and Take back on the store and warehouse stock pages, are not
//     offered to an Inventory Manager; Record use stays.
// Run: node --test scripts/customers/tests/inventory-manager-pages-540.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const read = f => readFileSync(join(REPO, f), 'utf8');
const built = await build({ entryPoints: [join(REPO, 'src/lib/permissions/customers.ts')], bundle: true, write: false, format: 'esm', platform: 'neutral', logLevel: 'silent' });
const perms = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

test('540: the role rules', () => {
  for (const r of ['owner', 'admin', 'manager', 'staff']) {
    assert.equal(perms.worksWithStockOnly(r), false, r);
    assert.equal(perms.canMakeInvoices(r), true, r);
    assert.equal(perms.canLendStock(r), true, r);
  }
  assert.equal(perms.worksWithStockOnly('inventory_manager'), true);
  assert.equal(perms.canMakeInvoices('inventory_manager'), false);
  assert.equal(perms.canLendStock('inventory_manager'), false);
  for (const r of [null, undefined, '']) { assert.equal(perms.canMakeInvoices(r), false); assert.equal(perms.canLendStock(r), false); }
});

test('540: the sentences are the database\'s, word for word', () => {
  const sql = read('supabase/540_an_inventory_manager_works_with_stock_only.sql');
  assert.deepEqual({ ...perms.INVENTORY_MANAGER_MESSAGES }, {
    invoice: 'An Inventory Manager does not make or change invoices.',
    loan: 'An Inventory Manager does not lend stock or take it back.',
    stock: 'An Inventory Manager works with stock only.',
  });
  for (const m of Object.values(perms.INVENTORY_MANAGER_MESSAGES)) assert.ok(sql.includes(`'${m}'`), m);
});

test('540: the menu hides what names customers or makes invoices from an Inventory Manager, and keeps stock', () => {
  const layout = read('src/components/AppLayout.tsx');
  for (const to of ['invoices', 'exchanges', 'therapy', 'affiliates']) {
    assert.match(layout, new RegExp(`to: '/${to}'[^\\n]*show: !worksWithStockOnly\\(role\\)`), to);
  }
  assert.match(layout, /to: '\/customers'[^\n]*show: canSeeCustomerList\(role\)/);
  for (const to of ['warehouse-inventory', 'store-inventory', 'transfers', 'stock-movements', 'tiktok-import', 'products', 'adjustments']) {
    assert.ok(!new RegExp(`to: '/${to}'[^\\n]*worksWithStockOnly`).test(layout), `${to} stays`);
  }
});

test('540: New Invoice, Lend and Take back are not offered to an Inventory Manager; Record use stays', () => {
  assert.match(read('src/pages/InvoicesPage.tsx'), /\{canMakeInvoices\(profile\?\.role\) && <button className="btn btn-primary" onClick=\{\(\) => \{ resetCreate\(\); setCreateOpen\(true\); \}\}><Plus size=\{16\} \/> New Invoice<\/button>\}/);
  const store = read('src/pages/StoreInventoryPage.tsx');
  assert.match(store, /\{canLendStock\(profile\?\.role\) && <button className="btn btn-secondary" disabled=\{!selectedStore \|\| !actHere\}[^\n]*setLendOpen\(true\)/);
  assert.match(store, /canAct=\{loans\.canAct === true && canLendStock\(profile\?\.role\)\}/);
  assert.match(store, /<button className="btn btn-primary" disabled=\{!selectedStore \|\| !actHere\}[^\n]*setUseOpen\(true\)/, 'Record use is not role-gated');
  const wh = read('src/pages/WarehouseInventoryPage.tsx');
  assert.match(wh, /\{canUseStock && canLendStock\(profile\?\.role\) && <button[^\n]*setLendOpen\(true\)/);
  assert.match(wh, /canAct=\{canUseStock && loans\.canAct === true && canLendStock\(profile\?\.role\)\}/);
  assert.match(wh, /\{canUseStock && <button className="btn btn-secondary" disabled=\{!selectedWh \|\| !actHere\}[^\n]*setUseOpen\(true\)/, 'Record use stays');
});
