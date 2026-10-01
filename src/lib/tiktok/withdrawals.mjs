// TikTok's "Withdrawal records" sheet (the owner's rules, 1 Oct 2026).
//
// TikTok's income export has it beside the settled lines: every change to the
// shop's TikTok balance (Earnings, GMV Pay Deduction, Payments) with its
// Reference ID, request and success dates, amount and status. It is found by
// its headers, like every other TikTok sheet, and read as text so a long
// Reference ID keeps every digit. The sheet also names the bank account; that
// column is never read.

export const WITHDRAWAL_HEADERS = {
  transaction_type: ['transaction type'],
  reference_id: ['reference id'],
  request_time: ['request time'],
  amount: ['amount'],
  status: ['status'],
  success_time: ['success time'],
};
const REQUIRED = ['transaction_type', 'reference_id', 'amount', 'success_time'];

const norm = h => String(h ?? '').toLowerCase().replace(/\s+/g, ' ').trim();

/**
 * The sheet's rows, from the workbook's sheets (as grids of text), or null
 * when no sheet has its headers. `skipSheet` is the sheet already read as the
 * settled lines. Rows without a Reference ID are left out.
 */
export function readWithdrawalRecords(grids, skipSheet) {
  for (const { name, grid } of grids ?? []) {
    if (name === skipSheet) continue;
    for (let r = 0; r < Math.min(10, grid.length); r++) {
      const map = {};
      (grid[r] ?? []).forEach((h, i) => {
        const n = norm(h);
        for (const [field, alts] of Object.entries(WITHDRAWAL_HEADERS)) {
          if (map[field] === undefined && alts.includes(n)) map[field] = i;
        }
      });
      if (!REQUIRED.every(f => map[f] !== undefined)) continue;
      const rows = grid.slice(r + 1)
        .map(row => {
          const o = {};
          for (const field of Object.keys(WITHDRAWAL_HEADERS)) {
            const v = map[field] === undefined ? '' : String(row[map[field]] ?? '').trim();
            if (v !== '') o[field] = v;
          }
          return o;
        })
        .filter(o => o.reference_id && o.transaction_type);
      return { sheetName: name, rows };
    }
  }
  return null;
}

/** "3 payouts and 31 other balance records" */
export function describeWithdrawals(rows) {
  const payouts = rows.filter(r => r.transaction_type === 'Payments').length;
  return describeBalanceCounts(payouts, rows.length - payouts);
}

/** The same, from what the database kept of a file (tiktok_batch_balance_counts). */
export function describeBalanceCounts(payouts, others) {
  const n = (k, one, many) => `${k} ${k === 1 ? one : many}`;
  return `${n(payouts, 'payout', 'payouts')} and ${n(others, 'other balance record', 'other balance records')}`;
}
