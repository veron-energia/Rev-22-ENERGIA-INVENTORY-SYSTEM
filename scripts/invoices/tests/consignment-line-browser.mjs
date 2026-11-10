// Consignment products in the invoice form (the user, 10 Nov 2026: "For consignment
// products, instead of them being in the Special Product, I would like them as a
// consignment Product for the invoice creation"), on the real invoice page in a
// real browser: in-memory fixtures, no network, every name invented.
//
//  - the Items dropdown offers Consignment right after Special Product ("Consignment",
//    the user's choice: "Consignment Product" does not fit the box on a phone);
//  - Special Product lists the special products not in consignment, Consignment
//    the others, each with its supplier ("Rentals: Yes, keep them" and
//    "Show the supplier", the user's answers), found by the supplier too, and a
//    product with no supplier says so; a product with no sale price is in
//    neither, as before;
//  - Rental lists every special product that rents, consignment or not;
//  - the line is saved as the special product line it always was;
//  - a saved line of a consignment product opens under Consignment, and
//    changing its category clears the product, as any change of category does.
//
// Run: node scripts/invoices/tests/consignment-line-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });

const common = { is_active: true, deleted_at: null };
const date = '2026-11-01T01:00:00Z';
const SP = { description: null, rate_day: 0, rate_week: 0, rate_month: 0, rate_year: 0, late_fee_per_day: 0, is_consignment: false, ...common };
const tables = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', ...common }],
  customers: [{ id: 'buyer', full_name: 'Test Buyer', phone: '+61 2 5550 1001', email: 'buyer@tests.invalid', date_of_birth: null, ...common }],
  profiles: [{ id: 'owner', full_name: 'Test Owner', role: 'owner', ...common }],
  products: [{ id: 'socks', name: 'Long Energia Socks', sku: 'SOCK', product_type: 'own', ...common }],
  store_product_prices: [{ store_id: 'store', product_id: 'socks', selling_price: 100, member_price: 100, ...common }],
  store_inventory: [{ store_id: 'store', product_id: 'socks', current_qty: 100 }],
  vouchers: [],
  special_products: [
    { ...SP, id: 'chair', product_id: 'p-chair', name: 'Test Chair', sku: 'CHR', sale_price: 500, rate_day: 20 },
    { ...SP, id: 'bed', product_id: 'p-bed', name: 'Fixture Bed', sku: 'BED', sale_price: 900, is_consignment: true },
    { ...SP, id: 'lamp', product_id: 'p-lamp', name: 'Fixture Lamp', sku: 'LMP', sale_price: 300, rate_day: 15, is_consignment: true },
    { ...SP, id: 'kit', product_id: 'p-kit', name: 'Fixture Kit', sku: 'KIT', sale_price: 200, is_consignment: true },
    { ...SP, id: 'rentonly', product_id: 'p-rent', name: 'Fixture Rent Only', sku: 'RNT', sale_price: 0, rate_week: 50, is_consignment: true },
  ],
  suppliers: [
    { id: 'sup-b', name: 'Fixture Supplier B', phone: null, ...common },
    { id: 'sup-a', name: 'Fixture Supplier A', phone: null, ...common },
    { id: 'sup-off', name: 'Fixture Supplier Off', phone: null, is_active: false, deleted_at: null },
    { id: 'sup-gone', name: 'Fixture Supplier Gone', phone: null, is_active: true, deleted_at: '2026-10-01T00:00:00Z' },
  ],
  product_suppliers: [
    { product_id: 'p-bed', supplier_id: 'sup-b' }, { product_id: 'p-bed', supplier_id: 'sup-a' },
    { product_id: 'p-bed', supplier_id: 'sup-off' }, { product_id: 'p-bed', supplier_id: 'sup-gone' },
    { product_id: 'p-lamp', supplier_id: 'sup-a' },
  ],
  payment_methods: [{ id: 'cash', name: 'Cash', ...common }],
  credit_packages: [],
  invoice_promotion_selections: [], promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
  invoice_payments: [],
};
const item = (id, over) => ({ id, invoice_id: 'inv-edit', line_kind: 'special_product', product_id: null, quantity: 1, topup_amount: 0,
  foc_quantity: 0, foc_amount: 0, line_discount: 0, line_voucher_id: null, line_discount_type: null, line_discount_percent: null,
  line_discount_reason: null, ...over });
