// The Payment Summary sheet: daily takings by payment method (427).
//
// Kept free of React so it can be tested with the Node runner. The figures
// come from daily_payments_by_method (one row per day per method, deleted
// invoices left out) and payment_methods_in_range (which methods, and which
// of them are wallet credit).
//
//   * The Total is the money taken: wallet credit spent is not money taken
//     (it was counted when the credit was bought), so wallet methods are left
//     out of it and shown after it, each in a column marked as wallet credit,
//     with their own total.
//   * Every day from From to To has a row; a day with no takings shows zeroes.
//   * Dates are written as text, day first (dd/mm/yyyy), straight from the
//     date, so no time zone can move them and a spreadsheet cannot read them
//     as American dates.

/** The default range: the 1st of this month to today (both Singapore days). */
export function paymentSummaryDefaultRange(today) {
  return { from: `${String(today).slice(0, 7)}-01`, to: String(today) };
}

/** Every calendar day from from to to, both included, as YYYY-MM-DD. */
export function daysBetween(from, to) {
  const out = [];
  const d = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || Number.isNaN(end.getTime())) return out;
  for (; d <= end; d.setUTCDate(d.getUTCDate() + 1)) out.push(d.toISOString().slice(0, 10));
  return out;
}

export const dayFirst = iso => String(iso).slice(0, 10).split('-').reverse().join('/');
const money = n => Math.round((Number(n) + Number.EPSILON) * 100) / 100;

export const TOTAL_HEADER = 'Total';
export const WALLET_TOTAL_HEADER = 'Wallet credit used (not money taken)';
export const walletHeader = name => `${name} (wallet credit)`;

/**
 * The sheet: { headers, body } for XLSX.utils.json_to_sheet, the last body row
 * the TOTAL row. methods: [{ payment_method_id, method_name, is_wallet_credit }];
 * rows: [{ pay_date, payment_method_id, method_name, amount }].
 */
export function buildPaymentSummary({ methods, rows, from, to }) {
  const list = (methods ?? []).map(m => ({ id: String(m.payment_method_id), name: String(m.method_name), wallet: !!m.is_wallet_credit }));
  const money_ = list.filter(m => !m.wallet).sort((a, b) => a.name.localeCompare(b.name));
  const wallet = list.filter(m => m.wallet).sort((a, b) => a.name.localeCompare(b.name));
  const headers = ['Date', ...money_.map(m => m.name), TOTAL_HEADER,
    ...(wallet.length ? [...wallet.map(m => walletHeader(m.name)), WALLET_TOTAL_HEADER] : [])];

  // date -> method id -> amount
  const byDate = new Map();
  for (const r of rows ?? []) {
    const day = String(r.pay_date).slice(0, 10);
    if (!byDate.has(day)) byDate.set(day, new Map());
    const cell = byDate.get(day);
    const id = String(r.payment_method_id);
    cell.set(id, money((cell.get(id) ?? 0) + (Number(r.amount) || 0)));
  }

  const totals = new Map();
  let grand = 0, walletGrand = 0;
  const body = daysBetween(from, to).map(day => {
    const cell = byDate.get(day) ?? new Map();
    const o = { Date: dayFirst(day) };
    let dayTotal = 0, dayWallet = 0;
    for (const m of money_) {
      const v = money(cell.get(m.id) ?? 0);
      o[m.name] = v; dayTotal = money(dayTotal + v);
      totals.set(m.id, money((totals.get(m.id) ?? 0) + v));
    }
    o[TOTAL_HEADER] = dayTotal; grand = money(grand + dayTotal);
    for (const m of wallet) {
      const v = money(cell.get(m.id) ?? 0);
      o[walletHeader(m.name)] = v; dayWallet = money(dayWallet + v);
      totals.set(m.id, money((totals.get(m.id) ?? 0) + v));
    }
    if (wallet.length) { o[WALLET_TOTAL_HEADER] = dayWallet; walletGrand = money(walletGrand + dayWallet); }
    return o;
  });

  const totalRow = { Date: 'TOTAL' };
  for (const m of money_) totalRow[m.name] = totals.get(m.id) ?? 0;
  totalRow[TOTAL_HEADER] = grand;
  for (const m of wallet) totalRow[walletHeader(m.name)] = totals.get(m.id) ?? 0;
  if (wallet.length) totalRow[WALLET_TOTAL_HEADER] = walletGrand;
  body.push(totalRow);
  return { headers, body, moneyTaken: grand, walletUsed: walletGrand };
}
