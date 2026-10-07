// Goods handed over before full payment (399, the Owner, 6 Oct 2026).
//
// A part payment on an invoice with goods still to collect is saved only with
// an answer: "Nothing taken", or the products the customer takes now (per
// product, up to what is still to collect, single products inside promotions
// and picks included). "Hand over items" records the same with no payment,
// and "Record items returned" (Owner/Manager) takes goods back: good to the
// shelf, damaged or not returned written off. The database checks everything
// again (invoice_handover_internal, record_invoice_goods_return); these
// helpers only decide what to ask, what to send, and what the copies say.
//
// The goods come from invoice_goods_status: per product, required (lines,
// promotion contents and picks), collected, still to collect, out with the
// customer (returnable) and in the store now.

const int = v => {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
};

/** invoice_goods_status's answer, with every number a number. Null for none. */
export function goodsFromRpc(data) {
  if (!data || typeof data !== 'object') return null;
  const products = (Array.isArray(data.products) ? data.products : []).map(p => ({
    product_id: String(p.product_id ?? ''),
    name: String(p.name ?? 'Unknown product'),
    required: int(p.required), collected: int(p.collected), to_collect: int(p.to_collect),
    out: int(p.out), in_store: int(p.in_store),
    via: Array.isArray(p.via) ? p.via.map(String) : [],
  }));
  const history = (Array.isArray(data.history) ? data.history : []).map(h => ({
    id: String(h.id ?? ''), kind: String(h.kind ?? ''), source: String(h.source ?? ''),
    created_at: String(h.created_at ?? ''), created_by_name: h.created_by_name ?? null, reason: h.reason ?? null,
    items: (Array.isArray(h.items) ? h.items : []).map(i => ({
      product_id: String(i.product_id ?? ''), name: i.name ?? null,
      quantity: int(i.quantity), good: int(i.good), damaged: int(i.damaged), not_returned: int(i.not_returned),
    })),
  }));
  return {
    invoice_id: String(data.invoice_id ?? ''), invoice_no: String(data.invoice_no ?? ''),
    status: String(data.status ?? ''), store_id: data.store_id ?? null, store_name: data.store_name ?? null,
    open: !!data.open, fulfil_from_warehouse: !!data.fulfil_from_warehouse,
    required_total: int(data.required_total), collected_total: int(data.collected_total),
    to_collect_total: int(data.to_collect_total), out_total: int(data.out_total),
    can_hand_over: !!data.can_hand_over, can_record_return: !!data.can_record_return,
    products, history,
  };
}

/** The products a customer can still take now. */
export function collectable(goods) {
  return (goods?.products ?? []).filter(p => p.to_collect > 0);
}

/** The products out with the customer that can be recorded as returned. */
export function returnable(goods) {
  return (goods?.products ?? []).filter(p => p.out > 0);
}

/**
 * Whether Record Payment must ask what the customer took: a part payment (more
 * than nothing, less than the balance) on an invoice whose goods may be handed
 * over now and that still has goods to collect. A full payment takes every
 * item, so it asks nothing; an invoice fulfilled from a warehouse hands over
 * nothing from the store.
 */
export function needsHandoverAnswer(goods, payTotal, outstanding) {
  if (!goods || !goods.can_hand_over || goods.to_collect_total <= 0) return false;
  const pay = Number(payTotal) || 0;
  const due = Number(outstanding) || 0;
  return pay > 0 && pay < due - 0.005;
}

/** A fresh pick: nothing chosen. */
export function emptyPick() { return {}; }

/** The pick with one product's quantity set (empty or invalid input is 0). */
export function setPick(pick, productId, value) {
  const n = String(value ?? '').trim() === '' ? 0 : Number(value);
  return { ...(pick ?? {}), [productId]: Number.isFinite(n) ? n : 0 };
}

/** The products picked, in the goods' order, with their quantities. */
export function pickedItems(goods, pick) {
  return collectable(goods)
    .map(p => ({ product: p, qty: Number(pick?.[p.product_id] ?? 0) || 0 }))
    .filter(x => x.qty !== 0);
}

/**
 * What is wrong with the answer, as a sentence for the operator, or null.
 *   answer  null (not answered yet), 'none' ("Nothing taken") or 'items'
 *   pick    { [product_id]: quantity }
 *   button  true for "Hand over items", which records items only
 */
