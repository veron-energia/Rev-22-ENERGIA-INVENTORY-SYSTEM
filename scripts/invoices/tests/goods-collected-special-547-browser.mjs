// 547 (the Owner, 27 Nov 2026): special, consignment and rental items on an invoice's Goods
// collected, on the real Invoices page in a real browser: in-memory fixtures, no network, every
// name invented. A PAID invoice with a massage chair (to collect), a consignment bed (delivered)
// and a rented lamp (collected):
//  - the invoice shows the special lines (Collected, Delivered, To collect) (answers 1, 4, 5, 6);
//  - "Record items collected" (not "Hand over items": nothing else can be handed over once paid)
//    offers the chair, with Collected / Delivered only on a consignment line, and sends it;
//  - an Owner sees "Record items returned", with a Returned box for each item out;
//  - the printed copy lists Collected / Delivered / To collect, and its terms do not say
//    "checked and collected" while something is still to collect;
//  - at 375 px nothing runs off the page.
//
// Run: node scripts/invoices/tests/goods-collected-special-547-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });

const common = { is_active: true, deleted_at: null };
const date = '2026-11-20T01:00:00Z';
const SP = { description: null, rate_day: 0, rate_week: 0, rate_month: 100, rate_year: 0, late_fee_per_day: 0, is_consignment: false, ...common };
const tables = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', ...common }],
  customers: [{ id: 'buyer', full_name: 'Test Buyer', phone: '+61 2 5550 1001', email: 'buyer@tests.invalid', date_of_birth: null, ...common }],
  profiles: [{ id: 'owner', full_name: 'Test Owner', role: 'owner', ...common }],
  products: [], store_product_prices: [], store_inventory: [], vouchers: [],
  special_products: [
    { ...SP, id: 'chair', product_id: 'p-chair', name: 'Test Massage Chair', sku: 'CHR', sale_price: 1000 },
    { ...SP, id: 'bed', product_id: 'p-bed', name: 'Test Air Bed', sku: 'BED', sale_price: 900, is_consignment: true },
    { ...SP, id: 'lamp', product_id: 'p-lamp', name: 'Test Heat Lamp', sku: 'LMP', sale_price: 300 },
  ],
  suppliers: [], product_suppliers: [],
  payment_methods: [{ id: 'cash', name: 'Cash', ...common }],
  credit_packages: [], invoice_promotion_selections: [], promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
  invoice_payments: [{ id: 'pay1', invoice_id: 'inv', payment_method_id: 'cash', amount: 2000, paid_at: date, created_at: date, entry_kind: 'payment' }],
};
const item = (id, over) => ({ id, invoice_id: 'inv', product_id: null, quantity: 1, topup_amount: 0, foc_quantity: 0, foc_amount: 0,
  line_discount: 0, line_voucher_id: null, line_discount_type: null, line_discount_percent: null, line_discount_reason: null, ...over });
tables.invoices = [{ id: 'inv', invoice_no: 'INV-2026-9301', store_id: 'store', customer_id: 'buyer', created_at: date, business_date: '2026-11-20',
  created_by: 'owner', edit_count: 0, manual_discount: 0, discount_voucher_id: null, status: 'paid', paid_amount: 2000, paid_at: date, locked_at: date,
  subtotal: 2000, discount_total: 0, total_amount: 2000, ...common }];
tables.invoice_items = [
  item('l-chair', { line_kind: 'special_product', special_product_id: 'chair', unit_price: 1000, line_total: 1000 }),
  item('l-bed', { line_kind: 'special_product', special_product_id: 'bed', unit_price: 900, line_total: 900 }),
  item('l-lamp', { line_kind: 'rental', special_product_id: 'lamp', unit_price: 100, line_total: 100, rental_rate_type: 'month', rental_periods: 1, rental_start_date: '2026-11-20' }),
];
const sp = o => ({ line_kind: 'special_product', special_product_id: null, is_consignment: false, can_deliver: false, quantity: 1,
  collected: 0, delivered: 0, out: 0, to_collect: 0, ...o });
