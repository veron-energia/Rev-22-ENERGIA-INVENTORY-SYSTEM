// The Special page on a phone (426, audit finding SALES-EXTRAS-15), in a real
// browser: at 375 px the page does not scroll sideways, the tabs and the
// waiting-list button wrap inside the screen, the waiting list is one column
// with its Release button on screen, and the Return and Receive windows fit.
// At 1280 px the waiting list keeps its three columns.
//
// The database is a stand-in (invented data only); the page is the real one,
// with the real stylesheet. Screenshots go to .invoice-test/browser/special-*.png.
//   node scripts/special/tests/special-page-browser.mjs
// Needs Playwright (PLAYWRIGHT_MODULE) and Chrome (CHROME_EXECUTABLE), as the
// other *-browser.mjs checks do.
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });

const tables = {
  special_products: [{ id: 'sp-1', product_id: 'p-1', name: 'Fixture Massage Chair Deluxe Edition', sku: 'FX-CHAIR-DELUXE-01',
    description: null, sale_price: 4800, rate_day: 30, rate_week: 150, rate_month: 400, rate_year: 3000, late_fee_per_day: 5, is_active: true }],
  warehouse_inventory: [{ warehouse_id: 'wh-1', product_id: 'p-1', current_qty: 4 }],
  store_inventory: [{ store_id: 'st-b', product_id: 'p-1', current_qty: 2 }],
  special_sales: [],
  rentals: [
    { id: 'r-1', rental_no: 'RNT-2026-9901', special_product_id: 'sp-1', customer_id: 'c-1', warehouse_id: null, store_id: 'st-b',
      source_store_id: 'st-b', invoice_id: 'inv-1', status: 'active', quantity: 1, rate_type: 'day', rate_amount: 30, periods: 2,
      rental_fee: 60, start_date: '2026-10-01', expected_return_date: '2026-10-03', late_fee_per_day: 5, late_fee_total: 0,
      late_days: 0, notes: null, stock_returned: null, fulfilled_at: '2026-10-01T02:00:00Z', activated_at: '2026-10-01T02:00:00Z',
      created_at: '2026-10-01T02:00:00Z' },
    { id: 'r-2', rental_no: 'RNT-2026-9902', special_product_id: 'sp-1', customer_id: 'c-1', warehouse_id: null, store_id: 'st-a',
      source_store_id: 'st-b', invoice_id: 'inv-2', status: 'cancelled', quantity: 1, rate_type: 'week', rate_amount: 150, periods: 1,
      rental_fee: 150, start_date: '2026-10-05', expected_return_date: '2026-10-12', late_fee_per_day: 5, late_fee_total: 0,
      late_days: 0, notes: 'From invoice INV-2026-9902', stock_returned: false, fulfilled_at: '2026-10-05T02:00:00Z',
      activated_at: '2026-10-05T02:00:00Z', cancelled_at: '2026-10-08T02:00:00Z', created_at: '2026-10-05T02:00:00Z' },
  ],
  warehouses: [{ id: 'wh-1', name: 'Fixture Central Warehouse', is_active: true }],
  payment_methods: [{ id: 'pm-1', name: 'Fixture Cash', is_active: true, is_wallet_credit: false }],
  stores: [{ id: 'st-a', name: 'Fixture Main Store', is_active: true }, { id: 'st-b', name: 'Fixture Roadshow & Van Store', is_active: true }],
  profiles: [],
  invoices: [{ id: 'inv-1', invoice_no: 'INV-2026-9901', status: 'paid' }, { id: 'inv-2', invoice_no: 'INV-2026-9902', status: 'cancelled' }],
  customers: [{ id: 'c-1', full_name: 'Fixture Renter With A Long Name', phone: '+61491571491', email: 'renter@example.com' }],
};
const waiting = [1, 2].map(n => ({
  doc_kind: n === 1 ? 'rental' : 'special_sale', doc_id: `w-${n}`, doc_no: `RNT-2026-991${n}`, invoice_no: `INV-2026-991${n}`,
  special_product_id: 'sp-1', product_name: 'Fixture Massage Chair Deluxe Edition', customer_name: 'Fixture Renter With A Long Name',
  store_name: 'Fixture Main Store', quantity: 1, rate_type: n === 1 ? 'day' : null, periods: n === 1 ? 3 : null,
  start_date: '2027-01-31', expected_return_date: '2027-02-03', rental_fee: 90, created_at: '2026-10-17T02:00:00Z',
}));

