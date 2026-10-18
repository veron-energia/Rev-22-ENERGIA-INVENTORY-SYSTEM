// What the Exchanges page asks before it sends an exchange (408, 9 Oct 2026).
//
// The database decides (create_product_exchange, create_bundle_component_exchange,
// create_bundle_exchange, exchange_assert_payments, exchange_bundle_quote); these
// helpers only keep the page from offering what it would refuse, and say why.
//
//   * No Wallet method pays an exchange: the exchange copies its payments into
//     the replacement invoice and takes no credit, so a wallet "payment" marked
//     the invoice paid with nothing taken (SALES-EXTRAS-M1).
//   * Nothing is taken when nothing is due; never more than is due; a whole
//     bundle takes exactly its top-up (SALES-EXTRAS-2).
//   * A whole-bundle exchange is for one bundle whose items were not exchanged
//     on their own (SALES-EXTRAS-2, SALES-EXTRAS-4).
//   * Every payment row with an amount has a method: a row left on
//     "— Method —" was counted as received but never sent, so the server
//     recorded that money as still owed.
//   * 424 (the Owner, 9 Oct 2026, Q17): a returned item counts for the lower
//     of today's price and what the customer paid for it, and a free item
//     gives none. The server works it out (exchange_credit_preview); the page
//     shows both figures and says which one counts (SALES-EXTRAS-5).
//   * The additional charge is taken in full now; an instalment is a label on
//     that money, and the replacement invoice records it (SALES-EXTRAS-14).
//   * 424 (the Owner, 9 Oct 2026, SALES-EXTRAS-M3): an exchange typed in late
//     counts on its exchange date, never before the 1st of this month and
//     never before the original sale.

