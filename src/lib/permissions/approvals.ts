/**
 * Who may approve what, as migration 533 decides it in the database (security
 * audit of 17 Nov 2026, finding M9; the user's decisions of 20 Nov 2026).
 * The pages use these only to show, hide or disable a button and to say why;
 * the database checks every change again and its message is still shown when
 * a refusal gets through (another tab, stale data).
 *
 *   1. A Manager does not approve a request they made themselves (a transfer,
 *      a stock correction, a refund or cancellation request), and does not
 *      resolve the discrepancy of a transfer they received themselves. An
 *      Owner or another Manager does. Owners still approve their own. A
 *      Manager may still reject or withdraw their own request.
 *   2. A Manager approves, reviews or rejects a transfer, resolves its
 *      discrepancy, or approves a stock correction only when every STORE
 *      involved is one they work at. Warehouses stay open to every Manager;
 *      an Owner gets every store.
 *   3. Only an Owner adds or removes a customer's credit by hand and records
 *      or corrects an affiliate payout.
 *   4. A Manager takes money back on an invoice, by a refund or by lowering a
 *      recorded payment, only while the two together, this change included,
 *      stay at or under S$1,000 (the user, 20 Nov 2026, later the same day).
 *   5. Owners only (the user, 20 Nov 2026): making a credit package or premium
 *      bundle line free (see canGiveFocOn in lib/invoices/business.ts), moving
 *      unused credit or vouchers to another customer, and recording or voiding
 *      an affiliate repayment.
 *   6. A Manager cannot approve a transfer request they edited, nor add lines
 *      or raise a quantity above the request while approving one.
 */
import type { UserRole } from '../../types';

/** 533 (M9, the user's decision of 20 Nov 2026): the most a Manager refunds on one invoice. */
export const MANAGER_REFUND_CAP = 1000;

/** 533 (M9): the sentences the database refuses with (code 42501). The pages
 *  say these, or a shorter one of the same meaning. */
export const APPROVAL_MESSAGES = {
  ownTransfer: 'A Manager cannot approve their own transfer request. An Owner or another Manager approves it.',
  ownCorrection: 'A Manager cannot approve their own stock correction. An Owner or another Manager approves it.',
  ownInvoiceRequest: 'A Manager cannot approve their own request. An Owner or another Manager approves it.',
  ownReceipt: 'A Manager cannot resolve a transfer they received themselves. An Owner or another Manager resolves it.',
  otherStore: 'A Manager approves only for the stores they work at.',
  creditOwnerOnly: 'Only an Owner can add or remove credit by hand.',
  payoutOwnerOnly: 'Only an Owner can record or correct an affiliate payout.',
  walletChangeOwnerOnly: 'Only an Owner can change a payment into or out of wallet credit.',
  refundCap: 'A Manager can take back up to S$1,000 on an invoice, refunds and lowered payments together; an Owner does anything above that.',
  focOwnerOnly: 'Only an Owner can make a credit package or premium bundle line free.',
  moveCreditOwnerOnly: 'Only an Owner can move unused credit or vouchers to another customer.',
  repaymentOwnerOnly: 'Only an Owner can record or void an affiliate repayment.',
  editedTransfer: 'A Manager who changed this transfer request cannot also approve it. An Owner or another Manager approves it.',
  raisedTransfer: 'A Manager cannot add lines or raise quantities while approving a transfer. An Owner or another Manager approves such a change.',
} as const;

/** Shorter notes for beside a disabled button. */
export const APPROVAL_NOTES = {
  ownRequest: 'Your own request: an Owner or another Manager approves it.',
  ownReceipt: 'You received this transfer: an Owner or another Manager resolves it.',
  otherStore: 'Not one of your stores: an Owner or a Manager who works there decides this.',
} as const;

const isManager = (r?: UserRole | null) => r === 'manager';

/** 533 (M9, 20 Nov 2026) rule 1: whether the signed-in person made the request. */
export const isOwnRequest = (requestedBy?: string | null, userId?: string | null): boolean =>
  !!requestedBy && !!userId && requestedBy === userId;

/** 533 (M9, 20 Nov 2026) rule 1: a Manager does not approve a request they
 *  made. Owners do; no other role approves. Rejecting and withdrawing are not
 *  covered by this. An unknown requester is allowed here: the server decides. */
export const canApproveOwnRequest = (role?: UserRole | null, requestedBy?: string | null, userId?: string | null): boolean =>
  role === 'owner' || (isManager(role) && !isOwnRequest(requestedBy, userId));

/** 533 (M9, 20 Nov 2026) rule 1: a Manager does not resolve the discrepancy
 *  of a transfer they received themselves. */
export const canResolveReceivedTransfer = (role?: UserRole | null, receivedBy?: string | null, userId?: string | null): boolean =>
  role === 'owner' || (isManager(role) && !isOwnRequest(receivedBy, userId));

/** 533 (M9, 20 Nov 2026) rule 2: the stores (never warehouses) a transfer touches. */
export function transferStoreIds(t: { source_type?: string | null; source_id?: string | null; dest_type?: string | null; dest_id?: string | null }): string[] {
  const ids: string[] = [];
  if (t.source_type === 'store' && t.source_id) ids.push(t.source_id);
  if (t.dest_type === 'store' && t.dest_id) ids.push(t.dest_id);
  return ids;
}

/** 533 (M9, 20 Nov 2026) rule 2: the store a stock correction is at, if it is at a store. */
export const adjustmentStoreIds = (p?: { location_type?: string | null; location_id?: string | null } | null): string[] =>
  p?.location_type === 'store' && p.location_id ? [p.location_id] : [];

