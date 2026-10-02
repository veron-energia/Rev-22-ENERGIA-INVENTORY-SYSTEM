// The customer's credit balance, printed on the invoice.
//
// Owner's decision, 2 Oct 2026: the printed invoice (both halves) and the
// customer copy sent as a PDF or image show the customer's wallet credit as it
// stands at the moment of printing — a total, then each kind they hold:
//
//   Credit balance (as at 2 Oct 2026)          S$350.00
//   Paid S$300.00 · Bonus S$50.00
//
// It shows when the invoice has a customer and either the customer holds credit
// or the invoice was paid at least partly from their wallet (then even at
// S$0.00, so the customer can see the credit was used up). It never shows on a
// cancelled or refunded invoice, and it never stops an invoice printing: if the
// balance cannot be read, the invoice prints without the line.
//
// The balance is read fresh for every print and send, never taken from what
// the page loaded earlier. The page loads a balance when an invoice is opened,
// and that read can still be in flight — or belong to the invoice opened before
// — when the button is pressed. Printing one customer's balance on another
// customer's invoice is the mistake this module exists to rule out.
//
// Amounts are added in whole cents so a long run of payments cannot drift by a
// fraction of a cent, and money prints the way the invoice page prints it.

/** The wallet's kinds of credit, in the order the invoice lists them. */
export const WALLET_KINDS = Object.freeze([
  Object.freeze(['paid', 'Paid']),
  Object.freeze(['bonus', 'Bonus']),
  Object.freeze(['legacy', 'Legacy']),
  Object.freeze(['promotional', 'Promotional']),
  Object.freeze(['exchange', 'Exchange']),
]);

/** Statuses whose invoice never carries the line (our default, not the owner's). */
export const NO_CREDIT_LINE_STATUSES = Object.freeze(['cancelled', 'refunded']);

/** How long a print or send waits for the balance before going ahead without it. */
export const CREDIT_BALANCE_TIMEOUT_MS = 3000;

const cents = v => { const n = Number(v); return Number.isFinite(n) ? Math.round(n * 100) : 0; };
const sgd = c => `S$${(c / 100).toFixed(2)}`;

/**
 * A payment as it counts towards what was paid. Every entry is stored with a
 * positive amount; a correction reversal takes money back, so it counts against.
 */
export function signedPaymentAmount(p) {
  return (p?.entry_kind === 'correction_reversal' ? -1 : 1) * Number(p?.amount ?? 0);
}

/** What the payment rows add up to — the figure printed as Total Paid. */
export function paymentsTotal(payments) {
  return (payments ?? []).reduce((s, p) => s + cents(signedPaymentAmount(p)), 0) / 100;
}

/**
 * Was any of this invoice still paid from the customer's wallet? Net of
 * corrections: a wallet payment that was reversed and taken in cash instead no
 * longer counts.
 */
export function paidWithWalletCredit(payments, walletMethodIds) {
  const wallet = new Set(walletMethodIds ?? []);
  if (wallet.size === 0) return false;
  return (payments ?? [])
    .filter(p => wallet.has(p?.payment_method_id))
    .reduce((s, p) => s + cents(signedPaymentAmount(p)), 0) > 0;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * Today's date in Singapore as '2 Oct 2026', whatever time zone the browser is
 * in. Built from numeric parts rather than a locale's month names, which vary
 * ('Sept' in some English locales).
 */
export function singaporeDateLabel(now = new Date()) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Singapore', year: 'numeric', month: 'numeric', day: 'numeric',
  }).formatToParts(now).map(p => [p.type, p.value]));
  return `${Number(parts.day)} ${MONTHS[Number(parts.month) - 1]} ${parts.year}`;
}

/** The balance's total in cents: the server's own total, or the kinds added up. */
function totalCents(balance) {
  const t = Number(balance?.available_total);
  if (balance?.available_total != null && Number.isFinite(t)) return Math.round(t * 100);
  return WALLET_KINDS.reduce((s, [k]) => s + cents(balance?.categories?.[k]), 0);
}

/**
 * Does this invoice carry the line? `balanceTotal` is null when the balance
 * could not be read, and then it never does.
 */
export function shouldShowCreditBalance({ customerId, status, balanceTotal, paidWithWallet }) {
  if (!customerId) return false;
  if (NO_CREDIT_LINE_STATUSES.includes(String(status ?? ''))) return false;
  if (balanceTotal == null || !Number.isFinite(Number(balanceTotal))) return false;
  return cents(balanceTotal) > 0 || !!paidWithWallet;
}

/**
 * The line itself, from customer_credit_balances(): { label, amount, detail }.
 * `detail` lists the kinds the customer holds, and is null when they hold none.
 */
export function creditBalanceLine(balance, now = new Date()) {
  const detail = WALLET_KINDS
    .map(([k, name]) => [name, cents(balance?.categories?.[k])])
    .filter(([, c]) => c !== 0)
    .map(([name, c]) => `${name} ${sgd(c)}`)
    .join(' · ');
  return {
    label: `Credit balance (as at ${singaporeDateLabel(now)})`,
    amount: sgd(totalCents(balance)),
    detail: detail || null,
  };
}

const escHtml = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** What separates one kind from the next in the breakdown: 'Paid S$300.00 · Bonus S$50.00'. */
export const CREDIT_KIND_SEPARATOR = ' · ';

/**
 * The breakdown broken into lines no wider than `maxWidth`, as `measure` sees
 * it (jsPDF's getTextWidth, a canvas's measureText). A line only ever breaks
 * between two kinds, so a kind's name is never left at the end of one line with
 * its amount on the next. A single kind wider than the space gets a line of its
 * own rather than being split.
 */
