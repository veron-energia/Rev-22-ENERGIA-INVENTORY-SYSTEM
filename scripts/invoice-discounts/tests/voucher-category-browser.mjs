// The Vouchers page side of one discount per invoice line (384), driven on the
// real page as the Owner would: in-memory fixtures, no network, no
// credentials, every name and amount invented.
//
// Checks the owner's rules (3 Oct 2026) where the Owner meets them:
//  - a discount voucher is offered on an invoice line as a Voucher, a Birthday
//    discount or a Staff discount, which the Owner sets here; a sellable
//    (normal) voucher has no category;
//  - a Birthday voucher also says when it applies: on the birthday itself or
//    anywhere in the birth month, and cannot be saved without it;
//  - a discount voucher saved before 384 (no category) shows as a Voucher;
//  - the voucher kinds no longer use the name of the line's "Percentage
//    discount" option.
//
// Run: node scripts/invoice-discounts/tests/voucher-category-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const common = { is_active: true, deleted_at: null, qty_type: 'unlimited', selling_price: 0, valid_from: null, valid_until: null,
  description: null, terms: null, created_at: '2026-09-01T01:00:00Z' };
const tables = {
  vouchers: [
    { id: 'v-gift', name: 'Gift Card S$50', code: 'GIFT50', voucher_kind: 'normal', discount_amount: null, discount_percent: null,
      max_discount_cap: null, discount_category: null, birthday_rule: null, ...common, selling_price: 50 },
    { id: 'v-bday', name: 'Birthday 20% (Actual Date)', code: 'BD20', voucher_kind: 'percentage_discount', discount_amount: null,
      discount_percent: 20, max_discount_cap: null, discount_category: 'birthday', birthday_rule: 'actual_date', ...common },
    { id: 'v-staff', name: 'Staff 10%', code: 'ST10', voucher_kind: 'percentage_discount', discount_amount: null,
      discount_percent: 10, max_discount_cap: null, discount_category: 'staff', birthday_rule: null, ...common },
    // Saved before 384: a discount voucher with no category yet.
    { id: 'v-old', name: 'Save S$5', code: 'SAVE5', voucher_kind: 'fixed_discount', discount_amount: 5,
      discount_percent: null, max_discount_cap: null, ...common },
  ],
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', is_active: true, deleted_at: null }],
  voucher_store_stock: [],
};

// Reads come from the fixtures; every insert and update is recorded and
// answered with the row as it would be saved.
const mock = `export const supabase={ from(table) {
 let rows=[...(window.__tables[table]||[])], one=false, write=null;
 const q=new Proxy({}, {get(_,key) {
  if(key==='then') return (ok,bad)=>{ let data;
   if(write){ window.__writes.push({table,...write}); data={id:write.id??'v-new',...write.payload}; }
   else data=JSON.parse(JSON.stringify(one?(rows[0]||null):rows));
   return Promise.resolve({data,error:null}).then(ok,bad); };
  return (...a)=>{
   if(key==='insert') write={op:'insert',payload:JSON.parse(JSON.stringify(a[0]))};
   if(key==='update') write={op:'update',payload:JSON.parse(JSON.stringify(a[0]))};
   if(key==='eq'&&write) write.id=a[1];
   else if(key==='eq'||key==='is') rows=rows.filter(r=>(r[a[0]]??null)===a[1]);
   if(key==='single'||key==='maybeSingle') one=true;
   return q; };
 }}); return q;
 }, rpc(name,args) {
  window.__calls.push({name,args:JSON.parse(JSON.stringify(args??null))});
  const q=new Proxy({}, {get(_,key){if(key==='then')return (ok,bad)=>Promise.resolve({data:null,error:null}).then(ok,bad);return()=>q;}});return q;
 }};`;