const num = v => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const money = n => `S$${num(n).toFixed(2)}`;
const numOrNull = v => (v === null || v === undefined || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
const cents = n => Math.round(num(n) * 100) / 100;

/** The methods an exchange's additional payment may use: active, not deleted, never wallet credit. */
export function exchangePaymentMethods(methods) {
  return (Array.isArray(methods) ? methods : [])
    .filter(m => m && !m.is_wallet_credit && m.is_active !== false && !m.deleted_at);
}

/** The ids of the products of a bundle line already exchanged on their own. */
export function componentsExchanged(line) {
  const done = line && Array.isArray(line.component_exchanged) ? line.component_exchanged : [];
  return done.map(d => String(d?.product_id ?? '')).filter(Boolean);
}

/**
 * Why a bundle line cannot be picked in this mode, or null.
 * mode: 'bundle' (the whole bundle) or 'component' (one of its items).
 */
export function bundleLineBlock(line, mode) {
  if (!line) return 'Choose a bundle';
  if (line.exchanged_at) return 'already exchanged';
  if (mode !== 'bundle') return null;
  if (componentsExchanged(line).length > 0) return 'an item was already exchanged on its own: use Bundle component';
  const qty = num(line.quantity);
  if (qty !== 1) return `${qty} bundles on this line: use Bundle component`;
  return null;
}

/**
 * What is wrong with one of the payment rows entered, or null.
 *   rows         [{ payment_method_id, amount }] as the page holds them
 *   allowedIds   the ids exchangePaymentMethods allows
 *   instalmentId the page's Instalment choice (its own fields say which real
 *                method the money comes through)
 * A row with an amount and no method would be counted as received but never
 * sent; a method outside allowedIds is wallet credit (or no longer active);
 * an amount is never negative.
 */
export function exchangePaymentRowProblem(rows, allowedIds, instalmentId) {
  const allowed = new Set((Array.isArray(allowedIds) ? allowedIds : []).map(String));
  for (const r of Array.isArray(rows) ? rows : []) {
    const amount = num(r?.amount);
    const id = r?.payment_method_id ? String(r.payment_method_id) : '';
    if (amount < 0) return 'A payment amount cannot be negative.';
    if (amount > 0 && !id) return `Choose a payment method for the ${money(amount)} entered, or remove that payment.`;
    if (id && id !== instalmentId && !allowed.has(id)) {
      return 'Choose a payment method for each payment. Wallet credit cannot pay an exchange.';
    }
  }
  return null;
}

/**
 * What is wrong with the payments entered, or null.
 *   due      what the exchange charges now (the top-up; 0 when nothing is due)
 *   received the sum of the amounts entered
 *   exact    a whole bundle: exactly the top-up (no instalment)
 */
export function exchangePaymentProblem({ due, received, exact }) {
  const d = Math.max(0, Math.round(num(due) * 100) / 100);
  const r = Math.round(num(received) * 100) / 100;
  if (d === 0 && r > 0) return `Nothing is due on this exchange, so no payment can be taken (${money(r)} entered). Remove the payment.`;
  if (r - d > 0.001) return `Payments (${money(r)}) exceed the additional charge of ${money(d)}.`;
  if (exact && d - r > 0.001) return `This exchange needs exactly ${money(d)} paid now (${money(r)} entered).`;
  if (!exact && d - r > 0.001) return `${money(d - r)} of the additional charge is not entered yet. The whole charge is taken now; an instalment only records how it is paid.`;
  return null;
}

/** exchange_bundle_preview's answer, with every number a number. Null for none. */
export function bundleQuoteFromRpc(data) {
  if (!data || typeof data !== 'object') return null;
  const items = list => (Array.isArray(list) ? list : []).map(i => ({
    product_id: String(i?.product_id ?? ''), name: String(i?.name ?? 'Unknown product'), quantity: num(i?.quantity),
  }));
  return {
    problem: data.problem ? String(data.problem) : null,
    credit: num(data.credit), replacement: num(data.replacement),
    topup: num(data.topup), nonrefundable: num(data.nonrefundable),
    // 424: the two figures behind the credit (null from a server before 424)
    todays_value: numOrNull(data.todays_value), paid: numOrNull(data.paid),
    returned: items(data.returned), replacement_items: items(data.replacement_items),
  };
}

/**
 * The line under the affiliate picker: what an exchange left empty is credited
 * to (exchange_original_context: affiliate, affiliate_inherited_id).
 */
export function affiliateHint(ctx) {
  const name = ctx && ctx.affiliate ? String(ctx.affiliate) : null;
  if (!name) return 'The original sale had no affiliate, so left empty this exchange has none.';
  if (ctx.affiliate_inherited_id) return `Left empty, this exchange keeps the original sale's affiliate (${name}).`;
  return `Original sale: ${name} (no longer eligible), so left empty this exchange has no affiliate.`;
}

// ── 424: what a returned item counts for ──────────────────────────────────

const figures = x => ({ todays: numOrNull(x?.todays), paid: numOrNull(x?.paid), credit: numOrNull(x?.credit) });

/**
 * exchange_credit_preview's answer, every number a number and a missing price
 * null. Null when there is no answer (a server before 424, or an error).
 */
export function creditPreviewFromRpc(data) {
  if (!data || typeof data !== 'object' || !Array.isArray(data.lines)) return null;
  return {
    lines: data.lines.map(l => ({
      invoice_item_id: String(l?.invoice_item_id ?? ''),
      line_kind: String(l?.line_kind ?? ''),
      quantity: num(l?.quantity),
      ...figures(l),
      components: (Array.isArray(l?.components) ? l.components : []).map(c => ({
        product_id: String(c?.product_id ?? ''),
        quantity: num(c?.quantity),
        options: (Array.isArray(c?.options) ? c.options : []).map(o => ({ quantity: num(o?.quantity), ...figures(o) })),
      })),
    })),
  };
}

/** One line of the preview, or null. */
export function previewLine(preview, lineId) {
  return (preview?.lines ?? []).find(l => l.invoice_item_id === String(lineId ?? '')) ?? null;
}

/**
 * What the chosen product lines count for together: { todays, paid, credit,
 * missing }. `missing` is true when a chosen line is not in the preview or has
 * no price at this store; the credit is then null.
 */
export function productLinesCredit(preview, lineIds) {
  const ids = Array.isArray(lineIds) ? lineIds : [];
  let todays = 0, paid = 0, credit = 0, missing = false;
  for (const id of ids) {
    const l = previewLine(preview, id);
    if (!l || l.credit === null || l.todays === null) { missing = true; continue; }
    todays += l.todays; paid += l.paid ?? 0; credit += l.credit;
  }
  return { todays: cents(todays), paid: cents(paid), credit: missing ? null : cents(credit), missing };
}

/** What `qty` of one product of a bundle line counts for ({ todays, paid, credit }), or null. */
export function componentCredit(preview, lineId, productId, qty) {
  const comp = (previewLine(preview, lineId)?.components ?? []).find(c => c.product_id === String(productId ?? ''));
  const opt = (comp?.options ?? []).find(o => o.quantity === num(qty));
  return opt ? { todays: opt.todays, paid: opt.paid, credit: opt.credit } : null;
}

/**
 * One plain sentence saying which figure the credit is. For one item of a
 * bundle (`share`), what was paid is that item's share of what the bundle was
 * paid, not the bundle's whole price.
 */
export function creditBasisText(fig, share = false) {
  if (!fig) return '';
  const { todays, paid, credit } = fig;
  const paidName = share ? 'its share of what the bundle was paid' : 'what was paid';
  if (credit === null || credit === undefined || todays === null || todays === undefined) {
    return 'No price at this store, so it cannot be valued here.';
  }
  if (num(paid) <= 0) return share ? 'The bundle was free, so it gives no credit.' : 'It was free, so it gives no credit.';
  // Several lines, some cheaper today and some bought at less: each counts for
  // the lower of its own two figures, so the credit is below both totals.
  if (num(credit) < Math.min(num(todays), num(paid)) - 0.005) {
    return `Each item counts for the lower of its own two figures: ${money(credit)} in all.`;
  }
  if (num(paid) < num(todays) - 0.005) {
    return `Counts for ${paidName} (${money(paid)}), which is less than today's price (${money(todays)}).`;
  }
  if (num(todays) < num(paid) - 0.005) {
    return `Counts for today's price (${money(todays)}), which is less than ${paidName} (${money(paid)}).`;
  }
  return `Counts for ${money(credit)}: today's price and ${paidName} are the same.`;
}

// ── 424: the exchange's day, and its instalment label ───────────────────────

const sgDay = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' });
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * The day an exchange is dated: the exchange date staff chose, else the
 * Singapore date it was saved (the first exchanges have no exchange date).
 * 'YYYY-MM-DD', or '' when there is neither.
 */
export function exchangeDay(e) {
  const chosen = /^\d{4}-\d{2}-\d{2}/.exec(String(e?.exchange_date ?? ''));
  if (chosen) return chosen[0];
  const at = e?.created_at ? new Date(e.created_at) : null;
  return at && Number.isFinite(at.getTime()) ? sgDay.format(at) : '';
}

/** 'YYYY-MM-DD' as '9 Oct 2026' (no time zone involved). */
export function displayDay(day) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(day ?? ''));
  if (!m || Number(m[2]) < 1 || Number(m[2]) > 12) return '';
  return `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}`;
}

