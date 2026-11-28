// The Class page (the Owner, 27 Nov 2026; migration 548) in a real browser, on a computer and on a phone:
// in-memory fixtures, no network, every name invented. Layout: nothing runs past the page edge (the buyers
// and the dates scroll inside their own box on a phone), the tabs wrap, the date box of a seat is usable;
// and the page's calls (a seat's date, a tick, an Owner's new date). Screenshots in .invoice-test/browser/.
//
// Run: node scripts/classes/tests/class-page-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });
// With SHOTS_DIR set, also save the pictures made for the Owner there (SHOTS_DIR=<folder> node ...).
const SHOTS = process.env.SHOTS_DIR;
if (SHOTS) await mkdir(SHOTS, { recursive: true });

const S = (id, seq, date, over = {}) => ({ id, seq, title: `Session ${seq}`, kind: 'lesson', session_date: date, starts_at: '20:00:00', ends_at: '22:00:00',
  mode: 'zoom', venue: null, must_attend: false, taken: 0, ...over });
const ADELPHI = 'The Adelphi, 1 Coleman Street #B1-37';
const skinDates = ['2027-01-27', '2027-02-24', '2027-03-24', '2027-04-28'].map((d, i) =>
  S(`k${i + 1}`, i + 1, d, { title: 'Class day', kind: 'class_day', mode: 'in_person', venue: ADELPHI, starts_at: '19:00:00', ends_at: '21:00:00', taken: i === 0 ? 6 : i }));
const data = {
  can_edit: true,
  classes: [
    { voucher_id: 'v-found', code: 'EmiLymphatic', name: 'Lymphatic Foundation Workshop 2027', price: 799, is_active: true, seat_mode: 'all_sessions', capacity_per_date: null, sort_order: 1,
      summary: 'Monthly Zoom workshop: 12 sessions and a graduation', seats_sold: 4,
      details: { fee_note: 'Early bird S$799 (usual S$4,788)', time_text: 'Fridays, 8:00-10:00 PM', format_text: 'Session 1 is in person at The Adelphi (must attend). Sessions 2 to 10 are on Zoom.',
        notes: ['Graduation: Sat 1 Jan 2028, 10:00 AM-3:00 PM, in person (venue to be confirmed).'] },
      sessions: [S('f1', 1, '2027-01-29', { mode: 'in_person', venue: 'The Adelphi', must_attend: true }), S('f2', 2, '2027-02-26'), S('f3', 3, '2027-03-26'),
        S('fg', 13, '2028-01-01', { title: 'Graduation', kind: 'graduation', starts_at: '10:00:00', ends_at: '15:00:00', mode: 'in_person' })] },
    { voucher_id: 'v-adv', code: 'AdvancedZoom', name: 'Lymphatic Advanced Workshop 2027', price: 1441, is_active: true, seat_mode: 'all_sessions', capacity_per_date: null, sort_order: 2,
      summary: null, seats_sold: 0, details: {}, sessions: [] },
    { voucher_id: 'v-skin', code: 'KPopClass', name: 'Korea No.1 Skin Care Workshop', price: 676, is_active: true, seat_mode: 'choose_date', capacity_per_date: 6, sort_order: 3,
      summary: '1-day course, in person, max 6 per class', seats_sold: 3,
      details: { fee_note: 'S$676 (usual S$1,174 = course S$499 + Skin Care Set S$675)', time_text: '7:00-9:00 PM', venue_text: ADELPHI,
        learn: ['Deep Cleansing', 'Intense Hydration', 'Restore & Protect'], notes: ['The Skin Care Set (9 products) is handled separately: no stock moves with the class.'] },
      sessions: skinDates },
    { voucher_id: 'v-lc', code: 'L-C', name: 'Lymphatic Class', price: 399, is_active: true, seat_mode: 'choose_date', capacity_per_date: null, sort_order: 4,
      summary: 'One in-person day of the Foundation class', seats_sold: 0, details: {}, sessions: [] },
  ],
  seats: [
    { voucher_id: 'v-found', invoice_item_id: 'it-1', seat_no: 1, seats_on_line: 2, invoice_id: 'i1', invoice_no: 'INV-2026-0001', invoice_status: 'paid', business_date: '2026-11-20',
      store_id: 's1', store_name: 'Test Store A', customer_id: 'c1', customer_name: 'Alice Fixture-Longsurname', customer_phone: '+61 2 5550 1001', session_id: null, attended: ['f1'] },
    { voucher_id: 'v-found', invoice_item_id: 'it-1', seat_no: 2, seats_on_line: 2, invoice_id: 'i1', invoice_no: 'INV-2026-0001', invoice_status: 'paid', business_date: '2026-11-20',
      store_id: 's1', store_name: 'Test Store A', customer_id: 'c1', customer_name: 'Alice Fixture-Longsurname', customer_phone: '+61 2 5550 1001', session_id: null, attended: [] },
    { voucher_id: 'v-skin', invoice_item_id: 'it-2', seat_no: 1, seats_on_line: 1, invoice_id: 'i2', invoice_no: 'INV-2026-0002', invoice_status: 'unpaid', business_date: '2026-11-21',
      store_id: 's1', store_name: 'Test Store A', customer_id: 'c2', customer_name: 'Bob Fixture', customer_phone: '+61 2 5550 1002', session_id: 'k2', attended: [] },
    { voucher_id: 'v-skin', invoice_item_id: 'it-3', seat_no: 1, seats_on_line: 1, invoice_id: 'i3', invoice_no: 'INV-2026-0003', invoice_status: 'paid', business_date: '2026-11-22',
      store_id: 's2', store_name: 'Test Store B', customer_id: 'c3', customer_name: 'Cara Fixture', customer_phone: 'LEGACY-NO-PHONE-CUST-123456', session_id: null, attended: [] },
  ],
};

