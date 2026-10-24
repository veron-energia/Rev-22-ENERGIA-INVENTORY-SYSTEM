// The note printed on the invoice (456) through the real Invoices page, in Chrome (the Owner, 22 Oct 2026,
// item 6): "Note printed on the invoice" is on the invoice screen, on both halves of the print above the
// signatures under "Note", on the PDF and on the image (so WhatsApp and email), escaped like everything
// else; the internal Notes ("Internal notes (not printed)") are on none of them; a long note never gets
// cut (the PDF takes another page, the image grows taller), and on a full invoice nothing above it gives way
// for it or runs off a page (its payments come out as without the note); Correct Invoice starts from the
// saved note and sends the new one; and an exchange's own note prints under Exchange Details on its
// replacement invoice.
//
// The real page and the real PDF and image renderers run in Chrome against an in-memory stand-in for
// Supabase (as credit-balance-print-browser.mjs does); every network request is blocked. The customers,
// invoices and notes are invented.
//
// Usage: node scripts/invoices/tests/print-note-browser.mjs
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
const T0 = '2026-10-21T02:00:00Z';
const common = { is_active: true, deleted_at: null };
const owner = { id: 'owner', full_name: 'Test Owner', role: 'owner', ...common };
const inv = (id, over = {}) => ({
  id, invoice_no: `INV-T-${id}`, store_id: 'store', customer_id: 'cust', status: 'paid', subtotal: 100, total_amount: 100,
  paid_amount: 100, discount_total: 0, manual_discount: 0, created_at: T0, paid_at: T0, business_date: '2026-10-21',
  created_by: 'owner', edit_count: 0, notes: null, print_note: null, ...common, ...over,
});
const NOTE = 'Thank you <b>Test Customer</b> & "family"\nCollect the second pair on Friday.';
const NOTE_HTML = 'Thank you &lt;b&gt;Test Customer&lt;/b&gt; &amp; &quot;family&quot;<br/>Collect the second pair on Friday.';
const LONG_LINES = Array.from({ length: 40 }, (_, n) => `Fixture note line ${n + 1}`);
const LONG = LONG_LINES.join('\n');
const EX_NOTE = 'Swapped for the larger size <L>\nCustomer keeps the box';
const FULL_NOTE = 'Thank you, Test Customer.\nCollect the second pair on Friday.';
const FULL = [['full', 9, 10], ['sum', 1, 23]];
const tables = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', address: '1 Example Road #01-01, Singapore 000001', phone: '+6560000000',
    whatsapp_phone: '+6590000000', email: 'shop@example.test', website: 'example.test', co_reg_no: 'TEST0001X',
    paynow_uen: 'TEST0001X', bank_account: '000-000000-0', policy_text: 'Exchanges within 7 days with receipt.\nVouchers are not refundable.', ...common }],
  customers: [{ id: 'cust', full_name: 'Test Customer', phone: '+61255504561', email: 'test.customer@example.com', ...common }],
  profiles: [owner],
  products: [{ id: 'socks', name: 'Test Socks', sku: 'SOCK', product_type: 'own', ...common }],
  store_product_prices: [{ store_id: 'store', product_id: 'socks', selling_price: 100, member_price: 100, non_member_price: 100, availability: 'available', ...common }],
  store_inventory: [{ store_id: 'store', product_id: 'socks', current_qty: 100 }],
  payment_methods: [{ id: 'cash', name: 'Cash', ...common }],
  promotions: [], promotion_store_prices: [], promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
  invoice_promotion_selections: [], invoice_revisions: [], invoice_service_staff: [], warehouses: [],
  vouchers: [], voucher_store_prices: [], special_products: [], therapy_package_rules: [], unlimited_therapy_packages: [],
  unlimited_therapy_store_prices: [], therapy_services: [], therapy_service_stores: [],
  invoices: [
    // A printed note with markup and a line break, and internal notes the system wrote.
    inv('noted', { print_note: NOTE, notes: 'Website order cs_test_SECRETONE (internal)' }),
    inv('plain', { notes: 'Internal only SECRETTWO' }),
    // A replacement invoice: its own notes are the system's; the exchange's note prints.
    inv('exch', { is_exchange: true, exchange_id: 'ex1', notes: 'Exchange EX-T-0001 of invoice INV-T-plain — SECRETTHREE' }),
    // Forty short lines on a six-line invoice: more than the 500 characters the server allows, so the
    // copies are shown never to cut a note, whatever its length.
    inv('longnote', { print_note: LONG, subtotal: 600, total_amount: 600, paid_amount: 600 }),
    // Full invoices with a two-line note, and their twins without one: nine lines and ten payments
    // (two pages), one line and twenty-three payments (one page, the payments in one row).
    ...FULL.flatMap(([id, lines, pays]) => [inv(`${id}note`, { print_note: FULL_NOTE, subtotal: lines * 10, total_amount: lines * 10, paid_amount: pays * 9 }),
      inv(`${id}plain`, { subtotal: lines * 10, total_amount: lines * 10, paid_amount: pays * 9 })]),
  ],
  invoice_payments: ['noted', 'plain', 'exch'].map((id, n) => ({ id: `pay-${n}`, invoice_id: id, payment_method_id: 'cash', amount: 100,
    entry_kind: 'receipt', created_at: T0, effective_at: T0 }))
    .concat([{ id: 'pay-long', invoice_id: 'longnote', payment_method_id: 'cash', amount: 600, entry_kind: 'receipt', created_at: T0, effective_at: T0 }]),
};
assert.ok(LONG.length > 500, 'the long fixture is longer than the page allows, to show the PDF and image never cut a note');
tables.invoice_items = tables.invoices.map(i => ({ id: `line-${i.id}`, invoice_id: i.id, line_kind: 'product', product_id: 'socks', quantity: 1,
  unit_price: 100, line_total: 100, topup_amount: 0, foc_quantity: 0 }));
