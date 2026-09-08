// What each settlement row means financially, and the money arithmetic.
//
// The reported figures are:
//
//   Total Revenue     sales proceeds after seller discounts and customer
//                     refunds, before platform fees and operating expenses
//   Total Fee         net transaction fees and deductions, excluding customer
//                     refunds and anything classified as an operating expense
//   Total Settlement  Revenue − Fee            (before operating expenses)
//   Total Expense     advertising and other identifiable operating payments,
//                     net of reversals
//   Total Income      Settlement − Expense
//
// Total Settlement is deliberately NOT TikTok's own "Total settlement amount".
// TikTok's figure already has advertising deducted; ours is struck before
// operating expenses so the two can be compared rather than confused. In the
// reference export, Income equals TikTok's net settlement exactly — that is a
// reconciliation, not a definition, and other files may legitimately differ
// where transfers or reserves are present.
//
// Money is integer cents throughout. Floating point addition over a few hundred
// rows drifts, and a settlement report that is a cent out invites someone to go
// looking for a cent that was never lost.

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/** A source amount to integer cents. Preserves sign; refuses nonsense. */
export function toCents(value) {
  if (value === null || value === undefined || value === '') return 0;
  if (typeof value === 'number') {
    return Number.isFinite(value) ? Math.round(value * 100) : 0;
  }
  let s = String(value).trim().replace(/,/g, '').replace(/\s/g, '');
  if (s === '' || s === '/' || s === '-') return 0;
  // Accounting parentheses: (5.00) is -5.00
  let negative = false;
  if (/^\(.*\)$/.test(s)) { negative = true; s = s.slice(1, -1); }
  s = s.replace(/^(SGD|MYR|USD|S\$|RM|\$)/i, '').trim();
  if (s.startsWith('-')) { negative = !negative; s = s.slice(1); }
  if (!/^\d*\.?\d*$/.test(s) || s === '' || s === '.') return 0;
  const [whole, frac = ''] = s.split('.');
  const cents = Number(whole || '0') * 100 + Number((frac + '00').slice(0, 2));
  return negative ? -cents : cents;
}

export const centsToNumber = c => c / 100;
export const formatCents = c => (c / 100).toFixed(2);

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------
//
// Deliberately finer than the stored `txn_class` ('order'/'adjustment'/
// 'refund'/'finance'), which cannot distinguish an advertising payment from a
// bank transfer — both are 'finance' — and so cannot answer "what did we spend".
// `txn_class` is left exactly as it is; this sits alongside it.

export const CATEGORY = {
  SALE: 'sale',                       // revenue and its fees
  SALE_REFUND: 'sale_refund',         // a refund settled as its own transaction
  FEE: 'fee',                         // a standalone fee deduction
  FEE_REVERSAL: 'fee_reversal',       // a fee refunded back
  AD_EXPENSE: 'ad_expense',           // advertising / operating payment
  EXPENSE_REVERSAL: 'expense_reversal',
  BALANCE_MOVEMENT: 'balance_movement', // withdrawal, transfer, reserve, financing
  UNKNOWN: 'unknown',                 // needs a human
};

/** Categories that must never silently contribute to a "reconciled" total. */
export const REVIEW_CATEGORIES = [CATEGORY.UNKNOWN];

const norm = s => String(s ?? '').trim().toLowerCase();

/**
 * Classify by documented economic meaning, not by whether a label contains a
 * word. "Affiliate Shop Ads commission" is a commission on a sale, not a payment
 * for advertising, so it stays a fee — matching on "ads" alone would move real
 * commission out of Fee and overstate advertising spend.
 *
 * A balance movement is money moving between the seller's own pots — a payout to
 * a bank account, a reserve being held or released, a loan advanced or repaid.
 * It is neither income nor expense, and counting it as either double-counts
 * activity that is already represented by the orders it came from.
 */
