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
//
// 547 (the Owner, 27 Nov 2026): and per special, consignment or rental line
// ("specials"): its units, Collected and Delivered as staff recorded them, out
// with the customer, and still to collect, on a paid invoice too. Staff of the
// invoice's store record Collected (the customer picked it up) or, for a
// consignment sale, Delivered (its supplier brought it to the customer); no
// stock moves: an Owner or Manager releases the item on Special & Rentals.
// "Record items returned" takes them back (Returned). In a pick, a special line
// is keyed "sp:<invoice line id>", and "how:<invoice line id>" is 1 for
// Delivered; in return entries, "sp:<invoice line id>" with its count in good.

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
      // 547: a special, consignment or rental item, by its invoice line.
      special: !!i.special, invoice_item_id: i.invoice_item_id ?? null, how: i.how ?? null, returned: int(i.returned),
    })),
  }));
  // 547: special, consignment and rental lines (absent before 547: none).
  const specials = (Array.isArray(data.specials) ? data.specials : []).map(p => ({
    invoice_item_id: String(p.invoice_item_id ?? ''),
    line_kind: p.line_kind === 'rental' ? 'rental' : 'special_product',
    special_product_id: p.special_product_id ?? null,
    name: String(p.name ?? 'Special product'),
    is_consignment: !!p.is_consignment, can_deliver: !!p.can_deliver,
    quantity: int(p.quantity), collected: int(p.collected), delivered: int(p.delivered),
    out: int(p.out), to_collect: int(p.to_collect),
  }));
  return {
    invoice_id: String(data.invoice_id ?? ''), invoice_no: String(data.invoice_no ?? ''),
    status: String(data.status ?? ''), store_id: data.store_id ?? null, store_name: data.store_name ?? null,
    open: !!data.open, fulfil_from_warehouse: !!data.fulfil_from_warehouse,
    required_total: int(data.required_total), collected_total: int(data.collected_total),
    to_collect_total: int(data.to_collect_total), out_total: int(data.out_total),
    can_hand_over: !!data.can_hand_over, can_record_return: !!data.can_record_return,
    products, history,
    specials, special_collected_total: int(data.special_collected_total),
    special_delivered_total: int(data.special_delivered_total), special_out_total: int(data.special_out_total),
    special_to_collect_total: int(data.special_to_collect_total),
    can_collect_special: !!data.can_collect_special, can_record_special_return: !!data.can_record_special_return,
  };
}

const SP = 'sp:';
const HOW = 'how:';

/** 547: the special, consignment and rental lines a customer can still collect now. */
export function collectableSpecials(goods) {
  return goods?.can_collect_special ? (goods?.specials ?? []).filter(p => p.to_collect > 0) : [];
}

/** 547: the special, consignment and rental lines out with the customer, to record as returned. */
export function returnableSpecials(goods) {
  return goods?.can_record_special_return ? (goods?.specials ?? []).filter(p => p.out > 0) : [];
}

/** 547: whether anything can be handed over or recorded as collected now. */
export function canHandOver(goods) {
  return !!goods && ((goods.can_hand_over && goods.to_collect_total > 0) || collectableSpecials(goods).length > 0);
}

/** 547: whether "Record items returned" has anything to take back. */
export function canRecordReturn(goods) {
  return !!goods && (goods.can_record_return || returnableSpecials(goods).length > 0);
}

/** 547: the pick with a special line's quantity set. */
export function setSpecialPick(pick, invoiceItemId, value) {
  return setPick(pick, SP + invoiceItemId, value);
}

/** 547: the pick with a consignment line's "how" set: 'collected' or 'delivered'. */
export function setSpecialHow(pick, invoiceItemId, how) {
  return { ...(pick ?? {}), [HOW + invoiceItemId]: how === 'delivered' ? 1 : 0 };
}

/** 547: how a special line was taken, as picked: 'delivered' or 'collected'. */
export function specialHow(pick, invoiceItemId) {
  return Number(pick?.[HOW + invoiceItemId] ?? 0) === 1 ? 'delivered' : 'collected';
}

