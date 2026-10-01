// TikTok's bank payouts as Xero sales invoices (the owner's rules, 1 Oct 2026).
//
// TikTok pays the shop's balance into the bank every Wednesday. The payouts
// come from TikTok's own "Withdrawal records" (imported with the settlement
// files, 375); tiktok_bank_payouts gives those paid between two dates. Each
// becomes one draft invoice in Xero's Sales Invoice template (the same as the
// invoice export), with one line for exactly what TikTok paid:
//
//   *ContactName   TikTok Shop
//   *InvoiceNumber TT-PAYOUT-<date paid>
//   Reference      TikTok's Reference ID of the payout
//   *Description   TikTok payout, settled Thu 27 Aug – Wed 2 Sep 2026
//   *UnitAmount    what TikTok paid, on the one account code given
//
// Before exporting, a person reads what could be wrong:
//   - a payout that differs from the app's own figure for its week (files not
//     imported, lines left out, or a negative week carried into it);
//   - a Wednesday with no payout imported, whose week the app says should pay
//     out, which no imported file reaches, or whose lines were left out;
//   - a payout TikTok has not transferred yet (not exported);
//   - a payout two imported files give different amounts for (not exported:
//     it is checked in TikTok and entered in Xero by hand);
//   - a payout in the imported files with no date (in no export).
//
// Amounts are handled as whole cents, so the file adds up exactly.

import { XERO_SALES_INVOICE_HEADERS, findMissingMandatory } from './salesInvoiceTemplate.mjs';

export const TIKTOK_XERO_CONTACT = 'TikTok Shop';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** Whole cents of an amount with at most two decimals (a number or a numeric string). */
export function toCents(amount) {
  const text = typeof amount === 'number' ? (Number.isFinite(amount) ? amount.toFixed(2) : '') : String(amount ?? '').trim();
  const m = /^(-?)(\d+)(?:\.(\d{1,2}))?$/.exec(text);
  if (!m) throw new Error('A TikTok payout has an invalid amount. Reload before exporting.');
  const cents = Number(m[2]) * 100 + Number((m[3] ?? '').padEnd(2, '0'));
  return m[1] && cents !== 0 ? -cents : cents;
}

