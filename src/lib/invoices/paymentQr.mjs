// Which QR image a payment method shows at the till (Owner, 6 Oct 2026).
//
// When staff choose PayNow, GrabPay or Atome on an invoice's Record Payment, a
// pop-up shows the store's own QR image (uploaded on the Stores page) for the
// customer to scan. Methods are matched by name, so "GrabPay Full Payment" and
// "Atome full payment" show the GrabPay and Atome images. Wallet credit never
// shows one, and neither does any other method.
//
// The image is the invoice's store's. A store without one borrows it from
// another active store, always the same one (the oldest, then by name), and the
// pop-up names that store. When no store has it there is nothing to show.

export const PAYMENT_QR_KINDS = Object.freeze([
  Object.freeze({ field: 'qr_paynow_url', match: 'paynow', label: 'PayNow' }),
  Object.freeze({ field: 'qr_grabpay_url', match: 'grabpay', label: 'GrabPay' }),
  Object.freeze({ field: 'qr_atome_url', match: 'atome', label: 'Atome' }),
]);

/** Lower case with spaces and punctuation gone, so "Pay Now" reads as "paynow". */
const squash = s => String(s ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');

/** The QR kind a payment method shows, or null for every other method. */
export function paymentQrKind(method) {
  if (!method || method.is_wallet_credit) return null;
  const name = squash(method.name);
  if (!name) return null;
  return PAYMENT_QR_KINDS.find(k => name.includes(k.match)) ?? null;
}

const usable = s => s && s.id && s.is_active !== false && !s.deleted_at;
const imageOf = (s, field) => String(s?.[field] ?? '').trim();

/**
 * The image for one kind: the invoice's own store's when it has one, else the
 * first other active store's that does, oldest first, then by name and id so
 * the answer never depends on the order the stores arrived in.
 */
export function paymentQrImage(field, storeId, stores) {
  if (!PAYMENT_QR_KINDS.some(k => k.field === field)) return null;
  const live = (stores ?? []).filter(usable);
  const own = storeId ? live.find(s => s.id === storeId) : undefined;
  if (own && imageOf(own, field)) {
    return { url: imageOf(own, field), storeId: own.id, storeName: String(own.name ?? ''), borrowed: false };
  }
  const made = s => { const t = Date.parse(s.created_at ?? ''); return Number.isNaN(t) ? Infinity : t; };
  const text = v => String(v ?? '').toLowerCase();
  const order = (a, b) => (made(a) - made(b))
    || (text(a.name) < text(b.name) ? -1 : text(a.name) > text(b.name) ? 1 : 0)
    || (String(a.id) < String(b.id) ? -1 : String(a.id) > String(b.id) ? 1 : 0);
  const other = live.filter(s => s.id !== storeId && imageOf(s, field)).sort(order)[0];
  return other
    ? { url: imageOf(other, field), storeId: other.id, storeName: String(other.name ?? ''), borrowed: true }
    : null;
}

/**
 * What the till shows for a method on an invoice of this store: null when the
 * method has no QR at all, otherwise its kind with the image to show (image is
 * null when no active store has one).
 */
export function paymentQrFor(method, storeId, stores) {
  const kind = paymentQrKind(method);
  if (!kind) return null;
  return { field: kind.field, label: kind.label, methodName: String(method.name ?? '').trim(),
           image: paymentQrImage(kind.field, storeId, stores) };
}

/** "S$1080.00" for a line's amount, as the rest of the page prints money, or null when none is entered. */
export function paymentQrAmount(amount) {
  const n = Number(amount);
  return Number.isFinite(n) && n > 0 ? `S$${n.toFixed(2)}` : null;
}
