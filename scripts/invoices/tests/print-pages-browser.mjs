// A printed invoice longer than one A4 sheet (the Owner, 22 Oct 2026, item 5), through the real
// Invoices page, in Chrome:
//  (a) each A4 landscape sheet holds page k of the customer copy (left) and page k of the office copy
//      (right), the cut line between them, the two copies in step; an invoice that fits one sheet
//      prints exactly as before (laid out to the pixel as the same markup without the page wrappers);
//  (b) page 2 onward starts with a compact line (Energia, the number, CUSTOMER COPY / OFFICE COPY
//      (continued), Page k of N) and the item table's head again; the full header and Bill To on
//      page 1 only;
//  (c) the totals, payments, signatures, terms, policy and footer only on the last page, whole, with
//      at least the last item line; every page but the last says "Continued on page k+1"; a line and
//      its promotion sub-rows never split unless the line alone is taller than a page; nothing on any
//      page runs past its half. Past the owner's rules, for what cannot keep them: a printed note
//      taller than a page goes on between its lines, and an exchange invoice's returned items between
//      their rows under their head again, so nothing is cut off; a first line that does not fit under
//      the header (or the only line, with the tail) starts page 2, whole;
//  (d) the PDF lists every line on as many A5 pages as it needs, each saying Page k of N, with no
//      "see the full invoice in store" cut; the image grows to about six A5 pages, then points to the
//      PDF.
//
// The real page and the real PDF and image renderers run in Chrome against an in-memory stand-in for
// Supabase (as credit-balance-print-browser.mjs does); every network request is blocked. Customers,
// products and amounts are invented.
//
// PRINT_PAGES_CAPTURE=<dir>: only write each invoice's print window HTML there (run once on the code
// before this change). PRINT_PAGES_BEFORE=<dir>: also check that each one-page invoice lays out to
// the pixel as that capture did.
//
// Usage: node scripts/invoices/tests/print-pages-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });
const CAPTURE = process.env.PRINT_PAGES_CAPTURE || null;
const BEFORE = process.env.PRINT_PAGES_BEFORE || null;

// ---------------------------------------------------------------------------
// Fixtures (invented)
// ---------------------------------------------------------------------------
const T0 = '2026-10-21T02:00:00Z';
const common = { is_active: true, deleted_at: null };
const owner = { id: 'owner', full_name: 'Test Owner', role: 'owner', ...common };
const LOGO = 'data:image/svg+xml;base64,' + Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="160" height="48"><rect width="160" height="48" fill="#888"/></svg>').toString('base64');
const POLICY = 'Items may be exchanged within 7 days with the receipt and the original box, after a check in store. '
  + 'Orders paid by deposit are final. Therapy packages run 12 months from the day they start.';
const NOTE_LINES = Array.from({ length: 45 }, (_, n) => `Note ${String(n + 1).padStart(2, '0')}`);
// Notes the server allows (500 characters at most) that are taller than a page: 120 one-character
// lines, and 62 short ones.
const NOTE_120 = Array.from({ length: 120 }, (_, n) => String(n % 10)).join('\n');
const NOTE_62 = Array.from({ length: 62 }, (_, n) => `Line ${String(n + 1).padStart(2, '0')}`).join('\n');
const NOTE_25 = NOTE_LINES.slice(0, 25).join('\n');
// An exchange invoice's own details (exchange_invoice_details), with k returned items.
const exchangeOf = (k, note = null) => ({ found: true, exchange_no: 'EX-T-0009', original_invoice_no: 'INV-T-0', reason: 'Test size', notes: note,
  returned_items: Array.from({ length: k }, (_, n) => ({ product: `Returned Test ${n + 1}`, quantity: 1, line_total: 10 })), returned_total: k * 10, foc_waived: 0 });
