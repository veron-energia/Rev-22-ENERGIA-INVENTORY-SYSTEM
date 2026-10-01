// TikTok's Wednesday payouts as Xero sales invoices (the owner's rules, 1 Oct 2026).
//
// TikTok pays the shop's balance into the bank every Wednesday: everything it
// settled from the Thursday before through that Wednesday, less the ads (GMV
// Pay) it took from the balance that week. tiktok_xero_payouts (374) gives a
// reporting month's Wednesdays with those figures; this turns them into rows of
// Xero's Sales Invoice template, the same template as the invoice export:
//
//   one draft invoice per Wednesday, to the contact "TikTok Shop", numbered
//   TT-PAYOUT-<date>, dated that Wednesday, with up to three lines
//     TikTok sales                         Total Revenue of the week
//     TikTok fees, commissions, shipping   less Total Fee (TikTok's "Total Fees")
//     TikTok ads and subscriptions         less Total Expense
//   so the invoice total is the money paid into the bank. A line of 0.00 is
//   left out.
//
// A negative week (ads and refunds above sales) is a credit note. So that
// every document has one sign, whatever Xero does with mixed signs, its
// positive lines stay on invoice TT-PAYOUT-<date> and its negative lines go on
// credit note TT-PAYOUT-<date>-CN; together they are the week.
//
// Which weeks go out: those whose Wednesday is over and that have money in
// them, and of those the ones the person ticks. Anything that could make a
// week differ from TikTok's payout comes with a warning to read first.
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

/** Cents as dollars for a person to read, e.g. -2600 -> "-S$26.00". */
export function sgd(cents) {
  return `${cents < 0 ? '-' : ''}S$${formatCents(Math.abs(cents))}`;
}

/** Cents as an amount with two decimals, e.g. -2600 -> "-26.00". */
export function formatCents(cents) {
  const abs = Math.abs(cents);
  return `${cents < 0 ? '-' : ''}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
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
const list = days => days.map(dayLabel).join(', ');

/**
 * The month's Wednesdays, each with its lines in cents, whether it goes out,
 * and what to read before exporting it.
 *
 *   status 'export'        its Wednesday is over and it has money in it
 *   status 'not_finished'  its Wednesday is today or later
 *   status 'nothing'       its Wednesday is over but there is nothing to pay
 */
export function planTikTokPayouts(data) {
  const weeks = (Array.isArray(data?.weeks) ? data.weeks : []).map(w => {
    const sales = toCents(w.revenue);
    const fees = -toCents(w.fee);
    const ads = -toCents(w.expense);
    const payout = toCents(w.payout);
    if (sales + fees + ads !== payout) {
      throw new Error(`The payout of ${dayLabel(w.payout_date)} does not add up. Reload before exporting.`);
    }
    const status = !w.finished ? 'not_finished' : (sales === 0 && fees === 0 && ads === 0 ? 'nothing' : 'export');
    return { ...w, cents: { sales, fees, ads, payout }, status, warnings: [] };
  });

  weeks.forEach((w, i) => {
    if (!w.finished) return;
    const warn = t => w.warnings.push(t);
    const uncovered = Array.isArray(w.uncovered_days) ? w.uncovered_days : [];
    if (Number(w.row_count ?? 0) === 0) {
      warn('No settled lines were imported for this week. If TikTok paid out, import its file first.');
    } else if (uncovered.length) {
      warn(`No imported file reaches ${list(uncovered)}. If TikTok settled anything on ${uncovered.length === 1 ? 'that day' : 'those days'}, import that file first, or this payout is short.`);
    }
    const leftOut = Number(w.left_out_count ?? 0);
    if (leftOut > 0) {
      warn(`${plural(leftOut, 'settled line was', 'settled lines were')} left out at confirmation (${sgd(toCents(w.left_out_settlement ?? 0))}) and ${leftOut === 1 ? 'is' : 'are'} not in this payout. Include ${leftOut === 1 ? 'it' : 'them'} on this page first if ${leftOut === 1 ? 'it belongs' : 'they belong'}.`);
    }
    const unknown = Number(w.unknown_count ?? 0);
    if (unknown > 0) {
      warn(`${plural(unknown, 'line has', 'lines have')} a TikTok type the app does not know, and ${unknown === 1 ? 'adds' : 'add'} nothing to this payout.`);
    }
    const moves = Number(w.balance_movement_count ?? 0);
    if (moves > 0) {
      warn(`${plural(moves, 'line moves', 'lines move')} money in or out of the TikTok balance (a reserve, withdrawal or financing) and ${moves === 1 ? 'is' : 'are'} not in this payout.`);
    }
    const other = Number(w.other_currency_count ?? 0);
    if (other > 0) warn(`${plural(other, 'line is', 'lines are')} not in SGD.`);
    const tiktokNet = toCents(w.tiktok_net ?? w.payout);
    if (tiktokNet !== w.cents.payout) {
      warn(`TikTok's own total for these lines is ${sgd(tiktokNet)}, not ${sgd(w.cents.payout)}. Check the week in TikTok before exporting.`);
    }
    if (w.status === 'export' && w.cents.payout < 0) {
      warn(`This week is negative (${sgd(w.cents.payout)}): TikTok pays nothing this Wednesday and takes ${sgd(-w.cents.payout)} from a later payout. It goes to Xero with credit note TT-PAYOUT-${w.payout_date}-CN; allocate that against the next payout's invoice.`);
    }
    const before = weeks[i - 1];
    if (before && before.status === 'export' && before.cents.payout < 0 && w.status === 'export') {
      warn(`TikTok takes the ${sgd(-before.cents.payout)} of ${dayLabel(before.payout_date)} from a payout from here on, so the bank may receive less than this invoice.`);
    }
  });

  const monthWarnings = [];
  const undated = Number(data?.undated_count ?? 0);
  if (undated > 0) {
    monthWarnings.push(`${plural(undated, 'counted settled line has', 'counted settled lines have')} no settled date, so ${undated === 1 ? 'it is' : 'they are'} in no week.`);
  }
  const exportable = weeks.filter(w => w.status === 'export');
  return {
    year: data?.year, month: data?.month,
    weeks, exportable, monthWarnings,
    exportCents: exportable.reduce((s, w) => s + w.cents.payout, 0),
    // The month's Total Income for every store, worked out separately (tiktok_settlement_totals).
    monthIncomeCents: toCents(data?.month_income ?? data?.income ?? 0),
  };
}