tables.invoices = [{ id: 'inv-edit', invoice_no: 'INV-EDIT', store_id: 'store', customer_id: 'buyer', created_at: date, business_date: '2026-11-01',
  created_by: 'owner', edit_count: 0, manual_discount: 0, discount_voucher_id: null, status: 'unpaid', paid_amount: 0,
  subtotal: 1400, discount_total: 0, total_amount: 1400, ...common }];
tables.invoice_items = [
  item('e1', { special_product_id: 'bed', unit_price: 900, line_total: 900 }),
  item('e2', { special_product_id: 'chair', unit_price: 500, line_total: 500 }),
];

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
  case 'credit_packages_for_store': data=[]; break;
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
const kinds = async (page, n) => (await kindOf(page, n).locator('option').allTextContents()).map(t => t.trim());
// The choices a line's item selector offers, as text, after typing a search.
async function listed(page, n, placeholder, query = '') {
  await line(page, n).getByRole('button', { name: placeholder }).click();
  const input = modal(page).getByPlaceholder(placeholder);
  await input.fill(query);
  await page.waitForTimeout(150);
  const text = (await input.locator('xpath=ancestor::div[3]').innerText()).replace(/\s+/g, ' ');
  await modal(page).locator('h3').first().click();
  await page.waitForTimeout(100);
  return text;
}
async function pick(page, n, placeholder, query, text) {
  await line(page, n).getByRole('button', { name: placeholder }).click();
  await modal(page).getByPlaceholder(placeholder).fill(query);
  await modal(page).getByPlaceholder(placeholder).locator('xpath=ancestor::div[3]').getByText(text).first().click();
}
async function pickCustomer(page, name) {
  await page.getByRole('button', { name: 'Search name, ID, phone or email…' }).first().click();
  await page.getByPlaceholder('Search name, ID, phone or email…').fill(name);
  await page.waitForFunction(() => !document.body.textContent.includes('Searching…'));
  const opt = page.locator('div', { hasText: new RegExp(`^${name}$`) }).last();
  await opt.waitFor(); await opt.click({ force: true });
}

