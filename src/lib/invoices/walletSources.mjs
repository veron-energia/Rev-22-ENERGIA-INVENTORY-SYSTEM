// Credit Package credit and Premium Bundle credit, kept apart (443).
//
// The Owner's answers, 21 Oct 2026 (CREDIT-SPLIT-1..14): a customer's credit
// is shown by where it came from — Credit Package, Premium Bundle, Other
// (opening balances, Adjust) — and staff choose which pays through a wallet
// method of its own:
//
//   Wallet — Credit Package Paid / Bonus     pays Credit Package credit only
//   Wallet — Premium Bundle Paid / Bonus     pays Premium Bundle credit only
//   Wallet — Paid Credit / Bonus Credit      pays Other credit only
//   Wallet — Legacy / Promotional/FOC / Exchange   any source, as before
//
// The server works out what each method can pay of the open invoice
// (invoice_wallet_availability) and where each past wallet payment's credit
// came from (invoice_payment_credit_sources). This module turns those into
// what the invoice page shows. Kept free of React so it is tested with the
// Node runner.

/** The sources, in the order the pages list them. */
export const WALLET_SOURCES = Object.freeze([
  Object.freeze(['credit_package', 'Credit Package']),
  Object.freeze(['premium_bundle', 'Premium Bundle']),
  Object.freeze(['other', 'Other']),
]);

/** The category order within a source. */
export const WALLET_CATEGORIES = Object.freeze([
  Object.freeze(['paid', 'Paid']),
  Object.freeze(['bonus', 'Bonus']),
  Object.freeze(['legacy', 'Legacy']),
  Object.freeze(['promotional', 'Promotional']),
  Object.freeze(['exchange', 'Exchange']),
]);

const SOURCE_NAME = Object.fromEntries(WALLET_SOURCES);
const CATEGORY_RANK = Object.fromEntries(WALLET_CATEGORIES.map(([k], i) => [k, i]));

/** 'Credit Package', 'Premium Bundle', 'Other'; '' for anything else. */
export function sourceName(source) {
  return SOURCE_NAME[source] ?? '';
}

const num = v => { const n = Number(v); return Number.isFinite(n) ? n : 0; };

/**
 * The source a wallet method pays from, as the server reads it
 * (wallet_method_source_filter): its own source; 'other' for a Paid or Bonus
 * method naming none; null (any source) for the rest.
 */
export function methodPaysFrom(method) {
  if (!method?.is_wallet_credit) return null;
  if (method.wallet_source) return method.wallet_source;
  return method.wallet_category === 'paid' || method.wallet_category === 'bonus' ? 'other' : null;
}

/**
 * What a past wallet payment's row adds after its method's name (CREDIT-SPLIT-13):
 * the sources its credit came from, in brackets — ' (Premium Bundle)', or
 * ' (Credit Package + Premium Bundle)' — when its method names no source and
 * some of the credit came from a Credit Package or a Premium Bundle. Nothing
 * for a method that names its source, or for credit that was all Other (since
 * 443 'Wallet — Paid Credit' pays Other credit only, so its name says so).
 * `sources` is the payment's entry from invoice_payment_credit_sources.
 */
export function paymentSourceSuffix(sources, method) {
  if (!Array.isArray(sources) || sources.length === 0) return '';
  if (method?.wallet_source) return '';
  if (!sources.some(s => s === 'credit_package' || s === 'premium_bundle')) return '';
  const names = WALLET_SOURCES.filter(([k]) => sources.includes(k)).map(([, n]) => n);
  return names.length ? ` (${names.join(' + ')})` : '';
}

/** A payment row's method as the invoice shows and prints it. */
export function paymentMethodLabel(name, sources, method) {
  return `${name ?? ''}${paymentSourceSuffix(sources, method)}`;
}

/**
 * What a wallet method can pay when the server's figures for this invoice are
 * not there (a server before 443, or the read failed): what the customer
 * holds of the method's category and source (customer_credit_balances).
 */
export function heldForMethod(method, balances) {
  if (!balances || !method?.is_wallet_credit) return 0;
  const cat = method.wallet_category;
  const from = methodPaysFrom(method);
  if (balances.sources && from && cat) return num(balances.sources?.[from]?.[cat]);
  if (!cat) return num(balances.available_total);
  return num(balances.categories?.[cat]);
}

/**
 * Record Payment's wallet methods (CREDIT-SPLIT-5..8): in the server's order
 * (Credit Package first, then Premium Bundle, then the rest), each labelled
 * with what it can pay of THIS invoice, and switched off when that is nothing.
 * A method also held beyond what it can pay here says so. `availability` is
 * invoice_wallet_availability(); when it is not there, `balances`
 * (customer_credit_balances) stand in, as before 443.
 */