const LINES = [
  { key: 'sales', code: 'salesCode', name: 'sales', text: 'TikTok sales (revenue after discounts and refunds)' },
  { key: 'fees', code: 'feesCode', name: 'fees', text: 'TikTok fees, commissions and shipping (TikTok\'s Total Fees)' },
  { key: 'ads', code: 'adsCode', name: 'ads', text: 'TikTok ads and subscriptions (GMV Pay)' },
];

/** The weeks to export: the ones chosen (by Wednesday), or every one that can go out. */
function chosen(plan, payoutDates) {
  if (!payoutDates) return plan.exportable;
  const want = new Set(payoutDates);
  return plan.exportable.filter(w => want.has(w.payout_date));
}

/** The account codes the chosen weeks need (a code is only needed when its line is). */
export function neededCodes(plan, payoutDates) {
  const weeks = chosen(plan, payoutDates);
  return LINES.filter(l => weeks.some(w => w.cents[l.key] !== 0)).map(l => l.code);
}

/**
 * Rows of Xero's Sales Invoice template for the chosen weeks (every week that
 * can go out when none are given). codes: { salesCode, feesCode, adsCode, taxType }.
 */
export function buildTikTokPayoutRows(plan, codes, payoutDates) {
  const weeks = chosen(plan, payoutDates);
  const taxType = String(codes?.taxType ?? '').trim();
  if (!taxType) throw new Error('Enter the Xero tax rate.');
  const need = neededCodes(plan, payoutDates);
  for (const l of LINES) {
    if (need.includes(l.code) && !String(codes?.[l.code] ?? '').trim()) {
      throw new Error(`Enter the Xero account code for TikTok ${l.name}.`);
    }
  }
  const rows = [];
  const documents = new Set();
  let totalCents = 0;
  let creditNotes = 0;
  for (const w of weeks) {
    const date = xeroDate(w.payout_date);
    const span = weekLabel(w);
    const reference = `TikTok payout ${dayLabel(w.payout_date)} ${isoDay(w.payout_date).getUTCFullYear()}`;
    const negative = w.cents.payout < 0;
    for (const l of LINES) {
      const cents = w.cents[l.key];
      if (cents === 0) continue;
      // A negative week: its negative lines make the credit note.
      const number = negative && cents < 0 ? `TT-PAYOUT-${w.payout_date}-CN` : `TT-PAYOUT-${w.payout_date}`;
      documents.add(number);
      rows.push({
        '*ContactName': TIKTOK_XERO_CONTACT,
        '*InvoiceNumber': number,
        Reference: reference,
        '*InvoiceDate': date, '*DueDate': date,
        '*Description': `${l.text}, settled ${span}`,
        '*Quantity': 1, '*UnitAmount': formatCents(cents),
        '*AccountCode': String(codes[l.code]).trim(), '*TaxType': taxType, TaxAmount: 0, Currency: 'SGD',
      });
    }
    totalCents += w.cents.payout;
    if (negative) creditNotes += 1;
  }
  const missing = findMissingMandatory(rows);
  if (missing.length) throw new Error(`Row ${missing[0].row} has no ${missing[0].field}. Complete the details before exporting.`);
  return {
    rows, headers: XERO_SALES_INVOICE_HEADERS,
    weeks: weeks.length, documents: documents.size, creditNotes, total: formatCents(totalCents),
  };
}

/** "xero-tiktok-payouts-2026-09.csv" */
export function tiktokXeroFilename(year, month) {
  return `xero-tiktok-payouts-${year}-${String(month).padStart(2, '0')}.csv`;
}
