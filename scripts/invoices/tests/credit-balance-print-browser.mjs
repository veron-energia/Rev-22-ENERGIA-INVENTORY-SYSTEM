// The credit balance on the printed invoice and on the PDF / image / WhatsApp /
// email copy, through the real invoices page (owner's decisions, 2 Oct 2026).
// Also the Total Paid fix: a corrected invoice's total matches its rows;
// Record Payment never offers the wallet of the customer opened before; no copy
// is made, and no correction opened, while an invoice's own payments, items and
// Bill To are still loading — after opening another invoice or when the open
// one reloads itself (a change from another tab, Record Payment on this one),
// from the first read of its row; a slow answer for the invoice before never lands on this
// one (Bill To, figures, promotion choices, the note below); a copy that went
// without the balance — it could not be read, or there was no room — is said
// on screen, and only once the copy has gone out; the printed credit block is
// whole or absent, never cut; and the PDF/image line sits beside the totals
// where it costs no height, and otherwise never costs an item row or pushes
// the footer down, even with a full store footer and a long payment list.
// 443 (the Owner, 21 Oct 2026, CREDIT-SPLIT-1..14), for a customer whose
// balance has sources (Ann keeps the categories alone, as a server before 443
// answers): the line reads Credit Package · Premium Bundle · Other; a past
// 'Wallet — Paid Credit' payment of Premium Bundle credit carries the source
// in brackets on screen, in the print, the PDF, the image, the payment
// correction and the guided refund, and no copy goes out before the sources
// are in (a slow answer; a reload after another tab's payment); Record
// Payment lists each wallet method with what it can pay of this invoice,
// Credit Package first, switched off at nothing, says Credit Package credit is
// used first on a Premium Bundle row unless the other rows already use it,
// and never offers another customer's figures once the invoice's customer
// changes.
//
// The real page and the real PDF and image renderers run in Chrome against an
// in-memory stand-in for Supabase; every network request is blocked. The
// customers, invoices and amounts are invented.
//
// The browser runs in Los Angeles at 10:30 on 1 Oct 2026, which is already
// 01:30 on 2 Oct in Singapore — so the as-at date proves it is Singapore's.
//
// Usage: node scripts/invoices/tests/credit-balance-print-browser.mjs
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
await mkdir('.invoice-test/browser', { recursive: true });

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------
const T0 = '2026-09-30T02:00:00Z';
const common = { is_active: true, deleted_at: null };
const owner = { id: 'owner', full_name: 'Test Owner', role: 'owner', ...common };
const staff = { id: 'staff', full_name: 'Test Staff', role: 'staff', ...common };
const inv = (id, customer_id, over = {}) => ({
  id, invoice_no: `INV-T-${id}`, store_id: 'store', customer_id, status: 'paid', subtotal: 100, total_amount: 100,
  paid_amount: 100, discount_total: 0, manual_discount: 0, created_at: T0, paid_at: T0, business_date: '2026-09-30',
  created_by: 'owner', edit_count: 0, notes: null, ...common, ...over,
});
const line = invoice_id => ({ id: `line-${invoice_id}`, invoice_id, line_kind: 'product', product_id: 'socks', quantity: 1,
  unit_price: 100, line_total: 100, topup_amount: 0, foc_quantity: 0 });
let payN = 0;
const pay = (invoice_id, payment_method_id, amount, entry_kind = 'receipt', extra = {}) => ({
  id: `pay-${++payN}`, invoice_id, payment_method_id, amount, entry_kind, created_at: T0, effective_at: T0, ...extra });

const tables = {
  stores: [{ id: 'store', name: 'Test Store', code: 'TEST', address: '1 Example Road #01-01, Singapore 000001', phone: '+6560000000',
    whatsapp_phone: '+6590000000', email: 'shop@example.test', website: 'example.test', co_reg_no: 'TEST0001X',
    paynow_uen: 'TEST0001X', bank_account: '000-000000-0', policy_text: 'Exchanges within 7 days with receipt.\nVouchers are not refundable.', ...common }],
  customers: [
    { id: 'ann', full_name: 'Ann Credit', phone: '+6590000001', email: 'ann@example.test', ...common },
    { id: 'ben', full_name: 'Ben Cash', phone: '+6590000002', email: 'ben@example.test', ...common },
    { id: 'cara', full_name: 'Cara Spent', phone: '+6590000003', ...common },
    { id: 'dee', full_name: 'Dee Retired', phone: '+6590000004', ...common },
  ],
  profiles: [owner, staff],
  products: [{ id: 'socks', name: 'Long Energia Socks', sku: 'SOCK', product_type: 'own', ...common }],
  store_product_prices: [{ store_id: 'store', product_id: 'socks', selling_price: 100, member_price: 100, non_member_price: 100, availability: 'available', ...common }],
  store_inventory: [{ store_id: 'store', product_id: 'socks', current_qty: 100 }],
  payment_methods: [
    { id: 'cash', name: 'Cash', ...common }, { id: 'bank', name: 'Bank Transfer', ...common },
    { id: 'wallet-paid', name: 'Wallet — Paid Credit', is_wallet_credit: true, wallet_category: 'paid', is_system: true, ...common },
    { id: 'wallet-bonus', name: 'Wallet — Bonus Credit', is_wallet_credit: true, wallet_category: 'bonus', is_system: true, ...common },
    // A wallet method since switched off: payments taken with it still came from the wallet.
    { id: 'wallet-old', name: 'Wallet — Old Credit', is_wallet_credit: true, wallet_category: 'legacy', is_system: true, ...common, is_active: false },
  ],
  promotions: [], promotion_store_prices: [], promotion_choice_groups: [], promotion_choice_options: [], promotion_items: [],
  invoice_promotion_selections: [], invoice_revisions: [], invoice_service_staff: [], warehouses: [],
  vouchers: [], voucher_store_prices: [], special_products: [], therapy_package_rules: [], unlimited_therapy_packages: [],
  unlimited_therapy_store_prices: [], therapy_services: [], therapy_service_stores: [],
  invoices: [
    // Corrected: S$3,000 taken in cash, reversed, replaced by S$500 by bank, then S$50 cash.
    inv('corrected', 'ann', { subtotal: 550, total_amount: 550, paid_amount: 550 }),
    inv('cash', 'ben'),
    inv('wallet', 'cara'),
    inv('old-wallet', 'dee'),
    inv('cancelled', 'ann', { status: 'cancelled' }),
    inv('refunded', 'ann', { status: 'refunded' }),
    // Not yet paid: Record Payment offers the customer's wallet.
    inv('owed-ann', 'ann', { status: 'unpaid', paid_amount: 0, paid_at: null }),
    inv('owed-ben', 'ben', { status: 'unpaid', paid_amount: 0, paid_at: null }),
    // Paid while it is open, from another tab: the open invoice reloads itself.
    inv('topay', 'ann', { status: 'unpaid', paid_amount: 0, paid_at: null }),
    // The same, with the invoice's own row slow to come back on the reload.
    inv('elsewhere', 'ann', { status: 'unpaid', paid_amount: 0, paid_at: null }),
    // Paid on this tab with Record Payment.
    inv('payhere', 'ben', { status: 'unpaid', paid_amount: 0, paid_at: null }),
    inv('part', 'ann', { status: 'partially_paid', paid_amount: 50 }),
    // Twelve instalments: the PDF/image line used to give way on this one.
    inv('instalments', 'ann', { subtotal: 120, total_amount: 120, paid_amount: 120 }),
    // Twenty items: more than the PDF/image page lists.
    inv('long', 'ann', { subtotal: 2000, total_amount: 2000, paid_amount: 2000 }),
    // Seven items and one payment: a full A5 page that still fits on one (B16).
    inv('tight', 'ann', { subtotal: 700, total_amount: 700, paid_amount: 700 }),
    // One promotion line each, with the customer's own choice inside.
    inv('promoA', 'ann'), inv('promoB', 'ben'),
  ],
  invoice_payments: [
    pay('corrected', 'cash', 3000),
    pay('corrected', 'cash', 3000, 'correction_reversal', { corrects_payment_id: 'pay-1', correction_reason: 'Keyed wrong' }),
    pay('corrected', 'bank', 500, 'correction_replacement', { corrects_payment_id: 'pay-1', correction_reason: 'Keyed wrong' }),
    pay('corrected', 'cash', 50),
    pay('cash', 'cash', 100),
    pay('wallet', 'wallet-paid', 40), pay('wallet', 'cash', 60),
    pay('old-wallet', 'wallet-old', 40), pay('old-wallet', 'cash', 60),
    pay('cancelled', 'cash', 100), pay('refunded', 'cash', 100),
    pay('part', 'cash', 50),
    ...Array.from({ length: 12 }, () => pay('instalments', 'cash', 10)),
    pay('promoA', 'cash', 100), pay('promoB', 'cash', 100),
    pay('long', 'cash', 2000), pay('tight', 'cash', 700),
  ],
};
tables.invoice_items = tables.invoices.map(i => i.id.startsWith('promo')
  ? { ...line(i.id), line_kind: 'promotion', product_id: null, promotion_id: 'promo1' } : line(i.id));
for (let n = 2; n <= 20; n++) tables.invoice_items.push({ ...line('long'), id: `line-long-${n}` });
for (let n = 2; n <= 7; n++) tables.invoice_items.push({ ...line('tight'), id: `line-tight-${n}` });
tables.promotions.push({ id: 'promo1', name: 'Test Promo', code: 'TP', ...common });
tables.invoice_promotion_selections.push(
  { id: 'sel-A', invoice_item_id: 'line-promoA', group_id: 'g', product_id: 'socks', quantity: 1 },
  { id: 'sel-B', invoice_item_id: 'line-promoB', group_id: 'g', product_id: 'socks', quantity: 2 });
const cats = c => ({ paid: 0, bonus: 0, legacy: 0, promotional: 0, exchange: 0, ...c });
const balances = {
  ann: { categories: cats({ paid: 300, bonus: 50 }), available_total: 350 },
  ben: { categories: cats({}), available_total: 0 },
  cara: { categories: cats({}), available_total: 0 },
  dee: { categories: cats({}), available_total: 0 },
};

