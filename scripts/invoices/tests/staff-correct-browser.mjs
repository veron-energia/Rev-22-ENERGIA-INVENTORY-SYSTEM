// A staff member corrects a paid or part-paid invoice (377), driven as a
// person would drive the page, at phone widths (375px and 320px). Real
// components, in-memory fixtures, no network and no credentials. The Owner's
// side of the same form is in invoice-actions-browser.mjs.
//
// Prices, payment amounts and dates, removing or splitting a payment, the
// store and who raised the invoice stay with an Owner or Manager. A saved
// line's price belongs to the item it was sold as: choosing another catalogue
// item drops it, so the catalogue price is shown and sent (the server refuses
// a saved price sent with another item to anyone but an Owner or Manager).
// Choosing the item the line already has (a therapy session or a ticket
// option too) keeps its saved price, and a therapy session its quantity.
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });

const date = '2026-09-01T01:00:00Z';
// One invented event with two ticket options, both covering its two days.
const EVENT_DAYS = ['2026-09-20', '2026-09-21'];
const TICKET_OPTIONS = [['day-pass', 'Day Pass', 60], ['vip-pass', 'VIP Pass', 200]].map(([option_id, option_name, price]) => ({
  option_id, option_name, days_count: 2, price, unit_price: price, early_bird: false, early_bird_until: null,
  event_id: 'fest', event_name: 'Fixture Fest', days: EVENT_DAYS.map(day => ({ day, capacity: null, registered: 0 })) }));
const common = { is_active: true, deleted_at: null };
// Two of each kind of catalogue item, a cheap one (sold) and a dear one.
const base = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', ...common }],
  customers: [{ id: 'customer', full_name: 'Test Customer', phone: '+6591234567', ...common }],
  profiles: [{ id: 'owner', full_name: 'Test Owner', role: 'owner', ...common }],
  products: [
    { id: 'socks', name: 'Long Energia Socks', sku: 'SOCK', product_type: 'own', ...common },
    { id: 'mattress', name: 'Test Mattress', sku: 'MATT', product_type: 'own', ...common },
  ],
  store_product_prices: [
    { store_id: 'store', product_id: 'socks', selling_price: 100, member_price: 100, non_member_price: 100, availability: 'available', ...common },
    { store_id: 'store', product_id: 'mattress', selling_price: 3000, member_price: 3000, non_member_price: 3000, availability: 'available', ...common },
  ],
  store_inventory: [{ store_id: 'store', product_id: 'socks', current_qty: 100 }, { store_id: 'store', product_id: 'mattress', current_qty: 10 }],
  vouchers: [
    { id: 'gift-small', name: 'Gift Small', code: 'GS', voucher_kind: 'normal', ...common },
    { id: 'gift-large', name: 'Gift Large', code: 'GL', voucher_kind: 'normal', ...common },
  ],
  voucher_store_prices: [
    { voucher_id: 'gift-small', store_id: 'store', selling_price: 40, available_at_store: true, ...common },
    { voucher_id: 'gift-large', store_id: 'store', selling_price: 400, available_at_store: true, ...common },
  ],
  promotions: [
    { id: 'promo-small', name: 'Promo Small', code: 'PS', ...common },
    { id: 'promo-large', name: 'Promo Large', code: 'PL', ...common },
  ],
  promotion_store_prices: [
    { promotion_id: 'promo-small', store_id: 'store', selling_price: 50, available_at_store: true, ...common },
    { promotion_id: 'promo-large', store_id: 'store', selling_price: 500, available_at_store: true, ...common },
  ],
  credit_packages: [
    { id: 'credit-small', name: 'Credit Small', customer_price: 100, paid_credit_amount: 100, ...common },
    { id: 'credit-large', name: 'Credit Large', customer_price: 1000, paid_credit_amount: 1000, ...common },
  ],
  premium_bundles: [
    { id: 'bundle-small', name: 'Bundle Small', customer_payment_amount: 200, free_voucher_qty: 0, grants_reward: false, ...common },
    { id: 'bundle-large', name: 'Bundle Large', customer_payment_amount: 2000, free_voucher_qty: 0, grants_reward: false, ...common },
  ],
  special_products: [
    { id: 'chair', name: 'Test Chair', sku: 'CHR', sale_price: 500, rate_day: 20, rate_week: 100, rate_month: 0, rate_year: 0, ...common },
    { id: 'bed', name: 'Test Bed', sku: 'BED', sale_price: 5000, rate_day: 200, rate_week: 1000, rate_month: 0, rate_year: 0, ...common },
  ],
  payment_methods: [
    { id: 'cash', name: 'Cash', ...common },
    { id: 'bank', name: 'Bank Transfer', ...common },
  ],
  therapy_services: [
    { id: 'massage', name: 'Test Massage', code: 'MSG', standard_price: 80, duration_minutes: 60, ...common },
    { id: 'facial', name: 'Test Facial', code: 'FCL', standard_price: 150, duration_minutes: 60, ...common },
  ],
  therapy_service_stores: [
    { service_id: 'massage', store_id: 'store', is_available: true, price_override: null },
    { service_id: 'facial', store_id: 'store', is_available: true, price_override: null },
  ],
  invoice_promotion_selections: [], promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
};
const invoice = (over = {}) => ({
  id: 'invoice', invoice_no: 'INV-TEST', store_id: 'store', customer_id: 'customer',
  subtotal: 100, total_amount: 100, discount_total: 0, manual_discount: 0,
  created_at: date, business_date: '2026-09-01', created_by: 'owner', edit_count: 0,
  ...common, ...over,
});
const lineOf = (over = {}) => ({ id: 'line', invoice_id: 'invoice', line_kind: 'product', product_id: 'socks', quantity: 1,
  unit_price: 100, line_total: 100, topup_amount: 0, foc_quantity: 0, ...over });