try {
  for (const width of [1280, 375]) {
    const tag = `${width} px`;
    // ── A new invoice ──────────────────────────────────────────────────────
    {
      const page = await open({ width });
      await page.getByRole('button', { name: 'New Invoice', exact: true }).click();
      const m = modal(page);
      await m.locator('select').filter({ has: page.locator('option[value="store"]') }).first().selectOption('store');
      await pickCustomer(page, 'Test Buyer');
      const k = await kinds(page, 0);
      ok(`${tag}: the Items dropdown has Consignment right after Special Product, then Rental`,
        k.indexOf('Consignment') === k.indexOf('Special Product') + 1 && k.indexOf('Rental') === k.indexOf('Consignment') + 1, k.join(' | '));
      ok(`${tag}: the box shows the whole of "Consignment"`, await kindOf(page, 0).evaluate(el => {
        const probe = document.createElement('select'); probe.style.width = 'auto';
        probe.append(new Option('Consignment')); el.after(probe);
        const need = probe.offsetWidth; probe.remove(); return need <= el.offsetWidth; }));

      await kindOf(page, 0).selectOption('special_product');
      const special = await listed(page, 0, 'Search special product…');
      ok(`${tag}: Special Product lists the special products not in consignment`, special.includes('Test Chair — S$500.00'), special);
      ok(`${tag}: and none in consignment`, !/Fixture (Bed|Lamp|Kit|Rent Only)/.test(special), special);

      await kindOf(page, 0).selectOption('consignment');
      ok(`${tag}: chosen, the category reads Consignment`, await kindOf(page, 0).inputValue() === 'consignment'
        && await kindOf(page, 0).evaluate(el => el.options[el.selectedIndex].text) === 'Consignment');
      const cons = await listed(page, 0, 'Search consignment product…');
      ok(`${tag}: Consignment lists the consignment products with a sale price`,
        ['Fixture Bed — S$900.00', 'Fixture Lamp — S$300.00', 'Fixture Kit — S$200.00'].every(s => cons.includes(s)), cons);
      ok(`${tag}: and not the others, nor one with no sale price`, !cons.includes('Test Chair') && !cons.includes('Fixture Rent Only'), cons);
      ok(`${tag}: each with its supplier: in use, by name`, cons.includes('BED · Supplier: Fixture Supplier A, Fixture Supplier B') && cons.includes('LMP · Supplier: Fixture Supplier A'), cons);
      ok(`${tag}: never one closed or deleted`, !/Supplier (Off|Gone)/.test(cons), cons);
      ok(`${tag}: and a product with no supplier says so`, cons.includes('KIT · No supplier linked yet'), cons);
      const bySupplier = await listed(page, 0, 'Search consignment product…', 'Supplier B');
      ok(`${tag}: a consignment product is found by its supplier`, bySupplier.includes('Fixture Bed') && !bySupplier.includes('Fixture Lamp'), bySupplier);

      await pick(page, 0, 'Search consignment product…', 'Bed', 'Fixture Bed — S$900.00');
      ok(`${tag}: picked, the line stays under Consignment`, await kindOf(page, 0).inputValue() === 'consignment');
      await page.screenshot({ path: `.invoice-test/browser/consignment-line-${width}.png`, fullPage: true });

      await m.getByRole('button', { name: 'Add Item' }).click();
      await kindOf(page, 1).selectOption('rental');
      const rental = await listed(page, 1, 'Search special product…');
      ok(`${tag}: Rental still lists every special product that rents, consignment or not`,
        rental.includes('Test Chair') && rental.includes('Fixture Lamp') && rental.includes('Fixture Rent Only') && !rental.includes('Fixture Bed'), rental);
      await kindOf(page, 1).selectOption('special_product');
      await pick(page, 1, 'Search special product…', 'Chair', 'Test Chair — S$500.00');

      await m.getByRole('button', { name: 'Create Invoice', exact: true }).click();
      await page.waitForFunction(() => window.__calls.some(c => c.name === 'create_invoice_with_details'));
      const call = await page.evaluate(() => window.__calls.findLast(c => c.name === 'create_invoice_with_details'));
      same(`${tag}: both lines are saved as the special product lines they always were`, call.args.p_items, [
        { kind: 'special_product', special_product_id: 'bed', quantity: 1, invoice_item_id: null },
        { kind: 'special_product', special_product_id: 'chair', quantity: 1, invoice_item_id: null },
      ]);
      ok(`${tag}: no page errors`, page.errors.length === 0, page.errors.join(' | '));
      await page.context().close();
    }
    // ── A saved invoice, edited ────────────────────────────────────────────
    {
      const page = await open({ width });
      await page.locator('tbody tr').filter({ has: page.getByText('INV-EDIT', { exact: true }) }).getByRole('button', { name: 'View', exact: true }).click();
      await page.getByRole('button', { name: 'Edit Invoice', exact: true }).click();
      await line(page, 1).waitFor();
      same(`${tag}: a saved consignment line opens under Consignment, the other under Special Product`,
        [await kindOf(page, 0).inputValue(), await kindOf(page, 1).inputValue()], ['consignment', 'special_product']);
      ok(`${tag}: with its product shown`, await line(page, 0).getByRole('button', { name: /Fixture Bed — S\$900\.00/ }).count() === 1);
      await kindOf(page, 0).selectOption('special_product');
      ok(`${tag}: another category clears the product, as any change of category does`,
        await line(page, 0).getByRole('button', { name: 'Search special product…' }).count() === 1);
      ok(`${tag}: no page errors when editing`, page.errors.length === 0, page.errors.join(' | '));
      await page.context().close();
    }
  }
  console.log(`PASS: ${checks} checks`);
} finally {
  await browser.close();
}