for (let n = 2; n <= 6; n++) tables.invoice_items.push({ ...tables.invoice_items.find(x => x.invoice_id === 'longnote'), id: `line-longnote-${n}` });
for (const [base, lines, pays] of FULL) for (const id of [`${base}note`, `${base}plain`]) {
  const first = tables.invoice_items.find(x => x.invoice_id === id);
  Object.assign(first, { unit_price: 10, line_total: 10 });
  for (let n = 2; n <= lines; n++) tables.invoice_items.push({ ...first, id: `line-${id}-${n}` });
  for (let n = 1; n <= pays; n++) tables.invoice_payments.push({ id: `pay-${id}-${n}`, invoice_id: id, payment_method_id: 'cash', amount: 9,
    entry_kind: 'receipt', created_at: T0, effective_at: T0 });
}
const exchangeDetails = { found: true, exchange_no: 'EX-T-0001', original_invoice_no: 'INV-T-plain', original_invoice_id: 'plain',
  reason: 'Wrong size', notes: EX_NOTE, returned_items: [{ product: 'Test Socks', quantity: 1, unit_price: 100, line_total: 100 }],
  returned_total: 100, replacement_items: [{ product: 'Test Socks', quantity: 1, unit_price: 100, line_total: 100 }], replacement_total: 100,
  exchange_credit_applied: 100, nonrefundable: 0, foc_waived: 0, net_topup: 0, payments: [], processed_by: 'Test Owner', processing_store: 'Test Store' };

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
      if (key === 'then') return (ok, bad) => Promise.resolve({ data: structuredClone(one ? (rows[0] || null) : rows), error: null }).then(ok, bad);
      return (...a) => {
        if (key === 'eq' || key === 'is') rows = rows.filter(r => r[a[0]] === a[1]);
        if (key === 'in') rows = rows.filter(r => a[1].includes(r[a[0]]));
        if (key === 'single' || key === 'maybeSingle') one = true; return q; };
    } });
    return q;
  }
  const finance = i => ({ total: Number(i.total_amount), net_received: Number(i.paid_amount), outstanding: Math.max(0, i.total_amount - i.paid_amount), refund_due: 0, refunded: 0, status: i.status });
  async function rpcImpl(name, args) {
    calls.push({ name, args: structuredClone(args) });
    const find = id => t().invoices.find(i => i.id === id);
    switch (name) {
      case 'invoice_list_page': {
        const rows = t().invoices.map(i => ({ ...i, customer_name: 'Test Customer' }));
        return { data: { rows, total: rows.length, pages: 1, summary: { matching: rows.length, total_amount: 0, outstanding: 0, paid: 0 } }, error: null };
      }
      case 'customer_credit_balances': return { data: { customer_id: args.p_customer_id, categories: { paid: 0, bonus: 0, legacy: 0, promotional: 0, exchange: 0 }, available_total: 0 }, error: null };
      case 'invoice_financial_position': return { data: finance(find(args.p_invoice_id)), error: null };
      case 'invoice_refund_options': return { data: { financial: finance(find(args.p_invoice_id)), sources: [], stock: [], benefits: [], lines: [], review_required: false }, error: null };
      case 'invoice_effective_affiliate': return { data: { found: true, has_affiliate: false }, error: null };
      case 'invoice_benefit_review_options': return { data: { lines: [] }, error: null };
      case 'exchange_invoice_details': return { data: args.p_invoice_id === 'exch' ? window.__exchange : { found: false }, error: null };
      // The correction summary: the test reads what was sent and stops here.
      case 'preview_invoice_correction': return { data: null, error: { message: 'Stopped by the test' } };
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
/** Text drawn into a jsPDF file: strings are written as (…) with \\( \\) \\\\ escapes. */
const pdfText = bytes => Buffer.from(bytes).toString('latin1').replace(/\\([()\\])/g, '$1').replace(/\xb7/g, '·');

async function openPage() {
  const context = await browser.newContext({ timezoneId: 'Asia/Singapore', acceptDownloads: true, viewport: { width: 1400, height: 1000 } });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/' ? route.fulfill({ contentType: 'text/html', body: HTML }) : route.abort());
  await page.goto('https://invoice.test/');
  await page.clock.setFixedTime(new Date('2026-10-22T04:00:00Z'));
  await page.evaluate(([t, ex, p]) => {
    window.__tables = t; window.__exchange = ex; window.__profile = p; window.__calls = []; window.__printed = [];
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
  }, [tables, exchangeDetails, owner]);
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
/** The image last saved: its height and every string drawn on it, with where. */
const image = page => page.evaluate(() => ({ height: window.__imageCanvas?.height ?? 0, width: window.__imageCanvas?.width ?? 0,
  texts: window.__imageCanvas?.__texts ?? [] }));
/** Every string drawn on each page of a PDF, with how far it is from the foot, in mm. */
const pdfPages = bytes => {
  const raw = Buffer.from(bytes).toString('latin1');
  const re = /(-?[\d.]+) (-?[\d.]+) Td\s*\(((?:\\.|[^\\)])*)\) Tj/g;
  return raw.split('endstream').slice(0, -1).map(s => s.slice(s.lastIndexOf('stream') + 6)).map(st => {
    const out = [];
    for (let m; (m = re.exec(st));) out.push({ mm: Number(m[2]) / (72 / 25.4), text: m[3].replace(/\\([()\\])/g, '$1').replace(/\xb7/g, '·') });
    return out;
  }).filter(p => p.length);
};
/** The payment rows drawn: how many listed, and how many summary rows. */
const paymentRows = texts => JSON.stringify([texts.filter(t => /^Cash · /.test(t)).length,
  texts.filter(t => /^Payments: \d+; full list on the store copy$/.test(t)).length]);
/** Each half of the print: its own HTML. */
const halves = html => html.split('<div class="cut">');

try {
  const page = await openPage();

  // ---- The invoice with a printed note -----------------------------------
  await view(page, 'noted');
  const modal = await page.locator('.modal').first().innerText();
  ok('the invoice screen shows the note printed on the invoice', modal.includes('Note printed on the invoice')
    && modal.includes('Thank you <b>Test Customer</b> & "family"') && modal.includes('Collect the second pair on Friday.'));
  ok('and not the internal notes', !modal.includes('SECRETONE'));
  let html = await print(page);
  ok('both halves print it under "Note", escaped, its line break kept',
    count(html, '<h2>Note</h2>') === 2 && count(html, NOTE_HTML) === 2 && !html.includes('<b>Test Customer</b>'));
  ok('above the signatures and after the payments, on each half', halves(html).every(h =>
    h.indexOf('<h2>Note</h2>') > h.indexOf('Payment Methods') && h.indexOf('<h2>Note</h2>') < h.indexOf('class="signrow"')));
  ok('the internal notes print on neither half', !html.includes('SECRETONE'));
  {
    // Laid out as printed: the note sits whole above the signatures and each half keeps its footer.
    const sheet = await page.context().newPage();
    await sheet.setViewportSize({ width: 1123, height: 794 });
    await sheet.addInitScript(() => { window.print = () => { window.__printed = true; }; });
    await sheet.route('**/*', route => route.request().url() === 'https://print.test/' ? route.fulfill({ contentType: 'text/html', body: html }) : route.abort());
    await sheet.goto('https://print.test/');
    await sheet.waitForFunction(() => window.__printed === true);
    await sheet.screenshot({ path: '.invoice-test/browser/print-note.png' });
    const layout = await sheet.evaluate(() => [...document.querySelectorAll('.copy')].map(c => {
      const note = c.querySelector('[data-testid="print-note"]').getBoundingClientRect();
      const sign = c.querySelector('.signrow').getBoundingClientRect();
      const box = c.getBoundingClientRect();
      const n = c.querySelector('[data-testid="print-note"]');
      return { above: note.bottom <= sign.top + 0.5, whole: n.scrollHeight <= n.clientHeight + 0.5,
               footer: c.querySelector('.footer').getBoundingClientRect().bottom <= box.bottom + 0.5,
               lines: n.innerText.split('\n').length };
    }));
    ok('rendered: on both halves the note is whole, above the signatures, and the footer is on the half',
      layout.length === 2 && layout.every(l => l.above && l.whole && l.footer && l.lines === 2), JSON.stringify(layout));
    await sheet.close();
  }
  let pdf = pdfText(await download(page, 'PDF', '.invoice-test/browser/print-note.pdf'));
  ok('the PDF draws it under NOTE', pdf.includes('(NOTE)') && pdf.includes('(Thank you <b>Test Customer</b> & "family")')
    && pdf.includes('(Collect the second pair on Friday.)'));
  ok('and not the internal notes', !pdf.includes('SECRETONE'));
  await download(page, 'Image', '.invoice-test/browser/print-note-image.png');
  let img = await image(page);
  const at = (texts, t) => texts.find(x => x.text === t);
  ok('the image draws it under NOTE, above the signatures, on one A5 page',
    !!at(img.texts, 'NOTE') && at(img.texts, 'Thank you <b>Test Customer</b> & "family"')?.y > at(img.texts, 'NOTE').y
      && at(img.texts, 'Collect the second pair on Friday.')?.y < at(img.texts, 'Staff Signature').y && img.height === 1680,
    JSON.stringify({ height: img.height, note: at(img.texts, 'NOTE') }));
  ok('and not the internal notes', !img.texts.some(x => x.text.includes('SECRETONE')));

  // ---- Correct Invoice starts from the saved note and sends the new one ---
  await page.getByRole('button', { name: 'Correct Invoice', exact: true }).click();
  const box = page.locator('[data-testid="invoice-print-note"]');
  await box.waitFor();
  ok('Correct Invoice shows the two boxes, each with what is saved',
    await box.inputValue() === NOTE && await page.locator('[data-testid="invoice-internal-notes"]').inputValue() === 'Website order cs_test_SECRETONE (internal)'
      && (await page.locator('.modal').last().innerText()).includes('Internal notes (not printed)')
      && Number(await box.getAttribute('maxlength')) === 500);
  await box.fill('Collect the second pair on Saturday.');
  await page.getByPlaceholder('e.g. Wrong quantity keyed at the till').fill('Customer asked');
  await page.getByRole('button', { name: 'Review Changes', exact: true }).click();
  await page.waitForFunction(() => window.__calls.some(c => c.name === 'preview_invoice_correction'));
  const sent = await page.evaluate(() => window.__calls.filter(c => c.name === 'preview_invoice_correction').at(-1).args.p_header);
  ok('Review Changes sends the new note in the header, the internal notes as they were',
    sent.print_note === 'Collect the second pair on Saturday.' && sent.notes === 'Website order cs_test_SECRETONE (internal)', JSON.stringify(sent));
  await page.getByRole('button', { name: 'Cancel', exact: true }).last().click();

  // ---- An invoice without one ----------------------------------------------
  await view(page, 'plain');
  html = await print(page);
  ok('an invoice with no printed note prints no Note, and never its internal notes',
    !html.includes('<h2>Note</h2>') && !html.includes('SECRETTWO'));
  pdf = pdfText(await download(page, 'PDF'));
  await download(page, 'Image');
  img = await image(page);
  ok('nor its PDF or image', !pdf.includes('(NOTE)') && !pdf.includes('SECRETTWO') && !at(img.texts, 'NOTE') && !img.texts.some(x => x.text.includes('SECRETTWO')));

  // ---- A replacement invoice: the exchange's own note under Exchange Details ---
  await view(page, 'exch');
  const exModal = await page.locator('.modal').first().innerText();
  ok('the replacement invoice\'s screen shows the exchange\'s note', exModal.includes('Note: Swapped for the larger size <L>') && !exModal.includes('SECRETTHREE'));
  html = await print(page);
  const exNoteHtml = 'Note: Swapped for the larger size &lt;L&gt;<br/>Customer keeps the box';
  ok('both halves print it under Exchange Details, before the returned items, escaped',
    count(html, exNoteHtml) === 2 && halves(html).every(h => h.indexOf('<h2>Exchange Details</h2>') < h.indexOf(exNoteHtml)
      && h.indexOf(exNoteHtml) < h.indexOf('Returned Item')));
  ok('its own (system) notes print nowhere, and it has no Note of its own', !html.includes('SECRETTHREE') && !html.includes('<h2>Note</h2>'));
  pdf = pdfText(await download(page, 'PDF', '.invoice-test/browser/print-note-exchange.pdf'));
  ok('the PDF draws it under EXCHANGE DETAILS', pdf.includes('(EXCHANGE DETAILS)') && pdf.includes('(Note: Swapped for the larger size <L>)')
    && pdf.includes('(Customer keeps the box)') && !pdf.includes('SECRETTHREE'));
  await download(page, 'Image');
  img = await image(page);
  ok('and so does the image, above Bill To', !!at(img.texts, 'EXCHANGE DETAILS') && at(img.texts, 'Customer keeps the box')?.y < at(img.texts, 'BILL TO').y
    && !img.texts.some(x => x.text.includes('SECRETTHREE')));

  // ---- Full invoices: nothing above the note gives way for it or runs off ---
  const shapes = [];
  for (const [base, lines, pays] of FULL) {
    const what = `${lines} line(s), ${pays} payments`;
    await view(page, `${base}plain`);
    const plainPdf = pdfPages(await download(page, 'PDF'));
    await download(page, 'Image');
    const plainImg = await image(page);
    await view(page, `${base}note`);
    const notePdf = pdfPages(await download(page, 'PDF', `.invoice-test/browser/print-note-${base}.pdf`));
    await download(page, 'Image', `.invoice-test/browser/print-note-${base}.png`);
    const noteImg = await image(page);
    const low = notePdf.flatMap((p, k) => p.filter(i => i.mm < 8 - 0.05).map(i => `page ${k + 1}: ${i.text} ${i.mm.toFixed(1)} mm`));
    ok(`${what}: the PDF with a note draws nothing lower than 8 mm from the foot of any page`, low.length === 0, low.join(' | '));
    const pdfTexts = pp => pp.flat().map(i => i.text);
    ok(`${what}: its payments come out as on the same invoice without the note, and every line of the note is drawn`,
      paymentRows(pdfTexts(notePdf)) === paymentRows(pdfTexts(plainPdf)) && FULL_NOTE.split('\n').every(l => pdfTexts(notePdf).includes(l))
        && notePdf.at(-1).some(i => i.text === 'Staff Signature') && notePdf.at(-1).some(i => i.text.includes('Co. Reg No.')),
      `${paymentRows(pdfTexts(notePdf))} vs ${paymentRows(pdfTexts(plainPdf))}, ${notePdf.length} page(s) vs ${plainPdf.length}`);
    const imgTexts = im => im.texts.map(x => x.text);
    ok(`${what}: the image too: the same payments as without the note, the note above the signatures, all of it on the image`,
      paymentRows(imgTexts(noteImg)) === paymentRows(imgTexts(plainImg))
        && FULL_NOTE.split('\n').every(l => at(noteImg.texts, l)?.y < at(noteImg.texts, 'Staff Signature').y)
        && noteImg.texts.every(x => x.y <= noteImg.height) && noteImg.texts.some(x => x.text.includes('Co. Reg No.')) && noteImg.height >= plainImg.height,
      `${paymentRows(imgTexts(noteImg))} vs ${paymentRows(imgTexts(plainImg))}, heights ${noteImg.height} vs ${plainImg.height}`);
    shapes.push(`${paymentRows(pdfTexts(plainPdf))}/${plainPdf.length}`);
  }
  ok('the two full invoices cover a copy on two pages with every payment and one on a page with their summary',
    shapes[0] === '[10,0]/2' && shapes[1] === '[0,1]/1', shapes.join(' '));

  // ---- A long note is never cut ------------------------------------------
  await view(page, 'longnote');
  pdf = pdfText(await download(page, 'PDF', '.invoice-test/browser/print-note-long.pdf'));
  ok('the PDF of a long note takes another page and draws every line', /Page 2 of [23]/.test(pdf)
    && LONG_LINES.every(l => pdf.includes(`(${l})`)), LONG_LINES.filter(l => !pdf.includes(`(${l})`)).join(', '));
  await download(page, 'Image', '.invoice-test/browser/print-note-long.png');
  img = await image(page);
  const lastLine = at(img.texts, LONG_LINES.at(-1));
  ok('the image grows taller and draws every line, the signatures and the footer after them',
    img.height > 1680 && LONG_LINES.every(l => !!at(img.texts, l)) && lastLine.y < at(img.texts, 'Staff Signature').y
      && img.texts.every(x => x.y <= img.height) && img.texts.some(x => x.text.includes('Co. Reg No.')),
    JSON.stringify({ height: img.height }));
  html = await print(page);
  ok('the print carries all of it on both halves', count(html, LONG_LINES.join('<br/>')) === 2);

  ok('no browser errors', page.errors.length === 0, page.errors.join(' | '));
  await page.context().close();
  console.log(`\nPASS print-note-browser: ${checks} checks`);
} finally {
  await browser.close();
}
