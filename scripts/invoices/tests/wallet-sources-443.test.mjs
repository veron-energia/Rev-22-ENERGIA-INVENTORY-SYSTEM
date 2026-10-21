// Credit Package credit and Premium Bundle credit kept apart, on the pages
// (443; the Owner's answers of 21 Oct 2026, CREDIT-SPLIT-1..14).
//
//   * Record Payment lists each wallet method with what it can pay of THIS
//     invoice (invoice_wallet_availability), Credit Package first, switched
//     off at nothing; "held" shows when the customer holds more than that.
//     Without the server's figures (before 443) it falls back to the balance,
//     by source when there are sources. A Premium Bundle row while Credit
//     Package credit could still pay says Credit Package is used first by
//     default; what the payment's other rows put on Credit Package credit is
//     taken off. Figures read for another customer of the invoice are never
//     offered. The wrong "Bonus Credit is always spent first" note is gone,
//     here and in the Credit Package editor.
//   * A past wallet payment shows where its credit came from in brackets,
//     e.g. 'Wallet — Paid Credit (Premium Bundle)', only when its method does
//     not say and some of it was Credit Package or Premium Bundle credit: on
//     screen, in the print, the PDF and image, the correction form, the
//     refund and correction panel and the guided Cancel/Refund; the copies
//     wait for the sources.
//   * The customer page shows Credit Package, Premium Bundle and Other, each
//     with its Paid and Bonus, and each package or bundle bought with what is
//     left (used up too; credit moved in marked received); the categories as
//     before from a server before 443.
//   * The printed / PDF / image line reads 'Credit Package S$… · Premium
//     Bundle S$… · Other S$…' (non-zero only); the kinds from a server before
//     443.
//   * The Payment Summary export gives each new method its own wallet column.
//
// Every name, id and amount is invented.
// Run: node --test scripts/invoices/tests/wallet-sources-443.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  WALLET_SOURCES, sourceName, methodPaysFrom, paymentSourceSuffix, paymentMethodLabel, heldForMethod,
  walletMethodOptions, creditPackageFirstNote, walletBySource, walletSourceTiles, purchasesBySource,
} from '../../../src/lib/invoices/walletSources.mjs';
import { creditBalanceLine, CREDIT_SOURCES } from '../../../src/lib/invoices/creditBalanceLine.mjs';
import { buildPaymentSummary } from '../../../src/lib/paymentSummary.mjs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const money = n => `S$${Number(n).toFixed(2)}`;

// The nine system wallet methods after 443, and one of a store's own.
const M = {
  pkPaid: { id: 'm-pk-paid', name: 'Wallet — Credit Package Paid', is_wallet_credit: true, wallet_category: 'paid', wallet_source: 'credit_package' },
  pkBonus: { id: 'm-pk-bonus', name: 'Wallet — Credit Package Bonus', is_wallet_credit: true, wallet_category: 'bonus', wallet_source: 'credit_package' },
  pbPaid: { id: 'm-pb-paid', name: 'Wallet — Premium Bundle Paid', is_wallet_credit: true, wallet_category: 'paid', wallet_source: 'premium_bundle' },
  pbBonus: { id: 'm-pb-bonus', name: 'Wallet — Premium Bundle Bonus', is_wallet_credit: true, wallet_category: 'bonus', wallet_source: 'premium_bundle' },
  paid: { id: 'm-paid', name: 'Wallet — Paid Credit', is_wallet_credit: true, wallet_category: 'paid', wallet_source: null },
  bonus: { id: 'm-bonus', name: 'Wallet — Bonus Credit', is_wallet_credit: true, wallet_category: 'bonus', wallet_source: null },
  legacy: { id: 'm-legacy', name: 'Wallet — Legacy Credit', is_wallet_credit: true, wallet_category: 'legacy', wallet_source: null },
  promo: { id: 'm-promo', name: 'Wallet — Promotional/FOC Credit', is_wallet_credit: true, wallet_category: 'promotional', wallet_source: null },
  exch: { id: 'm-exch', name: 'Wallet — Exchange Credit', is_wallet_credit: true, wallet_category: 'exchange', wallet_source: null },
  cash: { id: 'm-cash', name: 'Cash', is_wallet_credit: false },
};
// The methods as the page loads them: by name.
const methods = Object.values(M).sort((a, b) => a.name.localeCompare(b.name));
// invoice_wallet_availability() for a therapy session of 100 (as 443's suite has it).
const rank = ['pkPaid', 'pkBonus', 'pbPaid', 'pbBonus', 'paid', 'bonus', 'legacy', 'promo', 'exch'];
const figures = { pkPaid: [100, 1000], pkBonus: [0, 100], pbPaid: [100, 500], pbBonus: [50, 50], paid: [70, 70],
  bonus: [20, 20], legacy: [100, 105], promo: [15, 15], exch: [12, 12] };
