// Wallet credit as a line under Discount (the user's answers, 13 Nov 2026), through the real Invoices page in
// Chrome: on both printed halves, the PDF, the image (so WhatsApp and email) and the invoice screen, an invoice
// paid from the wallet shows each kind of credit as 'Wallet — <name>  −S$x' under Discount, and Total is what the
// credit left to pay; PAYMENT METHODS lists only money, and is left out when credit paid everything; credit
// refunded back into the wallet is a note under its line; the screen's Payments Recorded keeps every payment
// for staff to correct; and an invoice paid in money alone prints as before.
//
// The real page and the real PDF and image renderers run in Chrome against an in-memory stand-in for Supabase
// (as print-note-browser.mjs does); every network request is blocked. The customers, invoices and amounts are
// invented.
//
// Usage: node scripts/invoices/tests/wallet-credit-lines-browser.mjs
//        (pictures of each copy go to .invoice-test/browser/wallet-*.png and .pdf)
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });

// ---------------------------------------------------------------------------
// Fixtures (invented)
// ---------------------------------------------------------------------------
const T0 = '2026-11-11T02:00:00Z';
const T_BACK = '2026-11-12T03:00:00Z';
const common = { is_active: true, deleted_at: null };
const owner = { id: 'owner', full_name: 'Test Owner', role: 'owner', ...common };
const inv = (id, total, over = {}) => ({
  id, invoice_no: `INV-T-${id}`, store_id: 'store', customer_id: 'cust', status: 'paid', subtotal: total, total_amount: total,
  paid_amount: total, discount_total: 0, manual_discount: 0, created_at: T0, paid_at: T0, business_date: '2026-11-11',
  created_by: 'owner', edit_count: 0, notes: null, print_note: null, ...common, ...over,
});
const wm = (id, name, wallet_category, wallet_source = null) =>
  ({ id, name, is_wallet_credit: true, wallet_category, wallet_source, is_system: true, ...common });
const pay = (id, invoice_id, payment_method_id, amount) =>
  ({ id, invoice_id, payment_method_id, amount, entry_kind: 'receipt', created_at: T0, effective_at: T0 });
const tables = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', address: '1 Example Road #01-01, Singapore 000001', phone: '+6560000000',
    whatsapp_phone: '+6590000000', email: 'shop@example.test', website: 'example.test', co_reg_no: 'TEST0001X', ...common }],
  customers: [{ id: 'cust', full_name: 'Test Customer', phone: '+6590000001', email: 'test.customer@example.com', ...common }],
  profiles: [owner],
  products: [{ id: 'facial', name: 'Test Facial (with Test Cream)', sku: 'FAC', product_type: 'own', ...common }],
  store_product_prices: [{ store_id: 'store', product_id: 'facial', selling_price: 327, member_price: 327, non_member_price: 327, availability: 'available', ...common }],
  store_inventory: [{ store_id: 'store', product_id: 'facial', current_qty: 100 }],
  payment_methods: [
    { id: 'cash', name: 'Cash', ...common }, { id: 'paynow', name: 'PayNow', ...common },
    wm('pk-paid', 'Wallet — Credit Package Paid', 'paid', 'credit_package'),
    wm('pk-bonus', 'Wallet — Credit Package Bonus', 'bonus', 'credit_package'),
    wm('other-paid', 'Wallet — Paid Credit', 'paid'),
    wm('legacy', 'Wallet — Legacy Credit', 'legacy'),
  ],
  promotions: [], promotion_store_prices: [], promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
  invoice_promotion_selections: [], invoice_revisions: [], invoice_service_staff: [], warehouses: [],
  vouchers: [], voucher_store_prices: [], special_products: [], therapy_package_rules: [], unlimited_therapy_packages: [],
  unlimited_therapy_store_prices: [], therapy_services: [], therapy_service_stores: [],
  invoices: [
    inv('credit', 327),      // the user's example: all of it from Credit Package credit
    inv('mixed', 327),       // S$200 of Credit Package credit, S$127 by PayNow
    inv('bonus', 400),       // Credit Package Paid and Bonus together, the rest in cash
    inv('returned', 921),    // all of it from Credit Package credit, then S$327 of it back into the wallet
    inv('kinds', 500),       // Paid Credit (of Premium Bundle credit) and Legacy Credit, the rest in cash
    inv('cash', 100),        // money alone: as before
  ],
  invoice_payments: [
    pay('p-credit', 'credit', 'pk-paid', 327),
    pay('p-mixed-1', 'mixed', 'pk-paid', 200), pay('p-mixed-2', 'mixed', 'paynow', 127),
    pay('p-bonus-1', 'bonus', 'pk-paid', 300), pay('p-bonus-2', 'bonus', 'pk-bonus', 50), pay('p-bonus-3', 'bonus', 'cash', 50),
    pay('p-returned', 'returned', 'pk-paid', 921),
    pay('p-kinds-1', 'kinds', 'other-paid', 300), pay('p-kinds-2', 'kinds', 'legacy', 100), pay('p-kinds-3', 'kinds', 'cash', 100),
    pay('p-cash', 'cash', 'cash', 100),
  ],
  invoice_refunds: [
    { id: 'r-returned', invoice_id: 'returned', payment_id: 'p-returned', amount: 327, credit_returned: 327, created_at: T_BACK },
  ],
};
tables.invoice_items = tables.invoices.map(i => ({ id: `line-${i.id}`, invoice_id: i.id, line_kind: 'product', product_id: 'facial',
  quantity: 1, unit_price: i.total_amount, line_total: i.total_amount, topup_amount: 0, foc_quantity: 0 }));
