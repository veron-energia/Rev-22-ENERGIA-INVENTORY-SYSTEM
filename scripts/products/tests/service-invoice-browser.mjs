// 495 (the user, 6 Nov 2026): "Service should show as another category in the
// invoice Items dropdown list", and a service holds no stock. Driven on the real
// invoice page as a person would: in-memory fixtures, no network, no credentials,
// every name and amount invented.
//
//  - Items offers Service, right after Product;
//  - Service lists every service with a price at the store, with or without stock;
//    Product lists the products, as before: priced, and in stock;
//  - a service goes out as a plain product line, with nothing added to it;
//  - a saved service line comes back under Service, on a new form and a correction;
//  - a promotion's choice group offers a service with no stock;
//  - moving a line between the two starts it empty.
//
// Run from the repository's root: node scripts/products/tests/service-invoice-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const SHOTS = process.env.SHOTS_DIR || '.invoice-test/browser';
await mkdir(SHOTS, { recursive: true });

const common = { is_active: true, deleted_at: null };
const date = '2026-09-01T01:00:00Z';
const tables = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', ...common }, { id: 'store2', name: 'Other Store', code: 'OTHER', ...common }],
  customers: [{ id: 'buyer', full_name: 'Test Buyer', phone: '+61 2 5550 1234', email: 'buyer@tests.invalid', date_of_birth: null, ...common }],
  profiles: [{ id: 'owner', full_name: 'Test Owner', role: 'owner', ...common }],
  products: [
    { id: 'socks', name: 'Long Energia Socks', sku: 'SOCK', product_type: 'own', ...common },
    { id: 'lotion', name: 'Partner Lotion', sku: 'LOTN', product_type: 'third_party', ...common },
    { id: 'empty', name: 'Sold Out Mat', sku: 'MAT', product_type: 'own', ...common },
    { id: 'visit', name: 'Home Visit', sku: 'VISIT', product_type: 'no_commission', ...common },
    { id: 'repair', name: 'Machine Repair', sku: 'REPAIR', product_type: 'no_commission', ...common },
    { id: 'noprice', name: 'Unpriced Fee', sku: 'FEE', product_type: 'no_commission', ...common },
  ],
  store_product_prices: [
    { store_id: 'store', product_id: 'socks', selling_price: 100, member_price: 100, ...common },
    { store_id: 'store', product_id: 'lotion', selling_price: 80, member_price: 80, ...common },
    { store_id: 'store', product_id: 'empty', selling_price: 60, member_price: 60, ...common },
    { store_id: 'store', product_id: 'visit', selling_price: 94, member_price: 94, ...common },
    { store_id: 'store', product_id: 'repair', selling_price: 500, member_price: 500, ...common },
    // Priced at the other store alone: not on this store's list.
    { store_id: 'store2', product_id: 'noprice', selling_price: 10, member_price: 10, ...common },
  ],
  // A service has no stock row, or one at 0. Machine Repair has made-up stock left.
  store_inventory: [
    { store_id: 'store', product_id: 'socks', current_qty: 100 }, { store_id: 'store', product_id: 'lotion', current_qty: 100 },
    { store_id: 'store', product_id: 'empty', current_qty: 0 }, { store_id: 'store', product_id: 'repair', current_qty: 999 },
  ],
  vouchers: [], therapy_services: [], therapy_service_stores: [], special_products: [],
  payment_methods: [{ id: 'cash', name: 'Cash', ...common }], credit_packages: [],
  promotions: [{ id: 'choose', name: 'Choose One Deal', code: 'CHOOSE', fixed_price: 90, start_date: null, end_date: null, ...common }],
  promotion_store_prices: [{ promotion_id: 'choose', store_id: 'store', selling_price: 90, member_price: 90, available_at_store: true, ...common }],
  promotion_items: [],
  promotion_choice_groups: [{ id: 'g', promotion_id: 'choose', label: 'Choose one', item_kind: 'product', choose_qty: 1 }],
  promotion_choice_options: [{ id: 'o1', group_id: 'g', product_id: 'socks' }, { id: 'o2', group_id: 'g', product_id: 'visit' }, { id: 'o3', group_id: 'g', product_id: 'empty' }],
  invoice_promotion_selections: [], invoice_payments: [],
};
const item = (invoice_id, id, over) => ({ id, invoice_id, line_kind: 'product', product_id: 'socks', quantity: 1, unit_price: 100, line_total: 100,
  topup_amount: 0, foc_quantity: 0, foc_amount: 0, line_discount: 0, line_voucher_id: null, line_discount_type: null,
  line_discount_percent: null, line_discount_reason: null, ...over });
