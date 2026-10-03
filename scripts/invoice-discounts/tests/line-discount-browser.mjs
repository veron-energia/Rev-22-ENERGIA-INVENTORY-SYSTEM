// One discount per invoice line (384), driven on the real invoice page as a
// person would: in-memory fixtures, no network, no credentials, every name
// and amount invented.
//
// Checks the owner's rules (3 Oct 2026) where staff meet them:
//  - each line offers only the discounts its kind may take, in one Discount
//    select that replaced "FOC:" and "Line voucher:";
//  - what the form sends: FOC keys for FOC only, one discount otherwise, a
//    reason with a manual or percentage discount;
//  - the totals shown equal what the server will save (the arithmetic is
//    pinned to the cent in scripts/ui/tests/line-discounts.test.mjs);
//  - a correction brings every saved line back as it was saved: a voucher
//    saved before categories under its category, an old line with FOC and a
//    voucher both read-only until one discount is chosen, a retired voucher as
//    "(historical)", a special or rental line's FOC (it used to be dropped);
//  - the invoice screen names each line's discount and, for staff, its
//    reason; the print, the PDF and the image name the discount and never the
//    reason;
//  - a saved line the form leaves alone is not argued with (no birthday
//    warning the server will not repeat, a Make-FOC credit package's price can
//    be corrected), exchange credit is said to go when its line changes, and a
//    free quantity stays as chosen while the quantity is retyped.
//
// Run: node scripts/invoice-discounts/tests/line-discount-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });

const common = { is_active: true, deleted_at: null };
const date = '2026-09-01T01:00:00Z';
const REASON = 'Fixture internal reason';
const tables = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', ...common }],
  customers: [
    { id: 'buyer', full_name: 'Test Buyer', phone: '+65 9123 4567', email: 'buyer@tests.invalid', date_of_birth: '1990-10-03', ...common },
    { id: 'buyer2', full_name: 'Test Buyer Two', phone: '+65 9123 4568', email: null, date_of_birth: null, ...common },
  ],
  profiles: [{ id: 'owner', full_name: 'Test Owner', role: 'owner', ...common }],
  products: [
    { id: 'socks', name: 'Long Energia Socks', sku: 'SOCK', product_type: 'own', ...common },
    { id: 'lotion', name: 'Partner Lotion', sku: 'LOTN', product_type: 'third_party', ...common },
  ],
  store_product_prices: [
    { store_id: 'store', product_id: 'socks', selling_price: 100, member_price: 100, ...common },
    { store_id: 'store', product_id: 'lotion', selling_price: 80, member_price: 80, ...common },
  ],
  store_inventory: [{ store_id: 'store', product_id: 'socks', current_qty: 100 }, { store_id: 'store', product_id: 'lotion', current_qty: 100 }],
  vouchers: [
    { id: 'v-save', name: 'Save 10%', code: 'S10', voucher_kind: 'percentage_discount', discount_percent: 10, discount_category: 'voucher', ...common },
    { id: 'v-bday', name: 'Birthday 20% (Actual Date)', code: 'BD20', voucher_kind: 'percentage_discount', discount_percent: 20,
      discount_category: 'birthday', birthday_rule: 'actual_date', ...common },
    { id: 'v-staff', name: 'Staff 10%', code: 'ST10', voucher_kind: 'percentage_discount', discount_percent: 10, discount_category: 'staff', ...common },
    // Retired: not offered any more, still on the invoices that used them.
    { id: 'v-old', name: 'Old Birthday S$5', code: 'OB5', voucher_kind: 'fixed_discount', discount_amount: 5,
      discount_category: 'birthday', birthday_rule: 'whole_month', is_active: false, deleted_at: null },
    { id: 'v-gone', name: 'Old Invoice Voucher 15%', code: 'OI15', voucher_kind: 'percentage_discount', discount_percent: 15,
      discount_category: 'voucher', is_active: false, deleted_at: null },
  ],
  therapy_services: [{ id: 'massage', name: 'Test Massage', code: 'MSG', standard_price: 80, duration_minutes: 60, ...common }],
  therapy_service_stores: [{ service_id: 'massage', store_id: 'store', is_available: true, price_override: null }],
  special_products: [{ id: 'chair', name: 'Test Chair', sku: 'CHR', sale_price: 500, rate_day: 20, rate_week: 100, rate_month: 0, rate_year: 0, ...common }],
  payment_methods: [{ id: 'cash', name: 'Cash', ...common }],
  credit_packages: [{ id: 'credit', name: 'Credit Fixture', customer_price: 100, paid_credit_amount: 100, ...common }],
  invoice_promotion_selections: [], promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
  invoice_payments: [],
};
const FOC_REASONS = [{ id: 'r-good', code: 'GOOD', label: 'Goodwill', requires_note: false, sort_order: 1 }];