// Where each wallet payment's credit came from (443), for the bracket on a method naming no source.
const paySources = { kinds: { 'p-kinds-1': ['premium_bundle'], 'p-kinds-2': ['other'] } };
const balance = { customer_id: 'cust', categories: { paid: 11017, bonus: 0, legacy: 0, promotional: 0, exchange: 0 }, available_total: 11017,
  sources: { credit_package: { total: 3381 }, premium_bundle: { total: 7636 }, other: { total: 0 } } };

// ---------------------------------------------------------------------------
// The stand-in for the Supabase client.
// ---------------------------------------------------------------------------
const mock = `export const supabase = (() => {
  const t = () => window.__tables;
  const calls = (window.__calls = window.__calls || []);
  const thenable = p => { const q = new Proxy({}, { get(_, k) { if (k === 'then') return (ok, bad) => p.then(ok, bad); return () => q; } }); return q; };
  function from(table) {
    let rows = [...(t()[table] || [])], one = false;
    const q = new Proxy({}, { get(_, key) {
      if (key === 'then') return (ok, bad) => Promise.resolve(table === 'invoice_refunds' && window.__refundsError
        ? { data: null, error: { message: 'Stopped by the test' } }
        : { data: structuredClone(one ? (rows[0] || null) : rows), error: null }).then(ok, bad);
      return (...a) => {
        if (key === 'eq' || key === 'is') rows = rows.filter(r => r[a[0]] === a[1]);
        if (key === 'in') rows = rows.filter(r => a[1].includes(r[a[0]]));
        if (key === 'single' || key === 'maybeSingle') one = true; return q; };
    } });
    return q;
  }
  const refunded = id => (t().invoice_refunds || []).filter(r => r.invoice_id === id).reduce((s, r) => s + Number(r.amount), 0);
  const finance = i => ({ total: Number(i.total_amount), net_received: Number(i.paid_amount) - refunded(i.id), outstanding: 0,
    refund_due: 0, refunded: refunded(i.id), status: i.status });
  async function rpcImpl(name, args) {
    calls.push({ name, args: structuredClone(args) });
    const find = id => t().invoices.find(i => i.id === id);
    switch (name) {
      case 'invoice_list_page': {
        const rows = t().invoices.map(i => ({ ...i, customer_name: 'Test Customer' }));
        return { data: { rows, total: rows.length, pages: 1, summary: { matching: rows.length, total_amount: 0, outstanding: 0, paid: 0 } }, error: null };
      }
      case 'customer_credit_balances': return { data: window.__balance, error: null };
      case 'invoice_payment_credit_sources': return { data: window.__paySources[args.p_invoice_id] || {}, error: null };
      case 'invoice_financial_position': return { data: finance(find(args.p_invoice_id)), error: null };
      case 'invoice_refund_options': return { data: { financial: finance(find(args.p_invoice_id)), sources: [], stock: [], benefits: [], lines: [], review_required: false }, error: null };
      case 'invoice_effective_affiliate': return { data: { found: true, has_affiliate: false }, error: null };
      case 'invoice_benefit_review_options': return { data: { lines: [] }, error: null };
      case 'exchange_invoice_details': return { data: { found: false }, error: null };
      default: return { data: null, error: null };
    }
  }
  const rpc = (name, args) => thenable(rpcImpl(name, args));
  const channel = () => { const ch = { on() { return ch; }, subscribe() { return ch; }, unsubscribe() { return Promise.resolve('ok'); } }; return ch; };
  const storage = { from: () => ({ upload: async () => ({ error: null }), createSignedUrl: async () => ({ data: { signedUrl: 'https://files.example.test/x.pdf' }, error: null }) }) };
  const functions = { invoke: async () => ({ data: { ok: true }, error: null }) };
  return { from, rpc, channel, removeChannel: () => Promise.resolve('ok'), storage, functions,
    auth: { getSession: async () => ({ data: { session: { user: { id: window.__profile.id } } } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) } };
})();`;