const GOODS = {
  invoice_id: 'inv', invoice_no: 'INV-2026-9301', status: 'paid', store_id: 'store', store_name: 'Test Store', open: false,
  fulfil_from_warehouse: false, required_total: 0, collected_total: 0, to_collect_total: 0, out_total: 0,
  can_hand_over: false, can_record_return: false, products: [], history: [
    { id: 'h1', kind: 'handover', source: 'button', created_at: date, created_by_name: 'Test Owner', reason: null, items: [
      { invoice_item_id: 'l-bed', name: 'Test Air Bed', quantity: 1, how: 'delivered', special: true },
      { invoice_item_id: 'l-lamp', name: 'Test Heat Lamp (rental)', quantity: 1, how: 'collected', special: true }] }],
  specials: [
    sp({ invoice_item_id: 'l-bed', name: 'Test Air Bed', is_consignment: true, can_deliver: true, delivered: 1, out: 1 }),
    sp({ invoice_item_id: 'l-lamp', line_kind: 'rental', name: 'Test Heat Lamp (rental)', collected: 1, out: 1 }),
    sp({ invoice_item_id: 'l-chair', name: 'Test Massage Chair with a rather long name for a phone', to_collect: 1 }),
  ],
  special_collected_total: 1, special_delivered_total: 1, special_out_total: 2, special_to_collect_total: 1,
  can_collect_special: true, can_record_special_return: true,
};

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
  case 'invoice_goods_status': data=window.__goods; break;
  case 'invoice_list_goods_out': data=[]; break;
  case 'record_invoice_handover': data={success:true,items:[],specials:[{name:'Test Massage Chair with a rather long name for a phone',quantity:1,how:'collected'}]}; break;
  case 'record_invoice_goods_return': data={success:true}; break;
  case 'active_foc_reasons': data=[]; break;
  case 'invoice_financial_position': data=fin(find(args.p_invoice_id)); break;
  case 'invoice_refund_options': data={financial:fin(find(args.p_invoice_id)),sources:[],stock:[],benefits:[],lines:[],review_required:false}; break;
  case 'invoice_effective_affiliate': data={found:true,has_affiliate:false}; break;
  case 'invoice_benefit_review_options': data={lines:[]}; break;
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

async function open(width) {
  const context = await browser.newContext({ viewport: { width, height: 900 }, timezoneId: 'Asia/Singapore' });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/'
    ? route.fulfill({ contentType: 'text/html', body: '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>' })
    : route.abort());
  await page.goto('https://invoice.test/');
  await page.evaluate(([t, g]) => { window.__tables = JSON.parse(JSON.stringify(t)); window.__goods = g; window.__calls = []; }, [tables, GOODS]);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  await page.getByRole('button', { name: 'View', exact: true }).first().click();
  await page.locator('[data-testid="invoice-goods"]').waitFor();
  return page;
}
const noSideScroll = page => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);