/** Cents as an amount with two decimals, e.g. -2600 -> "-26.00". */
export function formatCents(cents) {
  const abs = Math.abs(cents);
  return `${cents < 0 ? '-' : ''}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
}

/** Cents as dollars for a person to read, e.g. -2600 -> "-S$26.00". */
export function sgd(cents) {
  return `${cents < 0 ? '-' : ''}S$${formatCents(Math.abs(cents))}`;
}

function isoDay(iso) {
  const day = /^\d{4}-\d{2}-\d{2}$/.test(String(iso ?? '')) ? new Date(`${iso}T00:00:00Z`) : null;
  if (!day || !Number.isFinite(day.getTime()) || day.toISOString().slice(0, 10) !== iso) {
    throw new Error('A TikTok payout has an invalid date. Reload before exporting.');
  }
  return day;
}

/** "Wed 2 Sep" */
export function dayLabel(iso) {
  const d = isoDay(iso);
  return `${WEEKDAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

/** "Thu 27 Aug – Wed 2 Sep 2026" */
export function weekLabel(week) {
  return `${dayLabel(week.week_start)} – ${dayLabel(week.week_end)} ${isoDay(week.week_end).getUTCFullYear()}`;
}

/** Xero's date format: DD/MM/YYYY. */
export function xeroDate(iso) {
  isoDay(iso);
  return iso.split('-').reverse().join('/');
}

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

/** "no imported file reaches Tue 15 Sep, Wed 16 Sep", or the whole week. */
function unreached(days, week) {
  return days.length >= 7 ? `no imported file reaches ${weekLabel(week)}` : `no imported file reaches ${days.map(dayLabel).join(', ')}`;
}

/**
 * The payouts that go out (TikTok transferred them), and what to read first.
 * `data` is tiktok_bank_payouts' answer.
 */
export function planBankPayouts(data) {
  const warnings = [];
  const exportable = [];
  const payouts = Array.isArray(data?.payouts) ? data.payouts : [];
  for (const p of payouts) {
    const cents = toCents(p.amount);
    const week = { week_start: p.week_start, week_end: p.wednesday };
    if (!p.transferred) {
      warnings.push(`${dayLabel(p.paid_on)}: a TikTok payout of ${sgd(cents)} is "${p.status ?? 'not transferred'}", not transferred, so it is not exported.`);
      continue;
    }
    const disagreeing = Array.isArray(p.disagreeing) ? p.disagreeing : [];
    if (disagreeing.length) {
      warnings.push(`${dayLabel(p.paid_on)}: imported TikTok files disagree on payout ${p.reference_id}: ${sgd(cents)} in "${p.file_name}", but `
        + disagreeing.map(o => `${sgd(toCents(o.amount))} in "${o.file_name}"`).join(', ')
        + '. It is not exported: check it in TikTok Seller Center and enter it in Xero by hand.');
      continue;
    }
    exportable.push({ ...p, cents });
    if (p.app_payout !== null && p.app_payout !== undefined) {
      const app = toCents(p.app_payout);
      if (app !== cents) {
        const why = [];
        const uncovered = Array.isArray(p.uncovered_days) ? p.uncovered_days : [];
        if (uncovered.length) why.push(unreached(uncovered, week));
        if (Number(p.left_out_count ?? 0) > 0) why.push(`${plural(Number(p.left_out_count), 'line was', 'lines were')} left out at confirmation`);
        warnings.push(`${dayLabel(p.paid_on)}: TikTok paid ${sgd(cents)}, but the app's settled lines for ${weekLabel(week)} come to ${sgd(app)}`
          + (why.length ? ` (${why.join('; ')})` : ' (for example, a negative week before it that TikTok took from this payout)')
          + '. The invoice uses what TikTok paid.');
      }
    }
  }
  for (const w of Array.isArray(data?.wednesdays_without_payout) ? data.wednesdays_without_payout : []) {
    const week = { week_start: w.week_start, week_end: w.wednesday };
    const app = toCents(w.app_payout ?? 0);
    const uncovered = Array.isArray(w.uncovered_days) ? w.uncovered_days : [];
    const why = [];
    if (uncovered.length) why.push(unreached(uncovered, week));
    if (Number(w.left_out_count ?? 0) > 0) why.push(`${plural(Number(w.left_out_count), 'line was', 'lines were')} left out at confirmation`);
    warnings.push(`${dayLabel(w.wednesday)}: no TikTok payout has been imported, `
      + (app > 0
        ? `but the app's settled lines for ${weekLabel(week)} come to ${sgd(app)}${why.length ? ` (${why.join('; ')})` : ''}`
        : `and ${why.length ? why.join('; ') : `the app's settled lines for ${weekLabel(week)} come to ${sgd(app)}`}`)
      + '. Import the TikTok income export that covers it, then export again.');
  }
  const undated = Number(data?.undated_payout_count ?? 0);
  if (undated > 0) {
    warnings.push(`${plural(undated, 'TikTok payout', 'TikTok payouts')} in the imported files ${undated === 1 ? 'has' : 'have'} no date, so ${undated === 1 ? 'it is' : 'they are'} in no export: check ${undated === 1 ? 'it' : 'them'} in TikTok Seller Center.`);
  }
  return { from: data?.from, to: data?.to, exportable, warnings, payoutCount: payouts.length };
}

/** Rows of Xero's Sales Invoice template: one invoice per payout, one line each. */
export function buildBankPayoutRows(plan, accountCode, taxType) {
  const code = String(accountCode ?? '').trim();
  const tax = String(taxType ?? '').trim();
  if (!code || !tax) throw new Error('Enter the Xero account code and tax rate.');
  const rows = [];
  const used = new Map();
  let totalCents = 0;
  for (const p of plan.exportable) {
    // Two payouts on one day would share a number; the second gets -2.
    const n = (used.get(p.paid_on) ?? 0) + 1;
    used.set(p.paid_on, n);
    const date = xeroDate(p.paid_on);
    rows.push({
      '*ContactName': TIKTOK_XERO_CONTACT,
      '*InvoiceNumber': `TT-PAYOUT-${p.paid_on}${n > 1 ? `-${n}` : ''}`,
      Reference: `TikTok ${p.reference_id}`,
      '*InvoiceDate': date, '*DueDate': date,
      '*Description': `TikTok payout, settled ${weekLabel({ week_start: p.week_start, week_end: p.wednesday })}`,
      '*Quantity': 1, '*UnitAmount': formatCents(p.cents),
      '*AccountCode': code, '*TaxType': tax, TaxAmount: 0, Currency: 'SGD',
    });
    totalCents += p.cents;
  }
  const missing = findMissingMandatory(rows);
  if (missing.length) throw new Error(`Row ${missing[0].row} has no ${missing[0].field}. Complete the details before exporting.`);
  return { rows, headers: XERO_SALES_INVOICE_HEADERS, payouts: rows.length, totalCents };
}

/** "xero-tiktok-payouts-2026-09-01-to-2026-09-30.csv" */
export function tiktokXeroFilename(from, to) {
  return `xero-tiktok-payouts-${from}-to-${to}.csv`;
}