const item = (invoice_id, id, over) => ({ id, invoice_id, line_kind: 'product', product_id: 'socks', quantity: 1, unit_price: 100, line_total: 100,
  topup_amount: 0, foc_quantity: 0, foc_amount: 0, line_discount: 0, line_voucher_id: null, line_discount_type: null,
  line_discount_percent: null, line_discount_reason: null, ...over });
// An unpaid invoice whose lines carry every kind of saved discount.
const editLines = [
  item('inv-edit', 'e1', { line_discount: 10, line_voucher_id: 'v-staff' }),                       // saved before 384: no type
  item('inv-edit', 'e2', { quantity: 2, line_total: 100, foc_quantity: 1, foc_amount: 100, foc_reason_id: 'r-retired',
    foc_reason: 'Saved FOC reason', line_voucher_id: 'v-save', line_discount: 10 }),               // FOC and a voucher both
  item('inv-edit', 'e3', { line_kind: 'therapy', product_id: null, therapy_service_id: 'massage', therapy_service_name_snapshot: 'Test Massage',
    unit_price: 80, line_total: 80, line_discount: 15, line_discount_type: 'manual', line_discount_reason: REASON }),
  item('inv-edit', 'e4', { line_kind: 'special_product', product_id: null, special_product_id: 'chair', unit_price: 500, line_total: 500,
    line_discount: 62.5, line_discount_type: 'percentage', line_discount_percent: 12.5, line_discount_reason: REASON }),
  item('inv-edit', 'e5', { line_discount: 5, line_voucher_id: 'v-old', line_discount_type: 'birthday' }), // a retired voucher
  item('inv-edit', 'e6', { line_kind: 'rental', product_id: null, special_product_id: 'chair', rental_rate_type: 'day', rental_periods: 2,
    rental_start_date: '2026-09-01', unit_price: 40, line_total: 0, foc_quantity: 1, foc_amount: 40, foc_reason_id: 'r-good' }),
  item('inv-edit', 'e7', {}),
  // A credit package given away with Make FOC: it takes no discount when
  // invoiced, and goes back unchanged rather than being refused.
  item('inv-edit', 'e8', { line_kind: 'credit_package', product_id: null, credit_package_id: 'credit', unit_price: 100, line_total: 0,
    foc_quantity: 1, foc_amount: 100, foc_reason_id: 'r-good', is_foc: true }),
];
// A paid invoice with a discount of each kind, to view, print and send.
const paidLines = [
  item('inv-paid', 'p1', { line_discount: 20, line_voucher_id: 'v-bday', line_discount_type: 'birthday' }),
  item('inv-paid', 'p2', { line_kind: 'therapy', product_id: null, therapy_service_id: 'massage', therapy_service_name_snapshot: 'Test Massage',
    unit_price: 80, line_total: 80, line_discount: 15, line_discount_type: 'manual', line_discount_reason: REASON }),
  item('inv-paid', 'p3', { line_kind: 'special_product', product_id: null, special_product_id: 'chair', unit_price: 500, line_total: 500,
    line_discount: 50, line_discount_type: 'percentage', line_discount_percent: 10, line_discount_reason: REASON }),
  item('inv-paid', 'p4', { line_discount: 10, line_voucher_id: 'v-staff' }),
  item('inv-paid', 'p5', { line_discount: 7 }),                                                      // exchange credit
];
// An unpaid invoice for a customer with no date of birth: exchange credit, and
// a voucher saved before 384 that is now on the Birthday list.
const oldLines = [
  item('inv-old', 'x1', { line_discount: 7 }),
  item('inv-old', 'x2', { line_discount: 20, line_voucher_id: 'v-bday' }),
];
const invoice = (id, no, over) => ({ id, invoice_no: no, store_id: 'store', customer_id: 'buyer', created_at: date, business_date: '2026-09-01',
  created_by: 'owner', edit_count: 0, manual_discount: 0, discount_voucher_id: null, ...common, ...over });