const availability = {
  invoice_id: 'inv-1', customer_id: 'c-1', payable: true, credit_line: false, default_method_id: M.pkPaid.id,
  methods: rank.map((k, i) => ({ payment_method_id: M[k].id, name: M[k].name, wallet_category: M[k].wallet_category,
    wallet_source: M[k].wallet_source, pays_from: methodPaysFrom(M[k]) ?? 'any',
    available: figures[k][0], held: figures[k][1], rank: i + 1 })),
};
// customer_credit_balances() after 443.
const balances = {
  customer_id: 'c-1',
  categories: { paid: 1570, bonus: 170, legacy: 105, promotional: 15, exchange: 12 },
  available_total: 1872,
  sources: {
    credit_package: { paid: 1000, bonus: 100, legacy: 0, promotional: 0, exchange: 0, total: 1100 },
    premium_bundle: { paid: 500, bonus: 50, legacy: 45, promotional: 0, exchange: 0, total: 595 },
    other: { paid: 70, bonus: 20, legacy: 60, promotional: 15, exchange: 12, total: 177 },
  },
  purchases: [
    { source: 'credit_package', name: 'Fixture Package', invoice_no: 'INV-2026-0901', bought_on: '2026-10-21', paid: 1000, bonus: 100, legacy: 0, total: 1100 },
    { source: 'premium_bundle', name: 'Fixture Bundle', invoice_no: 'INV-2026-0902', bought_on: '2026-10-21', paid: 500, bonus: 50, legacy: 45, total: 595 },
  ],
};

test('sources are named and listed Credit Package, Premium Bundle, Other', () => {
  assert.deepEqual(WALLET_SOURCES.map(([k]) => k), ['credit_package', 'premium_bundle', 'other']);
  assert.equal(sourceName('premium_bundle'), 'Premium Bundle');
  assert.equal(sourceName('nothing'), '');
  assert.deepEqual(CREDIT_SOURCES.map(([, n]) => n), ['Credit Package', 'Premium Bundle', 'Other']);
});

test('what each method pays from, as the server reads it', () => {
  assert.equal(methodPaysFrom(M.pkPaid), 'credit_package');
  assert.equal(methodPaysFrom(M.pbBonus), 'premium_bundle');
  assert.equal(methodPaysFrom(M.paid), 'other', 'Wallet — Paid Credit pays Other credit only');
  assert.equal(methodPaysFrom(M.bonus), 'other');
  assert.equal(methodPaysFrom(M.legacy), null, 'Legacy pays any source');
  assert.equal(methodPaysFrom(M.cash), null);
});

test('Record Payment: each wallet method with what it can pay of THIS invoice, Credit Package first', () => {
  const opts = walletMethodOptions({ methods, availability, balances, money });
  assert.deepEqual(opts.map(o => o.value), rank.map(k => M[k].id), 'the server\'s order: Credit Package first, then Premium Bundle, then the rest');
  assert.equal(opts[0].label, 'Wallet — Credit Package Paid — S$100.00 available (S$1000.00 held)');
  assert.equal(opts[1].label, 'Wallet — Credit Package Bonus — S$0.00 available (S$100.00 held)');
  assert.equal(opts[1].disabled, true, 'nothing it can pay here: switched off');
  assert.equal(opts[3].label, 'Wallet — Premium Bundle Bonus — S$50.00 available', 'no "held" when it is all usable');
  assert.equal(opts[0].disabled, false);
  assert.ok(!opts.some(o => o.value === M.cash.id), 'only wallet methods');
});