export function wrapCreditDetail(detail, maxWidth, measure) {
  if (!detail) return [];
  const lines = [];
  let line = '';
  for (const kind of String(detail).split(CREDIT_KIND_SEPARATOR)) {
    const longer = line ? `${line}${CREDIT_KIND_SEPARATOR}${kind}` : kind;
    if (line && measure(longer) > maxWidth) { lines.push(line); line = kind; } else line = longer;
  }
  if (line) lines.push(line);
  return lines;
}

/**
 * The line as printed: one table row in the payment table's style, the label
 * and total on the first line and the kinds underneath, so it costs the
 * half-page two short lines.
 *
 * Each printed half is a column of fixed height (PRINT_CSS .copy) in which
 * nothing else can shrink. This block can — min-height 0 — so on an invoice
 * long enough to fill the half-page it gives way rather than pushing the
 * signatures and footer off the bottom. CREDIT_BALANCE_FIT_SCRIPT then makes
 * that all or nothing before the page prints. The breakdown only wraps between
 * kinds: each kind's name and amount are joined by a non-breaking space, and so
 * is the dot to the kind before it.
 */
export function creditBalanceHtml(line) {
  if (!line) return '';
  const detail = line.detail
    ? String(line.detail).split(CREDIT_KIND_SEPARATOR).map(k => escHtml(k).replace(/ /g, '&nbsp;')).join('&nbsp;· ')
    : '';
  return `<div class="credit-balance" style="flex:0 1 auto;min-height:0;overflow:hidden">`
    + `<table class="paytbl" style="margin-top:3px"><tbody><tr>`
    + `<td><strong>${escHtml(line.label)}</strong>${detail ? `<div class="mut credit-detail">${detail}</div>` : ''}</td>`
    + `<td class="r"><strong>${escHtml(line.amount)}</strong></td>`
    + `</tr></tbody></table></div>`;
}

/**
 * Script for the print window, run once the invoice has laid out and before it
 * prints: `fitCreditBalance()`. A credit block the half-page has squeezed
 * would print cut through a line of text, a figure half visible. So a block
 * that does not fit first loses its breakdown; if the total still does not fit,
 * the block is left out. What prints is whole, or not there at all.
 */
export const CREDIT_BALANCE_FIT_SCRIPT = `function fitCreditBalance() {
  var cut = function (el) { return el.scrollHeight > el.clientHeight + 0.5; };
  var blocks = document.querySelectorAll('.credit-balance');
  for (var i = 0; i < blocks.length; i++) {
    var block = blocks[i];
    if (!cut(block)) continue;
    var detail = block.querySelector('.credit-detail');
    if (detail) { detail.style.display = 'none'; if (!cut(block)) continue; }
    block.style.display = 'none';
  }
}`;

/**
 * customer_credit_balances() refuses a role that may not see credit (admin,
 * inventory manager, staff with no store). That is not a failure to read: the
 * line is simply not theirs to print.
 */
export function isCreditAccessRefusal(error) {
  return /do not have access to customer credit/i.test(String(error?.message ?? ''));
}

/**
 * Read the customer's balance now and decide the line for this invoice.
 *
 * `fetchBalances(customerId)` is the customer_credit_balances call; it returns
 * { data, error } (a Supabase builder will do). Resolves to { line, unreadable }:
 * `line` is null when the invoice should not carry one — including whenever the
 * read fails, is refused (a role that may not see credit), times out, or
 * answers for a different customer. `unreadable` is true when an invoice that
 * can carry the line goes without it because the balance could not be read
 * (not when the role was refused), so the page can say so. It never rejects,
 * so a print can always go ahead.
 */
export async function readCreditBalanceForInvoice({
  invoice, payments, walletMethodIds, fetchBalances,
  now = () => new Date(), timeoutMs = CREDIT_BALANCE_TIMEOUT_MS,
}) {
  const none = { line: null, unreadable: false };
  const unreadable = { line: null, unreadable: true };
  const customerId = invoice?.customer_id ?? null;
  // Nothing to read for an invoice that can never carry the line.
  if (!customerId || NO_CREDIT_LINE_STATUSES.includes(String(invoice?.status ?? ''))) return none;

  let timer;
  let res;
  try {
    res = await Promise.race([
      Promise.resolve().then(() => fetchBalances(customerId)),
      new Promise(resolve => { timer = setTimeout(() => resolve({ data: null, error: { message: 'timed out' } }), timeoutMs); }),
    ]);
  } catch {
    return unreadable;
  } finally {
    clearTimeout(timer);
  }
  if (res?.error) return isCreditAccessRefusal(res.error) ? none : unreadable;
  const balance = res?.data;
  if (!balance || typeof balance !== 'object') return unreadable;
  // The server names the customer it answered for; a balance for anyone else
  // is never printed on this invoice.
  if (balance.customer_id != null && balance.customer_id !== customerId) return unreadable;

  const show = shouldShowCreditBalance({
    customerId, status: invoice.status,
    balanceTotal: totalCents(balance) / 100,
    paidWithWallet: paidWithWalletCredit(payments, walletMethodIds),
  });
  return { line: show ? creditBalanceLine(balance, typeof now === 'function' ? now() : now) : null, unreadable: false };
}

/** The line alone: readCreditBalanceForInvoice without the reason it is missing. */
export async function creditBalanceForInvoice(args) {
  return (await readCreditBalanceForInvoice(args)).line;
}
