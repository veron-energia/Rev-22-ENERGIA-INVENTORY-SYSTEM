// Wallet credit on an invoice's copies and on its screen (the user's answers,
// 13 Nov 2026).
//
// When wallet credit pays an invoice, its copies (the printed customer and
// office copies, the PDF and the image, so WhatsApp and email too) and the
// invoice screen show the credit as a line under Discount, and Total says what
// was left to pay in money:
//
//   Subtotal                     S$327.00
//   Discount                      −S$0.00
//   Wallet — Credit Package     −S$327.00
//   Total                          S$0.00
//
// - One line per kind of credit, with a minus sign. A Credit Package's or a
//   Premium Bundle's Paid and Bonus credit add together under the package's
//   name ('Wallet — Credit Package'). Every other wallet method keeps the name
//   its payment row had, where its credit came from in brackets included
//   ('Wallet — Paid Credit (Premium Bundle)').
// - Part paid in money: Total is what the credit left (S$327 = S$200 of credit
//   + S$127 PayNow: Total S$127.00).
// - PAYMENT METHODS lists only money (cash, card, PayNow and so on), and Paid
//   counts only that; the copies leave it out when credit paid everything.
//   The screen's Payments Recorded keeps every payment: staff correct them
//   there.
// - Credit refunded back into the wallet is a note under its line,
//   'S$327.00 returned to wallet 11/11/2026'. The line keeps the credit used,
//   and Total does not change.
//
// Only the copies and the screen change. The invoice's own total, the list,
// the reports, commission and Xero keep the full amount.
//
// Amounts are added in whole cents. Kept free of React so it is tested with the
// Node runner.
import { signedPaymentAmount } from './creditBalanceLine.mjs';

const cents = v => { const n = Number(v); return Number.isFinite(n) ? Math.round(n * 100) : 0; };
const sgd = c => `S$${(c / 100).toFixed(2)}`;

/** The packages whose Paid and Bonus credit print as one line, by wallet_source. */
export const PACKAGE_LINE_LABELS = Object.freeze({
  credit_package: 'Wallet — Credit Package',
  premium_bundle: 'Wallet — Premium Bundle',
});

/**
 * The line a wallet payment adds to: 'Wallet — Credit Package' or 'Wallet —
 * Premium Bundle' for those packages' own methods, their Paid and Bonus
 * together; for any other wallet method, the payment's label as its row
 * printed it (`paymentLabel`).
 */
export function walletLineLabel(paymentLabel, method) {
  return PACKAGE_LINE_LABELS[method?.wallet_source] ?? String(paymentLabel ?? '');
}

/**
 * What an invoice's copies and screen show of the wallet credit that paid it,
 * or null when they show the invoice as before: no wallet credit paid it (net
 * of corrections), or money went back and the refunds could not be read, so
 * which of it went back to the wallet is not known.
 *
 * - payments: the invoice's invoice_payments rows.
 * - isWallet(payment): whether the payment's method pays from the wallet.
 * - lineLabel(payment): the line it adds to (walletLineLabel).
 * - refunds: the invoice's invoice_refunds rows (payment_id, amount,
 *   credit_returned, created_at); null when they could not be read.
 * - refunded: what the invoice's financial position says was refunded.
 * - total: the invoice's total_amount.
 * - day(at): a moment as the copies print a day ('11/11/2026').
 *
 * Returns:
 * - lines: [{ label, amount, returned }], in the order the payments came;
 *   `amount` is the credit used as a number, `returned` one 'S$x returned to
 *   wallet <day>' per refund that put credit back. A kind whose payments
 *   were all reversed is left out.
 * - credit: the lines' sum.
 * - moneyPayments: the rows that were not wallet credit, for PAYMENT METHODS.
 * - moneyPaid, moneyRefunded: what was paid and refunded in money.
 * - totalLeft: what the credit left to pay, never below nothing.
 */
export function walletCredit({ payments, isWallet, lineLabel, refunds, refunded, total, day }) {
  const lines = [];
  const byLabel = new Map();
  const lineOfPayment = new Map();
  const moneyPayments = [];
  let moneyPaid = 0;
  for (const p of payments ?? []) {
    if (!isWallet(p)) {
      moneyPayments.push(p);
      moneyPaid += cents(signedPaymentAmount(p));
      continue;
    }
    const label = lineLabel(p);
    let line = byLabel.get(label);
    if (!line) {
      line = { label, cents: 0, returned: [] };
      byLabel.set(label, line);
      lines.push(line);
    }
    line.cents += cents(signedPaymentAmount(p));
    if (p?.id != null) lineOfPayment.set(p.id, line);
  }
  const shown = lines.filter(l => l.cents > 0);
  if (shown.length === 0) return null;
  // Which refunds put credit back into the wallet: without them, the copies
  // stay as they were rather than guess.
  if (refunds == null && cents(refunded) > 0) return null;

  let moneyRefunded = 0;
  for (const r of refunds ?? []) {
    const amount = cents(r?.amount);
    const back = Math.min(Math.max(cents(r?.credit_returned), 0), Math.max(amount, 0));
    moneyRefunded += Math.max(amount - back, 0);
    if (back > 0) {
      const own = lineOfPayment.get(r?.payment_id);
      const line = own && own.cents > 0 ? own : shown[0];
      line.returned.push({ cents: back, at: r?.created_at ?? null });
    }
  }
  const credit = shown.reduce((s, l) => s + l.cents, 0);
  return {
    lines: shown.map(l => ({
      label: l.label,
      amount: l.cents / 100,
      returned: l.returned
        .slice()
        .sort((a, b) => String(a.at ?? '').localeCompare(String(b.at ?? '')))
        .map(x => `${sgd(x.cents)} returned to wallet${x.at ? ` ${day(x.at)}` : ''}`),
    })),
    credit: credit / 100,
    moneyPayments,
    moneyPaid: moneyPaid / 100,
    moneyRefunded: moneyRefunded / 100,
    totalLeft: Math.max(cents(total) - credit, 0) / 100,
  };
}