test('Record Payment without the server\'s figures: the balance stands in, by source when there are sources', () => {
  const opts = walletMethodOptions({ methods, availability: null, balances, money });
  const label = id => opts.find(o => o.value === id).label;
  assert.deepEqual(opts.slice(0, 4).map(o => o.value), [M.pkPaid.id, M.pkBonus.id, M.pbPaid.id, M.pbBonus.id]);
  assert.equal(label(M.pkPaid.id), 'Wallet — Credit Package Paid — S$1000.00 available');
  assert.equal(label(M.paid.id), 'Wallet — Paid Credit — S$70.00 available', 'Other Paid only');
  assert.equal(label(M.legacy.id), 'Wallet — Legacy Credit — S$105.00 available', 'Legacy of any source');
  // A server before 443: no sources, the categories as before.
  const old = walletMethodOptions({ methods: [M.paid, M.bonus], availability: null,
    balances: { categories: { paid: 300, bonus: 0 }, available_total: 300 }, money });
  assert.deepEqual(old.map(o => [o.label, o.disabled]), [['Wallet — Paid Credit — S$300.00 available', false],
    ['Wallet — Bonus Credit — S$0.00 available', true]]);
  assert.equal(heldForMethod(M.pbPaid, balances), 500);
  assert.equal(heldForMethod(M.cash, balances), 0);
});

test('Credit Package first by default: a Premium Bundle row is reminded when Credit Package credit could pay', () => {
  const note = creditPackageFirstNote({ methodId: M.pbPaid.id, methods, availability, money });
  assert.match(note, /^Credit Package credit can pay S\$100\.00 of this invoice \(Wallet — Credit Package Paid\) and is used first by default\./);
  assert.equal(creditPackageFirstNote({ methodId: M.pkPaid.id, methods, availability, money }), null, 'not on a Credit Package row');
  assert.equal(creditPackageFirstNote({ methodId: M.paid.id, methods, availability, money }), null, 'not on an Other row');
  const noPackage = { ...availability, methods: availability.methods.map(a => a.wallet_source === 'credit_package' ? { ...a, available: 0 } : a) };
  assert.equal(creditPackageFirstNote({ methodId: M.pbPaid.id, methods, availability: noPackage, money }), null,
    'none when Credit Package credit cannot pay this invoice');
  assert.equal(creditPackageFirstNote({ methodId: M.pbPaid.id, methods, availability: null, money }), null);
});

test('Credit Package first: the payment\'s other rows count (one row per source, CREDIT-SPLIT-7)', () => {
  const note = otherLines => creditPackageFirstNote({ methodId: M.pbPaid.id, methods, availability, money, otherLines });
  // Row 1 puts all the Credit Package credit can pay on it: the Premium Bundle row is not told to drop.
  assert.equal(note([{ payment_method_id: M.pkPaid.id, amount: 100 }]), null, 'Credit Package credit already in use: no note');
  assert.equal(note([{ payment_method_id: M.pkPaid.id, amount: 60 }, { payment_method_id: M.pkBonus.id, amount: 40 }]), null,
    'across both Credit Package methods');
  // Part of it: the note quotes what is left.
  assert.match(note([{ payment_method_id: M.pkPaid.id, amount: 40 }]),
    /^Credit Package credit can pay S\$60\.00 more of this invoice \(Wallet — Credit Package Paid\) and is used first by default\./);
  // Rows on other methods, or not chosen yet, take nothing off.
  assert.match(note([{ payment_method_id: M.cash.id, amount: 50 }, { payment_method_id: '', amount: 30 },
    { payment_method_id: M.pbBonus.id, amount: 20 }]), /^Credit Package credit can pay S\$100\.00 of this invoice/);
  assert.match(note([]), /^Credit Package credit can pay S\$100\.00 of this invoice/);
});

