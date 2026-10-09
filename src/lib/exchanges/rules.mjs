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

const num = v => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const money = n => `S$${num(n).toFixed(2)}`;

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
  if (!exact && d - r > 0.001) return `${money(d - r)} of the additional charge is unaccounted for — take it now or cover it with an instalment.`;
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