export function classifyTransaction(transactionType, { adjustmentCents = 0 } = {}) {
  const t = norm(transactionType);
  if (t === '') return CATEGORY.UNKNOWN;

  const reversing = /refund|reversal|rebate|credited back|returned/.test(t);

  // 1. Advertising and operating payments. Matched on the documented payment
  //    types rather than the mere presence of "ads", and checked first so that
  //    "subscription fee" is read as an operating cost and not a platform fee.
  if (t.includes('gmv payment for tiktok ads')
      || t.includes('payment for tiktok ads')
      || t.includes('advertising payment')
      || /\bads? *(payment|top ?up|charge|spend)\b/.test(t)
      || t.includes('subscription fee')) {
    // Money out is the expense; the same payment coming back reduces it.
    return (reversing || adjustmentCents > 0) ? CATEGORY.EXPENSE_REVERSAL : CATEGORY.AD_EXPENSE;
  }

  // 2. The fee family, INCLUDING commissions. Checked before the generic refund
  //    branch so that "Affiliate commission refund" is read as a fee coming back
  //    rather than as a customer being refunded for a sale — they belong on
  //    opposite sides of the report.
  if (t.includes('commission') || t.includes('fee') || t.includes('penalt') || t.includes('fine')) {
    return (reversing || adjustmentCents > 0) ? CATEGORY.FEE_REVERSAL : CATEGORY.FEE;
  }

  // 3. Money moving between the seller's own balances. Neither income nor
  //    expense: the activity behind it is already counted in the orders.
  if (t.includes('withdraw') || t.includes('transfer') || t.includes('payout')
      || t.includes('remittance') || t.includes('reserve') || t.includes('hold release')
      || t.includes('loan') || t.includes('financing') || t.includes('repayment')
      || t.includes('deposit')) {
    return CATEGORY.BALANCE_MOVEMENT;
  }

  // 4. A refund settled as its own transaction reduces revenue in the period it
  //    settles in — not in the month the original order was created.
  if (t.includes('refund') || t.includes('return')) return CATEGORY.SALE_REFUND;

  if (t === 'order' || t.includes('order')) return CATEGORY.SALE;

  // An adjustment with no documented meaning is exactly the thing that must not
  // be quietly folded into a total.
  return CATEGORY.UNKNOWN;
}

// ---------------------------------------------------------------------------
// Per-row financial effect
// ---------------------------------------------------------------------------

/**
 * Turn one source row into its contribution, in cents.
 *
 * `fee` and `expense` come back as POSITIVE costs, because that is how they are
 * read on a report; the source's signed values are preserved on the row itself
 * so a reversal still reduces the cost rather than being flipped into a charge.
 * Applying Math.abs to every row would turn every rebate into another charge.
 *
 * Each economic movement is counted ONCE. An advertising payment appears in both
 * "Total settlement amount" and "Adjustment amount"; it is taken from the
 * adjustment and never added again as a fee or a revenue reduction.
 */
export function rowEffect(row) {
  const category = row.category ?? classifyTransaction(row.transactionType, {
    adjustmentCents: toCents(row.adjustmentAmount),
  });

  const revenue = toCents(row.totalRevenue);
  const feeSigned = toCents(row.totalFees);
  const adjustment = toCents(row.adjustmentAmount);

  const zero = { revenue: 0, fee: 0, expense: 0, category };

  switch (category) {
    case CATEGORY.SALE:
    case CATEGORY.SALE_REFUND:
      // Total Revenue in this export is ALREADY net of the customer refund; the
      // refund column is detail for explanation, not a second subtraction.
      return { ...zero, revenue, fee: -feeSigned };

    case CATEGORY.FEE:
    case CATEGORY.FEE_REVERSAL:
      // A standalone fee row carries its amount in the adjustment when there is
      // no Total Fees value of its own.
      return { ...zero, fee: feeSigned !== 0 ? -feeSigned : -adjustment };

    case CATEGORY.AD_EXPENSE:
    case CATEGORY.EXPENSE_REVERSAL:
      return { ...zero, expense: -adjustment };

    case CATEGORY.BALANCE_MOVEMENT:
      // Deliberately nothing. The money it describes is already represented by
      // the transactions that produced it.
      return zero;

    default:
      return zero;   // unknown: contributes nothing, and is surfaced for review
  }
}

/** Fold rows into the reported figures. */
export function summarise(rows) {
  const t = {
    rows: rows.length, revenue: 0, fee: 0, expense: 0,
    tiktokNetSettlement: 0, byCategory: {}, review: [],
  };
  for (const row of rows) {
    const e = rowEffect(row);
    t.revenue += e.revenue;
    t.fee += e.fee;
    t.expense += e.expense;
    t.tiktokNetSettlement += toCents(row.totalSettlementAmount);
    t.byCategory[e.category] = (t.byCategory[e.category] ?? 0) + 1;
    if (REVIEW_CATEGORIES.includes(e.category)) t.review.push(row);
  }
  t.settlement = t.revenue - t.fee;
  t.income = t.settlement - t.expense;
  return t;
}