export function walletMethodOptions({ methods, availability, balances, money }) {
  const fmt = money ?? (n => `S$${num(n).toFixed(2)}`);
  const wallet = (methods ?? []).filter(m => m?.is_wallet_credit);
  const byId = new Map((availability?.methods ?? []).map(a => [String(a.payment_method_id), a]));
  const rank = m => {
    const a = byId.get(String(m.id));
    if (a && Number.isFinite(Number(a.rank))) return [0, Number(a.rank), ''];
    const src = m.wallet_source === 'credit_package' ? 0 : m.wallet_source === 'premium_bundle' ? 1 : 2;
    return [1, src * 10 + (CATEGORY_RANK[m.wallet_category] ?? 6), String(m.name ?? '')];
  };
  return wallet
    .map(m => ({ m, r: rank(m) }))
    .sort((x, y) => x.r[0] - y.r[0] || x.r[1] - y.r[1] || x.r[2].localeCompare(y.r[2]))
    .map(({ m }) => {
      const a = byId.get(String(m.id));
      const available = a ? num(a.available) : heldForMethod(m, balances);
      const held = a ? num(a.held) : available;
      const extra = held > available + 0.005 ? ` (${fmt(held)} held)` : '';
      return { value: m.id, label: `${m.name} — ${fmt(available)} available${extra}`, disabled: available <= 0 };
    });
}

/**
 * Credit Package first (CREDIT-SPLIT-6): on a row paying from Premium Bundle
 * credit while Credit Package credit could still pay this invoice, a reminder
 * that Credit Package credit is used first by default (staff may keep their
 * choice). `otherLines` are the payment's other rows ({ payment_method_id,
 * amount }): what they already put on Credit Package methods is taken off
 * what Credit Package credit can pay, so a split the Owner allowed (one row
 * per source, CREDIT-SPLIT-7) is not told to drop its Premium Bundle row once
 * the Credit Package credit is in use. Null when it does not apply.
 */
export function creditPackageFirstNote({ methodId, methods, availability, money, otherLines }) {
  const fmt = money ?? (n => `S$${num(n).toFixed(2)}`);
  const m = (methods ?? []).find(x => x?.id === methodId);
  if (!m || m.wallet_source !== 'premium_bundle' || !availability?.methods) return null;
  const sourceOf = id => (methods ?? []).find(x => x?.id === id)?.wallet_source
    ?? availability.methods.find(a => String(a.payment_method_id) === String(id))?.wallet_source;
  const onPackage = (otherLines ?? [])
    .filter(l => l?.payment_method_id && sourceOf(l.payment_method_id) === 'credit_package')
    .reduce((s, l) => s + Math.max(0, num(l.amount)), 0);
  // Each Credit Package method's figure is worked out alone on the same
  // lines, so what the other rows take from Credit Package credit comes off
  // each of them.
  const pkg = availability.methods
    .filter(a => a.wallet_source === 'credit_package')
    .map(a => ({ a, left: Math.round((num(a.available) - onPackage) * 100) / 100 }))
    .filter(x => x.left > 0.005);
  if (pkg.length === 0) return null;
  const best = pkg.reduce((x, y) => (y.left > x.left ? y : x));
  return `Credit Package credit can pay ${fmt(best.left)}${onPackage > 0.005 ? ' more' : ''} of this invoice (${best.a.name}) and is used first by default. `
    + 'Keep Premium Bundle credit only if the customer asks for it.';
}

/**
 * The wallet by source for a summary line: [{ source, name, total, parts }]
 * for each source the customer holds, `parts` its categories held
 * ([name, amount], Paid then Bonus, ...). From customer_credit_balances; null
 * when it has no sources (a server before 443).
 */
export function walletBySource(balances) {
  if (!balances?.sources) return null;
  return WALLET_SOURCES
    .map(([k, name]) => {
      const s = balances.sources[k] ?? {};
      const parts = WALLET_CATEGORIES.map(([c, cn]) => [cn, num(s[c])]).filter(([, v]) => Math.abs(v) >= 0.005);
      return { source: k, name, total: num(s.total), parts };
    })
    .filter(x => Math.abs(x.total) >= 0.005);
}

/**
 * The customer page's three groups (CREDIT-SPLIT-4): Credit Package, Premium
 * Bundle and Other, always all three, each with its total and its parts —
 * Paid and Bonus always for a package or bundle (and any other kind it
 * holds, such as the Legacy lots linked to a bundle), only what is held for
 * Other. Null when the balance has no sources (a server before 443).
 */
export function walletSourceTiles(balances) {
  if (!balances?.sources) return null;
  return WALLET_SOURCES.map(([k, name]) => {
    const s = balances.sources[k] ?? {};
    const parts = WALLET_CATEGORIES
      .filter(([c]) => (k !== 'other' && (c === 'paid' || c === 'bonus')) || Math.abs(num(s[c])) >= 0.005)
      .map(([c, cn]) => [cn, num(s[c])]);
    return { source: k, name, total: num(s.total), parts };
  });
}

/**
 * Each Credit Package and Premium Bundle bought, with what is left
 * (CREDIT-SPLIT-4, the customer page): from customer_credit_balances'
 * 'purchases', grouped by source, Credit Package first. One used up is there
 * too, at 0; `received` marks credit moved in from another customer's
 * purchase (Move), which this customer did not buy.
 */
export function purchasesBySource(balances) {
  const list = Array.isArray(balances?.purchases) ? balances.purchases : [];
  return WALLET_SOURCES.slice(0, 2)
    .map(([k, name]) => ({
      source: k, name,
      items: list.filter(p => p?.source === k).map(p => ({
        name: p.name || name,
        invoiceNo: p.invoice_no ?? null,
        boughtOn: p.bought_on ?? null,
        received: p.received === true,
        parts: [['Paid', num(p.paid)], ['Bonus', num(p.bonus)], ['Legacy', num(p.legacy)]].filter(([, v]) => Math.abs(v) >= 0.005),
        total: num(p.total),
      })),
    }))
    .filter(g => g.items.length > 0);
}
