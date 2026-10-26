import React, { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';
// The popup's own styles. Approvals opens it from a separate page bundle, so it
// cannot rely on the invoices page having loaded them first.
import './invoice-controls.css';
import { useWaitingItems, WaitingItemsQuestion } from './WaitingItemsQuestion';
import { type WaitingAnswers, unansweredItems, waitingAnswerList, waitingAnswersOf, waitingItemLabel,
  withWaitingAnswers } from '../../lib/special/waitingItems';
import { rentalOutDoneNote, rentalOutReviewNote } from '../../lib/special/rentalFollows';
import { type AwaitingRental, type ReceiveChoice, NOT_BACK_YET, receiveHomeLabel, receiveRpcArgs,
  receivedChoices, receivedText, rentalsToReceive } from '../../lib/special/rentalReturn';

const money = (n: unknown) => `S$${Number(n || 0).toFixed(2)}`;
const actionWords = (a?: string | null) =>
  a === 'cancel' ? 'cancellation' : a === 'refund_partial' ? 'partial refund' : 'full refund';

/** What moved between the plan a request was raised with and the plan now, in
 *  words. The server only says "changed"; the approver needs to know what. */
function planChanges(asked: Plan | null | undefined, now: Plan | null | undefined): string[] {
  if (!asked || !now) return [];
  const out: string[] = [];
  // A cancellation's figure is the refund due; a refund's is the amount returned.
  const cancel = now.action === 'cancel';
  const fig = (p: Plan) => Number((cancel ? p.refund_due : p.refund_amount) || 0);
  if (fig(asked).toFixed(2) !== fig(now).toFixed(2))
    out.push(`the ${cancel ? 'refund due' : 'amount'} is now ${money(fig(now))} rather than ${money(fig(asked))}`);
  const stockKey = (p: Plan) => (p.stock ?? []).map(s => `${s.movement_id}:${s.outstanding}:${s.proposed_sellable}`).sort().join('|');
  if (stockKey(asked) !== stockKey(now)) {
    const a = (asked.stock ?? []).length, b = (now.stock ?? []).length;
    out.push(a === b ? 'the stock to take back is different'
      : `the stock to take back is now ${b} item line${b === 1 ? '' : 's'} rather than ${a}`);
  }
  const srcKey = (p: Plan) => (p.sources ?? []).map(s => `${s.payment_id}:${Number(s.amount || 0).toFixed(2)}`).sort().join('|');
  if (srcKey(asked) !== srcKey(now)) out.push('the payments the money goes back to are different');
  const overKey = (p: Plan) => (p.overrides_required ?? []).map(o => o.code).sort().join('|');
  if (overKey(asked) !== overKey(now)) out.push('what needs an override is different');
  const lineKey = (p: Plan) => (p.lines ?? []).map(l => `${l.invoice_item_id}:${l.selected_quantity}`).sort().join('|');
  if (lineKey(asked) !== lineKey(now)) out.push('the items it covers are different');
  return out;
}
/** 2026-09-12 -> 12 Sep 2026. Falls back to whatever it was given. */
const readableDate = (iso?: string | null) => {
  if (!iso) return '';
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) return iso;
  const month = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][Number(m[2]) - 1];
  return `${Number(m[3])} ${month} ${m[1]}`;
};
/** A timestamp as its Singapore calendar day, e.g. 9 Oct 2026. */
const sgDay = (ts?: string | null) => {
  if (!ts) return '';
  const d = new Date(ts);
  if (!Number.isFinite(d.getTime())) return '';
  return readableDate(new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d));
};

type Action = 'cancel' | 'refund_full' | 'refund_partial';
type PlanLine = { invoice_item_id: string; name: string; line_kind: string; quantity: number; selected_quantity: number; amount: number };
type PlanStock = { movement_id: string; product_name: string; store_name?: string; outstanding: number; proposed_sellable: number };
type Plan = {
  invoice_no: string; action: Action; refund_amount: number; refund_due: number;
  window: { created_on: string; deadline: string; within: boolean; days_remaining: number; override_required: boolean; creation_reliable: boolean; review_note?: string };
  lines: PlanLine[]; stock: PlanStock[]; sources: { payment_id: string; method: string; wallet: boolean; amount: number }[];
  overrides_required: { code: string; message: string; amount_required?: boolean; default_amount?: number | null; invoice_item_id?: string }[];
  blockers: { code: string; message: string }[];
  summary: string[]; requires_override: boolean; blocked: boolean; plan_hash: string;
  status?: string;
  /** The money the invoice holds now (invoice_net_received). */
  net_held?: number;
  /** 417 (the Owner, 9 Oct 2026): a cancellation whose customer already had
   *  part of what it sold. Not all the money held is owed back: the Owner or
   *  Manager states how much is. Null when nothing was used. */
  refund_owed?: { needed: boolean; held: number; used: string[]; message: string } | null;
  /** Money, credits, stock and overrides kept apart — the review renders these
   *  rather than inferring one quantity from another. */
  effects?: {
    money_returned: { total: number; destinations: { payment_id: string; method: string; wallet: boolean; amount: number }[] };
    benefits: { kind: string; holder?: string; credit_removed?: number | null; units_revoked?: number | null; accounting_value?: number; line?: string }[];
    stock_returned: PlanStock[];
    overrides: { code: string; message: string }[];
    /** Therapy a promotion granted, closed with its line (363). A used unit
     *  ends only on the override that states the amount. */
    therapy_closed?: { entitlement_no: string; package?: string; used: boolean; benefit?: string | null; line?: string }[];
    /** Used therapy on no invoice line (a correction removed it), which the action leaves running. */
    therapy_left?: { entitlement_no: string; package?: string; line?: string }[];
    /** 417: a credit package's reward entitlements, settled with this action:
     *  those not claimed yet are withdrawn, those already activated or claimed
     *  stay with the customer. */
    rewards?: { withdrawn: string[]; kept: string[] };
  };
};
/** invoice_request_status (417): the request waiting on this invoice, or the last one.
 *  It never carries the requester's own reason; approvers read that in the request. */
type RequestStatus = {
  invoice_id: string; pending: boolean; can_review?: boolean;
  request: null | { request_id: string; status: string; action: string; requested_by?: string | null;
    requested_at?: string | null; resolved_by?: string | null; resolved_at?: string | null;
    rejection_reason?: string | null; legacy?: boolean };
};

/**
 * The guided refund/cancellation flow.
 *
 * Staff choose what happened, not which ledger rows to touch: the plan — the
 * amount, the payment sources, the stock to take back, the vouchers,
 * entitlements and credits to reverse — is derived on the server from the
 * original invoice's own evidence and shown back in plain words.
 *
 * Four things are kept visibly apart, because they are four different events:
 * the request being submitted, the request being approved, money going back,
 * and goods coming back.
 */