const EXCHANGES = { exch3: exchangeOf(3), exch25: exchangeOf(25), exch40: exchangeOf(40), exchnote: exchangeOf(4, NOTE_120) };
const inv = (id, over = {}) => ({
  id, invoice_no: `INV-T-${id}`, store_id: 'store', customer_id: 'cust', status: 'paid', subtotal: 100, total_amount: 100,
  paid_amount: 100, discount_total: 0, manual_discount: 0, created_at: T0, paid_at: T0, business_date: '2026-10-21',
  created_by: 'owner', edit_count: 0, notes: null, print_note: null, ...common, ...over,
});
// [id, product lines, promotion lines (3 contents each), big promotion lines (70 contents), payments, extra,
//  options: first (a promotion line put first)]
const SHAPES = [
  ['five', 5, 0, 0, 1, {}],
  ['sixteen', 16, 0, 0, 1, {}],
  ['seventeen', 17, 0, 0, 1, {}],
  ['twenty', 20, 0, 0, 1, {}],
  ['sixty', 60, 0, 0, 2, {}],
  ['promo', 2, 14, 0, 1, {}],
  ['tall', 3, 0, 1, 1, {}],
  ['longnote', 6, 0, 0, 3, { print_note: NOTE_LINES.join('\n') }],
  ['many', 150, 0, 0, 1, {}],
  // The review of 23 Oct 2026: a note taller than a page; the only line and a tail that does not fit
  // under the header; a first line that does not fit under it; exchanges with many returned items.
  ['bignote', 20, 0, 0, 1, { print_note: NOTE_120 }],
  ['note62', 6, 0, 0, 3, { print_note: NOTE_62 }],
  ['oneline', 1, 0, 0, 1, { print_note: NOTE_25 }],
  ['firstpromo', 19, 0, 0, 1, {}, { first: 'promo45' }],
  ['exch3', 5, 0, 0, 1, { is_exchange: true, exchange_id: 'exch3' }],
  ['exch25', 20, 0, 0, 1, { is_exchange: true, exchange_id: 'exch25' }],
  ['exch40', 20, 0, 0, 1, { is_exchange: true, exchange_id: 'exch40' }],
  ['exchnote', 8, 0, 0, 1, { is_exchange: true, exchange_id: 'exchnote' }],
];
const tables = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', address: '1 Example Road #01-01, Singapore 000001', phone: '+6560000000',
    whatsapp_phone: '+6590000000', email: 'shop@example.test', website: 'example.test', co_reg_no: 'TEST0001X',
    paynow_uen: 'TEST0001X', bank_account: '000-000000-0', policy_text: POLICY, company_logo_url: LOGO, ...common }],
  customers: [{ id: 'cust', full_name: 'Test Customer', phone: '+61255504561', email: 'test.customer@example.com', ...common }],
  profiles: [owner],
  products: [{ id: 'socks', name: 'Test Socks', sku: 'SOCK', product_type: 'own', ...common },
    ...Array.from({ length: 70 }, (_, n) => ({ id: `c${n + 1}`, name: `Test Content ${n + 1}`, sku: `C${n + 1}`, product_type: 'own', ...common }))],
  store_product_prices: [{ store_id: 'store', product_id: 'socks', selling_price: 10, member_price: 10, non_member_price: 10, availability: 'available', ...common }],
  store_inventory: [{ store_id: 'store', product_id: 'socks', current_qty: 1000 }],
  payment_methods: [{ id: 'cash', name: 'Cash', ...common }],
  promotions: [{ id: 'promo3', name: 'Test Bundle', code: 'TB', ...common }, { id: 'promo70', name: 'Test Big Bundle', code: 'TBB', ...common },
    { id: 'promo45', name: 'Test Long Bundle', code: 'TLB', ...common }],
  promotion_items: [
    ...[1, 2, 3].map(n => ({ id: `pi3-${n}`, promotion_id: 'promo3', product_id: `c${n}`, quantity: 1 })),
    ...Array.from({ length: 70 }, (_, n) => ({ id: `pi70-${n + 1}`, promotion_id: 'promo70', product_id: `c${n + 1}`, quantity: 1 })),
    ...Array.from({ length: 45 }, (_, n) => ({ id: `pi45-${n + 1}`, promotion_id: 'promo45', product_id: `c${n + 1}`, quantity: 1 })),
  ],
  promotion_store_prices: [], promotion_choice_groups: [], promotion_choice_options: [],
  invoice_promotion_selections: [], invoice_revisions: [], invoice_service_staff: [], warehouses: [],
  vouchers: [], voucher_store_prices: [], special_products: [], therapy_package_rules: [], unlimited_therapy_packages: [],
  unlimited_therapy_store_prices: [], therapy_services: [], therapy_service_stores: [],
  invoices: [], invoice_items: [], invoice_payments: [],
};
for (const [id, products, promos, big, pays, over, opts = {}] of SHAPES) {
  const n = products + promos + big + (opts.first ? 1 : 0);
  tables.invoices.push(inv(id, { subtotal: n * 10, total_amount: n * 10, paid_amount: n * 10, ...over }));
  let k = 0;
  const lineOf = (extra) => ({ id: `line-${id}-${++k}`, invoice_id: id, line_kind: 'product', product_id: 'socks', quantity: 1,
    unit_price: 10, line_total: 10, topup_amount: 0, foc_quantity: 0, ...extra });
  // Product lines first, then the promotions, then the rest: a big promotion sits in the middle.
  if (opts.first) tables.invoice_items.push(lineOf({ line_kind: 'promotion', product_id: null, promotion_id: opts.first }));
  const first = Math.ceil(products / 2);
  for (let j = 0; j < first; j++) tables.invoice_items.push(lineOf({}));
  for (let j = 0; j < promos; j++) tables.invoice_items.push(lineOf({ line_kind: 'promotion', product_id: null, promotion_id: 'promo3' }));
  for (let j = 0; j < big; j++) tables.invoice_items.push(lineOf({ line_kind: 'promotion', product_id: null, promotion_id: 'promo70' }));
  for (let j = first; j < products; j++) tables.invoice_items.push(lineOf({}));
  for (let j = 0; j < pays; j++) tables.invoice_payments.push({ id: `pay-${id}-${j}`, invoice_id: id, payment_method_id: 'cash',
    amount: Number(((n * 10) / pays).toFixed(2)), entry_kind: 'receipt', created_at: T0, effective_at: T0 });
}