const receipt = (amount) => [{ id: 'payment', invoice_id: 'invoice', payment_method_id: 'cash', amount, created_at: date, entry_kind: 'receipt' }];
const paidWith = (line) => ({
  tables: { ...base, invoices: [invoice({ status: 'paid', paid_amount: line.line_total, paid_at: date,
    subtotal: line.line_total, total_amount: line.line_total })], invoice_items: [line], invoice_payments: receipt(line.line_total) },
  financial: { total: line.line_total, net_received: line.line_total, outstanding: 0, refund_due: 0, refunded: 0, status: 'paid' },
});

const scenarios = {
  paid: paidWith(lineOf()),
  partial: {
    tables: { ...base, invoices: [invoice({ status: 'partially_paid', paid_amount: 40 })], invoice_items: [lineOf()], invoice_payments: receipt(40) },
    financial: { total: 100, net_received: 40, outstanding: 60, refund_due: 0, refunded: 0, status: 'partially_paid' },
  },
  unpaid: {
    tables: { ...base, invoices: [invoice({ status: 'unpaid', paid_amount: 0 })], invoice_items: [lineOf()], invoice_payments: [] },
    financial: { total: 100, net_received: 0, outstanding: 100, refund_due: 0, refunded: 0, status: 'unpaid' },
  },
  refunded: {
    tables: { ...base, invoices: [invoice({ status: 'refunded', paid_amount: 0, paid_at: date })], invoice_items: [lineOf()], invoice_payments: receipt(100) },
    financial: { total: 100, net_received: 0, outstanding: 0, refund_due: 0, refunded: 100, status: 'refunded' },
  },
  // 409: cancelled with S$40 still held, owed back to the customer.
  cancelled_due: {
    tables: { ...base, invoices: [invoice({ status: 'cancelled', paid_amount: 40 })], invoice_items: [lineOf()], invoice_payments: receipt(40) },
    financial: { total: 100, net_received: 40, outstanding: 0, refund_due: 40, refunded: 0, status: 'cancelled' },
    plan: { action: 'cancel', refund_due: 40, overrides_required: [], blockers: [], lines: [], sources: [] },
  },
  // 409: cancelled with S$30 still held for a session the customer had: the
  // cancellation kept it, so it is not offered as owed back.
  cancelled_used: {
    tables: { ...base, invoices: [invoice({ status: 'cancelled', paid_amount: 30 })], invoice_items: [lineOf()], invoice_payments: receipt(30) },
    financial: { total: 100, net_received: 30, outstanding: 0, refund_due: 30, refunded: 0, status: 'cancelled' },
    plan: { action: 'cancel', refund_due: 0, blockers: [], lines: [], sources: [],
      overrides_required: [{ code: 'session_used', message: 'Sessions from this purchase have been delivered.' }] },
  },
  voucher: paidWith(lineOf({ line_kind: 'voucher', product_id: null, voucher_id: 'gift-small', unit_price: 40, line_total: 40 })),
  promotion: paidWith(lineOf({ line_kind: 'promotion', product_id: null, promotion_id: 'promo-small', unit_price: 50, line_total: 50 })),
  credit_package: paidWith(lineOf({ line_kind: 'credit_package', product_id: null, credit_package_id: 'credit-small', unit_price: 100, line_total: 100 })),
  premium_bundle: paidWith(lineOf({ line_kind: 'premium_bundle', product_id: null, premium_bundle_id: 'bundle-small', unit_price: 200, line_total: 200, bundle_voucher_selection: [] })),
  special_product: paidWith(lineOf({ line_kind: 'special_product', product_id: null, special_product_id: 'chair', unit_price: 500, line_total: 500 })),
  rental: paidWith(lineOf({ line_kind: 'rental', product_id: null, special_product_id: 'chair', rental_rate_type: 'day', rental_periods: 2,
    rental_start_date: '2026-09-01', unit_price: 40, line_total: 40 })),
  // Two sessions at an older S$60.00 (S$80.00 today).
  therapy: paidWith(lineOf({ line_kind: 'therapy', product_id: null, therapy_service_id: 'massage', therapy_service_name_snapshot: 'Test Massage',
    quantity: 2, unit_price: 60, line_total: 120 })),
  // Two people at the early-bird S$30.00 (S$60.00 now) on a two-day pass.
  ticket: paidWith(lineOf({ line_kind: 'event_ticket', product_id: null, event_ticket_option_id: 'day-pass', event_days: EVENT_DAYS,
    item_name_snapshot: 'Fixture Fest — Day Pass', quantity: 2, unit_price: 30, line_total: 60 })),
};