for (const width of [1280, 375]) {
  const page = await open(width);
  const panel = page.locator('[data-testid="invoice-goods"]');
  const text = await panel.innerText();
  ok(`${width} px: the paid invoice shows its special lines`, /Test Air Bed/.test(text) && /Test Heat Lamp \(rental\)/.test(text) && /Test Massage Chair/.test(text));
  ok(`${width} px: Collected, Delivered and To collect`, /Goods — 1 collected, 1 delivered, 1 to collect/.test(text) && /Delivered/.test(text), text.slice(0, 200));
  ok(`${width} px: the history says Collected and Delivered, recorded with Record items collected`,
    /Collected Test Heat Lamp \(rental\) × 1; Delivered Test Air Bed × 1 \(Record items collected\)/.test(text) && !/Handed over/.test(text), text);
  ok(`${width} px: the Owner can record items returned`, await panel.getByRole('button', { name: 'Record items returned' }).isVisible());
  const btn = page.getByRole('button', { name: 'Record items collected' });
  ok(`${width} px: "Record items collected", not "Hand over items"`, await btn.isVisible() && !(await page.getByRole('button', { name: 'Hand over items' }).count()));
  ok(`${width} px: nothing runs off the page`, await noSideScroll(page));
  await btn.click();
  const m = page.locator('.modal').last();
  await m.locator('[data-testid="handover-special"]').first().waitFor();
  ok(`${width} px: the window offers only the chair still to collect`, await m.locator('[data-testid="handover-special"]').count() === 1);
  ok(`${width} px: no Collected / Delivered choice for a special product that is not consignment`, await m.locator('select').count() === 0);
  ok(`${width} px: nothing entered: "Enter how many the customer takes now." under the line, "Enter at least one item." above Record`,
    (await m.locator('[data-testid="handover-hint"]').innerText()) === 'Enter how many the customer takes now.'
    && (await m.locator('[data-testid="handover-need-one"]').innerText()) === 'Enter at least one item.');
  ok(`${width} px: the window does not run off the page`, await noSideScroll(page));
  await m.getByLabel('Test Massage Chair with a rather long name for a phone: how many taken now').fill('1');
  await m.getByRole('button', { name: 'Record', exact: true }).click();
  await page.locator('[data-testid="invoice-goods-note"]').waitFor();
  const call = await page.evaluate(() => window.__calls.find(c => c.name === 'record_invoice_handover'));
  ok(`${width} px: it sends the chair as collected`, JSON.stringify(call?.args?.p_handover) === JSON.stringify({ items: [], specials: [{ invoice_item_id: 'l-chair', qty: 1, how: 'collected' }] }), JSON.stringify(call?.args));
  ok(`${width} px: and says so`, /Recorded: Test Massage Chair with a rather long name for a phone × 1 collected\./.test(await page.locator('[data-testid="invoice-goods-note"]').innerText()));
  await panel.getByRole('button', { name: 'Record items returned' }).click();
  const r = page.locator('.modal').last();
  await r.locator('[data-testid="return-special"]').first().waitFor();
  ok(`${width} px: Record items returned has a Returned box for the bed and the lamp`, await r.locator('[data-testid="return-special"]').count() === 2);
  ok(`${width} px: the returns window does not run off the page`, await noSideScroll(page));
  await r.getByRole('button', { name: 'Cancel' }).click();
  ok(`${width} px: no page errors`, page.errors.length === 0, page.errors.join('; '));
  await page.context().close();
}

// The printed copy (the page's own print window).
{
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/'
    ? route.fulfill({ contentType: 'text/html', body: '<html><body><div id="root"></div></body></html>' }) : route.abort());
  await page.goto('https://invoice.test/');
  await page.evaluate(([t, g]) => { window.__tables = JSON.parse(JSON.stringify(t)); window.__goods = g; window.__calls = []; }, [tables, GOODS]);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  await page.getByRole('button', { name: 'View', exact: true }).first().click();
  await page.locator('[data-testid="invoice-goods"]').waitFor();
  const [popup] = await Promise.all([page.waitForEvent('popup'), page.getByRole('button', { name: /^Print/ }).first().click()]);
  await popup.waitForLoadState();
  await popup.locator('[data-testid="print-goods"]').first().waitFor();
  const goods = await popup.locator('[data-testid="print-goods"]').first().innerText();
  ok('print: Collected / Delivered / To collect on a paid invoice', /Collected: Test Heat Lamp \(rental\) × 1/.test(goods) && /Delivered: Test Air Bed × 1/.test(goods)
    && /To collect: Test Massage Chair/.test(goods), goods);
  const body = (await popup.content()).toUpperCase();
  ok('print: its terms do not say "checked and collected" while something is to collect', !body.includes('CHECKED AND COLLECTED'));
  await context.close();
}

await browser.close();
console.log(`\n${checks} checks passed.`);