// ---------------------------------------------------------------------------
// The stand-in for the Supabase client (as print-note-browser.mjs).
// ---------------------------------------------------------------------------
const mock = `export const supabase = (() => {
  const t = () => window.__tables;
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
      case 'exchange_invoice_details': return { data: window.__exchanges[find(args.p_invoice_id)?.exchange_id] ?? { found: false }, error: null };
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
  // Minified, as the app is built (vite build): the print window's script is written from the
  // bundled functions' own text, so it must work from minified code.
  minify: true,
  plugins: [{ name: 'isolated-fixtures', setup(b) {
    b.onResolve({ filter: /(?:^|\/)supabase$/ }, () => ({ path: 'db', namespace: 'fixture' }));
    b.onResolve({ filter: /\/context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'fixture' }));
    b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => ({ contents: a.path === 'db' ? mock
      : a.path === 'auth' ? `export const useAuth=()=>({profile:window.__profile,session:{user:{id:window.__profile.id}},assignments:[],loading:false});` : '', loader: 'js' }));
  } }],
});
const bundle = built.outputFiles[0].text;
// The shared receipt print (Special Products, Rentals, the exchange document): printA5Document.
const receipts = (await build({
  stdin: { contents: `import { printA5Document } from './src/lib/printDoc'; window.__printA5 = printA5Document;`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, format: 'iife', write: false, minify: true,
})).outputFiles[0].text;
const css = (await readFile('src/styles/globals.css', 'utf8') + '\n' + await readFile('src/components/invoices/invoice-controls.css', 'utf8')).replace(/^@import.*$/gm, '');
const HTML = '<html><head></head><body><div id="root"></div></body></html>';

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => { assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`); checks++; console.log(`  ok  ${label}`); };

async function openPage() {
  const context = await browser.newContext({ timezoneId: 'Asia/Singapore', acceptDownloads: true, viewport: { width: 1400, height: 1000 } });
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/' ? route.fulfill({ contentType: 'text/html', body: HTML }) : route.abort());
  await page.goto('https://invoice.test/');
  await page.clock.setFixedTime(new Date('2026-10-22T04:00:00Z'));
  await page.evaluate(([t, p, ex]) => {
    window.__tables = t; window.__profile = p; window.__exchanges = ex; window.__printed = [];
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
  }, [tables, owner, EXCHANGES]);
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
async function download(page, button) {
  const wait = page.waitForEvent('download');
  await page.getByRole('button', { name: button, exact: true }).click();
  return readFile(await (await wait).path());
}
/** Every string drawn on each page of a PDF. */
const pdfPages = bytes => {
  const raw = Buffer.from(bytes).toString('latin1');
  const re = /(-?[\d.]+) (-?[\d.]+) Td\s*\(((?:\\.|[^\\)])*)\) Tj/g;
  return raw.split('endstream').slice(0, -1).map(s => s.slice(s.lastIndexOf('stream') + 6)).map(st => {
    const out = [];
    for (let m; (m = re.exec(st));) out.push({ mm: Number(m[2]) / (72 / 25.4), text: m[3].replace(/\\([()\\])/g, '$1').replace(/\xb7/g, '·').replace(/\x85/g, '…').replace(/\x97/g, '—') });
    return out;
  }).filter(p => p.length);
};

