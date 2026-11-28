// A class in the invoice form (the Owner, 27 Nov 2026; migration 548): the Items dropdown has a Class category
// listing the class vouchers, and Voucher stops listing them. Like Consignment it is only the page: the saved
// line stays a voucher line, priced, paid and paying commission as before. On the real invoice page in a real
// browser: in-memory fixtures, no network, every name invented.
//
//  - the Items dropdown offers Class right after Voucher, and "Class" fits the box;
//  - Voucher lists the vouchers that are not classes (a discount voucher too), Class lists the class vouchers
//    with their price at the store, each found by name or code;
//  - the lines are saved as the voucher lines they always were (no class flag is sent);
//  - a saved class line opens under Class, a saved ordinary voucher under Voucher; changing the category clears
//    the voucher, as any change of category does;
//  - before 548 is in (no class rows, or the class table cannot be read): no Class category, and Voucher lists
//    every voucher as before.
//
// Run: node scripts/classes/tests/class-line-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });
// With SHOTS_DIR set, also save the picture made for the Owner there.
const SHOTS = process.env.SHOTS_DIR;
if (SHOTS) await mkdir(SHOTS, { recursive: true });

const common = { is_active: true, deleted_at: null };
const date = '2026-11-01T01:00:00Z';
const V = (id, name, code, price, over = {}) => ({ id, name, code, voucher_kind: 'normal', discount_amount: null, discount_percent: null, max_discount_cap: null,
  qty_type: 'unlimited', selling_price: price, valid_from: null, valid_until: null, description: null, terms: null, reward_eligible: true,
  discount_category: null, birthday_rule: null, created_at: date, ...common, ...over });
const tables = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', ...common }],
  customers: [{ id: 'buyer', full_name: 'Test Buyer', phone: '+61 2 5550 1001', email: 'buyer@tests.invalid', date_of_birth: null, ...common }],
  profiles: [{ id: 'owner', full_name: 'Test Owner', role: 'owner', ...common }],
  products: [{ id: 'socks', name: 'Long Energia Socks', sku: 'SOCK', product_type: 'own', ...common }],
  store_product_prices: [{ store_id: 'store', product_id: 'socks', selling_price: 100, member_price: 100, ...common }],
  store_inventory: [{ store_id: 'store', product_id: 'socks', current_qty: 100 }],
  vouchers: [
    V('v-found', 'Lymphatic Foundation Workshop 2027', 'EmiLymphatic', 799),
    V('v-skin', 'Korea No.1 Skin Care Workshop', 'KPopClass', 676),
    V('v-plain', 'Fixture Sleep Voucher', 'SLEEP1', 72),
    V('v-disc', 'Fixture 10 Off', 'TEN', 0, { voucher_kind: 'fixed_discount', discount_amount: 10, discount_category: 'voucher' }),
  ],
  voucher_store_prices: ['v-found', 'v-skin', 'v-plain', 'v-disc'].map((v, i) => ({ id: `vsp-${i}`, voucher_id: v, store_id: 'store',
    selling_price: { 'v-found': 799, 'v-skin': 676, 'v-plain': 72, 'v-disc': 0 }[v], available_at_store: true, deleted_at: null })),
  class_vouchers: [{ voucher_id: 'v-found' }, { voucher_id: 'v-skin' }],
  special_products: [], suppliers: [], product_suppliers: [],
  payment_methods: [{ id: 'cash', name: 'Cash', ...common }],
  credit_packages: [],
  invoice_promotion_selections: [], promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
  invoice_payments: [],
};
const item = (id, over) => ({ id, invoice_id: 'inv-edit', line_kind: 'voucher', product_id: null, quantity: 1, topup_amount: 0,
  foc_quantity: 0, foc_amount: 0, line_discount: 0, line_voucher_id: null, line_discount_type: null, line_discount_percent: null,
  line_discount_reason: null, ...over });
tables.invoices = [{ id: 'inv-edit', invoice_no: 'INV-EDIT', store_id: 'store', customer_id: 'buyer', created_at: date, business_date: '2026-11-01',
  created_by: 'owner', edit_count: 0, manual_discount: 0, discount_voucher_id: null, status: 'unpaid', paid_amount: 0,
  subtotal: 871, discount_total: 0, total_amount: 871, ...common }];