export function InvoiceGuidedAction({ invoiceId, canApprove, onDone, onClose, requestId: reviewRequestId, paymentLabel }: {
  invoiceId: string; canApprove: boolean; onDone: () => Promise<void> | void; onClose: () => void;
  /** Approval mode: review an existing request instead of raising a new one.
   *  The same steps, plan, stock confirmation and override fields are reused,
   *  so an approval from Approvals and one from the invoice cannot diverge. */
  requestId?: string;
  /** 443: a payment's method as the invoice shows it, with where a wallet
   *  payment's credit came from, e.g. 'Wallet — Paid Credit (Premium Bundle)',
   *  so the review names the credit it gives back as the invoice does.
   *  Without it (Approvals), the method's name. */
  paymentLabel?: (paymentId: string, fallback: string) => string;
}) {
  const [step, setStep] = useState<1 | 2 | 3 | 4>(1);
  const [action, setAction] = useState<Action | null>(null);
  const [quantities, setQuantities] = useState<Record<string, number>>({});
  const [reason, setReason] = useState('');
  const [returnNotes, setReturnNotes] = useState('');
  const [plan, setPlan] = useState<Plan | null>(null);
  const [stockConfirm, setStockConfirm] = useState<Record<string, { sellable_quantity: number; damaged_quantity: number; not_returned_quantity: number }>>({});
  const [overrideReasons, setOverrideReasons] = useState<Record<string, string>>({});
  // Some overrides carry an amount the Owner/Manager states — terminating
  // therapy that has started, or a package whose vouchers were collected, has
  // no valuation rule, so the server refuses the override without one.
  const [overrideAmounts, setOverrideAmounts] = useState<Record<string, string>>({});
  /** One override's own key: an override that names its line is that line's
   *  alone, so two lines needing the same override each get their own reason
   *  and amount (the server matches them by line, 363 and 417). */
  const overrideKey = (o: Plan['overrides_required'][number]) =>
    o.invoice_item_id ? `${o.code}:${o.invoice_item_id}` : o.code;
  /** The line an override belongs to, by name, for its labels. */
  const overrideLine = (o: Plan['overrides_required'][number]) =>
    o.invoice_item_id ? plan?.lines.find(l => l.invoice_item_id === o.invoice_item_id)?.name : undefined;
  /** The amount box for one override: what was typed, else the plan's figure. */
  const typedAmount = (o: Plan['overrides_required'][number]) =>
    overrideAmounts[overrideKey(o)] ?? (o.default_amount != null ? String(o.default_amount) : '');
  const amountOverrides = (plan?.overrides_required ?? []).filter(o => o.amount_required);
  // Two amounts under one key cannot be told apart (an override that names no
  // line); those lines are refunded one at a time (Partial refund) instead.
  const sharedAmountKey = amountOverrides.some((o, i) => amountOverrides.findIndex(x => overrideKey(x) === overrideKey(o)) !== i);
  const amountProblem = (() => {
    if (sharedAmountKey) return 'More than one line on this invoice needs an amount stated by an Owner or Manager. Refund those lines one at a time with Partial refund, so each gets its own amount.';
    for (const o of amountOverrides) {
      const t = typedAmount(o).trim();
      const n = Number(t);
      if (t === '' || !Number.isFinite(n) || n < 0) return 'Enter the amount to refund (S$0 or more) for each override that asks for one.';
    }
    // Every override needs its reason, including those that take no amount.
    if ((plan?.overrides_required ?? []).some(o => !(overrideReasons[overrideKey(o)] ?? '').trim()))
      return 'Give a reason for each override.';
    return null;
  })();
  /** The action the plan on screen is for. The label, the refund tick and the
   *  review follow it, never a choice the plan has not caught up with. */
  const planAction: Action | null = plan?.action ?? action;
  /** What the plan returns: a refund's amount, or on a cancellation the refund due. */
  const planFigure = Number((planAction === 'cancel' ? plan?.refund_due : plan?.refund_amount) ?? 0);
  /** What will actually be refunded: the plan, with each stated amount in place of its line's figure. */
  const statedRefund = (() => {
    const base = planFigure;
    if (!amountOverrides.length || sharedAmountKey) return base;
    return amountOverrides.reduce((sum, o) => sum - Number(o.default_amount ?? 0) + (Number(typedAmount(o)) || 0), base);
  })();
  const [recordRefund, setRecordRefund] = useState(false);
  // 417 (the Owner, 9 Oct 2026): on a cancellation whose customer already had
  // part of it, the Owner or Manager states how much is owed back when the
  // money is not paid back now. It starts at the figure the review works out.
  const [owedText, setOwedText] = useState<string | null>(null);
  const owedNeeded = canApprove && planAction === 'cancel' && !!plan?.refund_owed?.needed && !recordRefund;
  const owedValue = owedText ?? (Math.round(Math.max(statedRefund, 0) * 100) / 100).toFixed(2);
  const owedProblem = (() => {
    if (!owedNeeded) return null;
    const n = Number(owedValue.trim());
    if (owedValue.trim() === '' || !Number.isFinite(n) || n < 0) return 'Enter how much is owed back to the customer (S$0 or more).';
    const held = Number(plan?.refund_owed?.held ?? plan?.net_held ?? Infinity);
    if (n > held + 0.004) return `That is more than the ${money(held)} this invoice holds.`;
    return null;
  })();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState<string>('');
  // A request ID names one request. It is renewed when a request this window
  // raised is withdrawn for a different choice (417, AFTER-M2).
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  /** The request this window raised, while it is still waiting (its approval
   *  failed or asked for confirmation). Choosing something else withdraws it. */
  const [ownRequest, setOwnRequest] = useState<{ id: string; action: Action; lines: string } | null>(null);
  // 417: a request already waiting on this invoice. An Owner or Manager reviews
  // it here; anyone else is told it is waiting.
  const [foundReviewId, setFoundReviewId] = useState<string | null>(null);
  const [waitingRequest, setWaitingRequest] = useState<RequestStatus['request']>(null);
  const activeReviewId = reviewRequestId ?? foundReviewId ?? undefined;
  const reviewing = Boolean(activeReviewId);
  const reviewingRef = useRef(reviewing);
  reviewingRef.current = reviewing;
  const [detail, setDetail] = useState<any>(null);
  const [rejecting, setRejecting] = useState(false);
  // 417 (AFTER-14): the approver's own note, empty until they write one. It is
  // the reason given for a rejection and the note kept with an approval. The
  // requester's reason is shown, not reused.
  const [approverNote, setApproverNote] = useState('');
  // A refresh that fails after a successful save must never look like a failed
  // save, and retrying it must never resubmit the action.
  const [refreshFailed, setRefreshFailed] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  // 417 (AFTER-7): rentals the finished action left with the customer.
  // Receiving one is its own confirmed event, recorded only when the item is
  // actually back: every item starts as "Not back yet".
  const [toReceive, setToReceive] = useState<AwaitingRental[]>([]);
  const [receiveChoice, setReceiveChoice] = useState<Record<string, ReceiveChoice>>({});
  const [receivedNotes, setReceivedNotes] = useState<string[]>([]);
  const [receiveError, setReceiveError] = useState('');
  const [warehouses, setWarehouses] = useState<{ id: string; name: string }[]>([]);
  const [approvedRequestId, setApprovedRequestId] = useState<string | null>(null);
  // 393: special products and rentals still waiting for a warehouse. A partial
  // refund asks, for each, whether the customer is still taking it; the
  // answers go with the request and are honoured when it is approved.
  const waitingItems = useWaitingItems(invoiceId);
  const [waitingAnswers, setWaitingAnswers] = useState<WaitingAnswers>({});
  // What a full refund would take back now. A partial refund that takes back
  // all of it closes the invoice, which cancels every waiting item whatever
  // was answered, so it is not asked about and the review says so.
  const [fullPlan, setFullPlan] = useState<Plan | null>(null);
  /** The plan the header describes: the one worked out last, or the first. */
  const shownPlan = plan ?? fullPlan;
  const coversWholeInvoice = (() => {
    if (action !== 'refund_partial' || !fullPlan?.lines?.length) return false;
    // Choosing: every line still refundable, at its full quantity.
    if (step <= 2 || plan?.action !== 'refund_partial')
      return fullPlan.lines.every(f => (quantities[f.invoice_item_id] ?? 0) >= f.quantity);
    // Worked out: each of those lines' whole remaining amount.
    return fullPlan.lines.every(f => {
      const l = plan.lines.find(x => x.invoice_item_id === f.invoice_item_id);
      return !!l && Number(l.amount) >= Number(f.amount) - 0.005;
    });
  })();
  const waitingLeft = coversWholeInvoice ? [] : unansweredItems(waitingItems, waitingAnswers);
  // 409: nothing a refund could return (an unpaid invoice, which staff can now
  // open this on too, or one whose lines have nothing refundable, like a
  // part-paid bundle that has released nothing): a refund request could never
  // be approved, so only a cancellation is offered. Money may still be held,
  // and the message says so rather than that nothing is held.
  const nothingToRefund = !reviewing && !!fullPlan && !fullPlan.blocked && Number(fullPlan.refund_amount ?? 0) <= 0;
  const heldNow = Number(fullPlan?.net_held ?? 0);
  // Each line's name as any plan gave it: a partial refund's plan lists only
  // the lines chosen, but a machine is still known by its own line's name.
  const [lineNames, setLineNames] = useState<Record<string, string>>({});
  useEffect(() => {
    const lines = [...(fullPlan?.lines ?? []), ...(plan?.lines ?? [])];
    if (lines.length) setLineNames(n => ({ ...n, ...Object.fromEntries(lines.map(l => [l.invoice_item_id, l.name])) }));
  }, [plan, fullPlan]);
  const lineName = (id: string) => lineNames[id];
  const dialog = useRef<HTMLDivElement>(null);
  const opener = useRef<Element | null>(null);
  // Kept in a ref so the key handler, bound once, always sees the current one.
  const closeRef = useRef<() => void>(() => onClose());

  // Keyboard and screen-reader behaviour: trap Tab, close on Escape, and put
  // focus back where it came from.
  useEffect(() => {
    opener.current = document.activeElement;
    dialog.current?.querySelector<HTMLElement>('button:not([disabled]), input, select, textarea')?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeRef.current(); return; }
      if (e.key !== 'Tab') return;
      const list = Array.from(dialog.current?.querySelectorAll<HTMLElement>(
        'button:not([disabled]), [href], input:not([disabled]), select, textarea, [tabindex]:not([tabindex="-1"])') ?? []);
      if (!list.length) return;
      const firstEl = list[0], lastEl = list[list.length - 1];
      if (e.shiftKey && document.activeElement === firstEl) { e.preventDefault(); lastEl.focus(); }
      else if (!e.shiftKey && document.activeElement === lastEl) { e.preventDefault(); firstEl.focus(); }
    };
    document.addEventListener('keydown', onKey, true);
    return () => { document.removeEventListener('keydown', onKey, true); (opener.current as HTMLElement | null)?.focus?.(); };
  }, [onClose]);

  const derive = useCallback(async (next: Action, qty: Record<string, number>) => {
    setBusy(true); setError('');
    const lines = Object.entries(qty).filter(([, q]) => q > 0)
      .map(([invoice_item_id, quantity]) => ({ invoice_item_id, quantity }));
    const { data, error } = await supabase.rpc('invoice_action_plan', {
      p_invoice_id: invoiceId, p_action: next, p_lines: lines,
    });
    setBusy(false);
    // 417 (AFTER-15): a plan that could not be worked out leaves none on
    // screen, so no earlier plan is reviewed under this choice.
    if (error) { setError(error.message); setPlan(null); setStockConfirm({}); return null; }
    const p = data as Plan;
    // A request found waiting on this invoice is being reviewed now: its own
    // plan is the one shown.
    if (reviewingRef.current) return p;
    setPlan(p);
    // Propose the goods as returned and sellable; the person confirms or edits.
    setStockConfirm(Object.fromEntries((p.stock ?? []).map(s => [s.movement_id,
      { sellable_quantity: s.proposed_sellable, damaged_quantity: 0, not_returned_quantity: 0 }])));
    return p;
  }, [invoiceId]);

  // Step 1 needs the line list, which the plan already carries.
  useEffect(() => {
    if (reviewRequestId) return;
    void derive('refund_full', {}).then(p => { if (p) setFullPlan(p); });
  }, [derive, reviewRequestId]);

  // 417 (AFTER-M2, AFTER-14): a request already waiting on this invoice. An
  // Owner or Manager reviews that one rather than raising a second; anyone
  // else is told it is waiting. Unreadable: the server still refuses a second.
  useEffect(() => {
    if (reviewRequestId) return;
    let cancelled = false;
    supabase.rpc('invoice_request_status', { p_invoice_id: invoiceId }).then(({ data, error }) => {
      if (cancelled || error || !data) return;
      const s = data as RequestStatus;
      if (!s.pending || !s.request) return;
      if (canApprove) setFoundReviewId(s.request.request_id);
      else setWaitingRequest(s.request);
    });
    return () => { cancelled = true; };
  }, [invoiceId, reviewRequestId, canApprove]);

  // Approval mode: load the request, then show its CURRENT effects.
  useEffect(() => {
    if (!activeReviewId) return;
    let cancelled = false;
    setBusy(true);
    supabase.rpc('invoice_action_request_detail', { p_request_id: activeReviewId }).then(({ data, error }) => {
      if (cancelled) return;
      setBusy(false);
      if (error) { setError(error.message); return; }
      const d = data as any;
      setDetail(d);
      setAction(d.action as Action);
      setQuantities(Object.fromEntries((d.requested_lines ?? []).map((l: any) => [l.invoice_item_id, l.quantity])));
      const p = (d.current_plan ?? d.requested_plan) as Plan | null;
      if (p) {
        setPlan(p);
        setStockConfirm(Object.fromEntries((p.stock ?? []).map(s => [s.movement_id,
          { sellable_quantity: s.proposed_sellable, damaged_quantity: 0, not_returned_quantity: 0 }])));
      }
      setStep(4);
      // 393: whether this partial refund closes the invoice, for what the
      // review says about items waiting for a warehouse. Not knowing, it
      // says what the answers do.
      if (d.action === 'refund_partial') {
        supabase.rpc('invoice_action_plan', { p_invoice_id: invoiceId, p_action: 'refund_full', p_lines: [] })
          .then(({ data: full, error: ferr }) => { if (!cancelled && !ferr && full) setFullPlan(full as Plan); });
      }
    });
    return () => { cancelled = true; };
  }, [activeReviewId, invoiceId]);

  const chooseAction = async (next: Action) => {
    setAction(next); setOwedText(null);
    if (next === 'refund_partial') { setStep(2); return; }
    // 417 (AFTER-15): only a plan that was worked out moves on.
    const p = await derive(next, {});
    if (p) setStep(3);
  };

  const reject = async () => {
    if (!activeReviewId || !approverNote.trim()) { setError('Give the requester a reason for the rejection.'); return; }
    setBusy(true); setError('');
    const { data, error } = await supabase.rpc('resolve_invoice_action_v2', {
      p_request_id: activeReviewId, p_approve: false, p_note: approverNote.trim(),
    });
    setBusy(false);
    if (error) { setError(error.message); return; }
    // 409: a request raised the old way had moved the invoice to "Refund
    // requested" or "Cancellation requested"; rejecting it puts it back.
    const restored = (data as any)?.invoice_status_restored as string | null | undefined;
    setDone(restored
      ? `Request rejected. The invoice is back to ${restored.replace(/_/g, ' ')}, as its payments show. Nothing else on it has changed.`
      : 'Request rejected. The invoice shows it was rejected, with your reason, to the staff of its store. Nothing on the invoice has changed.');
    try { await onDone(); } catch { /* the rejection is recorded either way */ }
  };

  /**
   * 417 (AFTER-M2): a request this window raised whose approval failed is
   * still waiting. Submitting something different withdraws it first (an
   * Owner or Manager's own rejection, with the reason said here) and raises
   * the new one under a new request ID. The same choice again is the same
   * request, which the server returns as it is.
   */
  const withdrawOwnRequest = async (nextAction: Action, linesKey: string): Promise<string | null> => {
    if (!ownRequest) return requestId;
    if (ownRequest.action === nextAction && ownRequest.lines === linesKey) return requestId;
    const { error } = await supabase.rpc('resolve_invoice_action_v2', {
      p_request_id: ownRequest.id, p_approve: false,
      p_note: `Replaced by a different choice (${actionWords(nextAction)}) in the same window.`,
    });
    if (error) { setError(`The earlier request could not be withdrawn, so nothing new was raised: ${error.message}`); return null; }
    const fresh = crypto.randomUUID();
    setOwnRequest(null); setRequestId(fresh);
    return fresh;
  };

  const submit = async () => {
    if (reviewing) { await approve(activeReviewId!); return; }
    if (!action || !reason.trim()) { setError('Enter a reason for the audit history.'); return; }
    if (plan && plan.action !== action) {
      setError(`The review shows a ${actionWords(plan.action)}, not a ${actionWords(action)}. Go back and choose again.`); return;
    }
    setBusy(true); setError('');
    const chosen = Object.entries(quantities).filter(([, q]) => q > 0)
      .map(([invoice_item_id, quantity]) => ({ invoice_item_id, quantity }));
    // Only a partial refund that leaves the invoice open asks; one that takes
    // it all back, a full refund or a cancellation closes them all. Only a
    // partial refund names lines: a full refund or a cancellation covers every
    // line, whatever was typed at step 2 before choosing it.
    const lines = action !== 'refund_partial' ? []
      : coversWholeInvoice ? chosen : withWaitingAnswers(chosen, waitingItems, waitingAnswers);
    const linesKey = JSON.stringify(lines);
    const rid = await withdrawOwnRequest(action, linesKey);
    if (!rid) { setBusy(false); return; }
    const { data, error } = await supabase.rpc('request_invoice_action_v2', {
      p_invoice_id: invoiceId, p_action: action, p_lines: lines,
      p_reason: reason.trim(), p_return_notes: returnNotes.trim() || null, p_request_id: rid,
    });
    setBusy(false);
    if (error) { setError(error.message); return; }
    if (!canApprove) {
      setDone(`Request submitted for approval. Nothing has changed on ${plan?.invoice_no ?? 'this invoice'} yet — no money has moved and no stock has been returned.`);
      await onDone();
      return;
    }
    const created = (data as any).request_id as string;
    setOwnRequest({ id: created, action, lines: linesKey });
    await approve(created);
  };

  /** After an approval: the rentals it left with the customer, on the lines it covered. */
  const loadToReceive = async (p: Plan | null) => {
    if (!p) return;
    const { data, error } = await supabase.rpc('invoice_rentals_awaiting_return', { p_invoice_id: invoiceId });
    if (error) return;
    const rows = rentalsToReceive(data as AwaitingRental[], p.action, (p.lines ?? []).map(l => l.invoice_item_id));
    setToReceive(rows);
    setReceiveChoice(Object.fromEntries(rows.map(r => [r.rental_id, NOT_BACK_YET])));
    if (rows.length) {
      // Active warehouses are the only other destinations; the server checks again.
      supabase.from('warehouses').select('id,name').eq('is_active', true).is('deleted_at', null)
        .order('name').then(({ data: w }) => setWarehouses((w as any[]) ?? []));
    }
  };

  const approve = async (requestRecordId: string) => {
    setBusy(true); setError('');
    const stock = Object.entries(stockConfirm).map(([movement_id, q]) => ({ movement_id, ...q }));
    if (amountProblem) { setBusy(false); setError(amountProblem); return; }
    if (owedProblem) { setBusy(false); setError(owedProblem); return; }
    const overrides: Record<string, unknown>[] = (plan?.overrides_required ?? []).map(o => {
      const typed = typedAmount(o);
      const line = o.invoice_item_id ? { invoice_item_id: o.invoice_item_id } : {};
      return o.amount_required
        ? { code: o.code, reason: overrideReasons[overrideKey(o)] ?? '', amount: typed.trim() === '' ? null : Number(typed), ...line }
        : { code: o.code, reason: overrideReasons[overrideKey(o)] ?? '', ...line };
    });
    // 417: the amount owed back on a part-used cancellation, as stated.
    if (owedNeeded) {
      overrides.push({ code: 'refund_owed', amount: Math.round(Number(owedValue) * 100) / 100,
        reason: (reviewing ? approverNote.trim() || detail?.reason : reason.trim()) || 'Stated when cancelling' });
    }
    const note = reviewing ? (approverNote.trim() || null) : reason.trim();
    const { data, error } = await supabase.rpc('resolve_invoice_action_v2', {
      p_request_id: requestRecordId, p_approve: true, p_note: note,
      p_plan_hash: plan?.plan_hash ?? null, p_overrides: overrides,
      p_stock: stock.length ? stock : null, p_record_refund: recordRefund,
    });
    setBusy(false);
    if (error) { setError(error.message); return; }
    const r = data as any;
    if (r?.confirmation_required) {
      const revised = r.revised_plan as Plan | null;
      // 417 (AFTER-M2): the request waiting is for another action. Its plan is
      // not shown under this choice, and nothing is confirmed.
      if (revised?.action && plan?.action && revised.action !== plan.action) {
        setError(`The request waiting on this invoice is for a ${actionWords(revised.action)}, not a ${actionWords(plan.action)}. Nothing was changed. Close this window and open the invoice again.`);
        return;
      }
      setPlan(revised);
      // The revised plan can list goods the first one did not (a promotion's
      // stock, since 361); give each its default so the fields show and the
      // next confirmation carries them. Figures already entered are kept.
      setStockConfirm(cur => ({
        ...Object.fromEntries(((revised?.stock ?? []) as PlanStock[]).map(s => [s.movement_id,
          { sellable_quantity: s.proposed_sellable, damaged_quantity: 0, not_returned_quantity: 0 }])),
        ...Object.fromEntries(Object.entries(cur).filter(([id]) =>
          ((revised?.stock ?? []) as PlanStock[]).some(s => s.movement_id === id))),
      }));
      setError('What this would do has changed since the request was raised. The revised effects are shown below — review them and confirm again.');
      return;
    }
    // Report what actually happened, from the server's own answer — never
    // "refund recorded" because a checkbox was ticked.
    const parts: string[] = [];
    if (r?.cancellation) parts.push('Invoice cancelled.');
    if (r?.refund_recorded) parts.push(`Refund of ${money(r?.refunded_amount)} recorded.`);
    if (Number(r?.goods_returned ?? 0) > 0) parts.push('Returned goods recorded.');
    if (Number(r?.refund_still_due ?? 0) > 0) {
      parts.push(`${money(r.refund_still_due)} is still due back to the customer — record it when the money actually goes back.`);
    }
    if (r?.refund_owed != null && Number(r?.refund_still_due ?? 0) <= 0 && !r?.refund_recorded) {
      parts.push('Nothing is owed back: the money it holds is kept for what the customer used.');
    }
    setOwnRequest(null);
    setApprovedRequestId(requestRecordId);
    setDone(parts.join(' ') || 'Done.');
    // 417 (AFTER-7): rentals the action left with the customer are received on
    // the next screen, once they are actually back.
    await loadToReceive(plan);
    // A save that worked must not be lost because the refresh failed.
    try { setRefreshFailed(false); await onDone(); } catch { setRefreshFailed(true); }
  };

  /** Records each rental marked as back, one call each, as its own event. */
  const recordReceived = async () => {
    const rows = receivedChoices(toReceive, receiveChoice);
    if (!rows.length) return;
    setBusy(true); setReceiveError('');
    const note = (reviewing ? detail?.reason : reason)?.trim()
      || (plan?.action === 'cancel' ? 'Received after the cancellation' : 'Received after the refund');  // 458
    const notes: string[] = [];
    const left: AwaitingRental[] = [];
    for (const r of toReceive) {
      const c = receiveChoice[r.rental_id] ?? NOT_BACK_YET;
      if (!c.outcome) { left.push(r); continue; }
      const { data, error } = await supabase.rpc('receive_returned_rental', receiveRpcArgs(r, c, note, approvedRequestId));
      if (error) { setReceiveError(`${r.rental_no} could not be recorded: ${error.message}`); left.push(r); continue; }
      notes.push(receivedText(r, c.outcome, data));
    }
    setBusy(false);
    setReceivedNotes(n => [...n, ...notes]);
    setToReceive(left);
    if (notes.length) { try { await onDone(); } catch { setRefreshFailed(true); } }
  };

  const line = (id: string) => plan?.lines.find(l => l.invoice_item_id === id);

  /** Anything the person has actually typed or chosen and would lose. */
  const hasUnsavedInput = () =>
    (!reviewing && reason.trim().length > 0)
    || returnNotes.trim().length > 0
    || approverNote.trim().length > 0
    || (!reviewing && Object.values(quantities).some(q => q > 0))
    || Object.values(overrideReasons).some(r => (r ?? '').trim().length > 0)
    || Object.keys(overrideAmounts).length > 0
    || (!reviewing && Object.keys(waitingAnswers).length > 0);

  // The project's existing pattern for abandoning work is a confirm(); a
  // finished success message closes straight away, with nothing to lose.
  const requestClose = () => {
    if (done || !hasUnsavedInput()
        || confirm('Discard what you have entered for this refund or cancellation?')) {
      onClose();
    }
  };
  closeRef.current = requestClose;

  if (done) return (
    <div className="invoice-guided-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="invoice-guided invoice-guided--done" role="dialog" aria-modal="true" aria-labelledby="ga-done" ref={dialog}>
        <h3 id="ga-done">Done</h3>
        <p>{done}</p>
        {receivedNotes.length > 0 && <ul aria-label="Rented items recorded">{receivedNotes.map((n, i) => <li key={i}>{n}</li>)}</ul>}
        {canApprove && toReceive.length > 0 && (
          <fieldset className="invoice-guided-stock">
            <legend>Rented items still with the customer</legend>
            {/* 458: a refund ends a rental out as a cancellation does. */}
            <p className="muted">{rentalOutDoneNote(plan?.action ?? '')} Record each one only
              when it is actually in your hands. Damaged and lost items are never put back on sale. An item not back
              yet stays on the invoice, where it can be received later.</p>
            {toReceive.map(r => {
              const c = receiveChoice[r.rental_id] ?? NOT_BACK_YET;
              const set = (next: Partial<ReceiveChoice>) => setReceiveChoice(v => ({ ...v, [r.rental_id]: { ...c, ...next } }));
              return (
                <div key={r.rental_id} className="invoice-guided-stock-row invoice-guided-receive-row">
                  <span>{r.item} <small>· {r.rental_no} · {r.quantity} out</small></span>
                  <label>What happened
                    <select value={c.outcome} aria-label={`What happened to ${r.rental_no}`}
                      onChange={e => set({ outcome: e.target.value as ReceiveChoice['outcome'] })}>
                      <option value="">Not back yet</option>
                      <option value="good">Back in good condition — on sale again</option>
                      <option value="damaged">Back but damaged — not for sale</option>
                      <option value="lost">Lost — never came back</option>
                    </select>
                  </label>
                  {c.outcome === 'good' && (
                    <label>Goes back to
                      <select value={c.warehouseId} aria-label={`Where ${r.rental_no} goes back to`}
                        onChange={e => set({ warehouseId: e.target.value })}>
                        <option value="">{receiveHomeLabel(r)}</option>
                        {warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
                      </select>
                    </label>)}
                </div>);
            })}
            {receiveError && <p className="invoice-guided-warn" role="alert">{receiveError}</p>}
            <div className="invoice-guided-foot">
              <button className="btn" disabled={busy || receivedChoices(toReceive, receiveChoice).length === 0}
                onClick={recordReceived}>{busy ? 'Recording…' : 'Record what came back'}</button>
            </div>
          </fieldset>
        )}
        {refreshFailed && (
          <div className="invoice-guided-warn" role="status">
            <strong>This was saved.</strong> The invoice on screen could not be reloaded, so what
            you can see behind this message may be out of date. Retrying only re-reads the
            invoice — it does not repeat the {planAction === 'cancel' ? 'cancellation' : 'refund'}.
            <div className="invoice-guided-foot">
              <button className="btn" disabled={refreshing} onClick={async () => {
                setRefreshing(true);
                try { await onDone(); setRefreshFailed(false); } catch { /* still stale */ }
                setRefreshing(false);
              }}>{refreshing ? 'Reloading…' : 'Reload the invoice'}</button>
            </div>
          </div>
        )}
        <div className="invoice-guided-foot"><button className="btn btn-primary" onClick={onClose}>Close</button></div>
      </div>
    </div>
  );

  return (
    <div className="invoice-guided-backdrop" onClick={e => { if (e.target === e.currentTarget) requestClose(); }}>
      <div className="invoice-guided" role="dialog" aria-modal="true" aria-labelledby="ga-title" ref={dialog}>
        <div className="invoice-guided-head">
          <h3 id="ga-title">Refund or cancel{shownPlan?.invoice_no ? ` ${shownPlan.invoice_no}` : ''}</h3>
          <button type="button" className="invoice-guided-close" aria-label="Close without saving"
            onClick={requestClose}>&times;</button>
        </div>
        {shownPlan && (
          <p className="invoice-guided-status">
            {shownPlan.status ? <span className="invoice-guided-chip">{String(shownPlan.status).replace(/_/g, ' ')}</span> : null}
            {shownPlan.window ? <span>Created {readableDate(shownPlan.window.created_on)}</span> : null}
          </p>
        )}
        <ol className="invoice-guided-steps" aria-label="Progress">
          {['Action', 'Items', 'Reason', 'Review'].map((label, n) => (
            <li key={label} aria-current={step === n + 1 ? 'step' : undefined}
              className={step === n + 1 ? 'current' : step > n + 1 ? 'done' : ''}>{label}</li>
          ))}
        </ol>

        <div className="invoice-guided-body">
        {plan?.window && !plan.window.within && (
          <p className="invoice-guided-warn" role="status">
            Outside the five-day window — created {plan.window.created_on}, open through {plan.window.deadline}.
            An Owner or Manager override with a reason is required.
          </p>
        )}
        {plan?.blocked && (
          <div className="invoice-guided-block" role="alert">
            <strong>This invoice needs review first.</strong>
            <ul>{plan.blockers.map(b => <li key={b.code}>{b.message}</li>)}</ul>
          </div>
        )}
        {waitingRequest && !reviewing && (
          <p className="invoice-guided-warn" role="status" data-testid="request-waiting">
            A {actionWords(waitingRequest.action)} request for this invoice is already waiting for approval
            {waitingRequest.requested_at ? ` since ${sgDay(waitingRequest.requested_at)}` : ''}
            {waitingRequest.requested_by ? ` (raised by ${waitingRequest.requested_by})` : ''}.
            Nothing more can be asked until an Owner or Manager decides on it.
          </p>
        )}

        {step === 1 && plan?.blocked && (
          <p className="muted">Every action is unavailable until the review above is resolved.</p>
        )}
        {step === 1 && (
          <div className="invoice-guided-choices">
            <button className="btn" disabled={busy || plan?.blocked || !!waitingRequest} onClick={() => chooseAction('cancel')}>
              <strong>Cancel invoice</strong><span>Cancel this purchase. Any refund due is shown before confirmation.</span></button>
            <button className="btn" disabled={busy || plan?.blocked || nothingToRefund || !!waitingRequest} onClick={() => chooseAction('refund_full')}>
              <strong>Full refund</strong><span>Review the remaining refundable items and amount.</span></button>
            <button className="btn" disabled={busy || plan?.blocked || nothingToRefund || !!waitingRequest} onClick={() => chooseAction('refund_partial')}>
              <strong>Partial refund</strong><span>Choose the items and quantities to refund.</span></button>
          </div>
        )}
        {step === 1 && nothingToRefund && (
          <p className="muted" role="status">{heldNow > 0.005
            ? `No item on this invoice can be refunded, so it can only be cancelled. It holds ${money(heldNow)} of payments.`
            : 'Nothing has been paid on this invoice, so it can only be cancelled.'}</p>
        )}

        {step === 2 && (
          <fieldset className="invoice-guided-lines">
            <legend>Which items are coming back?</legend>
            {/* Every line still refundable, whatever plan was worked out last. */}
            {((fullPlan ?? plan)?.lines ?? []).map(l => (
              <label key={l.invoice_item_id}>
                <span>{l.name} <small>({l.line_kind.replace(/_/g, ' ')}, {l.quantity} sold)</small></span>
                <input type="number" min={0} max={l.quantity} inputMode="numeric"
                  aria-label={`Quantity of ${l.name} coming back, out of ${l.quantity}`}
                  value={quantities[l.invoice_item_id] ?? 0}
                  onChange={e => setQuantities({ ...quantities, [l.invoice_item_id]: Math.max(0, Math.min(l.quantity, Number(e.target.value))) })} />
              </label>
            ))}
          </fieldset>
        )}
        {step === 2 && (coversWholeInvoice
          ? waitingItems.length > 0 && (
            <p className="muted">Every line goes back in full, so the {waitingItems.length === 1 ? 'item' : `${waitingItems.length} items`} still
              waiting for a warehouse {waitingItems.length === 1 ? 'is' : 'are'} cancelled when the refund is recorded.</p>)
          : (<>
            <WaitingItemsQuestion items={waitingItems} answers={waitingAnswers} onChange={setWaitingAnswers}
              lineName={lineName} disabled={busy} />
            {waitingLeft.length > 0 && Object.values(quantities).some(q => q > 0) && (
              <p className="muted">Answer for each item waiting for a warehouse to continue.</p>)}
          </>))}

        {step === 3 && (
          <div className="invoice-guided-why">
            <label>Reason <span aria-hidden="true">*</span>
              <textarea value={reason} onChange={e => setReason(e.target.value)} rows={2} required
                aria-describedby="ga-reason-help" placeholder="What happened, in a sentence" />
            </label>
            <p id="ga-reason-help" className="muted">Kept in the audit history and shown to whoever approves this.</p>
            <label>Return details <small>(optional)</small>
              <textarea value={returnNotes} onChange={e => setReturnNotes(e.target.value)} rows={2}
                placeholder="Condition, who is bringing it back, when" />
            </label>
          </div>
        )}

        {reviewing && detail && (
          <div className="invoice-guided-request" aria-label="The request being reviewed">
            <div><strong>{detail.requested_by ?? 'Staff'}</strong> asked to{' '}
              {detail.action === 'cancel' ? 'cancel this invoice'
                : detail.action === 'refund_partial' ? 'refund some items' : 'refund everything'}
              {' '}· {detail.store}</div>
            <div className="muted">Their reason: “{detail.reason}”{detail.return_notes ? ` · ${detail.return_notes}` : ''}</div>
            {detail.action === 'cancel'
              ? detail.requested_plan && <div>Refund due when asked: {money(detail.requested_plan.refund_due)}</div>
              : detail.requested_amount != null && <div>Amount when asked: {money(detail.requested_amount)}</div>}
            {(detail.requested_lines ?? []).length > 0 && (
              <div>Items requested: {(detail.requested_lines as any[]).map((l: any) =>
                `${line(l.invoice_item_id)?.name ?? 'item'} × ${l.quantity}`).join(', ')}</div>)}
            {detail.changed && (() => {
              const moved = planChanges(detail.requested_plan, detail.current_plan);
              return (
                <p className="invoice-guided-warn" role="status">
                  Something has changed since this was asked for
                  {moved.length > 0 ? `: ${moved.join('; ')}` : ''}. Review the current effects below before approving.
                </p>);
            })()}
            {detail.status !== 'pending' && (
              <p className="invoice-guided-warn" role="status">
                Already {detail.status}
                {detail.rejection_reason ? ` — ${detail.rejection_reason}` : ''}.
              </p>)}
          </div>
        )}

        {reviewing && detail?.legacy && (
          <div className="invoice-guided-block" role="alert">
            <strong>This request cannot be approved as it stands.</strong>
            <p>{detail.legacy_note}</p>
            {['refund_requested', 'cancellation_requested'].includes(String(detail.invoice_status)) && (
              <p className="muted">Rejecting it puts the invoice back to the status its payments show
                (it reads “{String(detail.invoice_status).replace(/_/g, ' ')}” until then).</p>)}
            <label>Reason for the requester
              <textarea value={approverNote} onChange={e => setApproverNote(e.target.value)} rows={2} /></label>
            <div className="invoice-guided-foot">
              <button className="btn" onClick={onClose}>Close</button>
              <button className="btn btn-danger" disabled={busy || !approverNote.trim()} onClick={reject}>Reject</button>
            </div>
          </div>
        )}

        {step === 4 && plan && !(reviewing && detail?.legacy) && (
          <div className="invoice-guided-review">
            <h4>What this will do</h4>
            {(() => {
              const fx = plan.effects;
              if (!fx) return <ul className="invoice-guided-summary">{plan.summary.map((s, n) => <li key={n}>{s}</li>)}</ul>;
              const credits = (fx.benefits ?? []).filter(b => b.credit_removed != null || b.units_revoked != null);
              const withdrawn = fx.rewards?.withdrawn ?? [];
              const kept = fx.rewards?.kept ?? [];
              return (<>
                {Number(fx.money_returned?.total ?? 0) > 0 && (
                  <section className="invoice-guided-section">
                    <h5>Money returned</h5>
                    <p className="invoice-guided-figure">{money(fx.money_returned.total)}</p>
                    <ul>{(fx.money_returned.destinations ?? []).map(d => (
                      <li key={d.payment_id}>{money(d.amount)} to {d.wallet && paymentLabel ? (paymentLabel(d.payment_id, d.method) || d.method) : d.method}
                        {d.wallet ? " — back to the credit it was paid from (held back there while that package is cancelled or refunded, or, if it was paid in full before, while its reopening waits for payment: see that package's invoice)" : ''}</li>))}</ul>
                    <p className="muted">Recording this does not send money anywhere. It records that
                      the money was returned; making the payment is a separate act.</p>
                  </section>
                )}
                {planAction === 'cancel' && Number(plan.refund_due ?? 0) > 0 && !recordRefund && (
                  <section className="invoice-guided-section">
                    <h5>Refund due</h5>
                    <p className="invoice-guided-figure">{money(owedNeeded ? Number(owedValue) || 0 : plan.refund_due)}</p>
                    <p className="muted">Nothing is recorded as returned until someone confirms it was.</p>
                  </section>
                )}
                {(credits.length > 0 || withdrawn.length > 0 || kept.length > 0) && (
                  <section className="invoice-guided-section">
                    <h5>Credits and benefits cancelled</h5>
                    <ul>{credits.map((b, n) => (
                      <li key={n}>
                        {b.credit_removed != null
                          ? <>{money(b.credit_removed)} of {b.kind} credit</>
                          : <>{b.units_revoked} unused voucher unit{Number(b.units_revoked) === 1 ? '' : 's'}</>}
                        {b.holder ? <> — {b.holder}</> : null}
                        {b.line ? <span className="muted"> ({b.line})</span> : null}
                      </li>))}
                      {withdrawn.length > 0 && <li>Reward entitlements withdrawn: {withdrawn.join(', ')}</li>}
                      {kept.length > 0 && <li>Reward entitlements kept (already activated or claimed, with their history): {kept.join(', ')}</li>}
                    </ul>
                  </section>
                )}
                {(fx.therapy_closed ?? []).length > 0 && (
                  <section className="invoice-guided-section">
                    <h5>Therapy closed</h5>
                    <ul>{(fx.therapy_closed ?? []).map(t => (
                      <li key={t.entitlement_no}>{t.entitlement_no}{t.package ? <> — {t.package}</> : null}
                        {t.used
                          ? <> <strong>has been used</strong>: ends only with the override below</>
                          : <> not used yet{t.benefit === 'voucher' ? '; vouchers not yet collected are withdrawn' : ''}</>}
                        {t.line ? <span className="muted"> ({t.line})</span> : null}
                      </li>))}</ul>
                  </section>
                )}
                {(fx.therapy_left ?? []).length > 0 && (
                  <section className="invoice-guided-section">
                    <h5>Therapy left running</h5>
                    <ul>{(fx.therapy_left ?? []).map(t => (
                      <li key={t.entitlement_no}>{t.entitlement_no}{t.package ? <> — {t.package}</> : null}: has been used and
                        is on no invoice line (a correction removed its line), so this does not end it.</li>))}</ul>
                  </section>
                )}
                {(fx.stock_returned ?? []).length > 0 && (
                  <section className="invoice-guided-section">
                    <h5>Stock returned</h5>
                    <ul>{fx.stock_returned.map(st2 => (
                      <li key={st2.movement_id}>{st2.proposed_sellable} × {st2.product_name} →{' '}
                        {st2.store_name ?? 'the original store'} <span className="muted">(condition confirmed below)</span></li>))}</ul>
                  </section>
                )}
                {(plan.overrides_required ?? []).length > 0 && (
                  <section className="invoice-guided-section">
                    <h5>Overrides required</h5>
                    <ul>{plan.overrides_required.map((o, n) => <li key={`${overrideKey(o)}:${n}`}>{o.message}</li>)}</ul>
                  </section>
                )}
              </>);
            })()}

            {(() => {
              // 393: what happens to the items still waiting for a warehouse.
              const label = (id: string) => {
                const item = waitingItems.find(w => w.doc_id === id);
                return item ? waitingItemLabel(item, lineName) : 'An item no longer waiting';
              };
              const asked = reviewing ? waitingAnswersOf(detail?.requested_lines) : waitingAnswerList(waitingItems, waitingAnswers);
              if (action === 'refund_partial' && !coversWholeInvoice) {
                if (!asked.length) return reviewing && waitingItems.length > 0 ? (
                  <section className="invoice-guided-section">
                    <h5>Waiting for a warehouse</h5>
                    <p className="muted">This request was raised without saying whether the customer is still taking
                      them, so an item is cancelled only if its line goes back in full.</p>
                    <ul>{waitingItems.map(w => <li key={w.doc_id}>{label(w.doc_id)}</li>)}</ul>
                  </section>) : null;
                return (
                  <section className="invoice-guided-section">
                    <h5>Waiting for a warehouse</h5>
                    <ul>{asked.map(a => (
                      <li key={a.doc_id}>{label(a.doc_id)}: {a.still_taking
                        ? 'the customer is still taking it, so it keeps waiting'
                        : 'the customer is not taking it, so it is cancelled'}</li>))}</ul>
                  </section>);
              }
              if (!waitingItems.length) return null;
              // A cancellation, a full refund, or a partial refund that takes
              // back everything still refundable: the invoice closes.
              const what = action === 'cancel' ? 'Cancelling the invoice cancels'
                : action === 'refund_partial' ? 'This refund takes back everything still refundable, so it closes the invoice and cancels'
                : 'A refund of the whole invoice cancels';
              return (
                <section className="invoice-guided-section">
                  <h5>Waiting for a warehouse</h5>
                  <p className="muted">{what} every item still waiting for a warehouse
                    {asked.length > 0 ? ', whatever was answered' : ''}:</p>
                  <ul>{waitingItems.map(w => <li key={w.doc_id}>{label(w.doc_id)}</li>)}</ul>
                </section>);
            })()}

            {plan.stock.length > 0 && (
              <fieldset className="invoice-guided-stock">
                <legend>Confirm the goods</legend>
                <p className="muted">A refund is not proof that anything came back. Damaged and not-returned
                  units are recorded separately and are never put back on sale.</p>
                {plan.stock.map(s => (
                  <div key={s.movement_id} className="invoice-guided-stock-row">
                    <span>{s.product_name} <small>→ {s.store_name ?? 'original store'}, {s.outstanding} outstanding</small></span>
                    {(['sellable_quantity', 'damaged_quantity', 'not_returned_quantity'] as const).map(k => (
                      <label key={k}>{k === 'sellable_quantity' ? 'Good' : k === 'damaged_quantity' ? 'Damaged' : 'Not returned'}
                        <input type="number" min={0} max={s.outstanding} inputMode="numeric"
                          value={stockConfirm[s.movement_id]?.[k] ?? 0}
                          onChange={e => setStockConfirm({ ...stockConfirm,
                            [s.movement_id]: { ...stockConfirm[s.movement_id], [k]: Math.max(0, Number(e.target.value)) } as any })} />
                      </label>
                    ))}
                  </div>
                ))}
              </fieldset>
            )}

            {/* 458: a refund ends a rental out as a cancellation does. */}
            {canApprove && planAction && plan.lines.some(l => l.line_kind === 'rental') && rentalOutReviewNote(planAction) && (
              <p className="muted">{rentalOutReviewNote(planAction)}</p>
            )}

            {canApprove && plan.overrides_required.length > 0 && (
              <fieldset className="invoice-guided-overrides">
                <legend>Override reasons</legend>
                {plan.overrides_required.map((o, i) => (
                  <div key={`${overrideKey(o)}:${i}`}>
                    <label><span>{overrideLine(o) ? <strong>{overrideLine(o)}: </strong> : null}{o.message}</span>
                      <input type="text" value={overrideReasons[overrideKey(o)] ?? ''} required
                        aria-label={`Reason for override: ${o.code}${overrideLine(o) ? ` (${overrideLine(o)})` : ''}`}
                        onChange={e => setOverrideReasons({ ...overrideReasons, [overrideKey(o)]: e.target.value })} />
                    </label>
                    {o.amount_required && (
                      <label><span>Amount to refund for this (S$)</span>
                        <input type="number" min={0} step="0.01" required
                          value={typedAmount(o)}
                          aria-label={`Amount for override: ${o.code}${overrideLine(o) ? ` (${overrideLine(o)})` : ''}`}
                          onChange={e => setOverrideAmounts({ ...overrideAmounts, [overrideKey(o)]: e.target.value })} />
                      </label>)}
                  </div>
                ))}
                {amountOverrides.length > 0 && !sharedAmountKey && Math.abs(statedRefund - planFigure) > 0.004 && (
                  <p className="invoice-guided-warn" role="status">
                    Refund stated by override: {money(statedRefund)} (the plan above shows {money(planFigure)}).
                  </p>
                )}
                {amountProblem && <p className="invoice-guided-warn" role="alert">{amountProblem}</p>}
              </fieldset>
            )}

            {canApprove && planAction === 'cancel' && (plan.refund_due ?? 0) > 0 && (
              <label className="invoice-guided-refunddue">
                <input type="checkbox" checked={recordRefund} onChange={e => setRecordRefund(e.target.checked)} />
                <span>The {money(plan.refund_due)} has actually gone back to the customer now.
                  Leave this unticked to cancel now and show <strong>Refund due</strong> until the money is really returned.</span>
              </label>
            )}

            {owedNeeded && (
              <fieldset className="invoice-guided-overrides" data-testid="refund-owed">
                <legend>Owed back to the customer</legend>
                <p className="muted">{plan.refund_owed?.message}</p>
                <label><span>Amount owed back (S$)</span>
                  <input type="number" min={0} step="0.01" required value={owedValue}
                    aria-label="Amount owed back to the customer"
                    onChange={e => setOwedText(e.target.value)} />
                </label>
                <p className="muted">This shows as the refund due until it is recorded as paid back. The rest of the
                  money is kept for what the customer used.</p>
                {owedProblem && <p className="invoice-guided-warn" role="alert">{owedProblem}</p>}
              </fieldset>
            )}

            {canApprove && reviewing && !rejecting && (
              <label className="invoice-guided-why">Your note <small>(optional, kept with the approval)</small>
                <textarea value={approverNote} onChange={e => setApproverNote(e.target.value)} rows={2} /></label>
            )}

            {error && <p className="invoice-guided-warn" role="alert">{error}</p>}
            {reviewing && rejecting && (
              <label className="invoice-guided-why">Reason for rejecting
                <textarea value={approverNote} onChange={e => setApproverNote(e.target.value)} rows={2} autoFocus
                  placeholder="Why this is refused, in your own words" /></label>
            )}
            {reviewing && rejecting && (
              <p className="muted">The invoice shows that this request was rejected, with this reason, to the staff of its store.</p>
            )}
            {!canApprove && <p className="muted">This will be sent to an Owner or Manager. Nothing changes until they approve it.</p>}
          </div>
        )}
        {error && step !== 4 && <p className="invoice-guided-warn" role="alert">{error}</p>}
        </div>

        {/* One footer, outside the scrolling body, so Back and the
            confirming action stay reachable however long the review gets. */}
        <div className="invoice-guided-foot">
          {step === 1 && (
            <button type="button" className="btn" onClick={requestClose}>Close</button>
          )}
          {step === 2 && (<>
            <button type="button" className="btn" onClick={() => setStep(1)}>Back</button>
            <button type="button" className="btn btn-primary"
              disabled={busy || !Object.values(quantities).some(q => q > 0) || waitingLeft.length > 0}
              onClick={async () => { const p = await derive('refund_partial', quantities); if (p) setStep(3); }}>Continue</button>
          </>)}
          {step === 3 && (<>
            <button type="button" className="btn" onClick={() => setStep(action === 'refund_partial' ? 2 : 1)}>Back</button>
            <button type="button" className="btn btn-primary" disabled={!reason.trim() || !plan}
              onClick={() => setStep(4)}>Continue</button>
          </>)}
          {step === 4 && plan && !(reviewing && detail?.legacy) && (<>
            {reviewing
              ? <button className="btn" onClick={() => rejecting ? setRejecting(false) : onClose()}>
                  {rejecting ? 'Back' : 'Close'}</button>
              : <button className="btn" onClick={() => setStep(3)}>Back</button>}
            {reviewing && !rejecting && (
              <button className="btn btn-danger" disabled={busy || detail?.status !== 'pending'}
                onClick={() => setRejecting(true)}>Reject</button>)}
            {reviewing && rejecting
              ? <button className="btn btn-danger" disabled={busy || !approverNote.trim()} onClick={reject}>Confirm rejection</button>
              : <button className="btn btn-primary"
                  disabled={busy || plan.blocked || (reviewing && detail?.status !== 'pending')
                    || (canApprove && (!!amountProblem || !!owedProblem))} onClick={submit}>
                  {(() => {
                    // The amount an Owner/Manager stated for an override is what is refunded.
                    const amount = canApprove ? statedRefund : Number(plan.refund_amount ?? 0);
                    if (!canApprove && !reviewing) {
                      return planAction === 'cancel' ? 'Submit cancellation request' : 'Submit refund request';
                    }
                    if (planAction === 'cancel') {
                      return recordRefund && Number(plan.refund_due ?? 0) > 0
                        ? `Confirm cancellation and ${money(canApprove ? statedRefund : plan.refund_due)} refund`
                        : 'Confirm cancellation';
                    }
                    return amount > 0 ? `Confirm ${money(amount)} refund` : 'Confirm refund';
                  })()}
                </button>}
          </>)}
        </div>

      </div>
    </div>
  );
}