/** The print window as printed: its HTML served, window.print noted, what each sheet holds read. */
async function render(context, html, name) {
  const sheet = await context.newPage();
  await sheet.setViewportSize({ width: 1123, height: 794 });
  await sheet.addInitScript(() => { window.__prints = 0; window.print = () => { window.__prints++; window.__sheetsAtPrint = document.querySelectorAll('.sheet').length; }; });
  await sheet.route('**/*', route => route.request().url() === 'https://print.test/' ? route.fulfill({ contentType: 'text/html; charset=utf-8', body: html }) : route.abort());
  await sheet.goto('https://print.test/');
  await sheet.waitForFunction(() => window.__prints === 1);
  await sheet.screenshot({ path: `.invoice-test/browser/print-pages-${name}.png`, fullPage: true });
  return sheet;
}
/** What each sheet holds, copy by copy. */
const readSheets = sheet => sheet.evaluate(() => {
  const boxes = el => [...el.children].flatMap(c => { const d = getComputedStyle(c).display; return d === 'contents' ? boxes(c) : d === 'none' ? [] : [c]; });
  return [...document.querySelectorAll('.sheet')].map(s => ({
    kids: [...s.children].map(k => k.className),
    breakAfter: s.style.breakAfter || '',
    copies: [...s.children].filter(k => k.classList.contains('copy')).map(c => {
      const box = c.getBoundingClientRect(), pad = parseFloat(getComputedStyle(c).paddingBottom);
      const low = Math.max(...boxes(c).map(e => e.getBoundingClientRect().bottom));
      const lines = [...c.querySelectorAll('table.p-items > tbody.p-row')].map(tb => [...tb.rows].map(tr => ({ sub: tr.classList.contains('sub'), name: tr.cells[0].textContent.trim() })));
      return {
        // Which copy: its tag on page 1, the compact line's label after.
        tag: (c.querySelector('.copytag') ?? c.querySelector('.p-conthead > div:last-child > b'))?.textContent.trim() ?? null,
        copytag: !!c.querySelector('.copytag'),
        cont: c.querySelector('.p-conthead')?.textContent ?? null,
        pageNo: c.querySelector('.p-pageno')?.textContent ?? null,
        foot: c.querySelector('.p-cont')?.textContent ?? null,
        billTo: [...c.querySelectorAll('h2')].some(h => h.textContent === 'Bill To'),
        logos: !!c.querySelector('img'),
        thead: !!c.querySelector('table.p-items thead'),
        items: !!c.querySelector('table.p-items'),
        lines, rows: lines.flat().map(r => r.name),
        // The exchange's returned items, and whether their table's head is on the page.
        returned: [...c.querySelectorAll('table')].filter(t => t.querySelector('th')?.textContent === 'Returned Item')
          .flatMap(t => [...t.querySelectorAll('tbody tr')].map(tr => tr.cells[0].textContent.trim())),
        returnedHead: [...c.querySelectorAll('table thead th')].some(th => th.textContent === 'Returned Item'),
        // The printed note's lines and the exchange's note's lines on the page.
        notes: [...c.querySelectorAll('[data-testid="print-note"]')].flatMap(n => n.innerText.split('\n')),
        exNotes: [...c.querySelectorAll('[data-testid="print-exchange-note"]')].flatMap(n => n.innerText.split('\n')),
        totals: !!c.querySelector('table.totals'), payments: [...c.querySelectorAll('h2')].some(h => h.textContent === 'Payment Methods'),
        note: !!c.querySelector('[data-testid="print-note"]'), sign: !!c.querySelector('.signrow'), terms: !!c.querySelector('.terms'),
        policy: !!c.querySelector('.policy'), footer: !!c.querySelector('.footer'),
        noteLines: c.querySelector('[data-testid="print-note"]')?.innerText.split('\n').length ?? 0,
        // How far the content runs past the half's content box (≤ 0: inside it), and past its edge.
        overContent: low - (box.bottom - pad), overEdge: low - box.bottom,
        footerAtFoot: c.querySelector('.footer') ? box.bottom - pad - c.querySelector('.footer').getBoundingClientRect().bottom : null,
      };
    }),
  }));
});
/** Every text on the sheet with where it is drawn: two layouts are the same when these are. */
const textBoxes = sheet => sheet.evaluate(() => {
  const out = [], walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n; (n = walk.nextNode());) {
    if (!n.textContent.trim() || n.parentElement.closest('script,style')) continue;
    const r = document.createRange(); r.selectNodeContents(n);
    for (const b of r.getClientRects()) out.push(`${n.textContent.trim().slice(0, 40)}|${b.x.toFixed(2)}|${b.y.toFixed(2)}|${b.width.toFixed(2)}|${b.height.toFixed(2)}`);
  }
  return out;
});
/** The same print window without the page wrappers: one tbody of rows in each table, no .p-head / .p-tail. */
const unwrapped = html => html
  .replace(/<div class="p-(?:head|tail)">/g, '<div data-unwrap>')
  .replace(/<\/body>/, `<script>
    for (const w of [...document.querySelectorAll('[data-unwrap]')]) w.replaceWith(...w.childNodes);
    for (const t of [...document.querySelectorAll('table')].filter(t => t.querySelector(':scope > tbody.p-row'))) { const bs = [...t.querySelectorAll(':scope > tbody')]; if (bs.length) { const one = document.createElement('tbody');
      for (const b of bs) one.append(...b.childNodes); bs[0].replaceWith(one); bs.slice(1).forEach(b => b.remove()); } }
  </script></body>`);