test('a past wallet payment shows its source in brackets only when its method does not say', () => {
  assert.equal(paymentMethodLabel('Wallet — Paid Credit', ['premium_bundle'], M.paid), 'Wallet — Paid Credit (Premium Bundle)');
  assert.equal(paymentMethodLabel('Wallet — Paid Credit', ['credit_package', 'premium_bundle'], M.paid),
    'Wallet — Paid Credit (Credit Package + Premium Bundle)');
  assert.equal(paymentMethodLabel('Wallet — Legacy Credit', ['premium_bundle', 'other'], M.legacy),
    'Wallet — Legacy Credit (Premium Bundle + Other)', 'the 3 Legacy lots linked to bundles read as Premium Bundle');
  assert.equal(paymentMethodLabel('Wallet — Paid Credit', ['other'], M.paid), 'Wallet — Paid Credit', 'all Other: the name says so');
  assert.equal(paymentMethodLabel('Wallet — Premium Bundle Paid', ['premium_bundle'], M.pbPaid), 'Wallet — Premium Bundle Paid',
    'a method of a source names it already');
  assert.equal(paymentMethodLabel('Cash', undefined, M.cash), 'Cash');
  assert.equal(paymentSourceSuffix([], M.paid), '');
  // A retired method the page no longer loads: still bracketed.
  assert.equal(paymentMethodLabel('Wallet — Old Credit', ['credit_package'], undefined), 'Wallet — Old Credit (Credit Package)');
});

test('the wallet by source: the summary line and the customer page\'s groups and purchases', () => {
  assert.deepEqual(walletBySource(balances).map(g => [g.name, g.total, g.parts]), [
    ['Credit Package', 1100, [['Paid', 1000], ['Bonus', 100]]],
    ['Premium Bundle', 595, [['Paid', 500], ['Bonus', 50], ['Legacy', 45]]],
    ['Other', 177, [['Paid', 70], ['Bonus', 20], ['Legacy', 60], ['Promotional', 15], ['Exchange', 12]]],
  ]);
  assert.equal(walletBySource({ categories: {}, available_total: 0 }), null, 'before 443: none');
  const empty = { ...balances, sources: { credit_package: { total: 0 }, premium_bundle: { total: 0 }, other: { paid: 5, total: 5 } } };
  assert.deepEqual(walletSourceTiles(empty).map(g => [g.name, g.total, g.parts]), [
    ['Credit Package', 0, [['Paid', 0], ['Bonus', 0]]],
    ['Premium Bundle', 0, [['Paid', 0], ['Bonus', 0]]],
    ['Other', 5, [['Paid', 5]]],
  ], 'all three groups, Paid and Bonus always for a package or bundle');
  assert.deepEqual(purchasesBySource(balances), [
    { source: 'credit_package', name: 'Credit Package', items: [{ name: 'Fixture Package', invoiceNo: 'INV-2026-0901', boughtOn: '2026-10-21',
      received: false, parts: [['Paid', 1000], ['Bonus', 100]], total: 1100 }] },
    { source: 'premium_bundle', name: 'Premium Bundle', items: [{ name: 'Fixture Bundle', invoiceNo: 'INV-2026-0902', boughtOn: '2026-10-21',
      received: false, parts: [['Paid', 500], ['Bonus', 50], ['Legacy', 45]], total: 595 }] },
  ]);
  assert.deepEqual(purchasesBySource({ categories: {} }), []);
  // One used up (S$0.00 left), and credit moved in from another customer's purchase.
  const more = purchasesBySource({ purchases: [
    { source: 'credit_package', name: 'Fixture Package', invoice_no: 'INV-2026-0903', bought_on: '2026-10-20', paid: 0, bonus: 0, legacy: 0, total: 0 },
    { source: 'credit_package', name: 'Fixture Package', invoice_no: 'INV-2026-0904', bought_on: '2026-10-19', paid: 40, total: 40, received: true },
  ] });
  assert.deepEqual(more[0].items.map(i => [i.invoiceNo, i.total, i.parts, i.received]),
    [['INV-2026-0903', 0, [], false], ['INV-2026-0904', 40, [['Paid', 40]], true]]);
});