const result = await build({
  stdin: { contents: `import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import VouchersPage from './src/pages/VouchersPage';createRoot(document.getElementById('root')).render(<BrowserRouter><VouchersPage/></BrowserRouter>);`, resolveDir: process.cwd(), loader: 'tsx' },
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
const css = (await readFile('src/styles/globals.css', 'utf8')).replace(/^@import.*$/gm, '');

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => {
  assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`);
  checks++; console.log(`  ok  ${label}`);
};
const same = (label, actual, expected) => { assert.deepEqual(actual, expected, label); checks++; console.log(`  ok  ${label}`); };

async function open() {
  const context = await browser.newContext({ viewport: { width: 1280, height: 1000 }, timezoneId: 'Asia/Singapore' });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://vouchers.test/'
    ? route.fulfill({ contentType: 'text/html', body: '<html><body><div id="root"></div></body></html>' })
    : route.abort());
  await page.goto('https://vouchers.test/');
  await page.evaluate(t => { window.__tables = JSON.parse(JSON.stringify(t)); window.__writes = []; window.__calls = []; }, tables);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  await page.getByText('Gift Card S$50').waitFor();
  return page;
}
const modal = page => page.locator('.modal').last();
const row = (page, name) => page.locator('tbody tr').filter({ has: page.getByText(name, { exact: true }) });
const lastWrite = page => page.evaluate(() => window.__writes.at(-1) ?? null);
const kindSelect = page => modal(page).locator('.form-group').filter({ hasText: 'Voucher Type' }).locator('select');

try {
  const page = await open();
  console.log('The list');
  same('each discount voucher says where it is offered; a sellable one says nothing', [
    await row(page, 'Birthday 20% (Actual Date)').locator('td').nth(2).innerText(),
    await row(page, 'Staff 10%').locator('td').nth(2).innerText(),
    await row(page, 'Save S$5').locator('td').nth(2).innerText(),
    await row(page, 'Gift Card S$50').locator('td').nth(2).innerText(),
  ].map(t => t.replace(/\s+/g, ' ').trim()), [
    'Percent-off voucher Birthday · on the birthday', 'Percent-off voucher Staff', 'Fixed-amount voucher Voucher', 'Normal (sellable)',
  ]);

  console.log('Adding a voucher');
  await page.getByRole('button', { name: 'Add Voucher' }).click();
  same('the voucher kinds do not borrow the name of the line\'s "Percentage discount"',
    await kindSelect(page).locator('option').allTextContents(), ['Normal (sellable)', 'Fixed-amount voucher', 'Percent-off voucher']);
  ok('a sellable voucher has no category', await page.locator('#voucher-discount-category').count() === 0);
  await modal(page).locator('.form-group').filter({ hasText: 'Name *' }).locator('input').fill('Birthday Month 10%');
  await modal(page).locator('.form-group').filter({ hasText: 'Code *' }).locator('input').fill('BM10');
  await kindSelect(page).selectOption('percentage_discount');
  await modal(page).getByPlaceholder('e.g. 10').fill('10');
  same('a discount voucher is offered as a Voucher, a Birthday discount or a Staff discount',
    await page.locator('#voucher-discount-category option').allTextContents(), ['Voucher', 'Birthday discount', 'Staff discount']);
  ok('a new one starts as a Voucher, with no rule to set', await page.locator('#voucher-discount-category').inputValue() === 'voucher'
    && await page.locator('#voucher-birthday-rule').count() === 0);
  await page.locator('#voucher-discount-category').selectOption('birthday');
  same('a Birthday voucher asks when it applies',
    await page.locator('#voucher-birthday-rule option').allTextContents(),
    ['— Choose —', 'On the birthday (the actual date)', 'In the birth month (the whole month)']);
  await modal(page).getByRole('button', { name: 'Save', exact: true }).click();
  ok('and is not saved without it', (await modal(page).innerText()).includes('Choose when the birthday discount applies: on the birthday itself, or in the birth month.')
    && await lastWrite(page) === null);
  await page.locator('#voucher-birthday-rule').selectOption('whole_month');
  await modal(page).getByRole('button', { name: 'Save', exact: true }).click();
  await page.waitForFunction(() => window.__writes.length > 0);
  let w = await lastWrite(page);
  same('the category and the rule are saved with the voucher',
    [w.op, w.payload.voucher_kind, w.payload.discount_percent, w.payload.discount_category, w.payload.birthday_rule],
    ['insert', 'percentage_discount', 10, 'birthday', 'whole_month']);

  console.log('Editing');
  await row(page, 'Birthday 20% (Actual Date)').locator('button.btn-icon').first().click();
  same('a Birthday voucher opens with its category and rule',
    [await page.locator('#voucher-discount-category').inputValue(), await page.locator('#voucher-birthday-rule').inputValue()], ['birthday', 'actual_date']);
  await page.locator('#voucher-discount-category').selectOption('staff');
  ok('another category has no rule', await page.locator('#voucher-birthday-rule').count() === 0);
  await modal(page).getByRole('button', { name: 'Save', exact: true }).click();
  await page.waitForFunction(() => window.__writes.length > 1);
  w = await lastWrite(page);
  same('so none is saved', [w.op, w.id, w.payload.discount_category, w.payload.birthday_rule], ['update', 'v-bday', 'staff', null]);

  await row(page, 'Save S$5').locator('button.btn-icon').first().click();
  ok('a discount voucher saved before categories opens as a Voucher', await page.locator('#voucher-discount-category').inputValue() === 'voucher');
  await modal(page).getByRole('button', { name: 'Cancel', exact: true }).click();

  await row(page, 'Gift Card S$50').locator('button.btn-icon').first().click();
  await modal(page).getByRole('button', { name: 'Save', exact: true }).click();
  await page.waitForFunction(() => window.__writes.length > 2);
  w = await lastWrite(page);
  same('a sellable voucher is saved with no category and no rule', [w.id, w.payload.discount_category, w.payload.birthday_rule], ['v-gift', null, null]);
  ok('no unexpected browser errors', page.errors.length === 0, page.errors.join(' | '));
  await page.context().close();
  console.log(`\n${checks} checks passed.`);
} finally {
  await browser.close();
}