export function handoverProblem(goods, answer, pick, { button = false } = {}) {
  if (!button && answer !== 'none' && answer !== 'items') {
    return 'Say what the customer took now: choose "Nothing taken", or the items taken.';
  }
  if (!button && answer === 'none') return null;
  for (const p of collectable(goods)) {
    const raw = pick?.[p.product_id];
    if (raw === undefined || raw === null || raw === '') continue;
    const q = Number(raw);
    if (!Number.isFinite(q) || q < 0 || q !== Math.trunc(q)) return `Enter a whole number for ${p.name}.`;
    if (q > p.to_collect) return `Only ${p.to_collect} of ${p.name} ${p.to_collect === 1 ? 'is' : 'are'} still to collect.`;
    if (q > p.in_store) {
      return `Only ${p.in_store} of ${p.name} ${p.in_store === 1 ? 'is' : 'are'} in ${goods?.store_name || 'the store'} now.`;
    }
  }
  if (pickedItems(goods, pick).length === 0) {
    return button
      ? 'Enter how many of at least one item the customer takes.'
      : 'Enter how many of at least one item the customer took, or choose "Nothing taken".';
  }
  return null;
}

/** The answer as record_invoice_settlement's payload.handover (or the button's p_handover). */
export function handoverPayload(goods, answer, pick) {
  if (answer === 'none') return { none: true };
  return { items: pickedItems(goods, pick).map(x => ({ product_id: x.product.product_id, qty: x.qty })) };
}

/** A fresh return entry: nothing recorded. */
export function emptyReturn() { return {}; }

/** The entry with one product's good, damaged or not-returned count set. */
export function setReturn(entries, productId, field, value) {
  const n = String(value ?? '').trim() === '' ? 0 : Number(value);
  const row = { good: 0, damaged: 0, not_returned: 0, ...(entries?.[productId] ?? {}) };
  row[field] = Number.isFinite(n) ? n : 0;
  return { ...(entries ?? {}), [productId]: row };
}

const RETURN_FIELDS = ['good', 'damaged', 'not_returned'];

/** What is wrong with "Record items returned", or null. */
export function returnProblem(goods, entries, reason) {
  let any = false;
  for (const p of returnable(goods)) {
    const row = entries?.[p.product_id];
    if (!row) continue;
    let total = 0;
    for (const f of RETURN_FIELDS) {
      const q = Number(row[f] ?? 0);
      if (!Number.isFinite(q) || q < 0 || q !== Math.trunc(q)) return `Enter whole numbers for ${p.name}.`;
      total += q;
    }
    if (total > p.out) return `Only ${p.out} of ${p.name} ${p.out === 1 ? 'is' : 'are'} out with the customer.`;
    if (total > 0) any = true;
  }
  if (!any) return 'Enter how many of at least one item came back good, damaged or not returned.';
  if (!String(reason ?? '').trim()) return 'Give the reason the goods came back.';
  return null;
}

/** The entries as record_invoice_goods_return's p_items. */
export function returnPayload(goods, entries) {
  return returnable(goods)
    .map(p => {
      const row = entries?.[p.product_id] ?? {};
      return { product_id: p.product_id, good: Number(row.good ?? 0) || 0, damaged: Number(row.damaged ?? 0) || 0,
               not_returned: Number(row.not_returned ?? 0) || 0 };
    })
    .filter(r => r.good + r.damaged + r.not_returned > 0);
}

const listOf = rows => rows.map(r => `${r.name} × ${r.qty}`).join(', ');

/** Collected and to-collect lists for the copies, from the goods. */
export function collectionLists(goods) {
  const products = (goods?.products ?? []).filter(p => p.required > 0);
  return {
    collected: products.filter(p => p.collected > 0).map(p => ({ name: p.name, qty: p.collected })),
    toCollect: products.filter(p => p.to_collect > 0).map(p => ({ name: p.name, qty: p.to_collect })),
  };
}

const NOT_REFUNDABLE = 'Goods and services sold are neither refundable nor exchangeable.';
const OPEN_STATUSES = ['draft', 'unpaid', 'partially_paid'];