/** 533 (M9, 20 Nov 2026) rule 2: a Manager works at every store listed (an
 *  empty list, such as a warehouse-only transfer, is open). Owners get every
 *  store. Any other role is not asked here. */
export const worksAtStores = (role: UserRole | null | undefined, storeIds: string[], myStoreIds: string[]): boolean =>
  role === 'owner' || (isManager(role) && storeIds.every(id => myStoreIds.includes(id)));

/** 533 (M9, 20 Nov 2026) rule 3: adding or removing customer credit by hand
 *  (adjust_customer_credit, add_legacy_credit). Managers still see credit. */
export const canAdjustCreditByHand = (role?: UserRole | null): boolean => role === 'owner';

/** 533 (M9, 20 Nov 2026) rule 3: recording or correcting an affiliate payout. */
export const canRecordAffiliatePayout = (role?: UserRole | null): boolean => role === 'owner';

const toCents = (n: unknown) => Math.round((Number(n) || 0) * 100);

/** 533 (M9, 20 Nov 2026) rule 4: whether this refund, added to what the
 *  invoice has already had refunded, is within what the person may refund.
 *  An Owner has no cap; a Manager stops above S$1,000 in total (exactly
 *  S$1,000 is allowed). Worked in cents so S$1,000.01 is never rounded away. */
export const refundWithinRole = (role: UserRole | null | undefined, alreadyRefunded: unknown, thisRefund: unknown): boolean =>
  role === 'owner' || (isManager(role) && toCents(alreadyRefunded) + toCents(thisRefund) <= MANAGER_REFUND_CAP * 100);

/** 533 (M9, 20 Nov 2026) rule 5: moving unused credit or vouchers to another customer. */
export const canMoveUnusedCredit = (role?: UserRole | null): boolean => role === 'owner';

/** 533 (M9, 20 Nov 2026) rule 5: recording or voiding an affiliate repayment (a deduction settlement). */
export const canRecordAffiliateRepayment = (role?: UserRole | null): boolean => role === 'owner';

/** 533 (M9, 20 Nov 2026) rule 4: how much recorded payments on an invoice have been lowered by
 *  corrections so far, counted as the database does (invoice_payment_lowered_by): for each
 *  payment that has a reversal row, the reversal's amount (stored positive, the original's) minus
 *  the SUM of all its replacement rows (a split's parts together), floored at 0. A removal (a
 *  reversal with no replacement) counts in full; a split that keeps its total counts 0; a raise
 *  on one payment never offsets a reduction on another. The database's own total decides. */
export function loweredPaymentsTotal(payments: { id: string; amount: unknown; entry_kind?: string | null; corrects_payment_id?: string | null }[] | null | undefined): number {
  const reversed = new Map<string, number>();
  const replaced = new Map<string, number>();
  for (const p of payments ?? []) {
    if (!p.corrects_payment_id) continue;
    const into = p.entry_kind === 'correction_reversal' ? reversed : p.entry_kind === 'correction_replacement' ? replaced : null;
    if (into) into.set(p.corrects_payment_id, (into.get(p.corrects_payment_id) ?? 0) + toCents(p.amount));
  }
  let cents = 0;
  for (const [id, was] of reversed) cents += Math.max(0, was - (replaced.get(id) ?? 0));
  return cents / 100;
}

/** 533 (M9, 20 Nov 2026) rule 6: a Manager who edited the request (any edit by them) does not approve it. */
export const canApproveEditedTransfer = (role: UserRole | null | undefined, editedBy?: string | null, userId?: string | null): boolean =>
  role === 'owner' || (isManager(role) && !isOwnRequest(editedBy, userId));

/** 533 (M9, 20 Nov 2026) rule 6: whether a review adds a line or approves above what was
 *  requested (added lines carry no requested quantity). A Manager's review may not. */
export const reviewRaisesRequest = (lines: { line_id?: string | null; requested_quantity?: number | null; approved_quantity?: number | null; added_by_approver?: boolean }[]): boolean =>
  lines.some(l => !!l.added_by_approver || !l.line_id || Number(l.approved_quantity ?? 0) > Number(l.requested_quantity ?? 0));

/** 533 (M9, 20 Nov 2026) rule 4: the drop in an invoice's recorded payments an Edit Invoice save
 *  would make: a removed payment in full, a split or corrected one by what it falls short of its
 *  old amount (a rise counts for nothing). */
export function paymentDropOf(
  payments: { id: string; amount: unknown }[],
  edits: Record<string, { remove?: boolean; parts: { amount: unknown }[] } | undefined>,
): number {
  let cents = 0;
  for (const p of payments) {
    const e = edits[p.id];
    if (!e) continue;
    const now = e.remove ? 0 : e.parts.reduce((s, x) => s + toCents(x.amount), 0);
    cents += Math.max(0, toCents(p.amount) - now);
  }
  return cents / 100;
}

/** 533 (M9, 20 Nov 2026, the user): only an Owner changes a recorded payment into or out of wallet
 *  credit. Of the methods listed, the ones a person may correct the payment to: an Owner (or any
 *  role the page does not limit) gets all; a Manager gets only methods on the same side of the
 *  wallet line as the payment's own method, so PayNow to NETS is fine and cash to wallet is not.
 *  The database refuses the rest with APPROVAL_MESSAGES.walletChangeOwnerOnly. */
export function methodsAllowedForPayment<M extends { id: string; is_wallet_credit?: boolean | null }>(
  role: UserRole | null | undefined, methods: M[], originalMethodId?: string | null,
): M[] {
  if (!isManager(role)) return methods;
  const original = methods.find(m => m.id === originalMethodId);
  if (!original) return methods;
  return methods.filter(m => !!m.is_wallet_credit === !!original.is_wallet_credit);
}