const invoice = (id, no, over) => ({ id, invoice_no: no, store_id: 'store', customer_id: 'buyer', created_at: date, business_date: '2026-09-01',
  created_by: 'owner', edit_count: 0, manual_discount: 0, discount_voucher_id: null, ...common, ...over });
tables.invoices = [invoice('inv-edit', 'INV-EDIT', { status: 'unpaid', paid_amount: 0, subtotal: 194, discount_total: 0, total_amount: 194 })];
tables.invoice_items = [item('inv-edit', 'e1', { product_id: 'visit', unit_price: 94, line_total: 94 }), item('inv-edit', 'e2', {})];

const mock = `export const supabase={ from(table) {
 let rows=[...(window.__tables[table]||[])], one=false;
 const q=new Proxy({}, {get(_,key) {
  if(key==='then') return (ok,bad)=>Promise.resolve({data:JSON.parse(JSON.stringify(one?(rows[0]||null):rows)),error:null}).then(ok,bad);
  return (...a)=>{if(key==='eq'||key==='is')rows=rows.filter(r=>(r[a[0]]??null)===a[1]);if(key==='in')rows=rows.filter(r=>a[1].includes(r[a[0]]));
   if(key==='single'||key==='maybeSingle')one=true;return q;};
 }}); return q;
 }, rpc(name,args) {
 window.__calls.push({name,args:JSON.parse(JSON.stringify(args??null))});
 const t=window.__tables, find=id=>t.invoices.find(i=>i.id===id);
 const fin=i=>i?{total:Number(i.total_amount),net_received:Number(i.paid_amount),outstanding:Math.max(0,i.total_amount-i.paid_amount),refund_due:0,refunded:0,status:i.status}:null;
 let data=[];
 switch(name){
  case 'invoice_list_page': { const rows=t.invoices.map(i=>({...i,customer_name:t.customers.find(c=>c.id===i.customer_id)?.full_name??null}));
    data={rows,total:rows.length,pages:1,summary:{matching:rows.length,total_amount:0,outstanding:0,paid:0}}; break; }
  case 'active_foc_reasons': data=[]; break;
  case 'invoice_financial_position': data=fin(find(args.p_invoice_id)); break;
  case 'invoice_refund_options': data={financial:fin(find(args.p_invoice_id)),sources:[],stock:[],benefits:[],lines:[],review_required:false}; break;
  case 'invoice_effective_affiliate': data={found:true,has_affiliate:false}; break;
  case 'invoice_benefit_review_options': data={lines:[]}; break;
  case 'preview_invoice_correction': data={invoice_no:'INV-EDIT',status:'unpaid',effects:[],needs_review:[],blocking:false}; break;
  case 'correct_invoice': data={ok:true}; break;
  case 'create_invoice_with_details': data='inv-created'; break;
  case 'credit_packages_for_store': data=t.credit_packages; break;
  case 'premium_bundles_for_store': data=[]; break;
  case 'invoice_display_names': case 'invoice_bill_to_source': case 'customer_credit_balances': case 'invoice_therapy_summary':
  case 'invoice_event_guests': case 'legacy_qualification_diagnose': case 'my_assigned_store_id': data=null; break;
  case 'staff_may_correct_invoice': data=false; break;
 }
 const q=new Proxy({}, {get(_,key){if(key==='then')return (ok,bad)=>Promise.resolve({data,error:null}).then(ok,bad);return()=>q;}});return q;
 }};`;