/** 547: a special line's quantity as picked (0 when none). */
export function specialPicked(pick, invoiceItemId) {
  return Number(pick?.[SP + invoiceItemId] ?? 0) || 0;
}

/** 547: the special lines picked, in the goods' order, with their quantities and how. */
export function pickedSpecials(goods, pick) {
  return collectableSpecials(goods)
    .map(p => ({ special: p, qty: specialPicked(pick, p.invoice_item_id),
                 how: p.can_deliver ? specialHow(pick, p.invoice_item_id) : 'collected' }))
    .filter(x => x.qty !== 0);
}

/** The products a customer can still take now. */
export function collectable(goods) {
  return (goods?.products ?? []).filter(p => p.to_collect > 0);
}

/** 547: the products that may be handed over now: none once paid in full or fulfilled from a
 *  warehouse (can_hand_over), when only special items can be recorded. */
export function collectableProducts(goods) {
  return goods?.can_hand_over === false ? [] : collectable(goods);
}

/** The products out with the customer that can be recorded as returned. */
export function returnable(goods) {
  return (goods?.products ?? []).filter(p => p.out > 0);
}

/** 547: the products "Record items returned" may take back now: only before full payment
 *  (can_record_return); a paid invoice's go through Refund / Cancel, as 399. */
export function returnableProducts(goods) {
  return goods?.can_record_return === false ? [] : returnable(goods);
}

/**
 * Whether Record Payment must ask what the customer took: a part payment (more
 * than nothing, less than the balance) on an invoice whose goods may be handed
 * over now and that still has goods to collect. A full payment takes every
 * item, so it asks nothing; an invoice fulfilled from a warehouse hands over
 * nothing from the store.
 */
export function needsHandoverAnswer(goods, payTotal, outstanding) {
  // 547: special, consignment and rental items still to collect ask too.
  if (!canHandOver(goods)) return false;
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
  return collectableProducts(goods)
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
  for (const p of collectableProducts(goods)) {
    const raw = pick?.[p.product_id];
    if (raw === undefined || raw === null || raw === '') continue;
    const q = Number(raw);
    if (!Number.isFinite(q) || q < 0 || q !== Math.trunc(q)) return `Enter a whole number for ${p.name}.`;
    if (q > p.to_collect) return `Only ${p.to_collect} of ${p.name} ${p.to_collect === 1 ? 'is' : 'are'} still to collect.`;
    if (q > p.in_store) {
      return `Only ${p.in_store} of ${p.name} ${p.in_store === 1 ? 'is' : 'are'} in ${goods?.store_name || 'the store'} now.`;
    }
  }
  // 547: special, consignment and rental lines: no store stock to check (they leave a warehouse,
  // a store or a supplier when an Owner or Manager releases them).
  for (const p of collectableSpecials(goods)) {
    const raw = pick?.[SP + p.invoice_item_id];
    if (raw === undefined || raw === null || raw === '') continue;
    const q = Number(raw);
    if (!Number.isFinite(q) || q < 0 || q !== Math.trunc(q)) return `Enter a whole number for ${p.name}.`;
    if (q > p.to_collect) return `Only ${p.to_collect} of ${p.name} ${p.to_collect === 1 ? 'is' : 'are'} still to collect.`;
    if (p.line_kind === 'rental' && q > 0 && q !== p.to_collect && p.to_collect === p.quantity) {
      return `A rental is collected whole: enter all ${p.to_collect} of ${p.name}.`;
    }
  }
  if (pickedItems(goods, pick).length === 0 && pickedSpecials(goods, pick).length === 0) {
    return button
      ? 'Enter how many of at least one item the customer takes.'
      : 'Enter how many of at least one item the customer took, or choose "Nothing taken".';
  }
  return null;
}