// ---------------------------------------------------------------------------
// The stand-in for the Supabase client.
// ---------------------------------------------------------------------------
const mock = `export const supabase = (() => {
  const t = () => window.__tables;
  const calls = (window.__calls = window.__calls || []);
  const thenable = p => { const q = new Proxy({}, { get(_, k) { if (k === 'then') return (ok, bad) => p.then(ok, bad); return () => q; } }); return q; };
  function from(table) {
    let rows = [...(t()[table] || [])], one = false, invoiceId = null, inIds = [];
    const q = new Proxy({}, { get(_, key) {
      // invoice_payments can be made slow (window.__paysDelay), as on a poor
      // connection, and any table for one invoice, or for one of the ids it is
      // read by (window.__slowFor[table][id]); an invoice's own row is read by
      // its id. Each read is noted in window.__reads, done once it has answered.
      // The page gets its own copy of the rows, as from a server: a row the
      // test changes later never changes what the page already holds.
      if (key === 'then') return (ok, bad) => {
        const read = { table, id: invoiceId, done: false };
        (window.__reads = window.__reads || []).push(read);
        return new Promise(r => setTimeout(r, table === 'invoice_payments' ? (window.__paysDelay || 0)
          : Math.max(0, ...[invoiceId, ...inIds].map(id => ((window.__slowFor || {})[table] || {})[id] || 0))))
          .then(() => { read.done = true; return { data: structuredClone(one ? (rows[0] || null) : rows), error: null }; }).then(ok, bad);
      };
      return (...a) => { if (key === 'eq' && (a[0] === 'invoice_id' || (table === 'invoices' && a[0] === 'id'))) invoiceId = a[1]; if (key === 'in') inIds = a[1];
        if (key === 'eq' || key === 'is') rows = rows.filter(r => r[a[0]] === a[1]); if (key === 'in') rows = rows.filter(r => a[1].includes(r[a[0]]));
        if (key === 'single' || key === 'maybeSingle') one = true; return q; };
    } });
    return q;
  }
  const finance = i => ({ total: Number(i.total_amount), net_received: Number(i.paid_amount), outstanding: Math.max(0, i.total_amount - i.paid_amount), refund_due: 0, refunded: 0, status: i.status });
  async function rpcImpl(name, args) {
    calls.push({ name, args });
    const find = id => t().invoices.find(i => i.id === id);
    switch (name) {
      case 'invoice_list_page': {
        const rows = t().invoices.map(i => ({ ...i, customer_name: t().customers.find(c => c.id === i.customer_id)?.full_name ?? null }));
        return { data: { rows, total: rows.length, pages: 1, summary: { matching: rows.length, total_amount: 0, outstanding: 0, paid: 0 } }, error: null };
      }
      case 'customer_credit_balances': {
        const wait = window.__balanceDelay || (window.__balanceDelayFor || {})[args.p_customer_id];
        if (wait) await new Promise(r => setTimeout(r, wait));
        if (window.__balanceError) return { data: null, error: { message: window.__balanceError } };
        const b = window.__balances[args.p_customer_id];
        return { data: b ? { customer_id: args.p_customer_id, ...b } : null, error: null };
      }
      case 'invoice_financial_position': return { data: finance(find(args.p_invoice_id)), error: null };
      case 'invoice_bill_to_source': {
        const wait = (window.__billToDelayFor || {})[args.p_invoice_id];
        if (wait) await new Promise(r => setTimeout(r, wait));
        return { data: (window.__billTo || {})[args.p_invoice_id] ?? null, error: null };
      }
      case 'invoice_refund_options': return { data: { financial: finance(find(args.p_invoice_id)), sources: [], stock: [], benefits: [], lines: [], review_required: false }, error: null };
      case 'invoice_effective_affiliate': return { data: { found: true, has_affiliate: false }, error: null };
      case 'invoice_benefit_review_options': return { data: { lines: [] }, error: null };
      // Staff may correct a paid invoice (377) when the test says so.
      case 'staff_may_correct_invoice': return { data: !!window.__staffMayCorrect, error: null };
      // Record Payment: the receipts go in and the invoice's row is written
      // afresh, paid or part-paid, as the server would.
      case 'record_invoice_settlement': {
        const ix = t().invoices.findIndex(i => i.id === args.p_invoice_id), was = t().invoices[ix];
        const at = new Date().toISOString(), receipts = args.p_payload.receipts;
        receipts.forEach(r => t().invoice_payments.push({ id: 'pay-' + was.id + '-' + r.key, invoice_id: was.id, payment_method_id: r.payment_method_id,
          amount: r.amount, entry_kind: 'receipt', created_at: at, effective_at: at }));
        const paid = Number(was.paid_amount) + receipts.reduce((s, r) => s + Number(r.amount), 0);
        t().invoices[ix] = { ...was, paid_amount: paid, status: paid >= Number(was.total_amount) ? 'paid' : 'partially_paid', paid_at: at };
        return { data: { ok: true }, error: null };
      }
      // W4-B04 (the split panels): one Credit Package and one Premium Bundle on
      // sale at the store, only when the test offers them (window.__splitOffers).
      case 'credit_packages_for_store': return { data: window.__splitOffers ? window.__splitOffers.packages : null, error: null };
      case 'premium_bundles_for_store': return { data: window.__splitOffers ? window.__splitOffers.bundles : null, error: null };
      case 'credit_package_benefit_preview': return { data: { found: true, package_name: 'Fixture Credit Package', customer_price: 500,
        paid_credit_total: 500, bonus_total: 50, grants_reward: false, reward_voucher_total: 0 }, error: null };
      case 'premium_bundle_benefit_preview': return { data: { found: true, bundle_name: 'Fixture Premium Bundle', customer_price: 600,
        paid_credit_total: 600, bonus_total: 60, free_voucher_total: 0, allowed_vouchers: [] }, error: null };
      // 443: what each wallet method can pay of an invoice, by the invoice's
      // customer now (window.__availFor; slow for one customer with
      // window.__availDelayFor), and the sources of its wallet payments
      // (window.__paySources, by invoice; slow with window.__sourcesDelay). An
      // invoice the test gives none for answers as a server before 443 does.
      case 'invoice_wallet_availability': {
        const i = find(args.p_invoice_id), a = i && (window.__availFor || {})[i.customer_id];
        const wait = i && (window.__availDelayFor || {})[i.customer_id];
        if (wait) await new Promise(r => setTimeout(r, wait));
        if (!a) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.invoice_wallet_availability' } };
        return { data: { invoice_id: i.id, customer_id: i.customer_id, payable: true, credit_line: false, ...structuredClone(a) }, error: null };
      }
      case 'invoice_payment_credit_sources': {
        const s = (window.__paySources || {})[args.p_invoice_id];
        if (s && window.__sourcesDelay) await new Promise(r => setTimeout(r, window.__sourcesDelay));
        if (!s) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.invoice_payment_credit_sources' } };
        return { data: structuredClone(s), error: null };
      }
      // The guided Refund / Cancel's plan, for an invoice the test gives one (window.__plans[invoice][action]).
      case 'invoice_action_plan': return { data: structuredClone(((window.__plans || {})[args.p_invoice_id] || {})[args.p_action] ?? null), error: null };
      case 'my_assigned_store_id': return { data: window.__profile.role === 'staff' ? 'store' : null, error: null };
      case 'my_assigned_stores': return { data: window.__profile.role === 'staff' ? [{ store_id: 'store', store_name: 'Test Store', is_default: true }] : [], error: null };
      default: return { data: null, error: null };
    }
  }
  const rpc = (name, args) => thenable(rpcImpl(name, args));
  const channel = () => { const ch = { on() { return ch; }, subscribe() { return ch; }, unsubscribe() { return Promise.resolve('ok'); } }; return ch; };
  // WhatsApp uploads the PDF and sends a link; the uploaded file is kept for the
  // test. window.__uploadFails: the upload is refused, so nothing is sent.
  const storage = { from: () => ({
    upload: async (path, blob) => {
      if (window.__uploadFails) return { error: { message: 'storage down' } };
      window.__uploaded = new Uint8Array(await blob.arrayBuffer()); return { error: null };
    },
    createSignedUrl: async () => ({ data: { signedUrl: 'https://files.example.test/invoice.pdf' }, error: null }),
  }) };
  // B16 (Q6): no email-sending service is called any more; a call here is recorded so the test can say so.
  const functions = { invoke: async (fn, { body }) => { window.__emailFunctionCalled = fn; return { data: { ok: true }, error: null }; } };
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
    // The real jsPDF, also handed to the test (window.__jsPDF) so it can stand in
    // for a device whose font measures text wider.
    b.onResolve({ filter: /^jspdf$/ }, a => a.importer === 'jspdf-exposed' ? undefined : { path: 'jspdf-exposed', namespace: 'fixture' });
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, a => a.path === 'jspdf-exposed'
      ? { contents: `import { jsPDF } from 'jspdf'; window.__jsPDF = jsPDF; export * from 'jspdf'; export { default } from 'jspdf';`, loader: 'js', resolveDir: process.cwd() }
      : ({ contents: a.path === 'db' ? mock
      : a.path === 'auth' ? `export const useAuth=()=>({profile:window.__profile,session:{user:{id:window.__profile.id}},assignments:[],loading:false});` : '', loader: 'js' }));
  } }],
});
const bundle = built.outputFiles[0].text;
const css = (await readFile('src/styles/globals.css', 'utf8') + '\n' + await readFile('src/components/invoices/invoice-controls.css', 'utf8')).replace(/^@import.*$/gm, '');
const HTML = '<html><head></head><body><div id="root"></div></body></html>';

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
let checks = 0;
const ok = (label, condition, detail = '') => { assert.ok(condition, `${label}${detail ? ` — ${detail}` : ''}`); checks++; console.log(`  ok  ${label}`); };

async function openPage(profile = owner) {
  const context = await browser.newContext({ timezoneId: 'America/Los_Angeles', acceptDownloads: true, viewport: { width: 1400, height: 1000 } });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  page.errors = []; page.on('pageerror', e => page.errors.push(e.message));
  page.consoleErrors = []; page.on('console', m => { if (m.type() === 'error') page.consoleErrors.push(m.text()); });
  await page.route('**/*', route => route.request().url() === 'https://invoice.test/' ? route.fulfill({ contentType: 'text/html', body: HTML }) : route.abort());
  await page.goto('https://invoice.test/');
  await page.clock.setFixedTime(new Date('2026-10-01T17:30:00Z'));
  await page.evaluate(([t, b, p]) => {
    window.__tables = t; window.__balances = b; window.__profile = p; window.__calls = [];
    window.__printed = []; window.__opened = [];
    // A print window records what is written into it, and the moment it opened
    // relative to the balance read.
    window.open = (url) => {
      window.__calls.push({ name: 'window.open', url });
      if (url) { if (window.__openThrows) throw new Error('blocked'); window.__opened.push(url); return null; }
      // B16 (AFTER-11): WhatsApp's window is opened blank in the click, then sent to the chat.
      const w = { closed: !!window.__closePrintWindow, opener: window, close() { w.closed = true; },
        location: { set href(u) { if (window.__openThrows) throw new Error('blocked'); window.__opened.push(u); } },
        document: { body: { textContent: '' },
        open() { window.__calls.push({ name: 'print.document.open' }); },
        // window.__printWriteFails: writing the invoice itself fails.
        write: html => { if (window.__printWriteFails && html.includes('CUSTOMER COPY')) throw new Error('write failed'); window.__printed.push(html); },
        close() {} } };
      window.__printWindow = w; return w;
    };
    window.__imageText = [];
    window.modalButton = name => [...document.querySelectorAll('.modal button')].find(b => b.textContent.trim() === name);
    const fill = CanvasRenderingContext2D.prototype.fillText;
    // Each canvas also keeps its own, so the one made into the image can be read (imageTexts).
    CanvasRenderingContext2D.prototype.fillText = function (text, ...args) {
      window.__imageText.push(String(text)); (this.canvas.__texts = this.canvas.__texts || []).push(String(text));
      return fill.call(this, text, ...args);
    };
    // window.__wideLabel: a device whose font draws the credit label far wider
    // than the column beside the totals (canvas and PDF alike).
    const measure = CanvasRenderingContext2D.prototype.measureText;
    CanvasRenderingContext2D.prototype.measureText = function (text) {
      return window.__wideLabel && String(text).startsWith('Credit balance (as at') ? { width: 5000 } : measure.call(this, text);
    };
    // window.__toBlobFails: the image cannot be made, so nothing is saved.
    const toBlob = HTMLCanvasElement.prototype.toBlob;
    HTMLCanvasElement.prototype.toBlob = function (done, ...rest) {
      window.__imageCanvas = this; return window.__toBlobFails ? done(null) : toBlob.call(this, done, ...rest);
    };
  }, [tables, balances, profile]);
  await page.addStyleTag({ content: css });
  await page.addScriptTag({ content: bundle });
  await page.evaluate(() => {
    const textWidth = window.__jsPDF.API.getTextWidth;
    window.__jsPDF.API.getTextWidth = function (text, ...rest) {
      return window.__wideLabel && String(text).startsWith('Credit balance (as at') ? 1000 : textWidth.call(this, text, ...rest);
    };
  });
  await page.getByRole('button', { name: 'View', exact: true }).first().waitFor();
  return page;
}
const row = (page, no) => page.locator('tbody tr').filter({ has: page.getByText(no, { exact: true }) });
async function view(page, id) {
  const close = page.getByRole('button', { name: 'Close', exact: true }).first();
  if (await close.isVisible().catch(() => false)) await close.click();
  await row(page, `INV-T-${id}`).getByRole('button', { name: 'View', exact: true }).click();
  await page.getByRole('button', { name: 'Print', exact: true }).waitFor();
  await page.waitForFunction(no => document.querySelector('.modal')?.innerText.includes(no), `INV-T-${id}`);
  // The copy buttons come on once this invoice's own rows are in.
  await page.waitForFunction(() => modalButton('Print') && !modalButton('Print').disabled);
}
const COPY_BUTTONS = ['Print', 'PDF', 'Image', 'WhatsApp', 'Email (from this device)'];
const copyButtonsOff = page => page.evaluate(names => names.map(n => modalButton(n)?.disabled), COPY_BUTTONS);
const CORRECT_TITLE = 'Correct this invoice with a reason and revision history';
/** A detail-modal button's disabled state and its title ('' when it has none). */
const buttonState = (page, name) => page.evaluate(n => { const b = modalButton(n); return b ? { disabled: b.disabled, title: b.getAttribute('title') ?? '' } : null; }, name);
/** The note that a copy went without the credit balance, once the page shows `expected` (or as it is after 2 s). */
async function unreadNote(page, expected = null) {
  const read = () => document.querySelector('[data-testid="credit-balance-unread"] > div')?.innerText ?? null;
  await page.waitForFunction(([fn, want]) => new Function(`return (${fn})()`)() === want, [read.toString(), expected], { timeout: 2000 }).catch(() => {});
  return page.evaluate(read);
}
/** Press Print and return the HTML written into the print window. */
async function print(page) {
  const before = await page.evaluate(() => window.__printed.length);
  await page.evaluate(() => { window.__calls.length = 0; });
  await page.getByRole('button', { name: 'Print', exact: true }).click();
  await page.waitForFunction(n => window.__printed.length > n, before);
  return page.evaluate(() => window.__printed[window.__printed.length - 1]);
}
/** The text drawn on the canvas that was made into the last image saved. */
const imageTexts = page => page.evaluate(() => window.__imageCanvas?.__texts ?? []);
const balanceReads = page => page.evaluate(() => window.__calls.filter(c => c.name === 'customer_credit_balances').map(c => c.args.p_customer_id));
const count = (s, needle) => s.split(needle).length - 1;
/** Text drawn into a jsPDF file: strings are written as (…) with \\( \\) \\\\ escapes, the middle dot as one byte. */
const pdfText = bytes => Buffer.from(bytes).toString('latin1').replace(/\\([()\\])/g, '$1').replace(/\xb7/g, '·');
async function downloadText(page, button, keepAs = null) {
  const wait = page.waitForEvent('download');
  await page.getByRole('button', { name: button, exact: true }).click();
  const d = await wait;
  if (keepAs) await d.saveAs(keepAs);
  return pdfText(await readFile(await d.path()));
}

const LABEL = 'Credit balance (as at 2 Oct 2026)';
try {
  // ---- The printed invoice -------------------------------------------------
  const page = await openPage(owner);

  await view(page, 'corrected');
  let html = await print(page);
  ok('both halves carry the credit balance, as at Singapore\'s date', count(html, LABEL) === 2, html.slice(0, 0));
  // A kind's name and amount are held together; a line may break only after a dot.
  ok('as a total and each kind held, in order', count(html, '<strong>S$350.00</strong>') === 2 && count(html, 'Paid&nbsp;S$300.00&nbsp;· Bonus&nbsp;S$50.00') === 2);
  ok('the line sits under the payment table', html.indexOf(LABEL) > html.indexOf('Total Paid'));
  {
    // Rendered as printed: the real print stylesheet and the print window's own
    // script, which fits the credit block once the page has laid out and before
    // it prints. Then the half-page is filled a little at a time.
    const sheet = await page.context().newPage();
    await sheet.setViewportSize({ width: 1123, height: 794 });
    await sheet.addInitScript(() => {
      window.__printCalls = 0;
      // What the credit blocks look like at the moment the page prints.
      window.print = () => { window.__printCalls++; window.__atPrint = [...document.querySelectorAll('.credit-balance')].map(b => ({
        hidden: getComputedStyle(b).display === 'none', whole: b.scrollHeight <= b.clientHeight + 0.5 })); };
    });
    let served = html;
    await sheet.route('**/*', route => route.request().url() === 'https://print.test/' ? route.fulfill({ contentType: 'text/html', body: served }) : route.abort());
    await sheet.goto('https://print.test/');
    await sheet.waitForFunction(() => window.__printCalls === 1);
    await sheet.screenshot({ path: '.invoice-test/browser/credit-balance-print.png' });
    const layout = await sheet.evaluate(() => {
      const fits = copy => copy.querySelector('.footer').getBoundingClientRect().bottom <= copy.getBoundingClientRect().bottom + 0.5;
      const hidden = el => getComputedStyle(el).display === 'none';
      const whole = block => hidden(block) || block.scrollHeight <= block.clientHeight + 0.5;
      const state = block => hidden(block) ? 'none' : hidden(block.querySelector('.credit-detail')) ? 'total' : 'full';
      const copies = [...document.querySelectorAll('.copy')];
      const out = { atStart: copies.map(c => ({ fits: fits(c), state: state(c.querySelector('.credit-balance')) })), steps: [] };
      // Fill the first half-page 2 px at a time, above the credit block.
      const copy = copies[0], block = copy.querySelector('.credit-balance'), detail = block.querySelector('.credit-detail');
      const spacer = document.createElement('div'); spacer.style.flex = '0 0 auto';
      block.parentNode.insertBefore(spacer, block);
      for (let h = 0; h <= 400; h += 2) {
        spacer.style.height = `${h}px`;
        block.style.display = 'none'; const without = fits(copy);
        block.style.display = ''; detail.style.display = '';
        const cutUnfitted = !whole(block);
        fitCreditBalance();
        out.steps.push({ h, without, withLine: fits(copy), cutUnfitted, whole: whole(block), state: state(block) });
      }
      return out;
    });
    ok('both printed halves show the line in full and end with their footer inside the page',
      layout.atStart.every(c => c.fits && c.state === 'full'), JSON.stringify(layout.atStart));
    ok('on a fuller half-page the line never pushes the footer off',
      layout.steps.every(r => !r.without || r.withLine), JSON.stringify(layout.steps.filter(r => r.without && !r.withLine).map(r => r.h)));
    ok('the credit block prints whole or not at all: never cut through a line of text',
      layout.steps.every(r => r.whole), JSON.stringify(layout.steps.filter(r => !r.whole).map(r => r.h)));
    const order = { full: 0, total: 1, none: 2 };
    ok('it gives way in order: the breakdown first, then the total',
      layout.steps.every((r, i) => i === 0 || order[r.state] >= order[layout.steps[i - 1].state])
        && ['full', 'total', 'none'].every(st => layout.steps.some(r => r.state === st)),
      layout.steps.map(r => r.state[0]).join(''));
    // The print window runs the fit before it prints: a half-page squeezed so
    // the block would be cut prints it whole (without the breakdown) instead.
    const squeezed = layout.steps.find(r => r.cutUnfitted && r.state === 'total') ?? layout.steps.find(r => r.cutUnfitted);
    ok('a squeezed half-page exists to check the print window against', !!squeezed);
    served = html.replaceAll('<div class="credit-balance"', `<div style="flex:0 0 auto;height:${squeezed.h}px"></div><div class="credit-balance"`);
    await sheet.goto('https://print.test/');
    await sheet.waitForFunction(() => window.__printCalls === 1);
    const atPrint = await sheet.evaluate(() => window.__atPrint);
    ok('the print window fits the block before it prints', atPrint.length === 2 && atPrint.every(b => b.whole), JSON.stringify(atPrint));
    await sheet.close();
  }
  ok('Total Paid on a corrected invoice matches the rows: 3000 − 3000 + 500 + 50', count(html, '<strong>S$550.00</strong>') === 2 && !html.includes('S$3550.00'));
  ok('the reversal still prints as a minus row', count(html, 'S$-3000.00') === 2);
  ok('the balance was read once, for this invoice\'s customer, at the moment of printing', JSON.stringify(await balanceReads(page)) === '["ann"]');
  ok('the print window opened before the balance was read, so no pop-up blocker stops it',
    await page.evaluate(() => window.__calls.findIndex(c => c.name === 'window.open') < window.__calls.findIndex(c => c.name === 'customer_credit_balances')));

  // The balance changes after the invoice was opened: the print shows it as it is now.
  await page.evaluate(() => { window.__balances.ann = { categories: { paid: 120, bonus: 0, legacy: 0, promotional: 0, exchange: 15 }, available_total: 135 }; });
  html = await print(page);
  ok('the balance is read fresh, not the one loaded when the invoice opened', count(html, '<strong>S$135.00</strong>') === 2 && count(html, 'Paid&nbsp;S$120.00&nbsp;· Exchange&nbsp;S$15.00') === 2 && !html.includes('S$350.00'));
  await page.evaluate(() => { window.__balances.ann = { categories: { paid: 300, bonus: 50, legacy: 0, promotional: 0, exchange: 0 }, available_total: 350 }; });

  // The next invoice belongs to a customer with nothing: Ann's balance never follows.
  await view(page, 'cash');
  html = await print(page);
  ok('no credit and no wallet payment: no line', !html.includes('Credit balance'));
  ok('and the previous customer\'s balance is not printed', !html.includes('S$350.00'));
  ok('the read was for the new customer', JSON.stringify(await balanceReads(page)) === '["ben"]');

  await view(page, 'wallet');
  html = await print(page);
  ok('paid from the wallet with nothing left: the line shows S$0.00', count(html, LABEL) === 2 && count(html, '<strong>S$0.00</strong>') === 2);
  ok('with no kinds listed under it', !html.includes('Paid S$0.00'));

  for (const id of ['cancelled', 'refunded']) {
    await view(page, id);
    html = await print(page);
    ok(`a ${id} invoice prints without the line`, !html.includes('Credit balance') && html.includes(`INV-T-${id}`));
    ok(`and does not read the balance at all (${id})`, (await balanceReads(page)).length === 0);
  }

  // A refused read (a role that may not see credit) prints without the line.
  await view(page, 'corrected');
  await page.evaluate(() => { window.__balanceError = 'You do not have access to customer credit'; });
  html = await print(page);
  ok('a refused balance read still prints the invoice, without the line', html.includes('INV-T-corrected') && !html.includes('Credit balance'));
  await page.evaluate(() => { window.__balanceError = null; window.__balanceDelay = 5000; });
  ok('a role that may not see credit is not told the balance could not be read', (await unreadNote(page)) === null);
  const started = Date.now();
  html = await print(page);
  ok('a balance read that hangs gives up and prints without the line', !html.includes('Credit balance') && Date.now() - started < 4800);
  ok('and the page says so, without holding the print up',
    (await unreadNote(page, 'Printed without the credit balance — it could not be read.')) === 'Printed without the credit balance — it could not be read.', String(await unreadNote(page)));
  await page.evaluate(() => { window.__balanceDelay = 0; window.__balanceError = 'network down'; });
  await downloadText(page, 'PDF');
  ok('a PDF saved after a failed read says it was saved without it',
    (await unreadNote(page, 'Saved without the credit balance — it could not be read.')) === 'Saved without the credit balance — it could not be read.', String(await unreadNote(page)));
  await page.evaluate(() => { window.__balanceError = null; });
  html = await print(page);
  ok('the note goes once the balance is read again', html.includes(LABEL) && (await unreadNote(page)) === null);
  await page.evaluate(() => { window.__balanceDelay = 0; window.__closePrintWindow = true; });
  const writes = await page.evaluate(() => window.__printed.length);
  await page.getByRole('button', { name: 'Print', exact: true }).click();
  await page.waitForTimeout(200);
  ok('a print window closed while the balance was read is left alone', await page.evaluate(n => window.__printed.length === n, writes));
  await page.evaluate(() => { window.__closePrintWindow = false; });

  // Something fails after the print window opened: the window says so rather
  // than staying on "Preparing the invoice…", and the error is logged.
  await page.evaluate(() => { window.__printWriteFails = true; window.__calls.length = 0; });
  page.consoleErrors.length = 0;
  await page.getByRole('button', { name: 'Print', exact: true }).click();
  await page.waitForFunction(() => window.__printed.some(h => h.includes('could not be prepared for printing')));
  ok('a print that fails tells the print window, and nothing is left hanging',
    await page.evaluate(() => window.__calls.some(c => c.name === 'print.document.open')) && page.errors.length === 0, page.errors.join(' | '));
  ok('and the error is logged', page.consoleErrors.some(t => t.includes('could not be prepared for printing')), page.consoleErrors.join(' | '));
  await page.evaluate(() => { window.__printWriteFails = false; });

  // A send that fails part-way always gives its button back.
  await page.evaluate(() => { window.__openThrows = true; });
  await page.getByRole('button', { name: 'WhatsApp', exact: true }).click();
  // B16 (AFTER-11): the browser refusing the chat is said as that, not as a send.
  await page.locator('.modal .alert-danger').filter({ hasText: 'Your browser blocked the WhatsApp window.' }).waitFor();
  ok('a send that throws gives its button back and says it failed',
    (await page.evaluate(() => modalButton('WhatsApp')?.textContent.trim())) === 'WhatsApp' && page.errors.length === 0, page.errors.join(' | '));
  await page.evaluate(() => { window.__openThrows = false; });

  // ---- No copy is made while the invoice's own payments are still loading ----
  // Cara paid from her wallet; Ben paid cash and holds nothing. Ben's invoice is
  // opened straight after Cara's, with its payments slow to arrive.
  await view(page, 'wallet');
  await page.evaluate(() => { window.__paysDelay = 1500; window.__calls.length = 0; });
  await page.getByRole('button', { name: 'Close', exact: true }).first().click();
  const openedAt = Date.now();
  await row(page, 'INV-T-cash').getByRole('button', { name: 'View', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('INV-T-cash'));
  ok('while its payments load, Print, PDF, Image, WhatsApp and Email are off',
    (await copyButtonsOff(page)).every(off => off === true), JSON.stringify(await copyButtonsOff(page)));
  ok('and the payments of the invoice before are not on screen', !(await page.locator('.modal').innerText()).includes('Wallet — Paid Credit'));
  const printsBefore = await page.evaluate(() => window.__printed.length);
  await page.evaluate(() => modalButton('Print').click());
  await page.waitForTimeout(100);
  ok('a press on Print while it is off opens nothing',
    await page.evaluate(n => window.__printed.length === n && !window.__calls.some(c => c.name === 'window.open'), printsBefore));
  await page.waitForFunction(() => !modalButton('Print').disabled);
  ok('the buttons come on once this invoice\'s own payments are in',
    Date.now() - openedAt >= 1400 && (await copyButtonsOff(page)).every(off => off === false), JSON.stringify(await copyButtonsOff(page)));
  html = await print(page);
  ok('and the copy is made from this invoice\'s payments alone',
    html.includes('INV-T-cash') && !html.includes('Wallet — Paid Credit') && !html.includes('Credit balance') && count(html, '<strong>S$100.00</strong>') === 2);
  await page.evaluate(() => { window.__paysDelay = 0; });

  // ---- Correct / Edit Invoice wait for the invoice's own rows too ---------------
  // Their form is built from those rows: opened early, it would start from a
  // blank line with no payments or service staff. One invoice per place the
  // button appears: paid, part-paid, cancelled (Correct Invoice) and unpaid
  // (Edit Invoice). Each is opened straight after another, its payments slow.
  for (const [id, name, readyTitle] of [['cash', 'Correct Invoice', CORRECT_TITLE], ['part', 'Correct Invoice', CORRECT_TITLE],
    ['cancelled', 'Correct Invoice', ''], ['owed-ben', 'Edit Invoice', '']]) {
    await view(page, 'wallet');
    await page.evaluate(() => { window.__paysDelay = 1500; });
    await page.getByRole('button', { name: 'Close', exact: true }).first().click();
    await row(page, `INV-T-${id}`).getByRole('button', { name: 'View', exact: true }).click();
    await page.waitForFunction(no => document.querySelector('.modal')?.innerText.includes(no), `INV-T-${id}`);
    ok(`${id}: while its rows load, ${name} is off and says why`,
      JSON.stringify(await buttonState(page, name)) === JSON.stringify({ disabled: true, title: 'Loading this invoice…' }), JSON.stringify(await buttonState(page, name)));
    await page.evaluate(n => modalButton(n).click(), name);
    await page.waitForTimeout(100);
    ok(`${id}: a press on it then opens nothing`, await page.evaluate(no => !!modalButton('Print') && document.querySelector('.modal').innerText.includes(no), `INV-T-${id}`));
    await page.waitForFunction(n => !modalButton(n).disabled, name);
    ok(`${id}: it comes on once they are in, as it always was`,
      JSON.stringify(await buttonState(page, name)) === JSON.stringify({ disabled: false, title: readyTitle }), JSON.stringify(await buttonState(page, name)));
    await page.evaluate(() => { window.__paysDelay = 0; });
  }

  // ---- A reload of the open invoice: the buttons wait for its rows again --------
  // Another tab records a S$100 wallet payment on Ann's open invoice: it is paid
  // now and her wallet is empty. The page reloads the invoice by itself, and its
  // payments are slow to come back. Until they are, the screen has the paid
  // invoice with the unpaid one's rows: a copy made then would mix the two.
  // The other tab writes a fresh row, as the server does: the page's own copy of
  // the invoice changes only when the reload brings the new one.
  await page.evaluate(() => { window.__billTo = { topay: 'Ann Source' }; });
  await view(page, 'topay');
  await page.evaluate(t0 => {
    const ix = window.__tables.invoices.findIndex(i => i.id === 'topay');
    window.__tables.invoices[ix] = { ...window.__tables.invoices[ix], status: 'paid', paid_amount: 100, paid_at: t0 };
    window.__tables.invoice_payments.push({ id: 'pay-topay', invoice_id: 'topay', payment_method_id: 'wallet-paid', amount: 100, entry_kind: 'receipt', created_at: t0, effective_at: t0 });
    window.__balances.ann = { categories: { paid: 0, bonus: 0, legacy: 0, promotional: 0, exchange: 0 }, available_total: 0 };
    window.__paysDelay = 1500; window.__calls.length = 0; window.__reads = [];
    new BroadcastChannel('energia:invoices').postMessage({ type: 'invoices-changed', ids: ['topay'], from: 'another-tab' });
  }, T0);
  const reloadAt = Date.now();
  // The reload has read the row back and opened the invoice from its full row:
  // the paid invoice is on screen, and its payments are still on their way.
  await page.waitForFunction(() => window.__reads.filter(r => r.table === 'invoices' && r.id === 'topay' && r.done).length === 2
    && window.__reads.some(r => r.table === 'invoice_payments' && r.id === 'topay' && !r.done) && !!modalButton('Correct Invoice'));
  ok('while the open invoice reloads, Print, PDF, Image, WhatsApp and Email are off',
    (await copyButtonsOff(page)).every(off => off === true), JSON.stringify(await copyButtonsOff(page)));
  ok('and so is Correct Invoice, saying why',
    JSON.stringify(await buttonState(page, 'Correct Invoice')) === JSON.stringify({ disabled: true, title: 'Loading this invoice…' }));
  ok('its own rows stay on screen meanwhile', (await page.locator('.modal').innerText()).includes('Long Energia Socks'));
  const printsBeforeReload = await page.evaluate(() => window.__printed.length);
  await page.evaluate(() => modalButton('Print').click());
  await page.waitForTimeout(100);
  ok('a press on Print during the reload opens nothing',
    await page.evaluate(n => window.__printed.length === n && !window.__calls.some(c => c.name === 'window.open'), printsBeforeReload));
  await page.waitForFunction(() => !modalButton('Print').disabled);
  ok('they come on once its payments are back',
    Date.now() - reloadAt >= 1400 && (await copyButtonsOff(page)).every(off => off === false)
      && JSON.stringify(await buttonState(page, 'Correct Invoice')) === JSON.stringify({ disabled: false, title: CORRECT_TITLE }));
  html = await print(page);
  ok('and the copy is the invoice as it is now: its wallet payment, S$0.00 left, its own Bill To',
    count(html, 'Wallet — Paid Credit') === 2 && count(html, LABEL) === 2 && count(html, '<strong>S$0.00</strong>') === 2
      && count(html, 'Ann Credit (Ann Source)') === 2, (html.match(/Ann Credit \([^)]*\)/) || [''])[0]);
  await page.evaluate(() => {
    window.__paysDelay = 0; window.__billTo = {};
    window.__balances.ann = { categories: { paid: 300, bonus: 50, legacy: 0, promotional: 0, exchange: 0 }, available_total: 350 };
  });

  // ---- ...from the moment the reload starts ------------------------------------
  // The same, with the open invoice's own row slow to come back (1 s a read).
  // The reload reads the row back by its id, then opens the invoice from its
  // full row. All that while the screen still has the invoice as it was —
  // unpaid, no wallet payment — and a copy reads the balance as it is now: a
  // copy made then would say unpaid beside a balance already spent on it.
  /** Each read of an invoice's own row since window.__reads was cleared: true once it has answered. */
  const rowReads = (p, id) => p.evaluate(i => window.__reads.filter(r => r.table === 'invoices' && r.id === i).map(r => r.done), id);
  const rowReadsSent = (p, id, n) => p.waitForFunction(([i, k]) => window.__reads.filter(r => r.table === 'invoices' && r.id === i).length >= k, [id, n]);
  await view(page, 'elsewhere');
  await page.evaluate(t0 => {
    const ix = window.__tables.invoices.findIndex(i => i.id === 'elsewhere');
    window.__tables.invoices[ix] = { ...window.__tables.invoices[ix], status: 'paid', paid_amount: 100, paid_at: t0 };
    window.__tables.invoice_payments.push({ id: 'pay-elsewhere', invoice_id: 'elsewhere', payment_method_id: 'wallet-paid', amount: 100, entry_kind: 'receipt', created_at: t0, effective_at: t0 });
    window.__balances.ann = { categories: { paid: 200, bonus: 50, legacy: 0, promotional: 0, exchange: 0 }, available_total: 250 };
    window.__slowFor = { invoices: { elsewhere: 1000 } }; window.__reads = []; window.__calls.length = 0;
    new BroadcastChannel('energia:invoices').postMessage({ type: 'invoices-changed', ids: ['elsewhere'], from: 'another-tab' });
  }, T0);
  const slowAt = Date.now();
  await rowReadsSent(page, 'elsewhere', 1);
  ok('the moment the open invoice starts reloading (its row asked for, nothing back yet), Print, PDF, Image, WhatsApp and Email are off',
    JSON.stringify(await rowReads(page, 'elsewhere')) === '[false]' && (await copyButtonsOff(page)).every(off => off === true),
    JSON.stringify([await rowReads(page, 'elsewhere'), await copyButtonsOff(page)]));
  ok('and so is Edit Invoice, saying why',
    JSON.stringify(await buttonState(page, 'Edit Invoice')) === JSON.stringify({ disabled: true, title: 'Loading this invoice…' }), JSON.stringify(await buttonState(page, 'Edit Invoice')));
  ok('the screen still has the invoice as it was, unpaid, with its own rows: the other tab\'s write is not on it until the reload brings it',
    await page.evaluate(() => !modalButton('Correct Invoice') && !!modalButton('Edit Invoice') && document.querySelector('.modal').innerText.includes('Long Energia Socks')));
  const printsBeforeSlow = await page.evaluate(() => window.__printed.length);
  await page.evaluate(() => modalButton('Print').click());
  await page.waitForTimeout(100);
  ok('a press on Print then opens nothing',
    await page.evaluate(n => window.__printed.length === n && !window.__calls.some(c => c.name === 'window.open'), printsBeforeSlow));
  // The row is back; the reload now opens the invoice, reading its full row.
  await rowReadsSent(page, 'elsewhere', 2);
  ok('still off while the reload opens the invoice from its full row',
    JSON.stringify(await rowReads(page, 'elsewhere')) === '[true,false]' && (await copyButtonsOff(page)).every(off => off === true)
      && (await buttonState(page, 'Edit Invoice'))?.disabled === true,
    JSON.stringify([await rowReads(page, 'elsewhere'), await copyButtonsOff(page), await buttonState(page, 'Edit Invoice')]));
  await page.waitForFunction(() => !!modalButton('Print') && !modalButton('Print').disabled);
  ok('they come on once the reload is in, and not before',
    Date.now() - slowAt >= 1900 && (await rowReads(page, 'elsewhere')).every(Boolean) && (await copyButtonsOff(page)).every(off => off === false)
      && JSON.stringify(await buttonState(page, 'Correct Invoice')) === JSON.stringify({ disabled: false, title: CORRECT_TITLE }));
  html = await print(page);
  ok('and the copy is the invoice as it is now: paid, from the wallet, with the S$250.00 left after it',
    count(html, '<b class="statusword">PAID</b>') === 2 && count(html, 'Wallet — Paid Credit') === 2
      && count(html, LABEL) === 2 && count(html, '<strong>S$250.00</strong>') === 2, (html.match(/statusword">[^<]*/) || [''])[0]);
  await page.evaluate(() => {
    window.__slowFor = {};
    window.__balances.ann = { categories: { paid: 300, bonus: 50, legacy: 0, promotional: 0, exchange: 0 }, available_total: 350 };
  });

  // ---- Record Payment on this tab: the copies wait from the read-back -----------
  // The payment is in once the server says so, but the screen has the unpaid
  // invoice until its row is read back (1 s), and then it is opened from its
  // full row (1 s more). A copy made in between would leave the payment out.
  await view(page, 'payhere');
  await page.getByRole('button', { name: 'Payment method', exact: true }).first().click();
  await page.getByRole('combobox', { name: 'Search payment method' }).fill('cash');
  await page.getByRole('combobox', { name: 'Search payment method' }).press('Enter');
  await page.evaluate(() => { window.__slowFor = { invoices: { payhere: 1000 } }; window.__reads = []; window.__calls.length = 0; });
  const payAt = Date.now();
  await page.getByRole('button', { name: 'Record Payment', exact: true }).click();
  await rowReadsSent(page, 'payhere', 1);
  ok('once Record Payment has gone through, the copy buttons are off while the invoice is read back',
    await page.evaluate(() => window.__calls.filter(c => c.name === 'record_invoice_settlement').length === 1)
      && JSON.stringify(await rowReads(page, 'payhere')) === '[false]' && (await copyButtonsOff(page)).every(off => off === true),
    JSON.stringify([await rowReads(page, 'payhere'), await copyButtonsOff(page)]));
  ok('while the screen still has it unpaid', await page.evaluate(() => !!modalButton('Edit Invoice') && !modalButton('Correct Invoice')));
  const printsBeforePaid = await page.evaluate(() => window.__printed.length);
  await page.evaluate(() => modalButton('Print').click());
  await page.waitForTimeout(100);
  ok('a press on Print then opens nothing',
    await page.evaluate(n => window.__printed.length === n && !window.__calls.some(c => c.name === 'window.open'), printsBeforePaid));
  await rowReadsSent(page, 'payhere', 2);
  ok('and while it is opened again from its full row',
    JSON.stringify(await rowReads(page, 'payhere')) === '[true,false]' && (await copyButtonsOff(page)).every(off => off === true),
    JSON.stringify([await rowReads(page, 'payhere'), await copyButtonsOff(page)]));
  await page.waitForFunction(() => !!modalButton('Print') && !modalButton('Print').disabled);
  ok('they come on once it is back', Date.now() - payAt >= 1900 && (await rowReads(page, 'payhere')).every(Boolean)
    && (await copyButtonsOff(page)).every(off => off === false));
  html = await print(page);
  ok('and the copy has the payment just recorded', count(html, '<b class="statusword">PAID</b>') === 2 && count(html, '<strong>S$100.00</strong>') === 2,
    (html.match(/statusword">[^<]*/) || [''])[0]);
  await page.evaluate(() => { window.__slowFor = {}; });

  // ---- The Bill To source is printed: the buttons wait for it as well -----------
  // Everything else of Ben's invoice is in at once; only its Bill To answer is slow.
  await page.evaluate(() => { window.__billTo = { cash: 'Ben Source' }; window.__billToDelayFor = { cash: 1500 }; window.__calls.length = 0; });
  await page.getByRole('button', { name: 'Close', exact: true }).first().click();
  const billToAt = Date.now();
  await row(page, 'INV-T-cash').getByRole('button', { name: 'View', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('INV-T-cash'));
  await page.waitForFunction(() => window.__calls.some(c => c.name === 'invoice_financial_position'));
  await page.waitForTimeout(600);
  ok('while its Bill To answer is on its way, the copy buttons stay off, though its rows are in',
    (await copyButtonsOff(page)).every(off => off === true) && (await page.locator('.modal').innerText()).includes('Long Energia Socks'),
    JSON.stringify(await copyButtonsOff(page)));
  await page.waitForFunction(() => !modalButton('Print').disabled);
  ok('and come on when it answers', Date.now() - billToAt >= 1400);
  html = await print(page);
  ok('so the copy prints this invoice\'s own Bill To', count(html, 'Ben Cash (Ben Source)') === 2, (html.match(/Ben Cash \([^)]*\)/) || [''])[0]);
  await page.evaluate(() => { window.__billTo = {}; window.__billToDelayFor = {}; });

  // The invoice before is closed while its Bill To source is still on its way:
  // when it lands, it is not printed on the next invoice.
  await page.evaluate(() => { window.__billTo = { wallet: 'Cara Source', cash: 'Ben Source' }; window.__billToDelayFor = { wallet: 1200 }; });
  await page.getByRole('button', { name: 'Close', exact: true }).first().click();
  await row(page, 'INV-T-wallet').getByRole('button', { name: 'View', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('INV-T-wallet'));
  await page.getByRole('button', { name: 'Close', exact: true }).first().click();
  await view(page, 'cash');
  await page.waitForTimeout(1500);
  html = await print(page);
  ok('a slow Bill To answer for the invoice before is never printed on this one',
    count(html, 'Ben Cash (Ben Source)') === 2 && !html.includes('Cara Source'), (html.match(/Ben Cash \([^)]*\)/) || [''])[0]);
  await page.evaluate(() => { window.__billTo = {}; window.__billToDelayFor = {}; });

  // An unpaid invoice (S$100 outstanding) is closed while its last read is on
  // its way; when that lands, its balance is not put on the paid one opened next.
  await page.evaluate(() => { window.__slowFor = { invoice_revisions: { 'owed-ann': 1200 } }; });
  await page.getByRole('button', { name: 'Close', exact: true }).first().click();
  await row(page, 'INV-T-owed-ann').getByRole('button', { name: 'View', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('INV-T-owed-ann'));
  await page.waitForTimeout(100);
  await page.getByRole('button', { name: 'Close', exact: true }).first().click();
  await view(page, 'cash');
  await page.waitForTimeout(1500);
  ok('a slow read for the invoice before never puts its balance on this one\'s PDF', !(await downloadText(page, 'PDF')).includes('Balance'));
  await page.evaluate(() => { window.__slowFor = {}; });

  // The invoice before is closed while its promotion choices are on their way:
  // when they land, they do not replace this invoice's own choices.
  await view(page, 'promoB');
  html = await print(page);
  ok('a promotion prints the customer\'s own choice under it', count(html, '× 2 (chosen)') === 2 && !html.includes('× 1 (chosen)'));
  await page.evaluate(() => { window.__slowFor = { invoice_promotion_selections: { 'line-promoA': 1500 } }; });
  await page.getByRole('button', { name: 'Close', exact: true }).first().click();
  await row(page, 'INV-T-promoA').getByRole('button', { name: 'View', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('INV-T-promoA'));
  await page.waitForTimeout(200);
  await page.getByRole('button', { name: 'Close', exact: true }).first().click();
  await view(page, 'promoB');
  await page.waitForTimeout(1600);
  html = await print(page);
  ok('a slow answer for the invoice before never replaces this one\'s promotion choices',
    count(html, '× 2 (chosen)') === 2 && !html.includes('× 1 (chosen)'), (html.match(/× \d \(chosen\)/g) || []).join(','));
  await page.evaluate(() => { window.__slowFor = {}; });

  // A print whose balance read gives up after another invoice was opened: the
  // note that it went without the balance belongs to the invoice it was made
  // from, not to the one open now.
  await view(page, 'corrected');
  await page.evaluate(() => { window.__balanceDelayFor = { ann: 5000 }; });
  const printsBeforeSwitch = await page.evaluate(() => window.__printed.length);
  await page.getByRole('button', { name: 'Print', exact: true }).click();
  await view(page, 'cash');
  await page.waitForFunction(n => window.__printed.length > n, printsBeforeSwitch, { timeout: 6000 });
  await page.waitForTimeout(300);
  html = await page.evaluate(() => window.__printed[window.__printed.length - 1]);
  ok('the print still goes out, for the invoice it was made from, without the line', html.includes('INV-T-corrected') && !html.includes('Credit balance'));
  ok('and no note about it appears on the invoice open now',
    (await unreadNote(page)) === null && (await page.locator('.modal').innerText()).includes('INV-T-cash'), String(await unreadNote(page)));
  await page.evaluate(() => { window.__balanceDelayFor = {}; });

  // ---- The note is said only once the copy has gone out -------------------------
  await view(page, 'corrected');
  await page.evaluate(() => { window.__balanceError = 'network down'; window.__closePrintWindow = true; });
  await page.getByRole('button', { name: 'Print', exact: true }).click();
  await page.waitForTimeout(300);
  ok('a print window closed before the invoice was written: nothing printed, nothing said', (await unreadNote(page)) === null, String(await unreadNote(page)));
  await page.evaluate(() => { window.__closePrintWindow = false; window.__uploadFails = true; });
  await page.getByRole('button', { name: 'WhatsApp', exact: true }).click();
  await page.locator('.modal .alert-danger').filter({ hasText: 'storage down' }).waitFor();
  ok('a send that failed is not reported as sent without the credit balance', (await unreadNote(page)) === null, String(await unreadNote(page)));
  await page.evaluate(() => { window.__uploadFails = false; });
  await page.getByRole('button', { name: 'WhatsApp', exact: true }).click();
  ok('one that went is', (await unreadNote(page, 'Sent without the credit balance — it could not be read.')) === 'Sent without the credit balance — it could not be read.', String(await unreadNote(page)));
  // B16: a second tap while a send is under way opens no second window and
  // sends nothing more; both buttons are off until it is done.
  await page.getByRole('button', { name: 'WhatsApp', exact: true }).waitFor();
  const opensBefore = await page.evaluate(() => window.__calls.filter(c => c.name === 'window.open').length);
  const logsBefore = await page.evaluate(() => window.__calls.filter(c => c.name === 'record_document_send').length);
  const busyButtons = await page.evaluate(async () => {
    window.__balanceDelay = 300;   // the send stays under way long enough to look
    const wa = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'WhatsApp');
    wa.click(); wa.click();        // the second before the page has redrawn
    await new Promise(r => setTimeout(r, 50));
    const now = [...document.querySelectorAll('button')];
    return { wa: now.find(b => b.textContent.includes('Preparing…'))?.disabled ?? null,
             email: now.find(b => b.textContent.trim().startsWith('Email (from this device)'))?.disabled ?? null };
  });
  await page.waitForFunction(() => [...document.querySelectorAll('button')].some(b => b.textContent.trim() === 'WhatsApp' && !b.disabled));
  await page.evaluate(() => { window.__balanceDelay = 0; });
  ok('a double tap on WhatsApp opens one window and sends once, with both send buttons off meanwhile',
    await page.evaluate(([o, l]) => window.__calls.filter(c => c.name === 'window.open').length === o + 1
      && window.__calls.filter(c => c.name === 'record_document_send').length <= l + 1, [opensBefore, logsBefore])
      && busyButtons.wa === true && busyButtons.email === true, JSON.stringify(busyButtons));
  await page.evaluate(() => { window.__toBlobFails = true; });
  await page.getByRole('button', { name: 'Image', exact: true }).click();
  await page.locator('.modal .alert-danger').filter({ hasText: 'Could not save (Could not create the invoice image.).' }).waitFor();
  ok('an image that could not be saved says so, and not that it was saved without the balance', (await unreadNote(page)) === null, String(await unreadNote(page)));
  await page.evaluate(() => { window.__toBlobFails = false; window.__balanceError = null; });

  // ---- Beside the totals, the PDF/image line fits where it used to give way ------
  // Ann's twelve instalments: the line used to be left off this invoice's PDF
  // and image for want of room under the payments.
  await view(page, 'instalments');
  let pdfDoc = await downloadText(page, 'PDF');
  ok('a twelve-instalment invoice carries the line in full on its PDF, with nothing said',
    pdfDoc.includes(LABEL) && pdfDoc.includes('Paid S$300.00 · Bonus S$50.00') && (await unreadNote(page)) === null);
  await downloadText(page, 'Image');
  let drawnText = await imageTexts(page);
  ok('and on its image', drawnText.includes(LABEL) && drawnText.includes('Paid S$300.00 · Bonus S$50.00') && (await unreadNote(page)) === null);
  // Twenty items: more than the page lists, so the copy is already full.
  await view(page, 'long');
  pdfDoc = await downloadText(page, 'PDF');
  ok('a full page carries it too, beside the totals', pdfDoc.includes(LABEL) && pdfDoc.includes('continued') && (await unreadNote(page)) === null);
  // A device whose font draws the label wider than the column beside the
  // totals. B16 (AFTER-8): twenty items run past one A5 page, so the copy
  // takes a second one, where the line has room under the payments.
  await page.evaluate(() => { window.__wideLabel = true; });
  pdfDoc = await downloadText(page, 'PDF');
  ok('a copy that runs long takes a second page, with the line on it and nothing said',
    pdfDoc.includes(LABEL) && pdfDoc.includes('INV-T-long (continued)') && (await unreadNote(page)) === null);
  await page.evaluate(() => { window.__imageCanvas = null; window.__imageText.length = 0; });
  await downloadText(page, 'Image');
  ok('its image grows taller instead, with the line on it',
    await page.evaluate(l => window.__imageCanvas.height > 1680 && window.__imageText.includes(l), LABEL) && (await unreadNote(page)) === null,
    String(await page.evaluate(() => window.__imageCanvas?.height)));
  // Seven items and one payment: one full page, with no room beside the
  // totals for that label, and none under the payments.
  await view(page, 'tight');
  pdfDoc = await downloadText(page, 'PDF');
  ok('with no room anywhere the PDF goes without the line', !pdfDoc.includes(LABEL) && pdfDoc.includes('INV-T-tight') && !pdfDoc.includes('(continued)'));
  ok('and the page says it was saved without it, for want of room',
    (await unreadNote(page, 'Saved without the credit balance — no room on the page.')) === 'Saved without the credit balance — no room on the page.', String(await unreadNote(page)));
  await page.evaluate(() => { window.__imageCanvas = null; });
  await downloadText(page, 'Image');
  drawnText = await imageTexts(page);
  // The image measures its own page, so it may have room where the PDF has
  // none; either way it says what it drew.
  const imageNote = drawnText.includes(LABEL) ? await unreadNote(page) : await unreadNote(page, 'Saved without the credit balance — no room on the page.');
  ok('the image says what it drew: the line, or that there was no room for it', drawnText.includes('INV-T-tight')
    && (drawnText.includes(LABEL) ? imageNote === null : imageNote === 'Saved without the credit balance — no room on the page.'),
    JSON.stringify([imageNote, drawnText.filter(t => /INV|Credit/.test(t))]));
  await page.evaluate(() => { window.__uploaded = null; });
  await page.getByRole('button', { name: 'WhatsApp', exact: true }).click();
  await page.waitForFunction(() => !!window.__uploaded);
  ok('and a PDF sent by WhatsApp: sent without it, said so',
    !pdfText(await page.evaluate(() => Array.from(window.__uploaded))).includes(LABEL)
      && (await unreadNote(page, 'Sent without the credit balance — no room on the page.')) === 'Sent without the credit balance — no room on the page.', String(await unreadNote(page)));
  html = await print(page);
  ok('the printed copy is not measured that way: it carries the line and says nothing', count(html, LABEL) === 2 && (await unreadNote(page)) === null);
  await page.evaluate(() => { window.__wideLabel = false; window.__uploaded = null; window.__opened = []; });

  // A wallet method since switched off still counts as the wallet.
  await view(page, 'old-wallet');
  html = await print(page);
  ok('a payment by a switched-off wallet method still shows the line at S$0.00',
    count(html, LABEL) === 2 && count(html, '<strong>S$0.00</strong>') === 2);
  await view(page, 'corrected');

  // ---- The PDF and image copies -----------------------------------------------
  let pdf = await downloadText(page, 'PDF', '.invoice-test/browser/credit-balance.pdf');
  ok('the PDF customer copy carries the line', pdf.includes(LABEL) && pdf.includes('S$350.00') && pdf.includes('Paid S$300.00 · Bonus S$50.00'));
  ok('the PDF payment rows still sum to its Paid figure', pdf.includes('S$-3000.00') && pdf.includes('S$550.00'));
  await page.evaluate(() => { window.__imageText.length = 0; });
  const image = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Image', exact: true }).click();
  await (await image).saveAs('.invoice-test/browser/credit-balance-image.png');
  ok('the image customer copy carries the line', await page.evaluate(l => window.__imageText.includes(l) && window.__imageText.includes('S$350.00') && window.__imageText.includes('Paid S$300.00 · Bonus S$50.00'), LABEL));

  // ---- WhatsApp and email send the same copy -------------------------------------
  await page.getByRole('button', { name: 'WhatsApp', exact: true }).click();
  await page.waitForFunction(() => window.__uploaded && window.__opened.some(u => u.startsWith('https://wa.me/')));
  ok('the PDF sent by WhatsApp carries the line', pdfText(await page.evaluate(() => Array.from(window.__uploaded))).includes(LABEL));
  ok('the WhatsApp window opened in the click, before the balance was read (AFTER-11)', await page.evaluate(() => {
    const calls = window.__calls; const sent = calls.map(c => c.name).lastIndexOf('window.open');
    return sent >= 0 && !calls[sent].url && calls.slice(sent).some(c => c.name === 'customer_credit_balances');
  }));
  ok('and the page says where to send it, not that it was sent',
    (await page.locator('[data-testid="invoice-send-note"]').innerText()).includes('WhatsApp should now be open with the invoice link; send the message there.'));
  // B16 (Q6): email goes from this device's mail app: on a phone the share sheet hands it the PDF.
  await page.evaluate(() => {
    window.__shared = null;
    Object.defineProperty(navigator, 'canShare', { configurable: true, value: () => true });
    Object.defineProperty(navigator, 'share', { configurable: true, value: async data => { window.__shared = data; } });
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => {} } });
  });
  await page.getByRole('button', { name: 'Email (from this device)', exact: true }).click();
  await page.waitForFunction(() => !!window.__shared);
  const emailed = pdfText(await page.evaluate(async () => Array.from(new Uint8Array(await window.__shared.files[0].arrayBuffer()))));
  ok('the PDF sent by email carries the line', emailed.includes(LABEL) && emailed.includes('S$350.00'));
  const emailNote = await page.locator('[data-testid="invoice-send-note"]').innerText();
  ok('and the page says where it went, never that it was attached or sent',
    emailNote.includes('went to the app you chose') && !/attached/i.test(emailNote), emailNote);
  ok('no email-sending service is called (Q6)', await page.evaluate(() => !window.__emailFunctionCalled));
  // A share sheet closed without choosing an app: "Not sent".
  await page.evaluate(() => { Object.defineProperty(navigator, 'share', { configurable: true,
    value: async () => { throw new DOMException('closed', 'AbortError'); } }); });
  await page.getByRole('button', { name: 'Email (from this device)', exact: true }).click();
  await page.locator('.modal .alert-danger').filter({ hasText: 'Not sent: the share sheet was closed.' }).waitFor();
  ok('a closed share sheet is "Not sent"', true);

  // ---- Record Payment never offers the previous customer's wallet -------------
  // (443: the wallet line under the form says what the customer holds, "S$350.00
  // held"; "available" beside each method is what it can pay of this invoice.)
  await view(page, 'owed-ann');
  await page.getByText('S$350.00 held').first().waitFor();
  ok('Record Payment offers the customer\'s own wallet', true);
  // Ann's answer is slow and Ben's slower; Ben's invoice is opened straight after Ann's.
  await page.evaluate(() => { window.__balanceDelayFor = { ann: 1500, ben: 800 }; });
  await view(page, 'owed-ann');
  await view(page, 'owed-ben');
  ok('the wallet of the customer before is cleared the moment another customer\'s invoice opens',
    !(await page.locator('.modal').innerText()).includes('S$350.00 held'));
  await page.waitForTimeout(2000);
  ok('and a slow answer for the invoice opened before is never shown on this one',
    !(await page.locator('.modal').innerText()).includes('S$350.00 held'));
  await page.evaluate(() => { window.__balanceDelayFor = {}; });

  await view(page, 'cash');
  pdf = await downloadText(page, 'PDF');
  ok('a PDF for a customer with nothing has no line', !pdf.includes('Credit balance'));
  await view(page, 'cancelled');
  pdf = await downloadText(page, 'PDF');
  ok('nor does a cancelled invoice\'s PDF', !pdf.includes('Credit balance'));
  ok('no browser errors (owner)', page.errors.length === 0, page.errors.join(' | '));
  await page.context().close();

  // ---- Staff print the same line -------------------------------------------------
  const sp = await openPage(staff);
  await view(sp, 'corrected');
  html = await print(sp);
  ok('a member of staff prints the same line', count(html, LABEL) === 2 && count(html, '<strong>S$350.00</strong>') === 2);
  // Staff who may correct a paid invoice (377): their Correct Invoice waits too.
  await sp.evaluate(() => { window.__staffMayCorrect = true; window.__paysDelay = 1500; });
  await sp.getByRole('button', { name: 'Close', exact: true }).first().click();
  await row(sp, 'INV-T-cash').getByRole('button', { name: 'View', exact: true }).click();
  await sp.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('INV-T-cash') && !!modalButton('Correct Invoice'));
  ok('a member of staff\'s Correct Invoice is off while the invoice loads, saying why',
    JSON.stringify(await buttonState(sp, 'Correct Invoice')) === JSON.stringify({ disabled: true, title: 'Loading this invoice…' }), JSON.stringify(await buttonState(sp, 'Correct Invoice')));
  await sp.waitForFunction(() => !modalButton('Correct Invoice').disabled);
  ok('and on once it is in, as it always was', JSON.stringify(await buttonState(sp, 'Correct Invoice')) === JSON.stringify({ disabled: false, title: CORRECT_TITLE }));
  await sp.evaluate(() => { window.__paysDelay = 0; });
  ok('no browser errors (staff)', sp.errors.length === 0, sp.errors.join(' | '));
  await sp.context().close();

  // ---- The image copy: beside the totals, else it gives way -------------------
  // The image is drawn on a canvas, so its layout is checked here in the
  // browser; the PDF's is checked in credit-balance-pdf-layout.test.mjs. A full
  // store footer, and payment lists up to an instalment plan's length. The
  // line goes in the empty left column beside the totals, where it costs no
  // height; a copy with no totals block has it under the payments, where it
  // gives way: the breakdown first, then the total.
  {
    const lib = await build({ stdin: { contents: `import { documentImageBlob } from './src/lib/invoiceImage'; window.__image = documentImageBlob;`, resolveDir: process.cwd(), loader: 'ts' },
      bundle: true, format: 'iife', write: false });
    const ip = await browser.newPage();
    await ip.route('**/*', route => route.request().url() === 'https://invoice.test/' ? route.fulfill({ contentType: 'text/html', body: HTML }) : route.abort());
    await ip.goto('https://invoice.test/');
    await ip.evaluate(() => {
      // Each canvas keeps the text drawn on it, and where; the one turned into
      // the image is remembered, and every canvas made for one image is listed.
      // Turning it into a PNG is skipped: only the drawing is checked here.
      window.__canvases = [];
      const getContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (...a) {
        const ctx = getContext.apply(this, a), canvas = this;
        if (ctx && !canvas.__texts) {
          canvas.__texts = []; window.__canvases.push(canvas); const fill = ctx.fillText;
          ctx.fillText = function (t, x, y, ...r) { canvas.__texts.push({ t: String(t), x: Math.round(x * 100) / 100, y, align: ctx.textAlign, w: ctx.measureText(String(t)).width }); return fill.call(this, t, x, y, ...r); };
        }
        return ctx;
      };
      HTMLCanvasElement.prototype.toBlob = function (done) { window.__imageCanvas = this; done(new Blob(['png'])); };
    });
    await ip.addScriptTag({ content: lib.outputFiles[0].text });
    const layout = await ip.evaluate(async () => {
      const H = 1680, MM = 8;
      const label = 'Credit balance (as at 2 Oct 2026)';
      const credits = [
        { label, amount: 'S$350.00', detail: 'Paid S$300.00 · Bonus S$50.00' },
        { label, amount: 'S$55555.55', detail: 'Paid S$11111.11 · Bonus S$11111.11 · Legacy S$11111.11 · Promotional S$11111.11 · Exchange S$11111.11' },
      ];
      // The totals blocks the invoice page makes (every one has a grand total),
      // and a copy with none at all.
      const shapes = {
        'part-paid': { totals: [['Subtotal', 'S$10.00'], ['Discount', '-S$0.00'], ['Paid', 'S$10.00'], ['Balance', 'S$5.00']], grandTotal: ['Total', 'S$10.00'] },
        'nothing paid or owed': { totals: [['Subtotal', 'S$0.00'], ['Discount', '-S$0.00']], grandTotal: ['Total', 'S$0.00'] },
        'no totals': { totals: [], grandTotal: undefined },
      };
      const doc = (n, pays, creditBalance, shape) => ({
        kindLabel: 'Tax Invoice', docNo: 'INV-T-0001', date: '02/10/2026', status: 'PAID', storeName: 'Test Store',
        storeAddress: '1 Example Road #01-01, Singapore 000001', storePhone: '+6560000000 · WhatsApp +6590000000',
        customerName: 'Ann Credit (-)', customerContact: '+6590000001 · ann@example.test',
        lines: Array.from({ length: n }, (_, i) => ({ name: `Test item ${i + 1}`, qty: 1, unit: 10, total: 10, notes: [] })),
        ...shapes[shape],
        payments: Array.from({ length: pays }, (_, i) => [`Cash · 0${(i % 9) + 1}/10/2026`, 'S$5.00']),
        creditBalance, staffName: 'Test Owner', policyText: 'Exchanges within 7 days with receipt.\nVouchers are not refundable.',
        payDetails: ['CIMB UEN: TEST0001X', 'CIMB corporate account: 000-000000-0'],
        footerBits: ['DID: +6560000000', 'Email: shop@example.test', 'Website: example.test', 'Co. Reg No.: TEST0001X'],
      });
      const draw = async (d, credit) => {
        window.__canvases = [];
        await window.__image(d);
        const used = window.__imageCanvas, t = used.__texts;
        const kinds = credit ? credit.detail.split(' · ') : [];
        const isCredit = x => !!credit && (x.t === credit.label || x.t === credit.amount || kinds.some(k => x.t.includes(k)));
        const detail = t.filter(x => kinds.some(k => x.t.includes(k)));
        const foot = t.filter(x => x.t.includes('Co. Reg No.'));
        const lab = t.find(x => x.t === label), sub = t.find(x => x.t === 'Subtotal');
        return {
          footer: foot.length ? foot[foot.length - 1].y : null,
          rows: t.filter(x => /^Test item \d+$/.test(x.t)).map(x => x.t).join(','),
          continued: t.some(x => x.t.startsWith('…continued')),
          state: !lab ? 'none' : detail.length ? 'full' : 'total',
          beside: !!lab && !!sub && lab.y === sub.y,
          // Everything else on the copy, exactly where it was drawn.
          rest: JSON.stringify(t.filter(x => !isCredit(x))),
          // The line itself, all left of the totals block and between its first and last lines.
          creditBox: t.filter(isCredit).map(x => ({ right: x.x + (x.align === 'right' ? 0 : x.w), y: x.y })),
          totalsBox: sub ? { left: (148.5 - 10 - 24 - 22) * MM, top: sub.y, bottom: (t.find(x => x.t === 'Total') || sub).y } : null,
          detailWhole: !detail.length || detail.map(x => x.t).join(' · ') === credit.detail,
          detailLines: detail.map(x => x.t),
          canvases: window.__canvases.length,
          released: window.__canvases.filter(c => c !== used).every(c => c.width === 0 && c.height === 0),
          // B16 (AFTER-8): an image that runs long grows taller; its payments may shorten first.
          height: used.height,
          shortened: t.some(x => /^Payments: \d+; full list on the store copy$/.test(x.t)),
          // AFTER-9: an A5 drawing stopped listing rows, so the copy went on to
          // the growing drawing, which lists them all (more canvases).
          cutOnA5: window.__canvases.some(c => c !== used && c.__texts.some(x => x.t.startsWith('…continued'))),
        };
      };
      const out = [];
      for (const shape of Object.keys(shapes)) {
        for (const [ci, credit] of credits.entries()) {
          for (const pays of [0, 2, 10, 11, 12]) {
            for (let n = 1; n <= 20; n++) {
              out.push({ shape, n, pays, ci, without: await draw(doc(n, pays, null, shape), null), withLine: await draw(doc(n, pays, credit, shape), credit) });
            }
          }
        }
      }
      // B16 (AFTER-9): promotions list what is inside them. Every line is
      // drawn, the image growing when it must; none is left off.
      const promo = [];
      for (const notes of [[4, 4, 0, 0, 0, 0], [9, 3, 0, 0], [3, 3, 3, 0]]) {
        const lines = notes.map((k, i) => ({ name: `Promotion line ${i + 1} with a long fixture bundle name`, qty: 1, unit: 10, total: 10,
          notes: Array.from({ length: k }, (_, j) => `Fixture content item ${j + 1} × 1 (included)`) }));
        const d = { ...doc(lines.length, 1, null, 'part-paid'), lines };
        window.__canvases = [];
        await window.__image(d);
        const t = window.__imageCanvas.__texts.map(x => x.t);
        promo.push({ notes: notes.join(','), drawn: lines.filter(l => t.includes(l.name)).length, of: lines.length,
          continued: t.some(x => x.startsWith('…continued')), contents: t.filter(x => x.startsWith('Fixture content item')).length,
          wanted: notes.reduce((a, b) => a + b, 0) });
      }
      return { H, MM, out, promo };
    });
    await ip.close();
    const { H, MM, out, promo } = layout;
    ok('an image lists every promotion line and what is in it, with no row left off (AFTER-9)',
      promo.every(p => p.drawn === p.of && !p.continued && p.contents === p.wanted), JSON.stringify(promo));
    const at = r => `${r.shape}/${r.n} items/${r.pays} payments/credit ${r.ci}`;
    const real = out.filter(r => r.shape !== 'no totals'), bare = out.filter(r => r.shape === 'no totals');
    ok('the image line never costs an item row, with a full footer and up to 12 payments',
      out.every(r => r.withLine.rows === r.without.rows && r.withLine.continued === r.without.continued),
      out.filter(r => r.withLine.rows !== r.without.rows).map(at).join('; '));
    // The footer's last baseline: no lower than without the line, or 8 mm above the edge if that is lower down.
    // B16 (AFTER-8): an image that runs long grows taller instead, and then its
    // footer is 8 mm above its own foot; the line never makes an A5 image grow.
    const grown = r => r.height > H;
    const onePage = r => !grown(r.withLine) && !grown(r.without);
    ok('and never pushes the footer lower than it was, or the on-page limit',
      out.every(r => r.withLine.footer <= Math.max(r.without.footer, r.withLine.height - 8 * MM) + 0.5),
      out.filter(r => !(r.withLine.footer <= Math.max(r.without.footer, r.withLine.height - 8 * MM) + 0.5)).map(r => `${at(r)}: ${r.without.footer} → ${r.withLine.footer}`).join('; '));
    ok('the line never makes an image grow or shorten its payments',
      out.every(r => grown(r.withLine) === grown(r.without) && r.withLine.shortened === r.without.shortened),
      out.filter(r => !(grown(r.withLine) === grown(r.without) && r.withLine.shortened === r.without.shortened)).map(at).join('; '));
    ok('a long image grows taller, with its footer at its own foot',
      out.some(r => grown(r.withLine)) && out.filter(r => grown(r.withLine)).every(r => r.withLine.footer <= r.withLine.height - 8 * MM + 0.5));
    // The owner's example (two kinds) fits beside every totals block at every
    // length; so do all five kinds beside a part-paid invoice's four totals
    // rows. Five long kinds beside only Subtotal and Discount (nothing paid,
    // nothing owed) do not: they go under the payments while there is room
    // (up to 8 items with no payments, 6 with two, 2 with ten, 1 with eleven or
    // twelve), and on a fuller page the total alone stays beside the totals.
    const fullBeside = r => r.ci === 0 || r.shape === 'part-paid';
    ok('with the totals the page makes, the image carries the owner\'s example in full beside them, and five kinds beside four totals rows, at every length and payment count',
      real.filter(fullBeside).every(r => r.withLine.state === 'full' && r.withLine.beside),
      real.filter(fullBeside).filter(r => !(r.withLine.state === 'full' && r.withLine.beside)).map(r => `${at(r)}: ${r.withLine.state}`).join('; '));
    ok('five long kinds beside two totals rows: in full under the payments while there is room, else the total beside the totals — never left off',
      real.filter(r => !fullBeside(r)).every(r => (r.withLine.state === 'full' && !r.withLine.beside) || (r.withLine.state === 'total' && r.withLine.beside))
        && real.filter(r => !fullBeside(r)).some(r => r.withLine.state === 'total'),
      real.filter(r => !fullBeside(r)).map(r => `${at(r)}: ${r.withLine.state}${r.withLine.beside ? ' beside' : ''}`).join('; '));
    ok('beside the totals it moves nothing: every other line is drawn exactly where it is without it',
      real.filter(r => r.withLine.beside).every(r => r.withLine.rest === r.without.rest),
      real.filter(r => r.withLine.beside && r.withLine.rest !== r.without.rest).map(at).join('; '));
    ok('and all of it sits left of the totals block, between its first and last lines',
      real.filter(r => r.withLine.beside).every(r => r.withLine.creditBox.every(b => b.right <= r.withLine.totalsBox.left - 3 * MM && b.y >= r.withLine.totalsBox.top && b.y <= r.withLine.totalsBox.bottom)),
      real.filter(r => r.withLine.beside && !r.withLine.creditBox.every(b => b.right <= r.withLine.totalsBox.left - 3 * MM && b.y >= r.withLine.totalsBox.top && b.y <= r.withLine.totalsBox.bottom)).map(at).join('; '));
    ok('with no totals block to sit beside, the line is drawn whole, without its breakdown, or not at all', bare.every(r => r.withLine.detailWhole && !r.withLine.beside));
    const order = { full: 0, total: 1, none: 2 };
    // While the image is one A5 page with every payment listed; once it grows
    // or its payments shorten, the line has room again (B16).
    const listed = r => onePage(r) && !r.withLine.shortened && !r.without.shortened;
    ok('and gives way in order as the page fills: the breakdown first, then the total',
      bare.filter(listed).every(r => { const next = bare.find(q => q.ci === r.ci && q.pays === r.pays && q.n === r.n + 1); return !next || !listed(next) || order[next.withLine.state] >= order[r.withLine.state]; })
        && bare.filter(r => !listed(r)).every(r => r.withLine.state !== 'none'));
    ok('that sweep reaches all three', ['full', 'total', 'none'].every(st => bare.filter(listed).some(r => r.withLine.state === st)));
    ok('a short image is unchanged below the line, with the line in full',
      out.filter(r => r.pays === 2 && r.n <= 3).every(r => r.withLine.footer === r.without.footer && r.withLine.state === 'full'));
    ok('the breakdown wraps between kinds only',
      out.every(r => r.withLine.detailLines.every(ln => ln.split(' · ').every(k => /^(Paid|Bonus|Legacy|Promotional|Exchange) S\$[\d.]+$/.test(k)))));
    // An image that runs long tries the shortened payments, then grows (each
    // growing drawing measured once, then drawn), so it takes more canvases.
    // B16 (AFTER-9): rows past the room an A5 page leaves above the
    // signatures send the copy to the growing drawing, which lists them all;
    // it stays one page tall when they fit.
    ok('every row is listed on the image, however many (AFTER-9)',
      out.every(r => r.withLine.rows.split(',').length === r.n && !r.withLine.continued && !r.without.continued)
        && out.some(r => r.without.cutOnA5 && !grown(r.without)),
      out.filter(r => r.withLine.rows.split(',').length !== r.n).map(at).join('; '));
    ok('one canvas an image beside the totals; at most three otherwise, and every one thrown away is released',
      real.filter(fullBeside).filter(onePage).filter(r => !r.withLine.shortened && !r.withLine.cutOnA5).every(r => r.withLine.canvases === 1)
        && out.filter(onePage).filter(r => !r.withLine.shortened && !r.withLine.cutOnA5 && !r.without.cutOnA5).every(r => r.withLine.canvases <= 3 && r.without.canvases === 1)
        && real.filter(fullBeside).filter(r => r.withLine.cutOnA5 && !r.withLine.shortened).every(r => r.withLine.canvases <= 3)
        && out.every(r => r.withLine.canvases <= 12 && r.withLine.released && r.without.released),
      JSON.stringify([
        ...real.filter(fullBeside).filter(onePage).filter(r => !r.withLine.shortened && !r.withLine.cutOnA5).filter(r => r.withLine.canvases !== 1),
        ...out.filter(onePage).filter(r => !r.withLine.shortened && !r.withLine.cutOnA5 && !r.without.cutOnA5).filter(r => !(r.withLine.canvases <= 3 && r.without.canvases === 1)),
        ...real.filter(fullBeside).filter(r => r.withLine.cutOnA5 && !r.withLine.shortened).filter(r => r.withLine.canvases > 3),
        ...out.filter(r => !(r.withLine.canvases <= 12 && r.withLine.released && r.without.released)),
      ].map(r => [at(r), r.withLine.canvases, r.without.canvases])));
  }

  // ---- W4-B16-PRICE-REASON (the Owner, 18 Oct 2026) --------------------------
  // A hand-changed price's reason is internal, as an FOC reason is (Q7): every
  // customer copy says 'Manual price override' only; staff see the reason on
  // screen. Added after the pages above, so none of their invoices change.
  const PRICE_REASON = 'Fixture reason: matched the old shelf tag';
  tables.invoices.push(inv('priced', 'ben', { subtotal: 80, total_amount: 80, paid_amount: 80 }));
  tables.invoice_items.push({ ...line('priced'), unit_price: 80, line_total: 80, price_overridden: true, override_reason: PRICE_REASON });
  tables.invoice_payments.push(pay('priced', 'cash', 80));
  {
    const pp = await openPage(owner);
    await view(pp, 'priced');
    const onScreen = await pp.locator('[data-testid="invoice-line-price-override"]').innerText();
    ok('staff see a hand-changed price and its internal reason on screen',
      onScreen.includes('Manual price override') && onScreen.includes(`internal reason: ${PRICE_REASON}`), onScreen);
    const printed = await print(pp);
    ok('the printed copy says "Manual price override" on both halves, never its reason',
      count(printed, 'Manual price override') === 2 && !printed.includes(PRICE_REASON) && !printed.includes('shelf tag'));
    const pdfCopy = await downloadText(pp, 'PDF');
    ok('nor does the PDF', pdfCopy.includes('Manual price override') && !pdfCopy.includes(PRICE_REASON) && !pdfCopy.includes('shelf tag'));
    await pp.evaluate(() => { window.__imageCanvas = null; });
    await downloadText(pp, 'Image');
    const drawn = await imageTexts(pp);
    ok('nor does the image', drawn.some(t => t.includes('Manual price override')) && !drawn.some(t => t.includes('shelf tag')), JSON.stringify(drawn));
    await pp.evaluate(() => { window.__uploaded = null; window.__opened = []; });
    await pp.getByRole('button', { name: 'WhatsApp', exact: true }).click();
    await pp.waitForFunction(() => window.__uploaded && window.__opened.some(u => u.startsWith('https://wa.me/')));
    const sentWa = pdfText(await pp.evaluate(() => Array.from(window.__uploaded)));
    ok('nor the PDF sent by WhatsApp', sentWa.includes('Manual price override') && !sentWa.includes('shelf tag'));
    await pp.evaluate(() => {
      window.__shared = null;
      Object.defineProperty(navigator, 'canShare', { configurable: true, value: () => true });
      Object.defineProperty(navigator, 'share', { configurable: true, value: async data => { window.__shared = data; } });
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async () => {} } });
    });
    await pp.getByRole('button', { name: 'Email (from this device)', exact: true }).click();
    await pp.waitForFunction(() => !!window.__shared);
    const sentEmail = pdfText(await pp.evaluate(async () => Array.from(new Uint8Array(await window.__shared.files[0].arrayBuffer()))));
    ok('nor the PDF sent by email', sentEmail.includes('Manual price override') && !sentEmail.includes('shelf tag'));
    ok('no browser errors (hand-changed price)', pp.errors.length === 0, pp.errors.join(' | '));
    await pp.context().close();
  }

  // ---- W4-B04-IM-ADD-CUSTOMER (the Owner, 18 Oct 2026) ------------------------
  // New Invoice's own Add customer button: Owners, Managers and Staff see it;
  // Inventory Managers do not, and still search and pick a customer on file.
  const inventoryManager = { id: 'im', full_name: 'Test Inventory Manager', role: 'inventory_manager', ...common };
  const manager = { id: 'mgr', full_name: 'Test Manager', role: 'manager', ...common };
  tables.profiles.push(inventoryManager, manager);
  for (const [who, profile, shown] of [['an Owner', owner, true], ['a Manager', manager, true], ['Staff', staff, true], ['an Inventory Manager', inventoryManager, false]]) {
    const np = await openPage(profile);
    await np.getByRole('button', { name: 'New Invoice', exact: true }).click();
    const field = np.locator('.customer-with-add');
    await field.waitFor();
    const buttons = await field.getByRole('button', { name: 'Add customer', exact: true }).count();
    const search = await field.getByRole('button', { name: 'Search name, ID, phone or email…' }).count();
    ok(`${who} ${shown ? 'sees' : 'does not see'} New Invoice's Add customer button, and can still search for a customer`,
      buttons === (shown ? 1 : 0) && search === 1, `buttons ${buttons}, search ${search}`);
    ok(`no browser errors (${who}, New Invoice)`, np.errors.length === 0, np.errors.join(' | '));
    await np.context().close();
  }

  // The same rule in the split panels (a Credit Package or a Premium Bundle
  // divided across customers): each row's + opens the same Add a customer
  // window, so an Inventory Manager is not shown it either, and still picks
  // each row's customer from those on file. The button that only adds a row
  // says 'Add another person', not 'Add Customer'.
  for (const [who, profile, shown] of [['an Owner', owner, true], ['a Manager', manager, true], ['Staff', staff, true], ['an Inventory Manager', inventoryManager, false]]) {
    const np = await openPage(profile);
    await np.evaluate(() => { window.__splitOffers = {
      packages: [{ id: 'pkg', name: 'Fixture Credit Package', code: 'FCP', customer_price: 500 }],
      bundles: [{ id: 'bundle', name: 'Fixture Premium Bundle', code: 'FPB', customer_payment_amount: 600, grants_reward: false, free_voucher_qty: 0 }],
    }; });
    await np.getByRole('button', { name: 'New Invoice', exact: true }).click();
    // Staff with one store have it fixed; everyone else chooses it.
    if (profile.role !== 'staff') await np.locator('select', { has: np.locator('option', { hasText: '— Select store —' }) }).selectOption('store');
    for (const [kind, placeholder, name] of [['credit_package', 'Search Credit Package…', 'Fixture Credit Package'],
                                             ['premium_bundle', 'Search Premium Bundle…', 'Fixture Premium Bundle']]) {
      await np.locator('.invoice-editor-line select').first().selectOption(kind);
      await np.getByRole('button', { name: placeholder }).click();
      await np.getByText(`💳 ${name} — `).click();
      await np.getByRole('button', { name: 'Split Across Customers', exact: true }).click();
      await np.getByText(`Customer Allocation — ${name}`).waitFor();
      const panel = np.locator('table', { has: np.locator('th', { hasText: 'Paid Credit' }) });
      await np.getByRole('button', { name: '+ Add another person', exact: true }).click();
      const rows = await panel.locator('tbody tr').count();
      const pluses = await panel.locator('button[title="Add a customer for this row"]').count();
      const searches = await panel.getByRole('button', { name: 'Search name, ID, phone or email…' }).count();
      const oldLabel = await np.getByRole('button', { name: '+ Add Customer', exact: true }).count();
      ok(`${who} ${shown ? 'sees' : 'does not see'} each row's + in the ${name.replace('Fixture ', '')} split, and can still search for each row's customer`,
        rows === 3 && pluses === (shown ? 3 : 0) && searches === 3 && oldLabel === 0,
        `rows ${rows}, pluses ${pluses}, searches ${searches}, '+ Add Customer' ${oldLabel}`);
      if (shown) {
        await panel.locator('button[title="Add a customer for this row"]').first().click();
        const dialog = np.locator('.quick-customer[role="dialog"]');
        await dialog.waitFor();
        ok(`${who}: a row's + opens the Add a customer window (${name.replace('Fixture ', '')})`,
          (await dialog.locator('#qc-title').innerText()).includes('Add a customer'));
        await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
        await dialog.waitFor({ state: 'detached' });
      }
      ok(`${who} is never shown the Add a customer window from the ${name.replace('Fixture ', '')} split unasked`,
        (await np.locator('.quick-customer[role="dialog"]').count()) === 0);
      await np.getByRole('button', { name: 'Single Customer', exact: true }).click();
    }
    ok(`no browser errors (${who}, split panels)`, np.errors.length === 0, np.errors.join(' | '));
    await np.context().close();
  }

  // ---- 443: Credit Package and Premium Bundle credit kept apart -----------------
  // (the Owner, 21 Oct 2026, CREDIT-SPLIT-1..14). Eve's balance has sources, as
  // a server with 443 answers; Ann's keeps the categories alone (before 443).
  // Eve's paid invoice was paid partly through 'Wallet — Paid Credit' from
  // Premium Bundle credit (before 443; invoice_payment_credit_sources says so)
  // and partly through 'Wallet — Credit Package Paid'.
  const wm = (id, name, cat, source) => ({ id, name, is_wallet_credit: true, wallet_category: cat, wallet_source: source, is_system: true, ...common });
  tables.payment_methods.push(wm('wallet-pk-paid', 'Wallet — Credit Package Paid', 'paid', 'credit_package'),
    wm('wallet-pk-bonus', 'Wallet — Credit Package Bonus', 'bonus', 'credit_package'),
    wm('wallet-pb-paid', 'Wallet — Premium Bundle Paid', 'paid', 'premium_bundle'),
    wm('wallet-pb-bonus', 'Wallet — Premium Bundle Bonus', 'bonus', 'premium_bundle'));
  tables.customers.push({ id: 'eve', full_name: 'Eve Sources', phone: '+61491570811', email: 'eve@example.com', ...common },
    { id: 'fay', full_name: 'Fay Nothing', phone: '+61491570812', ...common });
  for (const i of [inv('eve-paid', 'eve'), inv('eve-part', 'eve', { status: 'partially_paid', paid_amount: 60 }),
    inv('eve-owed', 'eve', { status: 'unpaid', paid_amount: 0, paid_at: null }),
    inv('eve-moves', 'eve', { status: 'unpaid', paid_amount: 0, paid_at: null })]) { tables.invoices.push(i); tables.invoice_items.push(line(i.id)); }
  tables.invoice_payments.push({ ...pay('eve-paid', 'wallet-paid', 40), id: 'pay-eve-1' }, { ...pay('eve-paid', 'wallet-pk-paid', 60), id: 'pay-eve-2' },
    { ...pay('eve-part', 'wallet-pk-paid', 60), id: 'pay-eve-3' });
  const src = (paid, bonus, legacy = 0) => ({ paid, bonus, legacy, promotional: 0, exchange: 0, total: paid + bonus + legacy });
  balances.eve = { categories: cats({ paid: 570, bonus: 80, legacy: 15 }), available_total: 665,
    sources: { credit_package: src(300, 30), premium_bundle: src(200, 50, 15), other: src(70, 0) } };
  balances.fay = { categories: cats({}), available_total: 0, sources: { credit_package: src(0, 0), premium_bundle: src(0, 0), other: src(0, 0) } };
  // invoice_wallet_availability for an invoice of 100: what each method can pay of it / holds, in the server's order.
  const availOf = (figures, def) => ({ default_method_id: def, methods: figures.map(([id, available, held], n) => {
    const m = tables.payment_methods.find(x => x.id === id);
    return { payment_method_id: id, name: m.name, wallet_category: m.wallet_category, wallet_source: m.wallet_source ?? null,
      pays_from: m.wallet_source ?? 'other', available, held, rank: n + 1 };
  }) });
  const AVAIL = {
    eve: availOf([['wallet-pk-paid', 100, 300], ['wallet-pk-bonus', 0, 30], ['wallet-pb-paid', 100, 200], ['wallet-pb-bonus', 50, 50],
      ['wallet-paid', 70, 70], ['wallet-bonus', 0, 0]], 'wallet-pk-paid'),
    fay: availOf([['wallet-pk-paid', 0, 0], ['wallet-pk-bonus', 0, 0], ['wallet-pb-paid', 0, 0], ['wallet-pb-bonus', 0, 0],
      ['wallet-paid', 0, 0], ['wallet-bonus', 0, 0]], null),
  };
  const SOURCES = { 'eve-paid': { 'pay-eve-1': ['premium_bundle'], 'pay-eve-2': ['credit_package'] }, 'eve-part': { 'pay-eve-3': ['credit_package'] } };
  // The guided Refund / Cancel of Eve's paid invoice gives each wallet payment's credit back.
  const PLAN = { invoice_no: 'INV-T-eve-paid', action: 'refund_full', refund_amount: 100, refund_due: 0,
    window: { created_on: '2026-09-30', deadline: '2026-10-05', within: true, days_remaining: 3, override_required: false, creation_reliable: true },
    lines: [{ invoice_item_id: 'line-eve-paid', name: 'Long Energia Socks', line_kind: 'product', quantity: 1, selected_quantity: 1, amount: 100 }],
    stock: [], sources: [{ payment_id: 'pay-eve-1', method: 'Wallet — Paid Credit', wallet: true, amount: 40 },
      { payment_id: 'pay-eve-2', method: 'Wallet — Credit Package Paid', wallet: true, amount: 60 }],
    overrides_required: [], blockers: [], summary: ['Test plan'], requires_override: false, blocked: false, plan_hash: 'h443', status: 'paid',
    effects: { money_returned: { total: 100, destinations: [{ payment_id: 'pay-eve-1', method: 'Wallet — Paid Credit', wallet: true, amount: 40 },
      { payment_id: 'pay-eve-2', method: 'Wallet — Credit Package Paid', wallet: true, amount: 60 }] },
      benefits: [], stock_returned: [], overrides: [], rewards: { withdrawn: [], kept: [] } } };
  const set443 = (p, extra = {}) => p.evaluate(([a, s, plan, x]) => {
    window.__availFor = a; window.__paySources = s; window.__plans = { 'eve-paid': { refund_full: plan } }; Object.assign(window, x);
  }, [AVAIL, SOURCES, PLAN, extra]);
  /** The wallet methods Record Payment's row `n` offers: [label, switched off]. */
  const walletOptions = async (p, n = 0) => {
    await p.getByRole('button', { name: 'Payment method', exact: true }).nth(n).click();
    const list = await p.locator('[role="listbox"][aria-label="Payment method"] [role="option"]')
      .evaluateAll(bs => bs.map(b => [b.textContent, b.disabled]).filter(([t]) => t.startsWith('Wallet')));
    await p.getByRole('combobox', { name: 'Search payment method' }).press('Escape');
    return list;
  };
  const chooseMethod = async (p, n, name) => {
    await p.getByRole('button', { name: 'Payment method', exact: true }).nth(n).click();
    await p.getByRole('combobox', { name: 'Search payment method' }).fill(name);
    await p.getByRole('combobox', { name: 'Search payment method' }).press('Enter');
  };
  const notes = p => p.locator('.modal p[role="note"]').allInnerTexts();
  const flat = h => h.replace(/&nbsp;/g, ' ');
  const BREAKDOWN = 'Credit Package S$330.00 · Premium Bundle S$265.00 · Other S$70.00';
  const BRACKETED = 'Wallet — Paid Credit (Premium Bundle)';

  {
    const p = await openPage(owner);
    await set443(p);
    await view(p, 'eve-paid');
    let text = await p.locator('.modal').innerText();
    ok('443: a past Paid Credit payment of Premium Bundle credit shows its source on screen; a Credit Package payment needs none',
      text.includes(`${BRACKETED} · `) && text.includes('Wallet — Credit Package Paid · ') && !text.includes('Wallet — Credit Package Paid ('), text);
    html = await print(p);
    ok('443: both printed halves carry the bracket', count(html, `${BRACKETED} · `) === 2 && count(html, 'Wallet — Credit Package Paid · ') === 2);
    ok('443: the printed credit line reads Credit Package · Premium Bundle · Other',
      count(flat(html), BREAKDOWN) === 2 && count(html, '<strong>S$665.00</strong>') === 2 && !flat(html).includes('Paid S$570.00'),
      (flat(html).match(/Credit Package S\$[^<]*/) || [''])[0]);
    pdf = await downloadText(p, 'PDF');
    ok('443: the PDF carries the bracket and the line by source (it may wrap after a dot)',
      pdf.includes('Paid Credit (Premium Bundle)') && ['Credit Package S$330.00', 'Premium Bundle S$265.00', 'Other S$70.00'].every(x => pdf.includes(x))
        && !pdf.includes('Paid S$570.00'));
    const img = p.waitForEvent('download');
    await p.getByRole('button', { name: 'Image', exact: true }).click();
    await img;
    const drawn = (await imageTexts(p)).join(' | ');
    ok('443: so does the image', drawn.includes(BRACKETED) && ['Credit Package S$330.00', 'Premium Bundle S$265.00', 'Other S$70.00'].every(x => drawn.includes(x)), drawn);
    // Correct amount / date opens the correction with the payment named as the invoice names it.
    await p.locator('.invoice-payment-record').filter({ hasText: BRACKETED }).getByRole('button', { name: 'Correct amount / date' }).click();
    await p.getByRole('button', { name: 'Recorded payment', exact: true }).waitFor();
    const chosen = await p.getByRole('button', { name: 'Recorded payment', exact: true }).innerText();
    ok('443: the payment correction names it with its source', chosen.startsWith(`${BRACKETED} · S$40.00`), chosen);
    // The guided Refund / Cancel says where each payment's credit goes back.
    await view(p, 'eve-paid');
    await p.getByRole('button', { name: 'Refund / Cancel', exact: true }).click();
    const dlg = p.getByRole('dialog', { name: /Refund or cancel/ });
    await dlg.getByRole('button', { name: /Full refund/ }).click();
    await dlg.getByPlaceholder('What happened, in a sentence').fill('Returned in the box');
    await dlg.getByRole('button', { name: 'Continue', exact: true }).click();
    await dlg.getByText('What this will do').waitFor();
    const review = await dlg.locator('.invoice-guided-review').innerText();
    ok('443: the guided refund names the credit it gives back as the invoice does',
      review.includes(`S$40.00 to ${BRACKETED} — restores the original credit`)
        && review.includes('S$60.00 to Wallet — Credit Package Paid — restores the original credit'), review);
    // Leave it without recording anything: Escape, and yes to discarding the reason typed.
    p.once('dialog', d => d.accept());
    await p.keyboard.press('Escape');
    await dlg.waitFor({ state: 'detached' });

    // ---- Record Payment: each wallet method with what it can pay of this invoice
    await view(p, 'eve-owed');
    await p.locator('[data-testid="wallet-summary"]').waitFor();
    const opts = await walletOptions(p);
    ok('443: Record Payment lists the wallet methods Credit Package first, each with what it can pay of this invoice, off at nothing',
      JSON.stringify(opts) === JSON.stringify([
        ['Wallet — Credit Package Paid — S$100.00 available (S$300.00 held)', false],
        ['Wallet — Credit Package Bonus — S$0.00 available (S$30.00 held)', true],
        ['Wallet — Premium Bundle Paid — S$100.00 available (S$200.00 held)', false],
        ['Wallet — Premium Bundle Bonus — S$50.00 available', false],
        ['Wallet — Paid Credit — S$70.00 available', false],
        ['Wallet — Bonus Credit — S$0.00 available', true]]), JSON.stringify(opts));
    const summary = await p.locator('[data-testid="wallet-summary"]').innerText();
    ok('443: the wallet under the form is by source, and the wrong Bonus-first note is gone',
      summary.includes('Wallet: S$665.00 held — Credit Package S$330.00 (Paid S$300.00, Bonus S$30.00) · Premium Bundle S$265.00 (Paid S$200.00, Bonus S$50.00, Legacy S$15.00) · Other S$70.00 (Paid S$70.00)')
        && !summary.includes('Bonus Credit is always spent first') && summary.includes('Credit Package credit is listed first'), summary);
    ok('443: no reminder before a method is chosen', (await notes(p)).length === 0);
    await chooseMethod(p, 0, 'Premium Bundle Paid');
    ok('443: a Premium Bundle row is told Credit Package credit is used first by default',
      JSON.stringify(await notes(p)) === JSON.stringify(['Credit Package credit can pay S$100.00 of this invoice (Wallet — Credit Package Paid) and is used first by default. Keep Premium Bundle credit only if the customer asks for it.']),
      JSON.stringify(await notes(p)));
    // One row per source (CREDIT-SPLIT-7): Credit Package credit on the first row for all it can pay, Premium Bundle on the second.
    await chooseMethod(p, 0, 'Credit Package Paid');
    await p.locator('.modal input[placeholder="Amount"]').first().fill('100');
    await p.getByRole('button', { name: 'Split Payment', exact: true }).click();
    await chooseMethod(p, 1, 'Premium Bundle Paid');
    ok('443: with the Credit Package credit already on another row, the Premium Bundle row is not told to drop', (await notes(p)).length === 0,
      JSON.stringify(await notes(p)));
    await p.locator('.modal input[placeholder="Amount"]').first().fill('40');
    ok('443: with part of it on another row, the reminder quotes what is left',
      JSON.stringify(await notes(p)) === JSON.stringify(['Credit Package credit can pay S$60.00 more of this invoice (Wallet — Credit Package Paid) and is used first by default. Keep Premium Bundle credit only if the customer asks for it.']),
      JSON.stringify(await notes(p)));

    // ---- Never another customer's figures once the invoice's customer changes
    const setCustomer = (id, cust) => p.evaluate(([i, c]) => {
      const ix = window.__tables.invoices.findIndex(x => x.id === i); window.__tables.invoices[ix] = { ...window.__tables.invoices[ix], customer_id: c };
    }, [id, cust]);
    const EVE_OFFER = 'Wallet — Credit Package Paid — S$100.00 available (S$300.00 held)';
    await view(p, 'eve-moves');
    ok('443: Eve\'s invoice offers Eve\'s figures', (await walletOptions(p)).some(([t]) => t === EVE_OFFER));
    // Another tab moves the open invoice to Fay (Edit Invoice); Fay's figures are slow.
    await setCustomer('eve-moves', 'fay');
    await p.evaluate(() => { window.__availDelayFor = { fay: 3000 };
      new BroadcastChannel('energia:invoices').postMessage({ type: 'invoices-changed', ids: ['eve-moves'], from: 'another-tab' }); });
    await p.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('Fay Nothing') && !!modalButton('Print') && !modalButton('Print').disabled);
    let offered = await walletOptions(p);
    ok('443: moved to another customer from another tab, it never offers the first customer\'s figures while the new ones load',
      offered.length === 6 && offered.every(([t, off]) => t.includes('S$0.00 available') && off), JSON.stringify(offered));
    await p.waitForTimeout(3200);
    offered = await walletOptions(p);
    ok('443: and then offers the new customer\'s own (nothing)', offered.every(([t, off]) => t.includes('S$0.00 available') && off), JSON.stringify(offered));
    // The same invoice closed, moved back to Eve and opened again, then closed and moved to Fay again.
    await setCustomer('eve-moves', 'eve');
    await p.evaluate(() => { window.__availDelayFor = {}; });
    await view(p, 'eve-moves');
    await p.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('Eve Sources'));
    await p.waitForTimeout(200);
    ok('443: back with Eve, Eve\'s figures', (await walletOptions(p)).some(([t]) => t === EVE_OFFER));
    await p.getByRole('button', { name: 'Close', exact: true }).first().click();
    await setCustomer('eve-moves', 'fay');
    await p.evaluate(() => { window.__availDelayFor = { fay: 3000 }; });
    await view(p, 'eve-moves');
    await p.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('Fay Nothing'));
    offered = await walletOptions(p);
    ok('443: closed and opened again with another customer, the first customer\'s figures are not offered either',
      offered.length === 6 && offered.every(([t, off]) => t.includes('S$0.00 available') && off), JSON.stringify(offered));
    await p.evaluate(() => { window.__availDelayFor = {}; });
    ok('no browser errors (443)', p.errors.length === 0, p.errors.join(' | '));
    await p.context().close();
  }

  // ---- 443: no copy goes out before the payments' sources are in ----------------
  {
    const p = await openPage(owner);
    await set443(p, { __sourcesDelay: 2500 });
    const openedAt443 = Date.now();
    await row(p, 'INV-T-eve-paid').getByRole('button', { name: 'View', exact: true }).click();
    await p.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('INV-T-eve-paid')
      && document.querySelector('.modal')?.innerText.includes('Long Energia Socks'));
    await p.waitForTimeout(500);
    ok('443: while the payments\' sources are on their way, Print, PDF, Image, WhatsApp and Email are off',
      (await copyButtonsOff(p)).every(off => off === true), JSON.stringify(await copyButtonsOff(p)));
    await p.waitForFunction(() => !!modalButton('Print') && !modalButton('Print').disabled);
    ok('443: they come on once the sources answer', Date.now() - openedAt443 >= 2400);
    html = await print(p);
    ok('443: the copy made the moment they come on carries the bracket on both halves', count(html, `${BRACKETED} · `) === 2,
      (html.match(/Wallet — Paid Credit[^·]*·/) || [''])[0]);
    pdf = await downloadText(p, 'PDF');
    ok('443: and so does the PDF', pdf.includes('Paid Credit (Premium Bundle)'));
    // A reload of the open invoice (another tab records the rest through
    // 'Wallet — Paid Credit' from Premium Bundle credit): the new payment's
    // source is read again, slowly; the copies wait for it.
    await view(p, 'eve-part');
    await p.evaluate(t0 => {
      const ix = window.__tables.invoices.findIndex(i => i.id === 'eve-part');
      window.__tables.invoices[ix] = { ...window.__tables.invoices[ix], status: 'paid', paid_amount: 100, paid_at: t0 };
      window.__tables.invoice_payments.push({ id: 'pay-eve-4', invoice_id: 'eve-part', payment_method_id: 'wallet-paid', amount: 40, entry_kind: 'receipt', created_at: t0, effective_at: t0 });
      window.__paySources['eve-part']['pay-eve-4'] = ['premium_bundle'];
      new BroadcastChannel('energia:invoices').postMessage({ type: 'invoices-changed', ids: ['eve-part'], from: 'another-tab' });
    }, T0);
    const reloadAt443 = Date.now();
    await p.waitForFunction(() => !!modalButton('Print') && modalButton('Print').disabled);
    await p.waitForFunction(() => document.querySelector('.modal')?.innerText.includes('Wallet — Paid Credit'));
    ok('443: while the reload\'s sources are on their way, the copies are off', (await copyButtonsOff(p)).every(off => off === true));
    await p.waitForFunction(() => !!modalButton('Print') && !modalButton('Print').disabled);
    html = await print(p);
    ok('443: after the reload, the payment just recorded prints with its source',
      Date.now() - reloadAt443 >= 2400 && count(html, `${BRACKETED} · `) === 2 && count(html, 'Wallet — Credit Package Paid · ') === 2,
      (html.match(/Wallet — Paid Credit[^·]*·/) || [''])[0]);
    ok('no browser errors (443, slow sources)', p.errors.length === 0, p.errors.join(' | '));
    await p.context().close();
  }

  console.log(`\nPASS credit-balance-print-browser: ${checks} checks`);
} finally {
  await browser.close();
}