const built = await build({
  stdin: { contents: `import React from 'react';import {createRoot} from 'react-dom/client';import {BrowserRouter} from 'react-router-dom';import InvoicesPage from './src/pages/InvoicesPage';createRoot(document.getElementById('root')).render(<BrowserRouter><InvoicesPage/></BrowserRouter>);`, resolveDir: process.cwd(), loader: 'tsx' },
  bundle: true, define: { 'import.meta.env': '{}' }, format: 'iife', write: false,
  plugins: [{ name: 'isolated-fixtures', setup(b) {
    b.onResolve({ filter: /(?:^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'fixture' }));
    b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'fixture' }));
    b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => ({ contents: a.path === 'db' ? mock
      : a.path === 'auth' ? `export const useAuth=()=>({profile:window.__profile,session:{user:{id:window.__profile.id}},assignments:[],loading:false});` : '', loader: 'js' }));
  } }],
});
const bundle = built.outputFiles[0].text;
const css = (await readFile('src/styles/globals.css', 'utf8') + '\n' + await readFile('src/components/invoices/invoice-controls.css', 'utf8')).replace(/^@import.*$/gm, '');
const HTML = '<html><head></head><body><div id="root"></div></body></html>';

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => { assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`); checks++; console.log(`  ok  ${label}`); };
const count = (s, needle) => s.split(needle).length - 1;
/** Text drawn into a jsPDF file: strings are written as (…) with \\( \\) \\\\ escapes, in WinAnsi. */
const pdfText = bytes => Buffer.from(bytes).toString('latin1').replace(/\\([()\\])/g, '$1').replace(/\xb7/g, '·').replace(/\x97/g, '—');

async function openPage() {
  const context = await browser.newContext({ timezoneId: 'Asia/Singapore', acceptDownloads: true, viewport: { width: 1400, height: 1000 } });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/' ? route.fulfill({ contentType: 'text/html', body: HTML }) : route.abort());
  await page.goto('https://invoice.test/');
  await page.clock.setFixedTime(new Date('2026-11-13T04:00:00Z'));
  await page.evaluate(([t, p, s, b]) => {
    window.__tables = t; window.__profile = p; window.__paySources = s; window.__balance = b; window.__calls = []; window.__printed = [];
    window.open = () => {
      const w = { closed: false, opener: window, close() { w.closed = true; }, location: { set href(u) {} },
        document: { body: { textContent: '' }, open() {}, write: html => { window.__printed.push(html); }, close() {} } };
      return w;
    };
    window.modalButton = name => [...document.querySelectorAll('.modal button')].find(b => b.textContent.trim() === name);
    const fill = CanvasRenderingContext2D.prototype.fillText;
    CanvasRenderingContext2D.prototype.fillText = function (text, x, y, ...rest) {
      (this.canvas.__texts = this.canvas.__texts || []).push({ text: String(text), x, y });
      return fill.call(this, text, x, y, ...rest);
    };
    const toBlob = HTMLCanvasElement.prototype.toBlob;
    HTMLCanvasElement.prototype.toBlob = function (done, ...rest) { window.__imageCanvas = this; return toBlob.call(this, done, ...rest); };
  }, [tables, owner, paySources, balance]);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  await page.getByRole('button', { name: 'View', exact: true }).first().waitFor();
  return page;
}
const row = (page, no) => page.locator('tbody tr').filter({ has: page.getByText(no, { exact: true }) });
async function view(page, id) {
  const close = page.getByRole('button', { name: 'Close', exact: true }).first();
  if (await close.isVisible().catch(() => false)) await close.click();
  await row(page, `INV-T-${id}`).getByRole('button', { name: 'View', exact: true }).click();
  await page.waitForFunction(no => document.querySelector('.modal')?.innerText.includes(no), `INV-T-${id}`);
  await page.waitForFunction(() => modalButton('Print') && !modalButton('Print').disabled);
}
async function print(page) {
  const before = await page.evaluate(() => window.__printed.length);
  await page.getByRole('button', { name: 'Print', exact: true }).click();
  await page.waitForFunction(n => window.__printed.length > n, before);
  return page.evaluate(() => window.__printed[window.__printed.length - 1]);
}
async function download(page, button, keepAs = null) {
  const wait = page.waitForEvent('download');
  await page.getByRole('button', { name: button, exact: true }).click();
  const d = await wait;
  if (keepAs) await d.saveAs(keepAs);
  return readFile(await d.path());
}
/** Every string drawn on the image last saved. */
const imageTexts = page => page.evaluate(() => (window.__imageCanvas?.__texts ?? []).map(x => x.text));
/** Each half of the print: its own HTML. */
const halves = html => html.split('<div class="cut">');
/** A half's totals table and its PAYMENT METHODS table, as plain rows: 'label | value'. */
const tableRows = (half, cls) => {
  const m = half.match(new RegExp(`<table class="${cls}">([\\s\\S]*?)</table>`));
  if (!m) return null;
  return [...m[1].matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)].map(r => [...r[1].matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)]
    .map(c => c[1].replace(/<[^>]+>/g, '').trim()).join(' | '));
};
/** The print laid out as printed, A4 landscape, with a picture of it. */
async function printed(page, html, picture) {
  const sheet = await page.context().newPage();
  await sheet.setViewportSize({ width: 1123, height: 794 });
  await sheet.addInitScript(() => { window.print = () => { window.__printed = true; }; });
  await sheet.route('**/*', route => route.request().url() === 'https://print.test/' ? route.fulfill({ contentType: 'text/html; charset=utf-8', body: html }) : route.abort());
  await sheet.goto('https://print.test/');
  await sheet.waitForFunction(() => window.__printed === true);
  await sheet.screenshot({ path: picture });
  const layout = await sheet.evaluate(() => [...document.querySelectorAll('.copy')].map(c => {
    const totals = c.querySelector('table.totals');
    const lines = [...totals.querySelectorAll('tr.wallet-line, tr.wallet-note')];
    return { lines: lines.map(r => ({ height: r.getBoundingClientRect().height, text: r.innerText.replace(/\s+/g, ' ').trim() })),
             totalsRight: Math.round(totals.getBoundingClientRect().right), copyRight: Math.round(c.getBoundingClientRect().right),
             overflow: c.scrollWidth > c.clientWidth + 1 };
  }));
  await sheet.close();
  return layout;
}

try {
  const page = await openPage();

  // ---- The user's example: all of it from Credit Package credit --------------
  await view(page, 'credit');
  {
    const screen = await page.getByTestId('invoice-wallet-totals').innerText();
    ok('the screen: Subtotal, Discount, the credit\'s line, Total what it left, Paid in money',
      /Subtotal\s+S\$327\.00/.test(screen) && /Discount\s+−S\$0\.00/.test(screen) && /Wallet — Credit Package\s+−S\$327\.00/.test(screen)
        && /Total\s+S\$0\.00/.test(screen) && /Paid S\$0\.00/.test(screen), screen);
    const recorded = await page.locator('.invoice-payment-record').allInnerTexts();
    ok('the screen\'s Payments Recorded still lists the wallet payment, to correct it there',
      recorded.length === 1 && recorded[0].includes('Wallet — Credit Package Paid') && recorded[0].includes('S$327.00'), JSON.stringify(recorded));
    await page.locator('.modal').first().screenshot({ path: '.invoice-test/browser/wallet-screen-credit.png' });
  }
  let html = await print(page);
  for (const [n, half] of halves(html).entries()) {
    const copy = n === 0 ? 'customer copy' : 'office copy';
    ok(`print, ${copy}: the totals read Subtotal, Discount, Wallet — Credit Package, Total S$0.00`,
      JSON.stringify(tableRows(half, 'totals')) === JSON.stringify(['Subtotal | S$327.00', 'Discount | −S$0.00', 'Wallet — Credit Package | −S$327.00', 'Total | S$0.00']),
      JSON.stringify(tableRows(half, 'totals')));
    // The credit balance's breakdown keeps each name with its amount (&nbsp;, creditBalanceLine.mjs).
    const flat = half.replace(/&nbsp;/g, ' ');
    ok(`print, ${copy}: no PAYMENT METHODS (credit paid everything), and the credit balance stays`,
      !half.includes('Payment Methods') && !half.includes('Wallet — Credit Package Paid') && flat.includes('Credit balance (as at 13 Nov 2026)')
        && flat.includes('Credit Package S$3381.00 · Premium Bundle S$7636.00') && flat.includes('<strong>S$11017.00</strong>'),
      (flat.match(/Credit balance[\s\S]{0,300}/) || [''])[0].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' '));
  }
  {
    const layout = await printed(page, html, '.invoice-test/browser/wallet-print-credit.png');
    ok('laid out: the credit line is one line on both halves, the totals inside the half', layout.length === 2
      && layout.every(l => l.lines.length === 1 && l.lines[0].height < 20 && l.totalsRight <= l.copyRight && !l.overflow), JSON.stringify(layout));
  }
  let pdf = pdfText(await download(page, 'PDF', '.invoice-test/browser/wallet-credit.pdf'));
  ok('the PDF: the credit\'s line with an ASCII minus, Total S$0.00, no payment rows',
    pdf.includes('(Wallet — Credit Package)') && pdf.includes('(-S$327.00)') && pdf.includes('(S$0.00)')
      && !pdf.includes('PAYMENT METHODS') && !pdf.includes('Wallet — Credit Package Paid') && !pdf.includes('(Paid)'));
  await download(page, 'Image', '.invoice-test/browser/wallet-image-credit.png');
  let img = await imageTexts(page);
  ok('the image: the same', img.includes('Wallet — Credit Package') && img.includes('-S$327.00') && img.includes('S$0.00')
    && !img.includes('PAYMENT METHODS') && !img.some(t => t.startsWith('Wallet — Credit Package Paid')), JSON.stringify(img.filter(t => /Wallet|Total|S\$0/.test(t))));

  // ---- Part credit, part money ------------------------------------------------
  await view(page, 'mixed');
  html = await print(page);
  for (const half of halves(html)) {
    ok('print: Total is what the credit left; PAYMENT METHODS lists the PayNow and Paid counts it alone',
      JSON.stringify(tableRows(half, 'totals')) === JSON.stringify(['Subtotal | S$327.00', 'Discount | −S$0.00', 'Wallet — Credit Package | −S$200.00', 'Total | S$127.00'])
        && JSON.stringify(tableRows(half, 'paytbl')) === JSON.stringify(['PayNow · 11/11/2026 | S$127.00', 'Paid | S$127.00']),
      JSON.stringify([tableRows(half, 'totals'), tableRows(half, 'paytbl')]));
  }
  await printed(page, html, '.invoice-test/browser/wallet-print-mixed.png');
  pdf = pdfText(await download(page, 'PDF'));
  ok('the PDF: the credit line, Paid S$127.00, Total S$127.00, the PayNow row alone',
    pdf.includes('(-S$200.00)') && pdf.includes('(PayNow · 11/11/2026)') && !pdf.includes('Wallet — Credit Package Paid ·')
      && count(pdf, '(S$127.00)') === 3);
  {
    const screen = await page.getByTestId('invoice-wallet-totals').innerText();
    ok('the screen: Total S$127.00 and Paid S$127.00', /Total\s+S\$127\.00/.test(screen) && /Paid S\$127\.00/.test(screen), screen);
  }

  // ---- A package's Paid and Bonus credit together --------------------------
  await view(page, 'bonus');
  html = await print(page);
  ok('print: Credit Package Paid and Bonus are one line, S$350.00; the cash is the payment row',
    halves(html).every(h => JSON.stringify(tableRows(h, 'totals')) === JSON.stringify(['Subtotal | S$400.00', 'Discount | −S$0.00', 'Wallet — Credit Package | −S$350.00', 'Total | S$50.00'])
      && JSON.stringify(tableRows(h, 'paytbl')) === JSON.stringify(['Cash · 11/11/2026 | S$50.00', 'Paid | S$50.00'])),
    JSON.stringify(tableRows(halves(html)[0], 'totals')));

  // ---- Credit refunded back into the wallet ---------------------------------
  await view(page, 'returned');
  {
    const screen = await page.getByTestId('invoice-wallet-totals').innerText();
    ok('the screen: the line keeps the credit used, the note under it says what went back and when',
      /Wallet — Credit Package\s+−S\$921\.00/.test(screen) && screen.includes('S$327.00 returned to wallet 12/11/2026') && /Total\s+S\$0\.00/.test(screen), screen);
  }
  html = await print(page);
  for (const half of halves(html)) {
    ok('print: the note under the credit line; Total S$0.00; no money refunded and no PAYMENT METHODS',
      JSON.stringify(tableRows(half, 'totals')) === JSON.stringify(['Subtotal | S$921.00', 'Discount | −S$0.00', 'Wallet — Credit Package | −S$921.00',
        'S$327.00 returned to wallet 12/11/2026', 'Total | S$0.00']) && !half.includes('Payment Methods') && !half.includes('Refunded'),
      JSON.stringify(tableRows(half, 'totals')));
  }
  {
    const layout = await printed(page, html, '.invoice-test/browser/wallet-print-returned.png');
    ok('laid out: the line and its note one line each', layout.every(l => l.lines.length === 2 && l.lines.every(x => x.height < 20)), JSON.stringify(layout));
  }
  pdf = pdfText(await download(page, 'PDF', '.invoice-test/browser/wallet-returned.pdf'));
  ok('the PDF carries the note', pdf.includes('(S$327.00 returned to wallet 12/11/2026)') && pdf.includes('(-S$921.00)') && !pdf.includes('(Refunded)'));
  await download(page, 'Image');
  img = await imageTexts(page);
  ok('and so does the image', img.includes('S$327.00 returned to wallet 12/11/2026') && img.includes('-S$921.00'));
  // Refunds that cannot be read: which went back to the wallet is not known, so the copy is as before.
  await page.evaluate(() => { window.__refundsError = true; });
  await view(page, 'cash');
  await view(page, 'returned');
  html = await print(page);
  ok('refunds unreadable: printed as before, the wallet payment and the refund under PAYMENT METHODS',
    !html.includes('<tr class="wallet-line">') && count(html, 'Wallet — Credit Package Paid · 11/11/2026') === 2 && count(html, 'Refunded') === 2
      && halves(html).every(h => tableRows(h, 'totals').at(-1) === 'Total | S$921.00'), JSON.stringify(tableRows(halves(html)[0], 'paytbl')));
  await page.evaluate(() => { window.__refundsError = false; });

  // ---- Other wallet methods keep their own names -----------------------------
  await view(page, 'kinds');
  html = await print(page);
  ok('print: Paid Credit with its source in brackets, then Legacy Credit, each its own line; cash the payment row',
    halves(html).every(h => JSON.stringify(tableRows(h, 'totals')) === JSON.stringify(['Subtotal | S$500.00', 'Discount | −S$0.00',
      'Wallet — Paid Credit (Premium Bundle) | −S$300.00', 'Wallet — Legacy Credit | −S$100.00', 'Total | S$100.00'])
      && JSON.stringify(tableRows(h, 'paytbl')) === JSON.stringify(['Cash · 11/11/2026 | S$100.00', 'Paid | S$100.00'])),
    JSON.stringify(tableRows(halves(html)[0], 'totals')));
  await printed(page, html, '.invoice-test/browser/wallet-print-kinds.png');

  // ---- Money alone: as before -------------------------------------------------
  await view(page, 'cash');
  ok('the screen without wallet credit is as before', (await page.getByTestId('invoice-wallet-totals').count()) === 0
    && (await page.locator('.modal').first().innerText()).includes('Paid S$100.00'));
  html = await print(page);
  ok('print without wallet credit is as before: Total the invoice\'s, the cash and Paid under PAYMENT METHODS',
    !html.includes('<tr class="wallet-line">') && halves(html).every(h => JSON.stringify(tableRows(h, 'totals')) === JSON.stringify(['Subtotal | S$100.00', 'Discount | −S$0.00', 'Total | S$100.00'])
      && JSON.stringify(tableRows(h, 'paytbl')) === JSON.stringify(['Cash · 11/11/2026 | S$100.00', 'Paid | S$100.00'])));

  ok('no browser errors', page.errors.length === 0, page.errors.join(' | '));
  await page.context().close();
  console.log(`\nPASS wallet-credit-lines-browser: ${checks} checks`);
} finally {
  await browser.close();
}