try {
  const page = await openPage();
  const prints = {};
  for (const [id] of SHAPES) { await view(page, id); prints[id] = await print(page); }
  if (CAPTURE) {
    await mkdir(CAPTURE, { recursive: true });
    for (const [id, html] of Object.entries(prints)) await writeFile(`${CAPTURE}/${id}.html`, html);
    console.log(`captured ${Object.keys(prints).length} print windows in ${CAPTURE}`);
    process.exit(0);
  }
  const ctx = page.context();

  // ---- One sheet: exactly as before ---------------------------------------
  for (const id of ['five', 'sixteen', 'exch3']) {
    const html = prints[id];
    if (id === 'exch3') {
      ok('exch3: each returned item its own body, the returned value with the last, the exchange printed whole on one sheet',
        (html.match(/<tbody class="p-row"><tr><td>Returned Test \d+<\/td>/g) || []).length === 6
          && /Returned Test 3<\/td><td class="r">1<\/td><td class="r">S\$10\.00<\/td><\/tr><tr><td colspan="2"><b>Returned value/.test(html));
    }
    ok(`${id}: the print markup wraps the head and tail and gives each line its own body`,
      (html.match(/<div class="p-head">/g) || []).length === 2 && (html.match(/<div class="p-tail">/g) || []).length === 2
        && html.includes('<table class="p-items">') && html.includes('<tbody class="p-row">'));
    const sheet = await render(ctx, html, id);
    const sheets = await readSheets(sheet);
    ok(`${id}: one sheet, nothing added: no page numbers, no compact line, no "Continued"`,
      sheets.length === 1 && sheets[0].copies.every(c => !c.pageNo && !c.cont && !c.foot), JSON.stringify(sheets.map(s => s.copies.map(c => [c.pageNo, c.cont, c.foot]))));
    ok(`${id}: both halves whole, their footers inside the half`, sheets[0].copies.every(c => c.overEdge <= 0.5 && c.footer && c.sign),
      JSON.stringify(sheets[0].copies.map(c => c.overEdge)));
    const now = await textBoxes(sheet);
    const bare = await render(ctx, unwrapped(html), `${id}-unwrapped`);
    const without = await textBoxes(bare);
    ok(`${id}: laid out to the pixel as the same markup without the page wrappers`, JSON.stringify(now) === JSON.stringify(without),
      now.find((t, i) => t !== without[i]) ?? `${now.length} vs ${without.length}`);
    if (BEFORE && existsSync(`${BEFORE}/${id}.html`)) {
      const old = await render(ctx, await readFile(`${BEFORE}/${id}.html`, 'utf8'), `${id}-before`);
      const was = await textBoxes(old);
      ok(`${id}: laid out to the pixel as the same invoice printed before this change`, JSON.stringify(now) === JSON.stringify(was),
        now.find((t, i) => t !== was[i]) ?? `${now.length} vs ${was.length}`);
      await old.close();
    }
    await bare.close(); await sheet.close();
  }

  // ---- Longer than one sheet ----------------------------------------------
  for (const id of ['seventeen', 'twenty', 'sixty', 'promo', 'tall', 'longnote', 'many', 'bignote', 'note62', 'oneline', 'firstpromo', 'exch25', 'exch40', 'exchnote']) {
    const html = prints[id];
    const sheet = await render(ctx, html, id);
    const sheets = await readSheets(sheet);
    const N = sheets.length;
    const allRows = await sheet.evaluate(src => {
      const doc = new DOMParser().parseFromString(src, 'text/html');
      return [...doc.querySelector('.copy').querySelectorAll('table.p-items > tbody.p-row > tr')].map(tr => tr.cells[0].textContent.trim());
    }, html);
    const at = `${id} (${N} sheets)`;
    ok(`${at}: more than one sheet, each the customer copy, the cut line and the office copy`,
      N >= 2 && sheets.every(s => JSON.stringify(s.kids) === JSON.stringify(['copy', 'cut', 'copy']) && s.copies[0].tag === 'CUSTOMER COPY' && s.copies[1].tag === 'OFFICE COPY'),
      JSON.stringify(sheets.map(s => s.kids)));
    ok(`${at}: the two copies in step: the same rows on each sheet`, sheets.every(s => JSON.stringify(s.copies[0].rows) === JSON.stringify(s.copies[1].rows)));
    for (const side of [0, 1]) {
      ok(`${at}: every row printed once, in order, on the ${side ? 'office' : 'customer'} copy`,
        JSON.stringify(sheets.flatMap(s => s.copies[side].rows)) === JSON.stringify(allRows),
        JSON.stringify([sheets.flatMap(s => s.copies[side].rows).find((r, k) => r !== allRows[k]), allRows.find((r, k) => r !== sheets.flatMap(s => s.copies[side].rows)[k])]));
    }
    const copies = sheets.flatMap(s => s.copies);
    ok(`${at}: nothing on any page runs past its half`, copies.every(c => c.overContent <= 0.5), JSON.stringify(copies.map(c => +c.overContent.toFixed(1))));
    ok(`${at}: a page break after every sheet but the last`, sheets.every((s, k) => (s.breakAfter === 'page') === (k < N - 1)), JSON.stringify(sheets.map(s => s.breakAfter)));
    ok(`${at}: page 1 has the full header, logos and Bill To, and says Page 1 of ${N}`,
      sheets[0].copies.every(c => c.copytag && c.billTo && c.logos && c.pageNo === `Page 1 of ${N}` && !c.cont));
    ok(`${at}: page 2 onward starts with the compact line, without the header or Bill To`,
      sheets.slice(1).every((s, k) => s.copies.every(c => !c.copytag && !c.billTo && !c.logos && !c.pageNo
        && c.cont === `Energia · INV-T-${id}${c.tag} (continued) · Page ${k + 2} of ${N}`)),
      JSON.stringify(sheets.slice(1).map(s => s.copies.map(c => c.cont))));
    ok(`${at}: every page with rows has the item table's head`, copies.every(c => !c.items || c.thead));
    ok(`${at}: every page but the last says where the copy goes on`,
      sheets.every((s, k) => s.copies.every(c => c.foot === (k < N - 1 ? `Continued on page ${k + 2}` : null))), JSON.stringify(copies.map(c => c.foot)));
    const last = sheets[N - 1].copies;
    ok(`${at}: the signatures, terms, policy and footer on the last page only, the footer at its foot`,
      last.every(c => c.sign && c.terms && c.policy && c.footer && Math.abs(c.footerAtFoot) <= 1)
        && sheets.slice(0, -1).every(s => s.copies.every(c => !c.sign && !c.terms && !c.policy && !c.footer)),
      JSON.stringify(last.map(c => c.footerAtFoot)));
    const withTotals = sheets.findIndex(s => s.copies[0].totals);
    ok(`${at}: the totals carry at least the last item line on to their page`,
      withTotals >= 0 && sheets[withTotals].copies.every(c => c.rows.at(-1) === allRows.at(-1)) && sheets.slice(0, withTotals).every(s => s.copies.every(c => !c.totals && !c.payments)));
    if (id === 'bignote' || id === 'note62') {
      // A note taller than a page (within the 500 characters the server allows): the tail goes on
      // between its parts, the totals with the last line, and the note between its lines: every line
      // once, in order, on both copies, nothing cut off.
      const want = (id === 'bignote' ? NOTE_120 : NOTE_62).split('\n');
      ok(`${at}: a note taller than a page goes on between its lines, each line once, in order, on both copies`,
        [0, 1].every(side => JSON.stringify(sheets.flatMap(s => s.copies[side].notes)) === JSON.stringify(want))
          && sheets.filter(s => s.copies[0].notes.length).length >= 2,
        JSON.stringify(sheets.map(s => s.copies[0].notes.length)));
      ok(`${at}: no sheet holds a single part alone but the last, and none is only the totals`,
        sheets.every(s => s.copies.every(c => !(c.totals && !c.rows.length))));
    } else if (id !== 'longnote') {
      ok(`${at}: the tail whole, on the last page`, withTotals === N - 1 && last.every(c => c.totals && c.payments));
    } else {
      // Forty-five lines of note and three payments: the tail is taller than a page with the last
      // line, so it goes on between its parts, the totals with the last line, the note whole.
      ok(`${at}: a tail taller than a page goes on between its parts, the totals with the last line, the note whole`,
        withTotals < N - 1 && copies.filter(c => c.note).length === 2 && copies.filter(c => c.note).every(c => c.noteLines === 45));
    }
    if (id === 'promo') {
      ok(`${at}: a promotion line and its three contents are never split`,
        copies.every(c => c.lines.every(l => !l[0].sub && (l[0].name.startsWith('Promotion:') ? l.length === 4 : l.length === 1))),
        JSON.stringify(copies.map(c => c.lines.map(l => l.length))));
    }
    if (id === 'tall') {
      // Seventy contents: the line alone is taller than a page, so it goes on between its rows.
      const parts = copies.filter((c, k) => k % 2 === 0).map(c => c.lines.filter(l => l.some(r => r.name.includes('Test Content'))).flat().length);
      ok(`${at}: a promotion line taller than a page goes on between its rows, each row once`,
        parts.filter(Boolean).length >= 2 && parts.reduce((a, b) => a + b, 0) === 71, JSON.stringify(parts));
    }
    if (id === 'oneline') {
      // The only line and the tail do not fit under the header, but fit a page together: page 1 holds
      // the header alone, page 2 the line and the whole tail.
      ok(`${at}: the only line goes on with the whole tail, page 1 the header alone`,
        N === 2 && sheets[0].copies.every(c => !c.rows.length && !c.totals && !c.items && c.billTo)
          && sheets[1].copies.every(c => c.rows.length === 1 && c.totals && c.payments && c.notes.length === 25 && c.sign && c.footer));
    }
    if (id === 'firstpromo') {
      // Forty-five contents: the first line does not fit under the header but fits a page of its own,
      // so it is not split: it starts page 2, whole.
      const promo = copies.map(c => c.lines.filter(l => l[0].name.startsWith('Promotion:'))).flat();
      ok(`${at}: the first line, a promotion of 45 contents, whole on page 2, page 1 the header alone`,
        promo.length === 2 && promo.every(l => l.length === 46) && sheets[1].copies.every(c => c.lines[0][0].name.startsWith('Promotion:'))
          && sheets[0].copies.every(c => !c.rows.length), JSON.stringify(sheets.map(s => s.copies[0].rows.length)));
    }
    if (id.startsWith('exch') && id !== 'exchnote') {
      // Every returned item once, in order, on both copies, under the returned items' head on every
      // page they are on; the replacement lines under their own.
      const k = Number(id.slice(4));
      const want = Array.from({ length: k }, (_, n) => `Returned Test ${n + 1}`).concat(['Returned value (exchange credit)']);
      ok(`${at}: each of the ${k} returned items once, in order, on both copies, under their head on every page they are on`,
        [0, 1].every(side => JSON.stringify(sheets.flatMap(s => s.copies[side].returned)) === JSON.stringify(want))
          && copies.every(c => !c.returned.length || c.returnedHead),
        JSON.stringify(sheets.map(s => s.copies[0].returned.length)));
      if (k === 40) ok(`${at}: the returned items go on to page 2, before the replacement lines`, sheets[1].copies.every(c => c.returned.length > 0));
    }
    if (id === 'exchnote') {
      const want = ('Note: ' + NOTE_120).split('\n');
      ok(`${at}: the exchange's note, taller than a page, goes on between its lines, each once, in order, on both copies`,
        [0, 1].every(side => JSON.stringify(sheets.flatMap(s => s.copies[side].exNotes)) === JSON.stringify(want))
          && sheets.filter(s => s.copies[0].exNotes.length).length >= 2, JSON.stringify(sheets.map(s => s.copies[0].exNotes.length)));
    }
    if (id === 'twenty') {
      ok(`${at}: twenty lines print on two sheets, page 1 full and the last line with the totals`,
        N === 2 && sheets[1].copies[0].rows.length >= 1 && sheets[0].copies[0].rows.length === 20 - sheets[1].copies[0].rows.length);
    }
    ok(`${at}: the window printed once, after the sheets were laid out`, await sheet.evaluate(n => window.__prints === 1 && window.__sheetsAtPrint === n, N));
    // As Chrome prints it: one A4 page a sheet.
    await sheet.emulateMedia({ media: 'print' });
    const asPrinted = (await readSheets(sheet)).flatMap(s => s.copies);
    ok(`${at}: laid out for print, still nothing past a half`, asPrinted.length === copies.length && asPrinted.every(c => c.overContent <= 0.5),
      JSON.stringify(asPrinted.map(c => +c.overContent.toFixed(1))));
    const pdf = await sheet.pdf({ preferCSSPageSize: true, printBackground: true });
    const pdfPagesN = (Buffer.from(pdf).toString('latin1').match(/\/Type\s*\/Page[^s]/g) || []).length;
    ok(`${at}: Chrome prints it on ${N} A4 pages`, pdfPagesN === N, `${pdfPagesN} pages`);
    await sheet.close();
  }

  // ---- The receipts and the exchange print go on to more sheets the same way --
  {
    await page.addScriptTag({ content: receipts });
    const docOf = (n) => ({ docNo: 'EX-T-0005', docTitle: 'Exchange', branding: { name: 'Test Store', company_logo_url: LOGO, phone: '+6560000000', co_reg_no: 'TEST0001X' },
      headerLines: ['Exchange date: 21 Oct 2026'], billToName: 'Test Customer', billToLines: ['+61255504561'],
      beforeItems: ['<h2>Returned Items</h2><table><thead><tr><th>Returned Item</th><th class="r">Qty</th><th class="r">Credit</th></tr></thead><tbody><tr><td>Test Socks</td><td class="r">1</td><td class="r">S$10.00</td></tr></tbody></table>'],
      itemHeading: 'Replacement Item',
      lines: Array.from({ length: n }, (_, k) => ({ name: `Test Item ${k + 1}`, qty: 1, unit: 10, total: 10, subLines: k % 5 === 0 ? ['Test Content A', 'Test Content B'] : [] })),
      totals: [{ label: 'Replacement total', value: `S$${n * 10}.00`, grand: true }], payments: [['Cash', `S$${n * 10}.00`]],
      extraBlocks: ['<h2>Notes</h2><div class="mut">Test note</div>'], signedByName: 'Test Owner', policyText: POLICY });
    const returnedOf = k => '<h2>Returned Items</h2><table><thead><tr><th>Returned Item</th><th class="r">Qty</th><th class="r">Credit</th></tr></thead>'
      + Array.from({ length: k }, (_, j) => `<tbody class="p-row"><tr><td>Returned Test ${j + 1}</td><td class="r">1</td><td class="r">S$10.00</td></tr></tbody>`).join('') + '</table>';
    {
      // An exchange document with forty returned items (ExchangesPage): they go on between their rows.
      const html = await page.evaluate(d => { window.__printA5(d); return window.__printed.at(-1); }, { ...docOf(6), beforeItems: [returnedOf(40)] });
      const sheet = await render(ctx, html, 'receipt-returned-40');
      const sheets = await readSheets(sheet);
      const want = Array.from({ length: 40 }, (_, j) => `Returned Test ${j + 1}`);
      ok('an exchange document of 40 returned items: each once, in order, on both copies, under their head, nothing past a half',
        sheets.length >= 2 && [0, 1].every(side => JSON.stringify(sheets.flatMap(s => s.copies[side].returned)) === JSON.stringify(want))
          && sheets.flatMap(s => s.copies).every(c => c.overContent <= 0.5 && (!c.returned.length || c.returnedHead)),
        JSON.stringify(sheets.map(s => s.copies.map(c => [c.returned.length, +c.overContent.toFixed(1)]))));
      await sheet.close();
    }
    {
      // A block taller than a page that cannot go on between rows (none of the copies' own markup has
      // one: a stand-in for a measure that no plan can mend). Only its own page runs past its half; the
      // other pages keep their room (the review of 23 Oct 2026: they were squeezed to a line a sheet).
      const plainHtml = await page.evaluate(d => { window.__printA5(d); return window.__printed.at(-1); }, docOf(45));
      const plainSheet = await render(ctx, plainHtml, 'receipt-45-plain');
      const plainFirst = (await readSheets(plainSheet))[0].copies[0].rows.length;
      await plainSheet.close();
      const tall = { ...docOf(45), extraBlocks: ['<div data-testid="tall-block" style="height:1000px;flex:none">Test tall block</div>'] };
      const html = await page.evaluate(d => { window.__printA5(d); return window.__printed.at(-1); }, tall);
      const sheet = await render(ctx, html, 'receipt-tall-block');
      const sheets = await readSheets(sheet);
      const holds = await sheet.evaluate(() => [...document.querySelectorAll('.sheet')].map(s => !!s.querySelector('[data-testid="tall-block"]')));
      const over = sheets.map(s => s.copies.some(c => c.overContent > 0.5));
      ok('a block taller than a page: only its own sheet runs past its half, page 1 as full as without it, every row once',
        over.filter(Boolean).length === 1 && over.every((o, k) => o === holds[k]) && sheets[0].copies[0].rows.length === plainFirst
          && sheets.length <= 5 && sheets.flatMap(s => s.copies[0].rows).filter(r => r.startsWith('Test Item')).length === 45,
        JSON.stringify({ over, holds, first: sheets[0].copies[0].rows.length, plainFirst, sheets: sheets.length }));
      await sheet.close();
    }
    for (const [n, sheetsWanted] of [[4, 1], [45, 3]]) {
      const html = await page.evaluate(d => { window.__printA5(d); return window.__printed.at(-1); }, docOf(n));
      const sheet = await render(ctx, html, `receipt-${n}`);
      const sheets = await readSheets(sheet);
      const at = `a receipt of ${n} lines`;
      const rows = sheets.map(s => s.copies[0].rows);
      ok(`${at}: ${sheetsWanted} sheet(s), the copies in step, every row once, nothing past a half`,
        sheets.length === sheetsWanted && sheets.every(s => JSON.stringify(s.copies[0].rows) === JSON.stringify(s.copies[1].rows))
          && rows.flat().filter(r => r.startsWith('Test Item')).length === n && sheets.flatMap(s => s.copies).every(c => c.overContent <= 0.5),
        JSON.stringify(sheets.map(s => s.copies.map(c => [c.rows.length, +c.overContent.toFixed(1)]))));
      if (n > 4) {
        ok(`${at}: page 2 on continues EX-T-0005, the signatures and footer on the last page, each line with its sub-lines`,
          sheets.slice(1).every((s, k) => s.copies.every(c => c.cont === `Energia · EX-T-0005${c.tag} (continued) · Page ${k + 2} of 3`))
            && sheets[2].copies.every(c => c.sign && c.footer && c.totals && c.rows.length >= 1)
            && sheets.slice(0, 2).every((s, k) => s.copies.every(c => !c.sign && !c.totals && c.foot === `Continued on page ${k + 2}`))
            && sheets[0].copies.every(c => c.pageNo === 'Page 1 of 3')
            && sheets.flatMap(s => s.copies).every(c => c.lines.every(l => !l[0].sub && l.length === (l[0].name.match(/Test Item (\d+)/)[1] % 5 === 1 ? 3 : 1))));
      } else {
        const now = await textBoxes(sheet);
        const bare = await render(ctx, unwrapped(html), `receipt-${n}-unwrapped`);
        ok(`${at}: one sheet, laid out to the pixel as without the page wrappers`, JSON.stringify(now) === JSON.stringify(await textBoxes(bare)));
        await bare.close();
      }
      await sheet.close();
    }
  }

  // ---- (d) The PDF and the image ------------------------------------------
  for (const [id, lines] of [['sixty', 60], ['many', 150]]) {
    await view(page, id);
    const pages = pdfPages(await download(page, 'PDF'));
    const texts = pages.flat().map(i => i.text);
    const N = pages.length;
    ok(`PDF of ${lines} lines: every line drawn, on ${N} A5 pages`, texts.filter(t => t === 'Test Socks').length === lines && N >= 3, `${texts.filter(t => t === 'Test Socks').length}`);
    ok(`PDF of ${lines} lines: every page says which of ${N} it is, none says to see the invoice in store`,
      pages.every((p, k) => p.some(i => i.text === `Page ${k + 1} of ${N}`)) && !texts.some(t => t.startsWith('…continued')));
    ok(`PDF of ${lines} lines: every page but the last says where it goes on`, pages.every((p, k) => p.some(i => i.text === `Continued on page ${k + 2}`) === (k < N - 1)));
    ok(`PDF of ${lines} lines: the signatures and the footer on the last page, nothing below 8 mm from any foot`,
      pages.at(-1).some(i => i.text === 'Staff Signature') && pages.at(-1).some(i => i.text.includes('Co. Reg No.'))
        && pages.every(p => p.every(i => i.mm >= 8 - 3 - 0.05)));
    await download(page, 'Image');
    const img = await page.evaluate(() => ({ height: window.__imageCanvas.height, texts: window.__imageCanvas.__texts.map(t => t.text) }));
    if (lines === 60) {
      ok('the image of 60 lines grows taller and draws every line, the footer at its foot',
        img.height > 1680 && img.texts.filter(t => t === 'Test Socks').length === 60 && img.texts.some(t => t.includes('Co. Reg No.')) && !img.texts.some(t => t.startsWith('…continued')), String(img.height));
    } else {
      // Rows down to six A5 pages, then the totals and the foot: well under a phone's 16.7 million pixels.
      ok('the image of 150 lines grows to about six A5 pages, then points to the PDF',
        img.height > 1680 * 5 && img.height * 1188 < 16.7e6 * 0.75 && img.texts.includes('…continued — see the PDF') && img.texts.some(t => t.includes('Co. Reg No.')),
        String(img.height));
    }
  }

  ok('no browser errors', page.errors.length === 0, page.errors.join(' | '));
  await page.context().close();
  console.log(`\nPASS print-pages-browser: ${checks} checks`);
} finally {
  await browser.close();
}