const mock = `export const supabase={ from(table) {
 let rows=[...(window.__tables[table]||[])], one=false;
 const q=new Proxy({}, {get(_,key) {
  if(key==='then') return (ok,bad)=>Promise.resolve({data:one?(rows[0]||null):rows,error:null}).then(ok,bad);
  return (...args)=>{if(key==='eq')rows=rows.filter(r=>r[args[0]]===args[1]);if(key==='in')rows=rows.filter(r=>args[1].includes(r[args[0]]));if(key==='single'||key==='maybeSingle')one=true;return q;};
 }}); return q;
 }, rpc(name,args) {
 window.__calls.push({name,args});
 let data=[];
 if(name==='invoice_list_page'){
   const all=(window.__tables.invoices||[]).filter(i=>!i.deleted_at);
   const rows=all.map(i=>({...i,customer_name:(window.__tables.customers||[]).find(c=>c.id===i.customer_id)?.full_name??null}));
   const sum=(k)=>rows.reduce((s,i)=>s+Number(i[k]||0),0);
   data={rows,total:rows.length,pages:rows.length?1:0,summary:{matching:rows.length,total_amount:sum('total_amount'),outstanding:rows.reduce((s,i)=>s+Math.max(0,Number(i.total_amount||0)-Number(i.paid_amount||0)),0),paid:sum('paid_amount')}};
 }
 if(name==='invoice_effective_affiliate')data={found:true,has_affiliate:false};
 if(name==='customer_search')data=window.__tables.customers;
 if(name==='invoice_financial_position')data=window.__financial;
 if(name==='invoice_refund_options')data={financial:window.__financial,stock:[],benefits:[],lines:[],review_required:false,
   // 409: a payment still holding money, for Record refund paid.
   sources:Number(window.__financial?.refund_due||0)>0?[{payment_id:'payment',method:'Cash',wallet:false,remaining:Number(window.__financial.net_received)}]:[]};
 if(name==='invoice_benefit_review_options')data={lines:[]};
 if(name==='invoice_action_plan'&&window.__plan)data=window.__plan;
 if(name==='preview_invoice_correction')data={invoice_no:'INV-TEST',status:'paid',effects:[],needs_review:[],blocking:false};
 if(name==='credit_packages_for_store')data=window.__tables.credit_packages;
 if(name==='premium_bundles_for_store')data=window.__tables.premium_bundles;
 // A staff member works at the test store, and the server says whether they may correct.
 if(name==='my_assigned_stores')data=window.__role==='staff'?[{store_id:'store',store_name:'Test Store'}]:[];
 if(name==='my_assigned_store_id')data=window.__role==='staff'?'store':null;
 if(name==='staff_may_correct_invoice')data=window.__staffMayCorrect!==false;
 if(name==='event_ticket_options_for_sale')data=window.__ticketOptions;
 // The people on a saved ticket line, as the guest list keeps them.
 if(name==='invoice_event_guests'){
   const lines=(window.__tables.invoice_items||[]).filter(it=>it.invoice_id===args.p_invoice_id&&it.line_kind==='event_ticket');
   data={event:lines.length?{event_id:'fest',event_name:'Fixture Fest',source:'ticket',override:false}:null,marked_not_event:false,
     lines:lines.map(it=>({invoice_item_id:it.id,event_id:'fest',event_name:'Fixture Fest',option_id:it.event_ticket_option_id,
       option_name:window.__ticketOptions.find(o=>o.option_id===it.event_ticket_option_id)?.option_name,days_count:2,days:it.event_days,
       event_days:it.event_days,guests:Array.from({length:it.quantity},(_,n)=>({guest_id:'guest-'+n,name:'Fixture Guest '+(n+1),phone:null,customer_id:null}))}))};
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
    // The signed-in role is the check's (window.__role).
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => ({ contents: a.path === 'db' ? mock : a.path === 'auth' ? `export const useAuth=()=>{const r=window.__role||'owner';return {profile:{id:r,full_name:'Test '+r,role:r},assignments:[],loading:false};};` : '', loader: 'js' }));
  } }],
});
const bundle = result.outputFiles[0].text;
const css = await readFile('src/styles/globals.css', 'utf8') + '\n' + await readFile('src/components/invoices/invoice-controls.css', 'utf8');

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => {
  assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`);
  checks++; console.log(`  ok  ${label}`);
};