/**
 * The terms line of a copy (print, PDF, image, WhatsApp, email). A fully paid
 * invoice keeps the standard line (undefined: the copy's own default, "...
 * have been checked and collected"). An unpaid or part-paid one never says
 * everything was collected: its terms stop at "neither refundable nor
 * exchangeable", and its goods are listed instead (copyCollectionLines).
 * Other statuses keep the standard line, as before.
 */
export function copyTermsText(status) {
  return OPEN_STATUSES.includes(String(status ?? '')) ? NOT_REFUNDABLE : undefined;
}

/**
 * An unpaid or part-paid copy's goods as lists, { collected, toCollect }.
 * Null once paid in full, for other statuses, and when the invoice has no
 * goods or they could not be read (the copy then says nothing about
 * collection).
 */
export function copyCollection(status, goods) {
  if (!OPEN_STATUSES.includes(String(status ?? '')) || !goods) return null;
  const lists = collectionLists(goods);
  return lists.collected.length + lists.toCollect.length === 0 ? null : lists;
}

/** The lists in full: "Collected: …" and "To collect: …" (each "none" when empty). */
export function collectionText(c) {
  return [`Collected: ${c.collected.length ? listOf(c.collected) : 'none'}`,
          `To collect: ${c.toCollect.length ? listOf(c.toCollect) : 'none'}`];
}

/**
 * An unpaid or part-paid copy's goods: "Collected: …" and "To collect: …"
 * (each "none" when empty), as the printed copy shows them. Null when
 * copyCollection is.
 */
export function copyCollectionLines(status, goods) {
  const c = copyCollection(status, goods);
  return c ? collectionText(c) : null;
}

const units = items => items.reduce((n, i) => n + (Number(i.qty) || 0), 0);

/**
 * One list on one line no wider than `width`, as `measure` measures it (the
 * PDF's and the image's own text widths): as many products as fit, in order,
 * then "+N more"; if not even the first fits, the number of items. For a copy
 * with no room for the lists in full.
 */
export function collectionLineFitted(label, items, width, measure) {
  if (!items.length) return `${label}: none`;
  for (let k = items.length; k >= 1; k--) {
    const more = items.length - k;
    const line = `${label}: ${listOf(items.slice(0, k))}${more ? `, +${more} more` : ''}`;
    if (measure(line) <= width) return line;
  }
  const n = units(items);
  return `${label}: ${n} item${n === 1 ? '' : 's'}`;
}

/**
 * The goods in a few words, for a copy with no room for the lists even on one
 * line each: added to its terms, which then take no more room than the
 * standard "... checked and collected" line they replace.
 */
export function collectionSummary(c) {
  return `Goods: ${units(c.collected)} collected, ${units(c.toCollect)} to collect.`;
}

/** One line of the hand-over history, as the invoice shows it. */
export function historyLine(entry) {
  const items = entry?.items ?? [];
  if (entry?.kind === 'nothing_taken') return 'Nothing taken';
  if (entry?.kind === 'return') {
    const parts = items.map(i => {
      const bits = [i.good ? `${i.good} good` : '', i.damaged ? `${i.damaged} damaged` : '',
                    i.not_returned ? `${i.not_returned} not returned` : ''].filter(Boolean);
      return `${i.name ?? 'Item'}: ${bits.join(', ')}`;
    });
    return `Returned — ${parts.join('; ')}`;
  }
  return `Handed over ${items.map(i => `${i.name ?? 'Item'} × ${i.quantity}`).join(', ')}`;
}

/** How the history line says where it was recorded. */
export function historySource(entry) {
  return entry?.source === 'payment' ? 'with a payment'
    : entry?.source === 'button' ? 'Hand over items'
    : entry?.source === 'return' ? 'Record items returned' : '';
}

/** The Invoices list's badge for an invoice with goods out, or null. */
export function goodsOutBadge(qty) {
  const n = int(qty);
  if (n <= 0) return null;
  return { label: 'Goods out', title: `${n} item${n === 1 ? '' : 's'} handed over before full payment` };
}

/** The correction refusal's message without its machine prefix. */
export function goodsRefusal(message) {
  const m = String(message ?? '');
  return /^GOODS_HANDED_OVER:\s*/.test(m) ? m.replace(/^GOODS_HANDED_OVER:\s*/, '') : null;
}