tables.invoices = [
  invoice('inv-edit', 'INV-EDIT', { status: 'unpaid', paid_amount: 0, subtotal: 980, discount_total: 234.13, total_amount: 745.87, discount_voucher_id: 'v-gone' }),
  invoice('inv-paid', 'INV-PAID', { status: 'paid', paid_amount: 698, paid_at: date, subtotal: 880, discount_total: 102, total_amount: 778 }),
  invoice('inv-old', 'INV-OLD', { customer_id: 'buyer2', status: 'unpaid', paid_amount: 0, subtotal: 200, discount_total: 27, total_amount: 173 }),
];
tables.invoice_items = [...editLines, ...paidLines, ...oldLines];
tables.invoice_payments = [{ id: 'pay', invoice_id: 'inv-paid', payment_method_id: 'cash', amount: 778, created_at: date, entry_kind: 'receipt' }];

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
  case 'active_foc_reasons': data=window.__focReasons; break;
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
const ok = (label, condition, detail = '') => {
  assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`);
  checks++; console.log(`  ok  ${label}`);
};
const same = (label, actual, expected) => { assert.deepEqual(actual, expected, label); checks++; console.log(`  ok  ${label}`); };

async function open({ width = 1280 } = {}) {
  const context = await browser.newContext({ viewport: { width, height: 1000 }, acceptDownloads: true, timezoneId: 'Asia/Singapore' });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/'
    ? route.fulfill({ contentType: 'text/html', body: '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>' })
    : route.abort());
  await page.goto('https://invoice.test/');
  await page.evaluate(([t, r]) => {
    window.__tables = JSON.parse(JSON.stringify(t)); window.__focReasons = r; window.__calls = []; window.__printed = []; window.__drawn = [];
    window.open = () => ({ closed: false, document: { body: { textContent: '' }, open() {}, write: html => window.__printed.push(html), close() {} } });
    const fill = CanvasRenderingContext2D.prototype.fillText;
    CanvasRenderingContext2D.prototype.fillText = function (text, ...rest) { window.__drawn.push(String(text)); return fill.call(this, text, ...rest); };
  }, [tables, FOC_REASONS]);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  await page.getByRole('button', { name: 'View', exact: true }).first().waitFor();
  return page;
}
const modal = page => page.locator('.modal').last();
const optionsOf = (page, label) => page.getByLabel(label, { exact: true }).locator('option').allTextContents();
const valueOf = (page, label) => page.getByLabel(label, { exact: true }).inputValue();
const lastCall = (page, name) => page.evaluate(n => window.__calls.findLast(c => c.name === n) ?? null, name);
async function pickCustomer(page, name, current = 'Search name, ID, phone or email…') {
  await page.getByRole('button', { name: current }).first().click();
  await page.getByPlaceholder('Search name, ID, phone or email…').fill(name);
  await page.waitForFunction(() => !document.body.textContent.includes('Searching…'));
  const opt = page.locator('div', { hasText: new RegExp(`^${name}$`) }).last();
  await opt.waitFor(); await opt.click({ force: true });
}
// Choose the item on line n (0-based) through its selector.
async function pickItem(page, n, placeholder, query, text) {
  const m = modal(page);
  await m.locator('.invoice-editor-line').nth(n).getByRole('button', { name: placeholder }).click();
  await m.getByPlaceholder(placeholder).fill(query);
  await m.getByPlaceholder(placeholder).locator('xpath=ancestor::div[3]').getByText(text).first().click();
}
const kindOf = (page, n) => modal(page).locator('.invoice-editor-line').nth(n).locator('select').first();
const addLine = page => modal(page).getByRole('button', { name: 'Add Item' }).click();
const viewInvoice = async (page, no) => {
  await page.locator('tbody tr').filter({ has: page.getByText(no, { exact: true }) }).getByRole('button', { name: 'View', exact: true }).click();
  await page.waitForFunction(() => { const b = [...document.querySelectorAll('.modal button')].find(x => x.textContent.trim() === 'Print'); return b && !b.disabled; });
};

const ALL = ['None', 'FOC', 'Vouchers', 'Birthday discount', 'Staff discount', 'Manual discount (S$)', 'Percentage discount (%)'];
const NO_VOUCHERS = ['None', 'FOC', 'Manual discount (S$)', 'Percentage discount (%)'];

try {
  // ── A new invoice ────────────────────────────────────────────────────────
  {
    console.log('New invoice');
    const page = await open();
    await page.getByRole('button', { name: 'New Invoice', exact: true }).click();
    const m = modal(page);
    await m.locator('select').filter({ has: page.locator('option[value="store"]') }).first().selectOption('store');
    await page.getByLabel('Invoice business date').fill('2026-10-03');
    await pickCustomer(page, 'Test Buyer');
    ok('the old "FOC:" and "Line voucher:" selects are gone', await m.getByText('Line voucher:').count() === 0 && await m.getByText('FOC:', { exact: true }).count() === 0);

    // Line 1: our own product, two of them, 10% off.
    await pickItem(page, 0, 'Search product name or SKU…', 'Socks', 'Long Energia Socks');
    same('our own product offers every discount', await optionsOf(page, 'Line 1 discount'), ALL);
    await m.getByPlaceholder('Qty').nth(0).fill('2');
    await page.getByLabel('Line 1 discount', { exact: true }).selectOption('percentage');
    await page.getByLabel('Line 1 discount percent').fill('10');
    await page.getByLabel('Line 1 discount reason').fill('Fixture reason');
    ok('a percentage shows what it takes off the line', (await m.locator('.invoice-line-discount').nth(0).innerText()).includes('− S$20.00'));

    // Line 2: a third-party product: no voucher of any category.
    await addLine(page);
    await pickItem(page, 1, 'Search product name or SKU…', 'Lotion', 'Partner Lotion');
    same('a third-party product offers FOC, manual or percentage only', await optionsOf(page, 'Line 2 discount'), NO_VOUCHERS);
    ok('and says why', (await m.locator('.invoice-line-discount').nth(1).innerText()).includes("vouchers, birthday and staff discounts don't apply"));
    await page.getByLabel('Line 2 discount', { exact: true }).selectOption('manual');
    await page.getByLabel('Line 2 discount amount').fill('81');
    await page.getByLabel('Line 2 discount reason').fill('Fixture reason');

    // Line 3: a birthday discount, checked against the customer's date of birth.
    await addLine(page);
    await pickItem(page, 2, 'Search product name or SKU…', 'Socks', 'Long Energia Socks');
    await page.getByLabel('Line 3 discount', { exact: true }).selectOption('birthday');
    same('Birthday lists the birthday vouchers only', await optionsOf(page, 'Line 3 voucher'),
      ['— Choose a voucher —', 'Birthday 20% (Actual Date) — 20% off · on the birthday']);
    await page.getByLabel('Line 3 voucher', { exact: true }).selectOption('v-bday');
    ok('on the birthday there is nothing to warn about', await page.getByTestId('birthday-discount-note').count() === 0);
    await page.getByLabel('Invoice business date').fill('2026-10-04');
    ok('the day after, the form says why it cannot apply, and still lets the server decide',
      /birthday itself \(3 October\); the invoice is dated 4 October 2026\. The server checks it again/.test(await page.getByTestId('birthday-discount-note').innerText()));
    await page.getByLabel('Invoice business date').fill('2026-10-03');
    // A customer with no date of birth on file: the form says what to add.
    await pickCustomer(page, 'Test Buyer Two', /^Test Buyer \(/);
    ok('a customer with no date of birth is told what to add',
      (await page.getByTestId('birthday-discount-note').innerText()).startsWith("Add the customer's date of birth to give a birthday discount."));
    await pickCustomer(page, 'Test Buyer', /^Test Buyer Two \(/);
    ok('and back on the birthday customer the note goes', await page.getByTestId('birthday-discount-note').count() === 0);

    // Line 4: therapy: FOC, manual or percentage.
    await addLine(page);
    await kindOf(page, 3).selectOption('therapy');
    await pickItem(page, 3, 'Search therapy package or session…', 'Massage', 'Test Massage');
    same('a therapy line offers FOC, manual or percentage', await optionsOf(page, 'Line 4 discount'), NO_VOUCHERS);
    await page.getByLabel('Line 4 discount', { exact: true }).selectOption('foc');
    ok('FOC starts with every unit free', await valueOf(page, 'Line 4 free quantity') === '1');
    await page.getByLabel('Line 4 FOC reason', { exact: true }).selectOption('r-good');

    // Line 5: a credit package takes no discount at all; a special product does.
    await addLine(page);
    await kindOf(page, 4).selectOption('credit_package');
    await pickItem(page, 4, 'Search Credit Package…', 'Credit', 'Credit Fixture');
    ok('a credit package has no Discount select', await page.getByLabel('Line 5 discount', { exact: true }).count() === 0);
    await kindOf(page, 4).selectOption('special_product');
    await pickItem(page, 4, 'Search special product…', 'Chair', 'Test Chair');
    same('a special product offers FOC, manual or percentage', await optionsOf(page, 'Line 5 discount'), NO_VOUCHERS);

    // The invoice-level manual discount and Discount Voucher still stack on top.
    await page.getByPlaceholder('0.00').last().fill('10');
    await page.locator('#manual-discount-reason').fill('Fixture invoice reason');
    await page.locator('#invoice-discount-voucher').selectOption('v-save');

    // The form refuses, naming the line, what the server would refuse.
    await m.getByRole('button', { name: 'Create Invoice', exact: true }).click();
    ok('a manual discount above the line is refused before saving',
      (await m.innerText()).includes("Line 2: The manual discount cannot be more than the line's value (S$80.00)."));
    await page.getByLabel('Line 2 discount amount').fill('5');
    await page.getByLabel('Line 1 discount reason').fill('');
    await m.getByRole('button', { name: 'Create Invoice', exact: true }).click();
    ok('so is a percentage with no reason', (await m.innerText()).includes('Line 1: Give the reason for the percentage discount. It stays internal.'));
    await page.getByLabel('Line 1 discount reason').fill('Fixture reason');
    ok('nothing was sent while the form refused', await lastCall(page, 'create_invoice_with_details') === null);

    // Subtotal 200 + 80 + 100 + 0 + 500 = 880. Lines: 20 + 5 + 20 = 45. Manual 10.
    // Voucher: (880 − 80 third-party) − 10 − 40 (the line discounts on our own
    // products; the S$5 on the third-party line is not in the base) = 750
    // → 10% = 75.00. Total 880 − 130.00.
    same('the totals are worked out as the server will', [
      await page.getByTestId('invoice-preview-subtotal').innerText(), await page.getByTestId('invoice-preview-line-discounts').innerText(),
      await page.getByTestId('invoice-preview-total').innerText()],
      ['Subtotal: S$880.00', '− line discounts S$45.00', 'Total: S$750.00']);
    ok('with the manual discount and the voucher shown', /− manual discount S\$10\.00[\s\S]*− voucher discount S\$75\.00/.test(await m.innerText()));
    await page.screenshot({ path: '.invoice-test/browser/line-discounts-new.png', fullPage: true });

    await m.getByRole('button', { name: 'Create Invoice', exact: true }).click();
    await page.waitForFunction(() => window.__calls.some(c => c.name === 'create_invoice_with_details'));
    const call = await lastCall(page, 'create_invoice_with_details');
    same('each line carries its one discount, and FOC keys only for FOC', call.args.p_items, [
      { kind: 'product', product_id: 'socks', quantity: 2, invoice_item_id: null, line_voucher_id: null,
        line_discount_type: 'percentage', line_discount_percent: 10, line_discount_reason: 'Fixture reason' },
      { kind: 'product', product_id: 'lotion', quantity: 1, invoice_item_id: null, line_voucher_id: null,
        line_discount_type: 'manual', line_discount_amount: 5, line_discount_reason: 'Fixture reason' },
      { kind: 'product', product_id: 'socks', quantity: 1, invoice_item_id: null, line_voucher_id: 'v-bday', line_discount_type: 'birthday' },
      { kind: 'therapy', therapy_package_id: null, therapy_service_id: 'massage', quantity: 1, therapy_benefit_intent: null, invoice_item_id: null,
        foc_quantity: 1, foc_reason_id: 'r-good', foc_reason: null },
      { kind: 'special_product', special_product_id: 'chair', quantity: 1, invoice_item_id: null },
    ]);
    same('the invoice-level manual discount and voucher are sent as before',
      [call.args.p_header.manual_discount, call.args.p_header.manual_discount_reason, call.args.p_header.discount_voucher_id],
      [10, 'Fixture invoice reason', 'v-save']);
    ok('no unexpected browser errors', page.errors.length === 0, page.errors.join(' | '));
    await page.context().close();
  }

  // ── Correcting an invoice: every saved line comes back as saved ──────────
  for (const width of [1280, 375]) {
    console.log(`Correction at ${width}px`);
    const page = await open({ width });
    await viewInvoice(page, 'INV-EDIT');
    // One discount per line: Make FOC only where the line has none.
    ok('Make FOC is offered only on the line with no discount', await modal(page).getByRole('button', { name: 'Make FOC' }).count() === 1);
    await page.getByRole('button', { name: 'Edit Invoice', exact: true }).click();
    const m = modal(page);
    same('a voucher saved before categories shows under its category', [await valueOf(page, 'Line 1 discount'), await valueOf(page, 'Line 1 voucher')], ['staff', 'v-staff']);
    ok('an old line with FOC and a voucher shows both, read-only, until it is changed',
      await valueOf(page, 'Line 2 discount') === 'legacy'
      && /FOC \(1 of 2 free\) and the voucher Save 10% −S\$10\.00\. Both stay as they are while this line is unchanged/.test(await page.getByTestId('legacy-line-discount').innerText()));
    same('a manual discount on a therapy line comes back with its reason',
      [await valueOf(page, 'Line 3 discount'), await valueOf(page, 'Line 3 discount amount'), await valueOf(page, 'Line 3 discount reason')], ['manual', '15.00', REASON]);
    same('a percentage on a special product comes back', [await valueOf(page, 'Line 4 discount'), await valueOf(page, 'Line 4 discount percent')], ['percentage', '12.5']);
    ok('a retired voucher stays chosen, as historical', await valueOf(page, 'Line 5 voucher') === 'v-old'
      && (await optionsOf(page, 'Line 5 voucher')).includes('Old Birthday S$5 (historical)'));
    // Born in October, invoice dated September: the server keeps this saved
    // line as it is without checking it again, so the form does not warn.
    ok('a saved birthday line left as it is carries no warning', await page.getByTestId('birthday-discount-note').count() === 0);
    same('a rental line keeps its FOC', [await valueOf(page, 'Line 6 discount'), await valueOf(page, 'Line 6 free quantity'), await valueOf(page, 'Line 6 FOC reason')], ['foc', '1', 'r-good']);
    ok('a credit package given away with Make FOC has no Discount select, and says it is kept',
      await page.getByLabel('Line 8 discount', { exact: true }).count() === 0
      && (await m.locator('.invoice-editor-line').nth(7).locator('xpath=following-sibling::*').allInnerTexts()).join(' ').includes('given with Make FOC — kept as it is'));
    ok('the invoice-level voucher no longer offered stays chosen, as historical', await page.locator('#invoice-discount-voucher').inputValue() === 'v-gone'
      && (await page.locator('#invoice-discount-voucher option').allTextContents()).includes('Old Invoice Voucher 15% (historical)'));
    // Kept lines keep their stored money: 980 subtotal, 102.50 of line discounts,
    // the 15% voucher on 877.50 = 131.63 (half up), total 745.87.
    same('kept lines are totalled from what was saved', await page.getByTestId('invoice-preview-total').innerText(), 'Total: S$745.87');
    // Switching away and back brings the saved values back, and the line stays unchanged.
    await page.getByLabel('Line 3 discount', { exact: true }).selectOption('percentage');
    await page.getByLabel('Line 3 discount', { exact: true }).selectOption('manual');
    same('switching back to the saved discount brings its values back',
      [await valueOf(page, 'Line 3 discount amount'), await valueOf(page, 'Line 3 discount reason')], ['15.00', REASON]);
    ok('nothing in the form is wider than the screen', await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), `${width}px`);
    await page.screenshot({ path: `.invoice-test/browser/line-discounts-edit-${width}.png`, fullPage: true });

    await m.getByRole('button', { name: 'Review Changes', exact: true }).click();
    await page.getByRole('button', { name: 'Save the correction', exact: true }).click();
    await page.waitForFunction(() => window.__calls.some(c => c.name === 'correct_invoice'));
    let call = await lastCall(page, 'correct_invoice');
    same('an unchanged correction sends every line back exactly as it was saved', call.args.p_items, [
      { kind: 'product', product_id: 'socks', quantity: 1, invoice_item_id: 'e1', unit_price: 100, line_voucher_id: 'v-staff' },
      { kind: 'product', product_id: 'socks', quantity: 2, invoice_item_id: 'e2', unit_price: 100, line_voucher_id: 'v-save',
        foc_quantity: 1, foc_reason_id: 'r-retired', foc_reason: 'Saved FOC reason' },
      { kind: 'therapy', therapy_package_id: null, therapy_service_id: 'massage', quantity: 1, therapy_benefit_intent: null, invoice_item_id: 'e3', unit_price: 80,
        line_discount_type: 'manual', line_discount_amount: 15, line_discount_reason: REASON },
      { kind: 'special_product', special_product_id: 'chair', quantity: 1, invoice_item_id: 'e4', unit_price: 500,
        line_discount_type: 'percentage', line_discount_percent: 12.5, line_discount_reason: REASON },
      { kind: 'product', product_id: 'socks', quantity: 1, invoice_item_id: 'e5', unit_price: 100, line_voucher_id: 'v-old', line_discount_type: 'birthday' },
      { kind: 'rental', special_product_id: 'chair', quantity: 1, rental_rate_type: 'day', rental_periods: 2, rental_start_date: '2026-09-01',
        rental_return_date: null, invoice_item_id: 'e6', unit_price: 40, foc_quantity: 1, foc_reason_id: 'r-good', foc_reason: null },
      { kind: 'product', product_id: 'socks', quantity: 1, invoice_item_id: 'e7', unit_price: 100, line_voucher_id: null },
      { kind: 'credit_package', credit_package_id: 'credit', quantity: 1, invoice_item_id: 'e8', unit_price: 100,
        foc_quantity: 1, foc_reason_id: 'r-good', foc_reason: null },
    ]);
    ok('and the invoice-level voucher', call.args.p_header.discount_voucher_id === 'v-gone');

    if (width === 1280) {
      // Changing the old FOC-and-voucher line means choosing one discount for it.
      await page.context().close();
      const p2 = await open({ width });
      await viewInvoice(p2, 'INV-EDIT');
      await p2.getByRole('button', { name: 'Edit Invoice', exact: true }).click();
      const m2 = modal(p2);
      await m2.getByPlaceholder('Qty').nth(1).fill('3');
      await m2.getByRole('button', { name: 'Review Changes', exact: true }).click();
      ok('a changed old line with FOC and a voucher must choose one',
        (await m2.innerText()).includes('Line 2: It still has both FOC and a voucher from before. Choose one discount for it.'));
      await p2.getByLabel('Line 2 discount', { exact: true }).selectOption('foc');
      ok('choosing FOC clears the voucher', await p2.getByTestId('legacy-line-discount').count() === 0);
      same('and keeps the FOC the line had (1 free, its reason and note), not every unit',
        [await valueOf(p2, 'Line 2 free quantity'), await valueOf(p2, 'Line 2 FOC reason'), await valueOf(p2, 'Line 2 FOC note')],
        ['1', 'r-retired', 'Saved FOC reason']);
      await p2.getByLabel('Line 2 discount', { exact: true }).selectOption('voucher');
      ok('choosing its voucher\'s category keeps the voucher instead', await valueOf(p2, 'Line 2 voucher') === 'v-save');
      await p2.getByLabel('Line 2 discount', { exact: true }).selectOption('foc');
      await p2.getByLabel('Line 2 FOC reason', { exact: true }).selectOption('r-good');
      await m2.getByRole('button', { name: 'Review Changes', exact: true }).click();
      await p2.getByRole('button', { name: 'Save the correction', exact: true }).click();
      await p2.waitForFunction(() => window.__calls.some(c => c.name === 'correct_invoice'));
      call = await lastCall(p2, 'correct_invoice');
      same('the line goes with FOC alone', call.args.p_items[1],
        { kind: 'product', product_id: 'socks', quantity: 3, invoice_item_id: 'e2', unit_price: 100, line_voucher_id: null,
          foc_quantity: 1, foc_reason_id: 'r-good', foc_reason: 'Saved FOC reason' });
      ok('no unexpected browser errors', p2.errors.length === 0, p2.errors.join(' | '));
      await p2.context().close();
    } else {
      ok('no unexpected browser errors', page.errors.length === 0, page.errors.join(' | '));
      await page.context().close();
    }
  }

  // ── Saved lines the form leaves to the server ────────────────────────────
  {
    console.log('Saved lines left alone');
    const page = await open();
    await viewInvoice(page, 'INV-EDIT');
    await page.getByRole('button', { name: 'Edit Invoice', exact: true }).click();
    const m = modal(page);
    // A line saved as a Birthday discount is checked again when the
    // correction moves the invoice's date (or customer), so the form warns then.
    await page.getByLabel('Invoice business date').fill('2026-11-01');
    ok('moving the invoice date brings the warning on a saved birthday line',
      /birth month \(October\); the invoice is dated 1 November 2026\. The server checks it again/.test(await page.getByTestId('birthday-discount-note').innerText()));
    await page.getByLabel('Invoice business date').fill('2026-09-01');
    ok('and moving it back takes it away', await page.getByTestId('birthday-discount-note').count() === 0);
    // The Owner corrects the price of a credit package given away with Make FOC.
    await page.getByLabel('Line 8 unit price', { exact: true }).fill('90');
    await m.getByRole('button', { name: 'Review Changes', exact: true }).click();
    ok('a Make-FOC credit package\'s price can be corrected', !/Line 8:/.test(await m.innerText()));
    await page.getByRole('button', { name: 'Save the correction', exact: true }).click();
    await page.waitForFunction(() => window.__calls.some(c => c.name === 'correct_invoice'));
    same('it goes to the server with its FOC', (await lastCall(page, 'correct_invoice')).args.p_items[7],
      { kind: 'credit_package', credit_package_id: 'credit', quantity: 1, invoice_item_id: 'e8', unit_price: 90,
        foc_quantity: 1, foc_reason_id: 'r-good', foc_reason: null });
    ok('no unexpected browser errors', page.errors.length === 0, page.errors.join(' | '));
    await page.context().close();

    const p2 = await open();
    await viewInvoice(p2, 'INV-OLD');
    await p2.getByRole('button', { name: 'Edit Invoice', exact: true }).click();
    const m2 = modal(p2);
    const discountRow = n => m2.locator('.invoice-line-discount').nth(n);
    ok('exchange credit on a line left as it is is kept', (await discountRow(0).innerText()).includes('S$7.00 from the exchange — kept as it is.'));
    ok('an old voucher now on the Birthday list, left as it is, carries no warning (no date of birth on file)',
      await valueOf(p2, 'Line 2 discount') === 'birthday' && await p2.getByTestId('birthday-discount-note').count() === 0);
    await m2.getByPlaceholder('Qty').nth(0).fill('2');
    ok('changing the exchange line says its credit goes',
      (await p2.getByTestId('exchange-credit-dropped').innerText()).includes('Changing this line drops its exchange credit of S$7.00. Undo the change to keep it.')
      && !(await discountRow(0).innerText()).includes('kept as it is'));
    await m2.getByPlaceholder('Qty').nth(0).fill('1');
    ok('undoing the change keeps it again', await p2.getByTestId('exchange-credit-dropped').count() === 0
      && (await discountRow(0).innerText()).includes('kept as it is'));
    await m2.getByPlaceholder('Qty').nth(1).fill('2');
    ok('changing the birthday line brings the warning, as the server will check it',
      (await p2.getByTestId('birthday-discount-note').innerText()).startsWith("Add the customer's date of birth to give a birthday discount."));
    ok('no unexpected browser errors', p2.errors.length === 0, p2.errors.join(' | '));
    await p2.context().close();
  }

  // ── A free quantity stays as chosen while the quantity is retyped ────────
  {
    console.log('Retyping the quantity of a FOC line');
    const page = await open();
    await page.getByRole('button', { name: 'New Invoice', exact: true }).click();
    const m = modal(page);
    await m.locator('select').filter({ has: page.locator('option[value="store"]') }).first().selectOption('store');
    await page.getByLabel('Invoice business date').fill('2026-10-03');
    await pickCustomer(page, 'Test Buyer');
    await pickItem(page, 0, 'Search product name or SKU…', 'Socks', 'Long Energia Socks');
    const qty = m.getByPlaceholder('Qty').nth(0);
    const retype = async digits => { await qty.fill(''); await qty.pressSequentially(digits); };
    const total = () => page.getByTestId('invoice-preview-total').innerText();
    await qty.fill('3');
    await page.getByLabel('Line 1 discount', { exact: true }).selectOption('foc');
    await page.getByLabel('Line 1 free quantity', { exact: true }).selectOption('1');
    await page.getByLabel('Line 1 FOC reason', { exact: true }).selectOption('r-good');
    same('1 of 3 free', [await valueOf(page, 'Line 1 free quantity'), await total()], ['1', 'Total: S$200.00']);
    await retype('4');
    same('the quantity cleared and 4 typed: still 1 free', [await valueOf(page, 'Line 1 free quantity'), await total()], ['1', 'Total: S$300.00']);
    await retype('12');
    same('12 typed digit by digit: still 1 free', [await valueOf(page, 'Line 1 free quantity'), await total()], ['1', 'Total: S$1100.00']);
    await page.getByLabel('Line 1 free quantity', { exact: true }).selectOption('12');
    await retype('5');
    same('all free stays all free', [await valueOf(page, 'Line 1 free quantity'), await total()], ['5', 'Total: S$0.00']);
    await page.getByLabel('Line 1 free quantity', { exact: true }).selectOption('2');
    await retype('1');
    ok('more free than the quantity is shown as such', await valueOf(page, 'Line 1 free quantity') === '2'
      && (await optionsOf(page, 'Line 1 free quantity')).includes('2 free — more than the quantity'));
    await m.getByRole('button', { name: 'Create Invoice', exact: true }).click();
    ok('and refused before saving', (await m.innerText()).includes('Line 1: The free quantity cannot be more than the quantity.')
      && await lastCall(page, 'create_invoice_with_details') === null);
    await retype('3');
    same('typed back up, the line is 2 of 3 free again', [await valueOf(page, 'Line 1 free quantity'), await total()], ['2', 'Total: S$100.00']);
    ok('no unexpected browser errors', page.errors.length === 0, page.errors.join(' | '));
    await page.context().close();
  }

  // ── The invoice screen, the print, the PDF and the image ─────────────────
  {
    console.log('Viewing and printing');
    const page = await open();
    await viewInvoice(page, 'INV-PAID');
    const shown = await page.getByTestId('invoice-line-discount').allInnerTexts();
    same('the invoice screen names each line\'s discount', shown.map(s => s.replace(/\s+/g, ' ').trim()), [
      '🎟 Birthday 20% (Actual Date) (birthday discount) − S$20.00',
      `Manual discount − S$15.00 · internal reason: ${REASON}`,
      `Percentage discount 10% − S$50.00 · internal reason: ${REASON}`,
      '🎟 Staff 10% (staff discount) − S$10.00',
      'Exchange credit − S$7.00',
    ]);
    ok('a reason is shown to staff beside its line', await page.getByTestId('invoice-line-discount-reason').count() === 2);
    await page.screenshot({ path: '.invoice-test/browser/line-discounts-detail.png', fullPage: true });

    await page.getByRole('button', { name: 'Print', exact: true }).click();
    await page.waitForFunction(() => window.__printed.length > 0);
    const html = await page.evaluate(() => window.__printed.at(-1));
    for (const text of ['Birthday 20% (Actual Date) −S$20.00', 'Discount −S$15.00', 'Discount 10% −S$50.00', 'Staff 10% −S$10.00']) {
      ok(`the print shows "${text}" on both copies`, html.split(text).length - 1 === 2);
    }
    ok('the print never shows a reason', !html.includes(REASON) && !html.includes('internal reason'));
    ok('nor a line for exchange credit (the totals name it)', !html.includes('−S$7.00'));

    const pdfText = bytes => Buffer.from(bytes).toString('latin1').replace(/\\([()\\])/g, '$1');
    const wait = page.waitForEvent('download');
    await page.getByRole('button', { name: 'PDF', exact: true }).click();
    const pdf = pdfText(await readFile(await (await wait).path()));
    for (const text of ['Birthday 20% (Actual Date) -S$20.00', 'Discount -S$15.00', 'Discount 10% -S$50.00', 'Staff 10% -S$10.00']) {
      ok(`the PDF shows "${text}"`, pdf.includes(text));
    }
    ok('the PDF never shows a reason', !pdf.includes(REASON));

    await page.evaluate(() => { window.__drawn = []; });
    const waitImage = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Image', exact: true }).click();
    await waitImage;
    const drawn = await page.evaluate(() => window.__drawn);
    ok('the image shows each discount', ['Discount -S$15.00', 'Discount 10% -S$50.00', 'Birthday 20% (Actual Date) -S$20.00'].every(t => drawn.includes(t)));
    ok('and never a reason', !drawn.some(t => t.includes(REASON)));
    ok('no unexpected browser errors', page.errors.length === 0, page.errors.join(' | '));
    await page.context().close();
  }
  console.log(`\n${checks} checks passed.`);
} finally {
  await browser.close();
}