const result = await build({
  stdin: { contents: `import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import InvoicesPage from './src/pages/InvoicesPage';createRoot(document.getElementById('root')).render(<BrowserRouter><InvoicesPage/></BrowserRouter>);`, resolveDir: process.cwd(), loader: 'tsx' },
  bundle: true, define: { 'import.meta.env': '{}' }, format: 'iife', write: false,
  plugins: [{ name: 'isolated-fixtures', setup(b) {
    b.onResolve({ filter: /(?:^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'fixture' }));
    b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'fixture' }));
    b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => ({ contents: a.path === 'db' ? mock
      : a.path === 'auth' ? `export const useAuth=()=>({profile:{id:'owner',full_name:'Test Owner',role:'owner'},session:{user:{id:'owner'}},assignments:[],loading:false});` : '', loader: 'js' }));
  } }],
});
const bundle = result.outputFiles[0].text;
const css = (await readFile('src/styles/globals.css', 'utf8') + '\n' + await readFile('src/components/invoices/invoice-controls.css', 'utf8')).replace(/^@import.*$/gm, '');

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => { assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`); checks++; console.log(`  ok  ${label}`); };
const same = (label, actual, expected) => { assert.deepEqual(actual, expected, label); checks++; console.log(`  ok  ${label}`); };

async function open({ width = 1280 } = {}) {
  const context = await browser.newContext({ viewport: { width, height: 1000 }, timezoneId: 'Asia/Singapore' });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/'
    ? route.fulfill({ contentType: 'text/html', body: '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>' })
    : route.abort());
  await page.goto('https://invoice.test/');
  await page.evaluate(t => { window.__tables = JSON.parse(JSON.stringify(t)); window.__calls = []; }, tables);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  await page.getByRole('button', { name: 'View', exact: true }).first().waitFor();
  return page;
}
const modal = page => page.locator('.modal').last();
const line = (page, n) => modal(page).locator('.invoice-editor-line').nth(n);
const kindOf = (page, n) => line(page, n).locator('select').first();
const lastCall = (page, name) => page.evaluate(n => window.__calls.findLast(c => c.name === n) ?? null, name);
const addLine = page => modal(page).getByRole('button', { name: 'Add Item' }).click();
async function pickCustomer(page, name) {
  await page.getByRole('button', { name: 'Search name, ID, phone or email…' }).first().click();
  await page.getByPlaceholder('Search name, ID, phone or email…').fill(name);
  await page.waitForFunction(() => !document.body.textContent.includes('Searching…'));
  const opt = page.locator('div', { hasText: new RegExp(`^${name}$`) }).last();
  await opt.waitFor(); await opt.click({ force: true });
}
// What a line's picker offers, by name; the picker is left closed.
async function listOf(page, n, placeholder) {
  await line(page, n).getByRole('button', { name: placeholder }).click();
  const text = await line(page, n).locator('xpath=.').innerText();
  await line(page, n).getByRole('button', { name: placeholder }).click().catch(() => {});
  await page.keyboard.press('Escape').catch(() => {});
  return text;
}
async function pick(page, n, placeholder, query, text) {
  const m = modal(page);
  await line(page, n).getByRole('button', { name: placeholder }).click();
  await m.getByPlaceholder(placeholder).fill(query);
  await m.getByPlaceholder(placeholder).locator('xpath=ancestor::div[3]').getByText(text).first().click();
}
const PRODUCT = 'Search product name or SKU…';
const SERVICE = 'Search service name or SKU…';

try {
  for (const width of [1280, 375]) {
    console.log(`New invoice at ${width}px`);
    const page = await open({ width });
    await page.getByRole('button', { name: 'New Invoice', exact: true }).click();
    const m = modal(page);
    await m.locator('select').filter({ has: page.locator('option[value="store"]') }).first().selectOption('store');
    await pickCustomer(page, 'Test Buyer');

    same('Items offers Service right after Product', (await kindOf(page, 0).locator('option').allTextContents()).slice(0, 3), ['Product', 'Service', 'Voucher']);
    same('a new line starts on Product', await kindOf(page, 0).inputValue(), 'product');

    const products = await listOf(page, 0, PRODUCT);
    ok('Product lists the products in stock', products.includes('Long Energia Socks') && products.includes('Partner Lotion'), products);
    ok('and no service, not even one with stock typed in', !products.includes('Home Visit') && !products.includes('Machine Repair') && !products.includes('Unpriced Fee'), products);
    ok('a product with no stock stays off, as before', !products.includes('Sold Out Mat'), products);

    await kindOf(page, 0).selectOption('service');
    same('the line now reads Service', await kindOf(page, 0).inputValue(), 'service');
    const services = await listOf(page, 0, SERVICE);
    ok('Service lists a service with no stock', services.includes('Home Visit') && services.includes('S$94.00'), services);
    ok('and one with stock typed in', services.includes('Machine Repair'), services);
    ok('and no product', !services.includes('Long Energia Socks') && !services.includes('Partner Lotion'), services);
    ok('a service with no price at this store stays off', !services.includes('Unpriced Fee'), services);

    await pick(page, 0, SERVICE, 'Visit', 'Home Visit');
    same('with a service picked it still reads Service', await kindOf(page, 0).inputValue(), 'service');
    await addLine(page);
    same('the next line starts on Product', await kindOf(page, 1).inputValue(), 'product');
    await pick(page, 1, PRODUCT, 'Socks', 'Long Energia Socks');
    same('the second reads Product', await kindOf(page, 1).inputValue(), 'product');

    // Moving a line between the two starts it empty.
    await addLine(page);
    await kindOf(page, 2).selectOption('service');
    await pick(page, 2, SERVICE, 'Repair', 'Machine Repair');
    await kindOf(page, 2).selectOption('product');
    same('from Service to Product it reads Product', await kindOf(page, 2).inputValue(), 'product');
    ok('and starts empty', await line(page, 2).getByRole('button', { name: PRODUCT }).count() === 1);
    await kindOf(page, 2).selectOption('service');
    ok('and back to Service, empty again', await line(page, 2).getByRole('button', { name: SERVICE }).count() === 1);

    await page.screenshot({ path: `${SHOTS}/service-invoice-${width}.png`, fullPage: true });
    if (width === 1280) {
      // A choice group offers the service with no stock, and the product with
      // none stays off, as before.
      await kindOf(page, 2).selectOption('promotion');
      await pick(page, 2, 'Search promotion name or code…', 'Choose', 'Choose One Deal');
      const body = await m.innerText();
      ok('a promotion\'s choice group offers the service with no stock', /Choose one[\s\S]*Home Visit/.test(body), body.slice(0, 500));
      ok('and not the product with no stock', !/Choose one[\s\S]*Sold Out Mat/.test(body));
    }
    ok('no unexpected browser errors', page.errors.length === 0, page.errors.join(' | '));
    await page.context().close();
  }

  // What goes to the server, on a form of its own.
  {
    console.log('What is sent');
    const page = await open();
    await page.getByRole('button', { name: 'New Invoice', exact: true }).click();
    const m = modal(page);
    await m.locator('select').filter({ has: page.locator('option[value="store"]') }).first().selectOption('store');
    await pickCustomer(page, 'Test Buyer');
    await kindOf(page, 0).selectOption('service');
    await pick(page, 0, SERVICE, 'Visit', 'Home Visit');
    await addLine(page);
    await pick(page, 1, PRODUCT, 'Socks', 'Long Energia Socks');
    same('the total counts the service', await page.getByTestId('invoice-preview-total').innerText(), 'Total: S$194.00');
    await m.getByRole('button', { name: 'Create Invoice', exact: true }).click();
    await page.waitForFunction(() => window.__calls.some(c => c.name === 'create_invoice_with_details'));
    const call = await lastCall(page, 'create_invoice_with_details');
    same('a service goes out as a plain product line, with nothing added', call.args.p_items, [
      { kind: 'product', product_id: 'visit', quantity: 1, invoice_item_id: null, line_voucher_id: null },
      { kind: 'product', product_id: 'socks', quantity: 1, invoice_item_id: null, line_voucher_id: null },
    ]);
    ok('no unexpected browser errors', page.errors.length === 0, page.errors.join(' | '));
    await page.context().close();
  }

  // A saved line comes back under Service.
  for (const width of [1280, 375]) {
    console.log(`Editing at ${width}px`);
    const page = await open({ width });
    await page.locator('tbody tr').filter({ has: page.getByText('INV-EDIT', { exact: true }) }).getByRole('button', { name: 'View', exact: true }).click();
    await page.getByRole('button', { name: 'Edit Invoice', exact: true }).click();
    same('the saved service reads Service', await kindOf(page, 0).inputValue(), 'service');
    ok('with its name', (await line(page, 0).innerText()).includes('Home Visit'));
    same('the saved product reads Product', await kindOf(page, 1).inputValue(), 'product');
    ok('with its name', (await line(page, 1).innerText()).includes('Long Energia Socks'));
    await page.screenshot({ path: `${SHOTS}/service-invoice-edit-${width}.png`, fullPage: true });
    ok('no unexpected browser errors', page.errors.length === 0, page.errors.join(' | '));
    await page.context().close();
  }
  console.log(`\n${checks} checks passed`);
} finally {
  await browser.close();
}