/** The answer as record_invoice_settlement's payload.handover (or the button's p_handover). */
export function handoverPayload(goods, answer, pick) {
  if (answer === 'none') return { none: true };
  const out = { items: pickedItems(goods, pick).map(x => ({ product_id: x.product.product_id, qty: x.qty })) };
  // 547: the special, consignment and rental items, only when there are any (a products-only
  // answer is sent exactly as before).
  const specials = pickedSpecials(goods, pick)
    .map(x => ({ invoice_item_id: x.special.invoice_item_id, qty: x.qty, how: x.how }));
  return specials.length ? { ...out, specials } : out;
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

/** 547: the entry with a special line's returned count set. */
export function setSpecialReturn(entries, invoiceItemId, value) {
  return setReturn(entries, SP + invoiceItemId, 'good', value);
}

/** 547: a special line's returned count as entered (0 when none). */
export function specialReturned(entries, invoiceItemId) {
  return Number(entries?.[SP + invoiceItemId]?.good ?? 0) || 0;
}

/** What is wrong with "Record items returned", or null. */
export function returnProblem(goods, entries, reason) {
  let any = false;
  for (const p of returnableSpecials(goods)) {
    const q = Number(entries?.[SP + p.invoice_item_id]?.good ?? 0);
    if (!Number.isFinite(q) || q < 0 || q !== Math.trunc(q)) return `Enter a whole number for ${p.name}.`;
    if (q > p.out) return `Only ${p.out} of ${p.name} ${p.out === 1 ? 'is' : 'are'} out with the customer.`;
    if (q > 0) any = true;
  }
  for (const p of returnableProducts(goods)) {
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
  return [
    ...returnableProducts(goods)
      .map(p => {
        const row = entries?.[p.product_id] ?? {};
        return { product_id: p.product_id, good: Number(row.good ?? 0) || 0, damaged: Number(row.damaged ?? 0) || 0,
                 not_returned: Number(row.not_returned ?? 0) || 0 };
      })
      .filter(r => r.good + r.damaged + r.not_returned > 0),
    // 547: the special, consignment and rental items that came back.
    ...returnableSpecials(goods)
      .map(p => ({ invoice_item_id: p.invoice_item_id, returned: specialReturned(entries, p.invoice_item_id) }))
      .filter(r => r.returned > 0),
  ];
}

const listOf = rows => rows.map(r => `${r.name} × ${r.qty}`).join(', ');

/** Collected, delivered and to-collect lists for the copies, from the goods. */
export function collectionLists(goods) {
  const products = (goods?.products ?? []).filter(p => p.required > 0);
  // 547: and the special, consignment and rental lines.
  const specials = goods?.specials ?? [];
  const delivered = specials.filter(p => p.delivered > 0).map(p => ({ name: p.name, qty: p.delivered }));
  return {
    collected: [...products.filter(p => p.collected > 0).map(p => ({ name: p.name, qty: p.collected })),
                ...specials.filter(p => p.collected > 0).map(p => ({ name: p.name, qty: p.collected }))],
    // Only when a supplier delivered something: a copy without it is as before 547.
    ...(delivered.length ? { delivered } : {}),
    toCollect: [...products.filter(p => p.to_collect > 0).map(p => ({ name: p.name, qty: p.to_collect })),
                ...specials.filter(p => p.to_collect > 0).map(p => ({ name: p.name, qty: p.to_collect }))],
  };
}

const NOT_REFUNDABLE = 'Goods and services sold are neither refundable nor exchangeable.';
const OPEN_STATUSES = ['draft', 'unpaid', 'partially_paid'];
const SETTLED_STATUSES = ['paid', 'completed_foc'];

/** 547: a paid invoice with a special, consignment or rental item still to collect (answer 6). */
function settledWithSpecialsToCollect(status, goods) {
  return SETTLED_STATUSES.includes(String(status ?? '')) && !!goods && (goods.special_to_collect_total ?? 0) > 0;
}

/** 547: the statuses whose copies read the goods: before full payment, and paid (for special items). */
export function copyReadsGoods(status) {
  return OPEN_STATUSES.includes(String(status ?? '')) || SETTLED_STATUSES.includes(String(status ?? ''));
}

/**
 * The terms line of a copy (print, PDF, image, WhatsApp, email). A fully paid
 * invoice keeps the standard line (undefined: the copy's own default, "...
 * have been checked and collected"). An unpaid or part-paid one never says
 * everything was collected: its terms stop at "neither refundable nor
 * exchangeable", and its goods are listed instead (copyCollectionLines).
 * Other statuses keep the standard line, as before.
 */
export function copyTermsText(status, goods) {
  // 547: nor does a paid one with a special, consignment or rental item still to collect.
  return OPEN_STATUSES.includes(String(status ?? '')) || settledWithSpecialsToCollect(status, goods) ? NOT_REFUNDABLE : undefined;
}

/**
 * An unpaid or part-paid copy's goods as lists, { collected, toCollect }.
 * Null once paid in full, for other statuses, and when the invoice has no
 * goods or they could not be read (the copy then says nothing about
 * collection).
 */
export function copyCollection(status, goods) {
  // 547: a paid invoice lists its goods too while a special item is still to collect.
  if ((!OPEN_STATUSES.includes(String(status ?? '')) && !settledWithSpecialsToCollect(status, goods)) || !goods) return null;
  const lists = collectionLists(goods);
  return lists.collected.length + (lists.delivered ?? []).length + lists.toCollect.length === 0 ? null : lists;
}

/** The lists in full: "Collected: …" and "To collect: …" (each "none" when empty). */
export function collectionText(c) {
  // 547: "Delivered: …" only when a supplier delivered something.
  return [`Collected: ${c.collected.length ? listOf(c.collected) : 'none'}`,
          ...((c.delivered ?? []).length ? [`Delivered: ${listOf(c.delivered)}`] : []),
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
  const delivered = units(c.delivered ?? []);
  return `Goods: ${units(c.collected)} collected, ${delivered ? `${delivered} delivered, ` : ''}${units(c.toCollect)} to collect.`;
}

/** One line of the hand-over history, as the invoice shows it. */
export function historyLine(entry) {
  const items = entry?.items ?? [];
  if (entry?.kind === 'nothing_taken') return 'Nothing taken';
  if (entry?.kind === 'return') {
    const parts = items.map(i => {
      if (i.special) return `${i.name ?? 'Item'}: ${i.returned} returned`;  // 547
      const bits = [i.good ? `${i.good} good` : '', i.damaged ? `${i.damaged} damaged` : '',
                    i.not_returned ? `${i.not_returned} not returned` : ''].filter(Boolean);
      return `${i.name ?? 'Item'}: ${bits.join(', ')}`;
    });
    return `Returned — ${parts.join('; ')}`;
  }
  // 547 (the Owner's words): products "Handed over", as 399; special, consignment and rental
  // items "Collected", or "Delivered" when their supplier brought them.
  const list = rows => rows.map(i => `${i.name ?? 'Item'} × ${i.quantity}`).join(', ');
  const products = items.filter(i => !i.special);
  const collected = items.filter(i => i.special && i.how !== 'delivered');
  const delivered = items.filter(i => i.special && i.how === 'delivered');
  return [products.length ? `Handed over ${list(products)}` : '',
          collected.length ? `Collected ${list(collected)}` : '',
          delivered.length ? `Delivered ${list(delivered)}` : '']
    .filter(Boolean).join('; ');
}

/** How the history line says where it was recorded. 547: a button entry of special items alone,
 *  on an invoice whose products can no longer be handed over (paid, say), was recorded with the
 *  button the invoice shows then, "Record items collected"; `goods` is the invoice's goods. */
export function historySource(entry, goods) {
  const onlySpecial = (entry?.items ?? []).length > 0 && (entry?.items ?? []).every(i => i.special);
  return entry?.source === 'payment' ? 'with a payment'
    : entry?.source === 'button' ? (onlySpecial && goods && !goods.can_hand_over ? 'Record items collected' : 'Hand over items')
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