const mount = async (page, scenario, role, { staffMayCorrect = true } = {}) => {
  const s = scenarios[scenario];
  // Everything except the fixture page is refused, so nothing can reach out.
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/'
    ? route.fulfill({ contentType: 'text/html', body: '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>' })
    : route.abort());
  await page.goto('https://invoice.test/');
  await page.evaluate(([t, f, r, may, tickets, plan]) => { window.__tables = JSON.parse(JSON.stringify(t)); window.__financial = f; window.__calls = [];
    window.__role = r; window.__staffMayCorrect = may; window.__ticketOptions = tickets; window.__plan = plan; },
    [s.tables, s.financial, role, staffMayCorrect, TICKET_OPTIONS, s.plan ?? null]);
  await page.addStyleTag({ content: css.replace(/^@import.*$/gm, '') });
  await page.addScriptTag({ content: bundle });
  await page.getByRole('button', { name: 'View', exact: true }).first().click();
};
const openCorrection = async (page) => {
  await page.getByRole('button', { name: 'Correct Invoice', exact: true }).click();
  return page.locator('.modal').last();
};
// Choose another catalogue item on the line: open its selector (showing the
// current item), search, pick.
const choose = async (page, modal, current, search, target) => {
  await modal.getByRole('button', { name: current }).first().click();
  await modal.getByPlaceholder(search).fill(target);
  await page.getByText(new RegExp(target)).last().click();
};
// The same, picking the option inside the selector's own list (its search box
// is the list's first row), for items whose name shows elsewhere on the form.
const pick = async (modal, current, search, query, option) => {
  await modal.getByRole('button', { name: current }).first().click();
  const box = modal.getByPlaceholder(search);
  await box.fill(query);
  await box.locator('xpath=ancestor::div[3]').getByText(option).first().click();
};
// Save the correction with a reason, as the form asks: through the review
// where it offers one. Returns what the page sent to correct_invoice.
const save = async (page, reason) => {
  await page.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill(reason);
  const review = page.getByRole('button', { name: 'Review Changes', exact: true });
  if (await review.count()) {
    await review.click();
    await page.getByRole('button', { name: 'Save the correction', exact: true }).click();
  } else {
    await page.getByRole('button', { name: 'Save Changes', exact: true }).click();
  }
  await page.waitForFunction(() => window.__calls.some(c => c.name === 'correct_invoice'));
  return page.evaluate(() => window.__calls.findLast(c => c.name === 'correct_invoice'));
};
const sent = (save) => JSON.stringify(save?.args?.p_items ?? save?.args ?? {}).slice(0, 260);