const mock = `export const supabase={ from(table) {
 const q=new Proxy({}, {get(_,key) { if(key==='then') return (ok,bad)=>Promise.resolve({data:[],error:null}).then(ok,bad); return ()=>q; }}); return q;
 }, rpc(name,args) {
 window.__calls.push({name,args:JSON.parse(JSON.stringify(args??null))});
 const data = name==='class_page_data' ? JSON.parse(JSON.stringify(window.__data)) : { changed: true };
 const q=new Proxy({}, {get(_,key){if(key==='then')return (ok,bad)=>Promise.resolve({data,error:null}).then(ok,bad);return()=>q;}});return q;
 }};`;
const result = await build({
  stdin: { contents: `import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import ClassPage from './src/pages/ClassPage';createRoot(document.getElementById('root')).render(<BrowserRouter><ClassPage /></BrowserRouter>);`, resolveDir: process.cwd(), loader: 'tsx' },
  bundle: true, define: { 'import.meta.env': '{}' }, format: 'iife', write: false,
  plugins: [{ name: 'isolated-fixtures', setup(b) {
    b.onResolve({ filter: /(?:^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'fixture' }));
    b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'fixture' }));
    b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => ({ contents: a.path === 'db' ? mock
      : a.path === 'auth' ? `export const useAuth=()=>({profile:{id:'owner',full_name:'Test Owner',role:window.__role||'owner'},session:{user:{id:'owner'}},assignments:[],loading:false});` : '', loader: 'js' }));
  } }],
});
const bundle = result.outputFiles[0].text;
const css = (await readFile('src/styles/globals.css', 'utf8')).replace(/^@import.*$/gm, '');

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => { assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`); checks++; console.log(`  ok  ${label}`); };

async function open({ width, role = 'owner', canEdit = true }) {
  const context = await browser.newContext({ viewport: { width, height: 1000 }, timezoneId: 'Asia/Singapore' });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://class.test/'
    ? route.fulfill({ contentType: 'text/html', body: '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="root"></div></body></html>' })
    : route.abort());
  await page.goto('https://class.test/');
  await page.evaluate(([d, r, e]) => { window.__data = { ...JSON.parse(JSON.stringify(d)), can_edit: e }; window.__role = r; window.__calls = []; }, [data, role, canEdit]);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  await page.getByRole('tab', { name: 'Korea No.1 Skin Care Workshop' }).waitFor();
  return page;
}
const noSideways = page => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);

try {
  for (const width of [1280, 375]) {
    const tag = `${width} px`;
    const page = await open({ width });
    ok(`${tag}: the first class shows its details, dates and buyers`, (await page.locator('body').innerText()).includes('Early bird S$799 (usual S$4,788)')
      && await page.locator('[data-testid=class-sessions] tbody tr').count() === 4 && await page.locator('[data-testid=class-seat]').count() === 2);
    ok(`${tag}: nothing runs past the page edge`, await noSideways(page));
    await page.screenshot({ path: `.invoice-test/browser/class-page-${width}-foundation.png`, fullPage: true });
    if (SHOTS) await page.screenshot({ path: `${SHOTS}/${width === 1280 ? 'a-class-foundation-1280' : 'd-class-foundation-375'}.png`, fullPage: true });
    // Ticking a seat for the session shown.
    const box = page.locator('[data-testid=class-seat]').first().locator('input[type=checkbox]');
    ok(`${tag}: for the first session (the next one) seat 1 shows as attended`, await box.isChecked());
    await page.locator('#class-tick-session').selectOption('f2');
    ok(`${tag}: for the second session nobody has attended yet`, !(await box.isChecked()));
    await box.click();
    const tick = await page.evaluate(() => window.__calls.findLast(c => c.name === 'class_set_attendance'));
    ok(`${tag}: ticking a seat sends the session, the invoice line and the seat`, JSON.stringify(tick.args) === JSON.stringify({ p_session_id: 'f2', p_invoice_item_id: 'it-1', p_seat_no: 1, p_attended: true }), JSON.stringify(tick));
    // Skin care.
    await page.getByRole('tab', { name: 'Korea No.1 Skin Care Workshop' }).click();
    ok(`${tag}: skin care shows the capacity and the full date`, (await page.locator('[data-testid=class-sessions]').innerText()).includes('6 of 6')
      && (await page.locator('[data-testid=class-sessions]').innerText()).includes('Full'));
    ok(`${tag}: nothing runs past the page edge on skin care either`, await noSideways(page));
    const sel = page.locator('[data-testid=class-seat]').nth(1).locator('select');
    const opts = await sel.locator('option').allTextContents();
    ok(`${tag}: a seat's date box lists the dates with their places`, opts.join(' | ') === 'Not chosen yet | Wed 27 Jan 2027 · 6 of 6 (full) | Wed 24 Feb 2027 · 1 of 6 | Wed 24 Mar 2027 · 2 of 6 | Wed 28 Apr 2027 · 3 of 6', opts.join(' | '));
    ok(`${tag}: the full date cannot be picked`, await sel.locator('option').nth(1).isDisabled());
    await sel.selectOption('k3');
    const chosen = await page.evaluate(() => window.__calls.findLast(c => c.name === 'class_choose_date'));
    ok(`${tag}: choosing a date sends the line, the seat and the date`, JSON.stringify(chosen.args) === JSON.stringify({ p_invoice_item_id: 'it-3', p_seat_no: 1, p_session_id: 'k3' }), JSON.stringify(chosen));
    ok(`${tag}: a placeholder phone is not shown`, !(await page.locator('body').innerText()).includes('LEGACY'));
    await page.screenshot({ path: `.invoice-test/browser/class-page-${width}-skin.png`, fullPage: true });
    if (SHOTS && width === 1280) {
      // The date box of a seat, opened as a list: the dates with their places, the full one greyed.
      await sel.evaluate(el => { el.size = el.options.length; el.style.height = 'auto'; });
      await page.screenshot({ path: `${SHOTS}/b-class-skin-care-1280.png`, fullPage: true });
      await sel.evaluate(el => { el.size = 0; el.style.height = ''; });
    }
    if (SHOTS && width === 375) await page.screenshot({ path: `${SHOTS}/d-class-skin-care-375.png`, fullPage: true });
    // The Lymphatic Class: no dates yet, an Owner adds one.
    await page.getByRole('tab', { name: 'Lymphatic Class' }).click();
    await page.getByRole('button', { name: 'Add date' }).click();
    await page.locator('#cs-date').fill('2027-02-06');
    await page.locator('#cs-title').fill('In-person day');
    await page.screenshot({ path: `.invoice-test/browser/class-page-${width}-add-date.png`, fullPage: false });
    await page.locator('.modal').getByRole('button', { name: 'Save' }).click();
    const saved = await page.evaluate(() => window.__calls.findLast(c => c.name === 'class_save_session'));
    ok(`${tag}: an Owner's new date is sent with its class`, saved.args.p_voucher_id === 'v-lc' && saved.args.p_session_id === null && saved.args.p_data.session_date === '2027-02-06', JSON.stringify(saved));
    ok(`${tag}: no page errors`, page.errors.length === 0, page.errors.join(' | '));
    await page.context().close();
  }
  // Staff: no editing buttons.
  {
    const page = await open({ width: 1280, role: 'staff', canEdit: false });
    ok('staff: no Add date, Edit details, Edit or Remove', await page.getByRole('button', { name: 'Add date' }).count() === 0
      && await page.getByRole('button', { name: 'Edit details' }).count() === 0 && await page.locator('[aria-label^="Edit "], [aria-label^="Remove "]').count() === 0);
    await page.context().close();
  }
  console.log(`PASS: ${checks} checks`);
} finally {
  await browser.close();
}