// ── 424 (the Owner, 9 Oct 2026): the day an exchange's sale counts on ──────
//
// An exchange typed in late counts on the exchange date staff choose, in the
// sales reports and commission, but never before the 1st of the current month
// in Singapore, so a month already sent to Xero is not changed. It is never
// before the original sale, nor in the future. The server checks the same
// (set_exchange_details) and dates the replacement invoice by it.

const DAY = /^\d{4}-\d{2}-\d{2}$/;

/** The original sale's day: its invoice date, else the Singapore day it was made. 'YYYY-MM-DD' or ''. */
export function saleDay(invoice) {
  return exchangeDay({ exchange_date: invoice?.business_date ?? null, created_at: invoice?.created_at ?? null });
}

/** The earliest day an exchange may be dated: the 1st of today's month, or the original sale's day if later. */
export function exchangeDateFloor(today, originalDay) {
  const first = DAY.test(String(today ?? '')) ? `${String(today).slice(0, 7)}-01` : '';
  const orig = DAY.test(String(originalDay ?? '')) ? String(originalDay) : '';
  return orig > first ? orig : first;
}

/** What is wrong with the exchange date chosen, or null. Empty means today. */
export function exchangeDateProblem(day, today, originalDay) {
  const d = String(day ?? '');
  if (d === '') return null;
  if (!DAY.test(d)) return 'Choose a valid exchange date.';
  if (d > String(today)) return 'An exchange cannot be dated in the future.';
  const first = exchangeDateFloor(today, '');
  if (d < first) {
    return `An exchange can be dated from the 1st of this month (${displayDay(first)}) at the earliest. An earlier month may already be in Xero.`;
  }
  if (DAY.test(String(originalDay ?? '')) && d < String(originalDay)) {
    return `An exchange cannot be dated before the original sale (${displayDay(String(originalDay))}).`;
  }
  return null;
}

/** The line under the exchange date: the day the replacement sale counts on. */
export function exchangeDateHint(day, today) {
  const d = DAY.test(String(day ?? '')) ? String(day) : String(today);
  if (d < String(today)) {
    return `This exchange counts on ${displayDay(d)} in the sales reports, commission and Xero, not on the day you save it.`;
  }
  return 'The replacement sale counts on this date in the sales reports, commission and Xero.';
}

/**
 * The instalment label the replacement invoice records: the real method and
 * months of the last Instalment row with money in it (an invoice carries one
 * set of terms, as on the Invoices page), or null.
 */
export function instalmentLabelFrom(rows, instalmentId) {
  let label = null;
  for (const r of Array.isArray(rows) ? rows : []) {
    if (r?.payment_method_id !== instalmentId || !(num(r?.amount) > 0) || !r?.instalment?.method_id) continue;
    label = { method_id: String(r.instalment.method_id), months: num(r.instalment.months) };
  }
  return label;
}