test('the printed line: Credit Package · Premium Bundle · Other, non-zero only; the kinds before 443', () => {
  const at = new Date('2026-10-21T04:00:00Z');
  assert.deepEqual(creditBalanceLine(balances, at), {
    label: 'Credit balance (as at 21 Oct 2026)', amount: 'S$1872.00',
    detail: 'Credit Package S$1100.00 · Premium Bundle S$595.00 · Other S$177.00' });
  const some = { ...balances, available_total: 340, sources: { credit_package: { total: 300 }, premium_bundle: { total: 0 }, other: { total: 40 } } };
  assert.equal(creditBalanceLine(some, at).detail, 'Credit Package S$300.00 · Other S$40.00');
  const none = { ...balances, available_total: 0, sources: { credit_package: { total: 0 }, premium_bundle: { total: 0 }, other: { total: 0 } } };
  assert.equal(creditBalanceLine(none, at).detail, null);
  assert.equal(creditBalanceLine({ categories: { paid: 300, bonus: 50 }, available_total: 350 }, at).detail,
    'Paid S$300.00 · Bonus S$50.00', 'a server before 443: the kinds, as before');
});

test('the Payment Summary gives each new method its own wallet column, after the money', () => {
  const ms = [
    { payment_method_id: 'm-cash', method_name: 'Cash', is_wallet_credit: false },
    { payment_method_id: M.pkPaid.id, method_name: M.pkPaid.name, is_wallet_credit: true },
    { payment_method_id: M.pbPaid.id, method_name: M.pbPaid.name, is_wallet_credit: true },
    { payment_method_id: M.paid.id, method_name: M.paid.name, is_wallet_credit: true },
  ];
  const rows = [
    { pay_date: '2026-10-21', payment_method_id: 'm-cash', method_name: 'Cash', amount: 40 },
    { pay_date: '2026-10-21', payment_method_id: M.pkPaid.id, method_name: M.pkPaid.name, amount: 50 },
    { pay_date: '2026-10-21', payment_method_id: M.pbPaid.id, method_name: M.pbPaid.name, amount: 30 },
  ];
  const { headers, body, moneyTaken, walletUsed } = buildPaymentSummary({ methods: ms, rows, from: '2026-10-21', to: '2026-10-21' });
  assert.deepEqual(headers, ['Date', 'Cash', 'Total', 'Wallet — Credit Package Paid (wallet credit)', 'Wallet — Paid Credit (wallet credit)',
    'Wallet — Premium Bundle Paid (wallet credit)', 'Wallet credit used (not money taken)']);
  assert.equal(moneyTaken, 40);
  assert.equal(walletUsed, 80);
  assert.equal(body[0]['Wallet — Premium Bundle Paid (wallet credit)'], 30);
});

// ── The pages read and show it ───────────────────────────────────────────────
const page = read('src/pages/InvoicesPage.tsx');
const customers = read('src/pages/CustomersPage.tsx');
const panel = read('src/components/invoices/InvoiceFinancePanel.tsx');
const guided = read('src/components/invoices/InvoiceGuidedAction.tsx');
const therapy = read('src/pages/TherapyPage.tsx');