tables.invoice_items = [
  item('e1', { voucher_id: 'v-found', unit_price: 799, line_total: 799 }),
  item('e2', { voucher_id: 'v-plain', unit_price: 72, line_total: 72 }),
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
      ok(`${tag}: the Items dropdown has Class right after Voucher`, k.indexOf('Class') === k.indexOf('Voucher') + 1 && k.indexOf('Class') > 0, k.join(' | '));
      const cut = await kindOf(page, 0).evaluate(el => ['Product', 'Voucher', 'Class', 'Promotion', 'Special Product', 'Premium Bundle'].filter(label => {
        const probe = document.createElement('select'); probe.style.width = 'auto';
        probe.append(new Option(label)); el.after(probe);
        const need = probe.offsetWidth; probe.remove(); return need > el.offsetWidth; }));
      same(`${tag}: the box shows Class and the others in full`, cut, []);

      if (SHOTS && width === 1280) {
        // The item type box opened as a list (a native drop-down is not drawn in a headless picture).
        await kindOf(page, 0).evaluate(el => { el.size = el.options.length; el.style.height = 'auto'; el.style.width = '170px'; });
        await modal(page).screenshot({ path: `${SHOTS}/c-invoice-item-type-class-1280.png` });
        await kindOf(page, 0).evaluate(el => { el.size = 0; el.style.height = ''; el.style.width = '150px'; });
      }
      await kindOf(page, 0).selectOption('voucher');
      const vouchers = await listed(page, 0, 'Search voucher name or code…');
      ok(`${tag}: Voucher lists the ordinary voucher and the discount voucher`, vouchers.includes('Fixture Sleep Voucher — S$72.00') && vouchers.includes('Fixture 10 Off'), vouchers);
      ok(`${tag}: and neither class`, !vouchers.includes('Lymphatic Foundation Workshop 2027') && !vouchers.includes('Korea No.1 Skin Care Workshop'), vouchers);

      await kindOf(page, 0).selectOption('class');
      ok(`${tag}: chosen, the category reads Class`, await kindOf(page, 0).inputValue() === 'class'
        && await kindOf(page, 0).evaluate(el => el.options[el.selectedIndex].text) === 'Class');
      const classes = await listed(page, 0, 'Search class name or code…');
      ok(`${tag}: Class lists both classes with their price at the store`,
        classes.includes('Lymphatic Foundation Workshop 2027 — S$799.00') && classes.includes('Korea No.1 Skin Care Workshop — S$676.00'), classes);
      ok(`${tag}: and not the ordinary vouchers`, !classes.includes('Fixture Sleep Voucher') && !classes.includes('Fixture 10 Off'), classes);
      const byCode = await listed(page, 0, 'Search class name or code…', 'KPop');
      ok(`${tag}: a class is found by its code`, byCode.includes('Korea No.1 Skin Care Workshop') && !byCode.includes('Foundation'), byCode);

      await pick(page, 0, 'Search class name or code…', 'Skin', 'Korea No.1 Skin Care Workshop — S$676.00');
      ok(`${tag}: picked, the line stays under Class`, await kindOf(page, 0).inputValue() === 'class');
      await line(page, 0).getByPlaceholder('Qty').fill('2');
      ok(`${tag}: the total is two seats, S$1352.00`, (await line(page, 0).innerText()).includes('S$1352.00'), await line(page, 0).innerText());
      await m.getByRole('button', { name: 'Add Item' }).click();
      await kindOf(page, 1).selectOption('voucher');
      await pick(page, 1, 'Search voucher name or code…', 'Sleep', 'Fixture Sleep Voucher — S$72.00');
      await page.screenshot({ path: `.invoice-test/browser/class-line-${width}.png`, fullPage: true });

      await m.getByRole('button', { name: 'Create Invoice', exact: true }).click();
      await page.waitForFunction(() => window.__calls.some(c => c.name === 'create_invoice_with_details'));
      const call = await page.evaluate(() => window.__calls.findLast(c => c.name === 'create_invoice_with_details'));
      same(`${tag}: both lines are saved as the voucher lines they always were`, call.args.p_items, [
        { kind: 'voucher', voucher_id: 'v-skin', quantity: 2, invoice_item_id: null },
        { kind: 'voucher', voucher_id: 'v-plain', quantity: 1, invoice_item_id: null },
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
      same(`${tag}: a saved class line opens under Class, the ordinary voucher under Voucher`,
        [await kindOf(page, 0).inputValue(), await kindOf(page, 1).inputValue()], ['class', 'voucher']);
      ok(`${tag}: with its class shown`, await line(page, 0).getByRole('button', { name: /Lymphatic Foundation Workshop 2027 — S\$799\.00/ }).count() === 1);
      await kindOf(page, 0).selectOption('voucher');
      ok(`${tag}: another category clears the voucher, as any change of category does`,
        await line(page, 0).getByRole('button', { name: 'Search voucher name or code…' }).count() === 1);
      ok(`${tag}: no page errors when editing`, page.errors.length === 0, page.errors.join(' | '));
      await page.context().close();
    }
  }
  // ── Before 548: no class rows, or no class table ──────────────────────────
  for (const [what, set] of [['no class rows', t => { t.class_vouchers = []; }], ['no class table', t => { delete t.class_vouchers; }]]) {
    const saved = JSON.parse(JSON.stringify(tables));
    set(tables);
    const page = await open({ width: 1280 });
    await page.getByRole('button', { name: 'New Invoice', exact: true }).click();
    const m = modal(page);
    await m.locator('select').filter({ has: page.locator('option[value="store"]') }).first().selectOption('store');
    await pickCustomer(page, 'Test Buyer');
    const k = await kinds(page, 0);
    ok(`before 548 (${what}): no Class category`, !k.includes('Class'), k.join(' | '));
    await kindOf(page, 0).selectOption('voucher');
    const vouchers = await listed(page, 0, 'Search voucher name or code…');
    ok(`before 548 (${what}): Voucher lists every voucher as before`, vouchers.includes('Lymphatic Foundation Workshop 2027') && vouchers.includes('Fixture Sleep Voucher'), vouchers);
    await page.context().close();
    Object.assign(tables, saved);
  }
  console.log(`PASS: ${checks} checks`);
} finally {
  await browser.close();
}
