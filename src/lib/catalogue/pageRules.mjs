// Small rules shared by the Vouchers page, the store price window, Therapy
// Services, the holiday tools and the split panels (423). Plain functions, so the node tests
// can check them without a browser.

/** Today in Singapore, YYYY-MM-DD. */
export function sgToday(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

/**
 * A voucher is out of date only after its last valid day, in Singapore.
 * Both are YYYY-MM-DD, so they compare as text.
 */
export function isPastValidUntil(validUntil, today = sgToday()) {
  if (!validUntil) return false;
  return String(validUntil).slice(0, 10) < today;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "9 Oct 2026" from YYYY-MM-DD, with no time zone shift; '' when empty. */
export function dayText(value) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value ?? '');
  if (!m) return '';
  return `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}`;
}

/** "09/10/2026" from YYYY-MM-DD, for the Excel export; '' when empty. */
export function dayNumbers(value) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value ?? '');
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '';
}

/**
 * What is wrong with a typed price, or null when it can be saved.
 * Blank is allowed (the caller says what blank means).
 */
export function priceProblem(text) {
  const t = String(text ?? '').trim();
  if (t === '') return null;
  const n = Number(t);
  if (!Number.isFinite(n)) return 'is not a number';
  if (n < 0) return 'cannot be negative';
  return null;
}

/**
 * The stores whose typed price or "available" tick differs from what is
 * saved. drafts: { [storeId]: { m, avail } }; saved: rows with store_id,
 * selling_price and available_at_store. A store with no saved row counts as
 * blank and available.
 */
export function unsavedStoreNames(stores, drafts, saved) {
  const names = [];
  for (const s of stores ?? []) {
    const d = drafts?.[s.id];
    if (!d) continue;
    const row = (saved ?? []).find(r => r.store_id === s.id);
    const savedPrice = row?.selling_price == null ? '' : Number(row.selling_price);
    const typed = String(d.m ?? '').trim() === '' ? '' : Number(d.m);
    const savedAvail = row ? row.available_at_store !== false : true;
    if (typed !== savedPrice || !!d.avail !== savedAvail) names.push(s.name);
  }
  return names;
}

/** "A, B and C". */
export function listText(items) {
  const a = (items ?? []).filter(Boolean);
  if (a.length <= 1) return a.join('');
  return `${a.slice(0, -1).join(', ')} and ${a[a.length - 1]}`;
}

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

/**
 * What still depends on a voucher, from soft_delete_voucher's answer, as
 * short lines for the delete question.
 */
export function voucherDependents(answer) {
  const lines = [];
  const units = Number(answer?.holders_units ?? 0);
  const people = Number(answer?.holders_customers ?? 0);
  if (units > 0) {
    lines.push(`${plural(people, 'customer holds', 'customers hold')} ${plural(units, 'unit', 'units')} of it. They keep them.`);
  }
  const stock = (answer?.store_stock ?? []).filter(s => Number(s.quantity) > 0);
  if (stock.length > 0) {
    lines.push(`In stock: ${stock.map(s => `${s.store_name} ${s.quantity}`).join(', ')}.`);
  }
  const used = answer?.used_in ?? {};
  const offered = [
    [used.promotions, 'live promotion', 'live promotions'],
    [used.premium_bundles, 'premium bundle', 'premium bundles'],
    [used.credit_packages, 'credit package', 'credit packages'],
    [used.therapy_packages, 'therapy package', 'therapy packages'],
  ].filter(([n]) => Number(n) > 0).map(([n, one, many]) => plural(Number(n), one, many));
  if (offered.length > 0) lines.push(`Offered by ${listText(offered)}.`);
  return lines;
}

/**
 * The rows for set_therapy_service_stores, or the first problem, naming the
 * store. rows: { [storeId]: { available, override } }.
 */
export function serviceStoreRows(stores, rows) {
  const out = [];
  for (const s of stores ?? []) {
    const r = rows?.[s.id] ?? { available: false, override: '' };
    const problem = priceProblem(r.override);
    if (problem) return { problem: `The price at ${s.name} ${problem}. Leave it empty to charge the standard price.`, rows: [] };
    const t = String(r.override ?? '').trim();
    out.push({ store_id: s.id, is_available: !!r.available, price_override: t === '' ? null : Number(t) });
  }
  return { problem: null, rows: out };
}

/**
 * How many periods the recalculation would lengthen. The server leaves out a
 * period with no holiday country first, and never shortens one.
 */
export function lengtheningCount(rows) {
  return (rows ?? []).filter(r => !r.needs_country && r.change_days != null && Number(r.change_days) > 0 && !r.shortens).length;
}

/**
 * True when a call got no answer from the database (the network or a gateway
 * failed), so it may or may not have been done. A refusal from the database
 * or the API always has a code; postgrest-js sends code '' when there was no
 * answer, so this tests for a code that is not empty.
 */
export function outcomeUnknown(error) {
  return !!error && !error.code;
}

// A split sale whose answer was lost keeps its request id until a try
// succeeds, so the split opened again for the same package and store sends
// the same id: the server then shows the sale already made instead of making
// a second one. Kept for the tab (sessionStorage), or for the page when the
// browser blocks storage.
const heldSplitIds = new Map();
const tabStorage = () => { try { return globalThis.sessionStorage ?? null; } catch { return null; } };

/** The key of a split sale: what it sells and where. */
export function splitRequestKey(kind, storeId, itemId) {
  return `split-request:${kind}:${storeId}:${itemId}`;
}

/** The request id kept for this split after a lost answer, or null. */
export function heldSplitRequest(key) {
  try { const id = tabStorage()?.getItem(key); if (id) return id; } catch { /* storage blocked */ }
  return heldSplitIds.get(key) ?? null;
}

/** Keep the request id of a split whose answer was lost. */
export function holdSplitRequest(key, id) {
  heldSplitIds.set(key, id);
  try { tabStorage()?.setItem(key, id); } catch { /* storage blocked: the page keeps it */ }
}

/** The split was made and shown: its id is not needed again. */
export function releaseSplitRequest(key) {
  heldSplitIds.delete(key);
  try { tabStorage()?.removeItem(key); } catch { /* storage blocked */ }
}

/**
 * True when the server refused a split because its request id already made
 * another sale (423): an earlier try, whose answer was lost, made invoices
 * with other customers, amounts or vouchers. That id can never make this
 * sale, so the panel lets it go.
 */
export function splitRequestUsed(error) {
  return !!error && !!error.code && /already used for another sale/.test(String(error.message ?? ''));
}