test('the invoice page reads what each method can pay and each payment\'s sources, for this invoice only', () => {
  assert.match(page, /supabase\.rpc\('invoice_wallet_availability', \{ p_invoice_id: inv\.id \}\)[\s\S]{0,120}if \(!superseded\(\)\) setPayAvail/);
  assert.match(page, /supabase\.rpc\('invoice_payment_credit_sources', \{ p_invoice_id: inv\.id \}\)[\s\S]{0,120}if \(!superseded\(\)\) setPaySources/);
  assert.match(page, /payAvail\?\.invoice_id === detail\.id && payAvail\?\.customer_id === detail\.customer_id \? payAvail : null/,
    'another invoice\'s, or another customer\'s, figures are never offered');
  assert.match(page, /setPayAvail\(prev => \(prev\?\.invoice_id === inv\.id && prev\?\.customer_id === inv\.customer_id \? prev : null\)\)/,
    'figures read for the invoice\'s earlier customer are dropped on a reload, as the wallet is');
  assert.match(page, /\.\.\.\(hasCreditLine \? \[\] : walletOptions\)/, 'no wallet method on an invoice that sells credit');
  assert.doesNotMatch(page, /Bonus Credit is always spent first/, 'the wrong note is gone');
  assert.doesNotMatch(therapy, /Bonus Credit is always spent before Paid Credit/, 'and from the Credit Package editor');
  assert.match(therapy, /Bonus Credit is paid with its own wallet method \(Wallet — Credit Package Bonus\)/);
  assert.match(page, /packageFirstNote\(pl\.payment_method_id, i\)/, 'the Credit Package first reminder on a payment row');
  assert.match(page, /otherLines: payLines\.filter\(\(_, j\) => j !== row\)/, 'with the payment\'s other rows');
});

test('every place a payment row is shown or printed uses its label with the source', () => {
  assert.equal((page.match(/printedMethod\(p2?\.payment_method_id\)/g) ?? []).length, 0, 'no payment row uses the bare method name');
  assert.match(page, /\$\{paymentLabel\(pm, 'Payment'\)\} · \$\{displayDay/, 'the PDF and image copy');
  assert.match(page, /<tr><td>\$\{esc\(paymentLabel\(p\)\)\}/, 'the printed copy');
  assert.match(page, /className="invoice-payment-record-label">\{paymentLabel\(p\) \|\| '—'\}/, 'Payments Recorded');
  assert.match(page, /\{paymentLabel\(p2\) \|\| '—'\} — wallet credit; corrected from the payment list, not here/, 'the correction form');
  assert.match(page, /paymentLabel=\{\(paymentId, fallback\) => paymentLabel\(/, 'the refund and correction panel');
  assert.match(panel, /paymentLabel\?: \(paymentId: string, fallback: string\) => string;/);
  assert.match(panel, /\$\{sourceLabel\(s\)\} · \$\{s\.wallet \? 'restore credit' : 'actual refund'\}/);
  assert.match(panel, /\$\{sourceLabel\(s\)\} · \$\{s\.wallet \? 'credit restored' : 'money returned'\}/);
  assert.match(panel, /label: `\$\{payLabel\(p\.id, methods\.find/);
  // The guided Cancel/Refund (step 4, Money returned), opened from the invoice.
  assert.match(guided, /paymentLabel\?: \(paymentId: string, fallback: string\) => string;/);
  assert.match(guided, /to \{d\.wallet && paymentLabel \? \(paymentLabel\(d\.payment_id, d\.method\) \|\| d\.method\) : d\.method\}/);
  assert.match(page, /<InvoiceGuidedAction[\s\S]{0,200}paymentLabel=\{\(paymentId, fallback\) => paymentLabel\(/, 'the invoice passes its labels');
});

test('the copies wait for the payment sources they print', () => {
  assert.match(page, /const sourcesLoaded = supabase\.rpc\('invoice_payment_credit_sources'/);
  assert.match(page, /await Promise\.all\(\[namesLoaded, billToLoaded, goodsLoaded, sourcesLoaded\]\)/);
  // A failed read never holds the copies: it settles either way.
  assert.match(page, /setPaySources\(error \? \{\} : [^\n]*\n\s*\(\) => \{ if \(!superseded\(\)\) setPaySources\(\{\}\); \}\);/);
});

test('the customer page shows the wallet by source and each purchase, the categories without sources', () => {
  assert.match(customers, /walletSourceTiles\(credit\)/);
  assert.match(customers, /purchasesBySource\(credit\)/);
  assert.match(customers, /creditTiles \? \(/, 'by source when the server gives sources');
  assert.match(customers, /\(\['paid','bonus','legacy','promotional','exchange'\] as const\)\.map/, 'the categories otherwise');
});