try {
  for (const width of [375, 320]) {
    const page = await browser.newPage({ viewport: { width, height: 900 }, isMobile: true, hasTouch: true });
    page.setDefaultTimeout(8000);
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    console.log(`Width ${width}`);

    // --- what staff are offered ------------------------------------------
    await mount(page, 'paid', 'staff');
    await page.getByRole('button', { name: 'Correct Invoice', exact: true }).waitFor();
    ok('staff are offered Correct Invoice on a paid invoice of their store',
       await page.getByRole('button', { name: 'Correct Invoice', exact: true }).count() === 1);
    // 409: staff raise refunds and cancellations through the guided dialog, as a request.
    ok('beside Request refund / cancel (the guided dialog, as a request)',
       await page.getByRole('button', { name: 'Request refund / cancel', exact: true }).count() === 1);
    ok('the old Request Refund is gone',
       await page.getByRole('button', { name: 'Request Refund', exact: true }).count() === 0);
    ok('and not the Owner / Manager Refund / Cancel',
       await page.getByRole('button', { name: 'Refund / Cancel', exact: true }).count() === 0);
    ok('the page asked the server about this invoice', await page.evaluate(() =>
       window.__calls.some(c => c.name === 'staff_may_correct_invoice' && c.args.p_invoice_id === 'invoice')));
    await openCorrection(page);
    ok('the form says what stays with an Owner or Manager',
       await page.getByTestId('staff-correction-note').count() === 1);
    ok('a payment amount is read-only for staff',
       await page.getByLabel('Payment amount', { exact: true }).isDisabled());
    ok('and so is the date it was received',
       await page.getByLabel('Date received', { exact: true }).isDisabled());
    ok('there is no Remove (recorded by mistake) for staff',
       await page.getByRole('button', { name: 'Remove', exact: true }).count() === 0);
    ok('and no split across methods',
       await page.getByRole('button', { name: '+ Split across methods', exact: true }).count() === 0);
    ok('and the payment note says why', await page.getByTestId('staff-payment-note').count() === 1);
    ok('no unit price for staff', await page.getByLabel(/unit price/).count() === 0);
    ok('no Raised by for staff', await page.getByText('Raised by', { exact: true }).count() === 0);
    ok('the store stays fixed, and says who can move it',
       await page.getByTestId('staff-store-note').count() === 1);
    ok('nothing in the form is wider than the screen', await page.evaluate(() =>
       document.documentElement.scrollWidth <= window.innerWidth + 1), `${width}px`);
    // A method change is sent as a method change, never as an amount or date correction.
    await page.getByRole('button', { name: 'Payment method', exact: true }).click();
    await page.getByRole('combobox', { name: 'Search payment method' }).fill('bank');
    await page.getByRole('combobox', { name: 'Search payment method' }).press('Enter');
    const staffSave = await save(page, 'Paid by bank transfer, keyed as cash');
    const staffHeader = staffSave?.args?.p_header ?? {};
    ok('a staff method change is sent as a method change only, at the saved price and store',
       JSON.stringify(staffHeader.payment_methods) === JSON.stringify([{ payment_id: 'payment', payment_method_id: 'bank' }])
       && (staffHeader.payment_corrections ?? []).length === 0
       && (staffHeader.payment_removals ?? []).length === 0
       && staffHeader.store_id === 'store' && !('created_by' in staffHeader)
       && staffSave?.args?.p_items?.[0]?.unit_price === 100
       && staffSave?.args?.p_reason === 'Paid by bank transfer, keyed as cash',
       JSON.stringify(staffSave?.args ?? {}).slice(0, 240));

    await mount(page, 'partial', 'staff');
    await page.getByRole('button', { name: 'Correct Invoice', exact: true }).waitFor();
    ok('staff are offered Correct Invoice on a part-paid invoice',
       await page.getByRole('button', { name: 'Correct Invoice', exact: true }).count() === 1);
    ok('and can ask for a refund or cancellation of it (409; the old button could not)',
       await page.getByRole('button', { name: 'Request refund / cancel', exact: true }).count() === 1);
    // The request opens the guided dialog in request mode: it submits a
    // request and never offers to confirm anything.
    await page.getByRole('button', { name: 'Request refund / cancel', exact: true }).click();
    await page.getByRole('dialog').getByText('Cancel invoice', { exact: true }).waitFor();
    ok('the guided dialog opens for staff', await page.getByRole('dialog').getByText('Full refund', { exact: true }).count() === 1);
    ok('the old request function is never called', await page.evaluate(() =>
       !window.__calls.some(c => c.name === 'request_invoice_action')));
    ok('nothing in the dialog fits wider than the screen', await page.evaluate(() =>
       document.documentElement.scrollWidth <= window.innerWidth + 1), `${width}px`);

    // 409: an Owner sees "Record refund paid" on a cancelled invoice still
    // holding money; staff do not.
    await mount(page, 'cancelled_due', 'owner');
    await page.getByRole('button', { name: 'Record refund paid', exact: true }).waitFor();
    ok('an Owner is offered Record refund paid on a cancelled invoice with a refund due',
       await page.getByRole('button', { name: 'Record refund paid', exact: true }).count() === 1
       && await page.getByRole('button', { name: 'Refund / Cancel', exact: true }).count() === 0);
    await page.getByRole('button', { name: 'Record refund paid', exact: true }).click();
    await page.getByText('Paid back through', { exact: true }).waitFor();
    ok('it opens the form with the refund due prefilled', await page.getByLabel(/Cash · money returned/).inputValue() === '40');
    ok('and the form fits the screen', await page.evaluate(() =>
       document.documentElement.scrollWidth <= window.innerWidth + 1), `${width}px`);
    await mount(page, 'cancelled_due', 'staff');
    ok('staff are not offered Record refund paid',
       await page.getByRole('button', { name: 'Record refund paid', exact: true }).count() === 0);
    // 409 review: the S$30 held for a delivered session is not owed back.
    await mount(page, 'cancelled_used', 'owner');
    await page.getByTestId('refund-due-used').waitFor();
    ok('on a cancelled invoice whose customer had part of it, Record refund paid is not offered',
       await page.getByRole('button', { name: 'Record refund paid', exact: true }).count() === 0);
    ok('the invoice says why: what was used, and that not all of it is owed back',
       /sessions delivered/.test(await page.getByTestId('refund-due-used').textContent())
       && /Not all of it is owed back/.test(await page.getByTestId('refund-due-used').textContent()));
    ok('the page asked the cancellation\'s plan', await page.evaluate(() =>
       window.__calls.some(c => c.name === 'invoice_action_plan' && c.args.p_action === 'cancel')));
    ok('and the note fits the screen', await page.evaluate(() =>
       document.documentElement.scrollWidth <= window.innerWidth + 1), `${width}px`);
    await mount(page, 'refunded', 'owner');
    ok('nor is anyone on a refunded invoice with nothing due',
       await page.getByRole('button', { name: 'Record refund paid', exact: true }).count() === 0);

    // Where the server says no (for example a refund request is waiting), it is not offered.
    await mount(page, 'paid', 'staff', { staffMayCorrect: false });
    await page.waitForFunction(() => window.__calls.some(c => c.name === 'staff_may_correct_invoice'));
    ok('staff are not offered Correct Invoice where the server says no',
       await page.getByRole('button', { name: 'Correct Invoice', exact: true }).count() === 0);
    ok('and still have Request refund / cancel',
       await page.getByRole('button', { name: 'Request refund / cancel', exact: true }).count() === 1);

    await mount(page, 'refunded', 'staff');
    ok('staff are not offered Correct Invoice on a refunded invoice',
       await page.getByRole('button', { name: 'Correct Invoice', exact: true }).count() === 0);
    ok('nor a refund or cancellation request (nothing is left to refund)',
       await page.getByRole('button', { name: 'Request refund / cancel', exact: true }).count() === 0);
    ok('and the page did not even ask', await page.evaluate(() =>
       !window.__calls.some(c => c.name === 'staff_may_correct_invoice')));

    await mount(page, 'unpaid', 'staff');
    ok('an unpaid invoice still offers staff Edit Invoice, not Correct Invoice',
       await page.getByRole('button', { name: 'Edit Invoice', exact: true }).count() === 1
       && await page.getByRole('button', { name: 'Correct Invoice', exact: true }).count() === 0);

    // --- a saved price stays with what was sold --------------------------
    // Staff pick the mattress on the saved socks line: the form shows the
    // mattress at its catalogue price and sends no unit price.
    await mount(page, 'paid', 'staff');
    let modal = await openCorrection(page);
    await choose(page, modal, /Long Energia Socks/, 'Search product name or SKU…', 'Test Mattress');
    ok('after a swap the line shows the new item at its catalogue price',
       (await modal.innerText()).includes('S$3000.00'));
    let swap = await save(page, 'Took the mattress instead');
    let item = swap?.args?.p_items?.[0] ?? {};
    ok('a staff swap is sent without the saved price, so the server charges the catalogue price',
       item.product_id === 'mattress' && item.invoice_item_id === 'line' && !('unit_price' in item), sent(swap));

    // Choosing the saved item again brings its saved price back.
    await mount(page, 'paid', 'staff');
    modal = await openCorrection(page);
    await choose(page, modal, /Long Energia Socks/, 'Search product name or SKU…', 'Test Mattress');
    await choose(page, modal, /Test Mattress/, 'Search product name or SKU…', 'Long Energia Socks');
    swap = await save(page, 'Picked the wrong item, put it back');
    item = swap?.args?.p_items?.[0] ?? {};
    ok('choosing the saved item again sends its saved price again',
       item.product_id === 'socks' && item.unit_price === 100, sent(swap));

    // Every other selector that sets a line's price does the same.
    for (const [scenario, current, search, target, field, id] of [
      ['voucher', /Gift Small/, 'Search voucher name or code…', 'Gift Large', 'voucher_id', 'gift-large'],
      ['promotion', /Promo Small/, 'Search promotion name or code…', 'Promo Large', 'promotion_id', 'promo-large'],
      ['credit_package', /Credit Small/, 'Search Credit Package…', 'Credit Large', 'credit_package_id', 'credit-large'],
      ['premium_bundle', /Bundle Small/, 'Search Premium Bundle…', 'Bundle Large', 'premium_bundle_id', 'bundle-large'],
      ['special_product', /Test Chair/, 'Search special product…', 'Test Bed', 'special_product_id', 'bed'],
    ]) {
      await mount(page, scenario, 'staff');
      modal = await openCorrection(page);
      await choose(page, modal, current, search, target);
      swap = await save(page, `Wrong ${scenario} keyed`);
      item = swap?.args?.p_items?.[0] ?? {};
      ok(`a ${scenario.replace('_', ' ')} swap is sent without the saved price`,
         item[field] === id && item.invoice_item_id === 'line' && !('unit_price' in item), sent(swap));
    }

    // A rental kept longer is priced for its new length, not the saved one.
    await mount(page, 'rental', 'staff');
    modal = await openCorrection(page);
    const periods = modal.getByText('Periods', { exact: true }).locator('..').locator('input');
    await periods.fill('5');
    swap = await save(page, 'Kept it longer');
    item = swap?.args?.p_items?.[0] ?? {};
    ok('a rental kept longer is sent without the saved price',
       item.rental_periods === 5 && !('unit_price' in item), sent(swap));
    await mount(page, 'rental', 'staff');
    modal = await openCorrection(page);
    await modal.getByText('Rate', { exact: true }).locator('..').locator('select').selectOption('week');
    swap = await save(page, 'Weekly rate');
    item = swap?.args?.p_items?.[0] ?? {};
    ok('and so is a rental moved to another rate',
       item.rental_rate_type === 'week' && !('unit_price' in item), sent(swap));

    // --- a therapy session and a ticket option ------------------------------
    // Choosing the session the line already has keeps its saved price and
    // quantity; another session drops both (catalogue price, one session);
    // and choosing the saved one again brings them back.
    const SESSION = 'Search therapy package or session…';
    await mount(page, 'therapy', 'staff');
    modal = await openCorrection(page);
    await pick(modal, /Test Massage/, SESSION, 'Test Massage', /Test Massage — session/);
    swap = await save(page, 'Same session, checked again');
    item = swap?.args?.p_items?.[0] ?? {};
    ok('choosing the same therapy session again sends its saved price and quantity',
       item.therapy_service_id === 'massage' && item.invoice_item_id === 'line' && item.unit_price === 60 && item.quantity === 2, sent(swap));
    await mount(page, 'therapy', 'staff');
    modal = await openCorrection(page);
    await pick(modal, /Test Massage/, SESSION, 'Test Facial', /Test Facial — session/);
    swap = await save(page, 'It was a facial');
    item = swap?.args?.p_items?.[0] ?? {};
    ok('another therapy session is sent without the saved price, as one session',
       item.therapy_service_id === 'facial' && !('unit_price' in item) && item.quantity === 1, sent(swap));
    await mount(page, 'therapy', 'staff');
    modal = await openCorrection(page);
    await pick(modal, /Test Massage/, SESSION, 'Test Facial', /Test Facial — session/);
    await pick(modal, /Test Facial/, SESSION, 'Test Massage', /Test Massage — session/);
    swap = await save(page, 'Picked the wrong session, put it back');
    item = swap?.args?.p_items?.[0] ?? {};
    ok('choosing the saved session again brings back its saved price and quantity',
       item.therapy_service_id === 'massage' && item.unit_price === 60 && item.quantity === 2, sent(swap));

    const TICKET = 'Search event or ticket…';
    await mount(page, 'ticket', 'staff');
    modal = await openCorrection(page);
    await pick(modal, /Fixture Fest — Day Pass/, TICKET, 'Day Pass', /Fixture Fest — Day Pass/);
    swap = await save(page, 'Same ticket, checked again');
    item = swap?.args?.p_items?.[0] ?? {};
    ok('choosing the same ticket option again sends its saved price, people and days',
       item.event_ticket_option_id === 'day-pass' && item.invoice_item_id === 'line' && item.unit_price === 30
       && item.quantity === 2 && JSON.stringify(item.event_days) === JSON.stringify(EVENT_DAYS), sent(swap));
    await mount(page, 'ticket', 'staff');
    modal = await openCorrection(page);
    await pick(modal, /Fixture Fest — Day Pass/, TICKET, 'VIP Pass', /Fixture Fest — VIP Pass/);
    swap = await save(page, 'They bought the VIP pass');
    item = swap?.args?.p_items?.[0] ?? {};
    ok('another ticket option is sent without the saved price',
       item.event_ticket_option_id === 'vip-pass' && !('unit_price' in item) && item.quantity === 2, sent(swap));

    // --- an Owner's swap ----------------------------------------------------
    // The Owner sees the unit price emptied to the catalogue price, and may
    // still type one.
    await mount(page, 'paid', 'owner');
    modal = await openCorrection(page);
    const unit = modal.getByLabel('Line 1 unit price', { exact: true });
    ok('an Owner sees the saved unit price', await unit.inputValue() === '100');
    await unit.fill('90');
    await choose(page, modal, /Long Energia Socks/, 'Search product name or SKU…', 'Long Energia Socks');
    ok('choosing the same item again keeps a price the Owner typed', await unit.inputValue() === '90');
    await choose(page, modal, /Long Energia Socks/, 'Search product name or SKU…', 'Test Mattress');
    ok('after a swap the Owner\'s unit price is empty (the catalogue price applies)',
       await unit.inputValue() === '' && (await modal.innerText()).includes('S$3000.00'));
    await unit.fill('150');
    swap = await save(page, 'Mattress at an agreed price');
    item = swap?.args?.p_items?.[0] ?? {};
    ok('and a price the Owner types is sent', item.product_id === 'mattress' && item.unit_price === 150, sent(swap));

    ok('no unexpected browser errors', errors.length === 0, errors.join(' | '));
    await page.close();
  }
  console.log(`\n${checks} checks passed.`);
} finally {
  await browser.close();
}