const mock = `
const T = ${JSON.stringify(tables)};
const W = ${JSON.stringify(waiting)};
const thenable = v => { const q = new Proxy({}, { get(_, k) { if (k === 'then') return (ok, bad) => Promise.resolve(v).then(ok, bad); return () => q; } }); return q; };
export const supabase = {
  from: t => thenable({ data: T[t] || [], error: null }),
  rpc: async (name) => {
    if (name === 'special_docs_awaiting_fulfilment') return { data: W, error: null };
    if (name === 'special_product_availability') return { data: [
      { location_type: 'warehouse', warehouse_id: 'wh-1', warehouse_name: 'Fixture Central Warehouse', on_hand: 4, reserved: 0, available: 4 },
      { location_type: 'store', warehouse_id: 'st-b', warehouse_name: 'Fixture Roadshow & Van Store', on_hand: 2, reserved: 1, available: 1 }], error: null };
    return { data: [], error: null };
  },
  storage: { from: () => ({}) },
};
export const fetchCustomersByIds = async () => T.customers;
`;
const built = await build({
  stdin: { contents: `import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import SpecialPage from './src/pages/SpecialPage';createRoot(document.getElementById('root')).render(<BrowserRouter><div className="app-main"><SpecialPage/></div></BrowserRouter>);`, resolveDir: process.cwd(), loader: 'tsx' },
  bundle: true, define: { 'import.meta.env': '{}' }, format: 'iife', write: false, logLevel: 'silent',
  plugins: [{ name: 'fixtures', setup(b) {
    b.onResolve({ filter: /(?:^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'fixture' }));
    b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'fixture' }));
    b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => ({ contents: a.path === 'db' ? mock
      : a.path === 'auth' ? `export const useAuth=()=>({profile:{id:'u-1',role:'owner',full_name:'Fixture Owner'},loading:false});` : '', loader: 'js' }));
  } }],
});
const bundle = built.outputFiles[0].text;
const css = (await readFile('src/styles/globals.css', 'utf8')).replace(/^@import.*$/gm, '');
const HTML = '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>';

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => { assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`); checks++; console.log(`  ok  ${label}`); };

async function open(width) {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.setViewportSize({ width, height: 800 });
  page.setDefaultTimeout(8000);
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://special.test/' ? route.fulfill({ contentType: 'text/html', body: HTML }) : route.abort());
  await page.goto('https://special.test/');
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  await page.getByRole('button', { name: /Waiting for a warehouse/ }).waitFor();
  return { page, errors, context };
}
const noSideScroll = page => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const rightEdge = (loc) => loc.evaluate(el => el.getBoundingClientRect().right);

try {
  // ── A phone ─────────────────────────────────────────────────────────────
  {
    const { page, errors, context } = await open(375);
    ok('375 px: the page does not scroll sideways', await noSideScroll(page));
    for (const name of ['Catalog', 'Sales', 'Rentals']) {
      ok(`375 px: the ${name} tab is on screen`, (await rightEdge(page.getByRole('button', { name, exact: true }))) <= 375);
    }
    ok('375 px: the waiting-list button is on screen', (await rightEdge(page.getByRole('button', { name: /Waiting for a warehouse/ }))) <= 375);
    await page.screenshot({ path: '.invoice-test/browser/special-375-catalog.png', fullPage: true });

    await page.getByRole('button', { name: /Waiting for a warehouse/ }).click();
    const dlg = page.getByRole('dialog', { name: 'Waiting for a warehouse' });
    await dlg.waitFor();
    const cols = await page.locator('.special-queue-row').first().evaluate(el => getComputedStyle(el).gridTemplateColumns.split(' ').length);
    ok('375 px: the waiting list is one column', cols === 1, `${cols} columns`);
    const fits = await page.locator('.special-queue-row').evaluateAll(rows => rows.every(r => r.scrollWidth <= r.clientWidth + 1));
    ok('375 px: no waiting-list row runs past its edge', fits);
    const release = page.getByRole('button', { name: 'Release' }).first();
    const modalRight = await page.locator('.modal').evaluate(el => el.getBoundingClientRect().right);
    ok('375 px: Release is on screen, inside the window', (await rightEdge(release)) <= Math.min(375, modalRight));
    ok('375 px: the warehouse choice is inside the window', (await rightEdge(page.locator('.special-queue-row select').first())) <= modalRight);
    ok('375 px: the column headings are hidden', !(await page.locator('.special-queue-head').isVisible()));
    await page.screenshot({ path: '.invoice-test/browser/special-375-waiting.png' });
    await page.getByRole('button', { name: 'Change' }).click();
    const change = page.getByRole('dialog', { name: /Change rental terms/ });
    await change.waitFor();
    ok('375 px: the Change window fits', (await rightEdge(page.locator('.modal').last())) <= 375);
    await page.screenshot({ path: '.invoice-test/browser/special-375-change.png' });
    await change.getByRole('button', { name: 'Cancel' }).click();
    await dlg.getByRole('button', { name: 'Close', exact: true }).last().click();

    await page.getByRole('button', { name: 'Rentals', exact: true }).click();
    await page.getByText('RNT-2026-9902').waitFor();
    ok('375 px: the Rentals tab shows as chosen', /btn-primary/.test(await page.getByRole('button', { name: 'Rentals', exact: true }).getAttribute('class')));
    ok('375 px: the Rentals tab does not scroll the page sideways', await noSideScroll(page));
    ok('375 px: a cancelled rental still out says so', await page.getByText('Cancelled, still with customer').isVisible());
    await page.screenshot({ path: '.invoice-test/browser/special-375-rentals.png', fullPage: true });
    await page.getByRole('button', { name: /Receive returned item: .* \(RNT-2026-9902\)/ }).click();
    await page.getByRole('dialog', { name: /Receive returned item — RNT-2026-9902/ }).waitFor();
    ok('375 px: the Receive window fits', (await rightEdge(page.locator('.modal').last())) <= 375);
    await page.screenshot({ path: '.invoice-test/browser/special-375-receive.png' });
    await page.getByRole('dialog', { name: /Receive returned item/ }).getByRole('button', { name: 'Cancel' }).click();
    await page.getByRole('button', { name: 'Return', exact: true }).first().click();
    await page.getByRole('dialog', { name: /Return — RNT-2026-9901/ }).waitFor();
    ok('375 px: the Return window fits', (await rightEdge(page.locator('.modal').last())) <= 375);
    ok('375 px: no page errors', errors.length === 0, errors.join(' | '));
    await context.close();
  }
  // ── A computer ──────────────────────────────────────────────────────────
  {
    const { page, errors, context } = await open(1280);
    await page.getByRole('button', { name: /Waiting for a warehouse/ }).click();
    await page.getByRole('dialog', { name: 'Waiting for a warehouse' }).waitFor();
    const cols = await page.locator('.special-queue-row').first().evaluate(el => getComputedStyle(el).gridTemplateColumns.split(' ').length);
    ok('1280 px: the waiting list keeps its three columns', cols === 3, `${cols} columns`);
    ok('1280 px: the column headings show', await page.locator('.special-queue-head').isVisible());
    await page.screenshot({ path: '.invoice-test/browser/special-1280-waiting.png' });
    ok('1280 px: no page errors', errors.length === 0, errors.join(' | '));
    await context.close();
  }
  console.log(`PASS: ${checks} checks`);
} finally {
  await browser.close();
}
