import type { BirthdayRule, LineDiscountType, VoucherDiscountCategory } from '../../types';

/**
 * One discount per invoice line (384).
 *
 * A line is either given free of charge (FOC, some or all of its units) or
 * carries one discount: a discount voucher (Vouchers, Birthday or Staff, told
 * apart by the category the Owner sets on the Vouchers page), a manual amount
 * in S$, or a percentage of the line. Every discount but FOC is stored as the
 * line's line_discount, which commission, refunds and the wallet cap already
 * read. The invoice-level manual discount and Discount Voucher still stack on
 * top, as before.
 *
 * Kept free of React and of the database, so the form, the printed copies
 * and the tests share one copy of the rules, and one copy of the arithmetic,
 * which follows create_invoice to the cent.
 */

export type LineKind = 'product' | 'voucher' | 'promotion' | 'therapy' | 'special_product' | 'rental'
  | 'credit_package' | 'premium_bundle' | 'event_ticket';

/**
 * What a line's Discount select holds. '' is no discount. Two values are only
 * ever restored, never chosen: 'legacy', a line saved before the one-discount
 * rule with FOC and a voucher both, kept as it is until it is changed; and
 * 'exchange', the exchange credit an exchange invoice keeps on its lines.
 */
export type DiscountChoice = '' | 'foc' | LineDiscountType | 'legacy' | 'exchange';

export const VOUCHER_CATEGORIES: VoucherDiscountCategory[] = ['voucher', 'birthday', 'staff'];
export const LINE_DISCOUNT_TYPES: LineDiscountType[] = ['voucher', 'birthday', 'staff', 'manual', 'percentage'];

export const DISCOUNT_CHOICE_LABELS: Record<DiscountChoice, string> = {
  '': 'None', foc: 'FOC', voucher: 'Vouchers', birthday: 'Birthday discount', staff: 'Staff discount',
  manual: 'Manual discount (S$)', percentage: 'Percentage discount (%)',
  legacy: 'FOC + voucher (saved earlier)', exchange: 'Exchange credit',
};

/** The fields of a voucher the discount rules read. */
export interface DiscountVoucher {
  id: string; name: string; voucher_kind: string;
  discount_amount?: number | null; discount_percent?: number | null; max_discount_cap?: number | null;
  discount_category?: VoucherDiscountCategory | null; birthday_rule?: BirthdayRule | null;
}

export const isVoucherChoice = (c: DiscountChoice | null | undefined): c is VoucherDiscountCategory =>
  c === 'voucher' || c === 'birthday' || c === 'staff';

/** A discount voucher's category. One saved before 384 counts as a plain voucher. */
export function voucherCategory(v: DiscountVoucher | null | undefined): VoucherDiscountCategory | null {
  if (!v || v.voucher_kind === 'normal') return null;
  return v.discount_category ?? 'voucher';
}

/**
 * The choices a line of this kind offers (owner, 3 Oct 2026).
 *
 * Credit packages and premium bundles take none: a discount there scales the
 * credit down, and both are refused when the invoice is created. FOC goes
 * where it always went. A voucher (Vouchers, Birthday, Staff) only on our own
 * products, never a third-party one; only the categories that have a voucher
 * on offer are listed. Manual and Percentage on every other line. An
 * Inventory Manager gives neither FOC nor a voucher, as before (the server
 * refuses both); Manual and Percentage are open to everyone who invoices.
 */
export function discountChoicesFor(kind: LineKind, o: { thirdParty?: boolean; categories?: Iterable<VoucherDiscountCategory>; inventoryManager?: boolean } = {}): DiscountChoice[] {
  if (kind === 'credit_package' || kind === 'premium_bundle') return [];
  if (o.inventoryManager) return ['', 'manual', 'percentage'];
  const out: DiscountChoice[] = ['', 'foc'];
  if (kind === 'product' && !o.thirdParty) {
    const have = new Set(o.categories ?? VOUCHER_CATEGORIES);
    for (const c of VOUCHER_CATEGORIES) if (have.has(c)) out.push(c);
  }
  out.push('manual', 'percentage');
  return out;
}

// ── money, in whole cents ──────────────────────────────────────────────────
// Prices are stored to the cent, so working in integer cents is exact and
// rounding can follow Postgres' round(numeric, 2): half away from zero.

export const toCents = (n: number | string | null | undefined): number => {
  const x = Number(n ?? 0);
  return Number.isFinite(x) ? Math.round(x * 100) : 0;
};
export const fromCents = (c: number): number => c / 100;

/** n / d for integers, rounded half away from zero. */
export function divRound(n: number, d: number): number {
  if (d === 0) return 0;
  const sign = (n < 0) !== (d < 0) ? -1 : 1;
  const a = Math.abs(n), b = Math.abs(d);
  let q = Math.floor(a / b);
  let r = a - q * b;
  if (r < 0) { q -= 1; r += b; }
  if (r >= b) { q += 1; r -= b; }
  if (2 * r >= b) q += 1;
  return sign * q;
}

/** A percentage to thousandths, as numeric(6,3) holds it. */
const milliPercent = (p: number | string | null | undefined) => Math.round(Number(p ?? 0) * 1000);

/** round(value × % / 100, 2), in cents. */
export const percentOfCents = (valueCents: number, percent: number | string | null | undefined): number =>
  divRound(valueCents * milliPercent(percent), 100000);

/**
 * voucher_discount_amount, in cents. A fixed voucher needs the base strictly
 * above its amount: null when it is not, which the server refuses. A
 * percentage voucher is round(base × % / 100, 2), capped. Never above the base.
 */
export function voucherDiscountCents(v: DiscountVoucher | null | undefined, baseCents: number): number | null {
  if (!v) return 0;
  let disc: number;
  if (v.voucher_kind === 'fixed_discount') {
    disc = toCents(v.discount_amount);
    if (baseCents <= disc) return null;
  } else if (v.voucher_kind === 'percentage_discount') {
    disc = percentOfCents(baseCents, v.discount_percent);
    if (v.max_discount_cap != null && disc > toCents(v.max_discount_cap)) disc = toCents(v.max_discount_cap);
  } else {
    return null;
  }
  if (disc > baseCents) disc = baseCents;
  return disc < 0 ? 0 : disc;
}

export interface LineMoneyInput {
  /** The unit price the server will use: the saved one, or the catalogue's. */
  unit: number | null;
  quantity: number;
  /** A promotion's top-up for the whole line. */
  topup?: number;
  choice: DiscountChoice;
  foc_quantity?: number;
  voucher?: DiscountVoucher | null;
  amount?: string | number | null;
  percent?: string | number | null;
  thirdParty?: boolean;
  /** A saved line the form has not changed: the server keeps what it stored. */
  saved?: { line_total: number; line_discount: number; foc_amount: number } | null;
}

/** One line's money, in cents. `charged` is line_total; `discount` is line_discount. */
export interface LineMoney {
  gross: number; foc: number; charged: number; discount: number; thirdParty: boolean;
  /** A fixed voucher the line's value is not above: the server refuses it. */
  voucherRefused?: boolean;
}

/**
 * A line as create_invoice works it out: gross = unit × quantity (+ a
 * promotion's top-up), FOC = round(gross × free ÷ quantity, 2), charged =
 * gross − FOC, then the line's one discount on what is charged. With one
 * discount per line a discounted line has no FOC, so that is the line's whole
 * value, unit × quantity.
 */
export function lineMoney(l: LineMoneyInput): LineMoney {
  const thirdParty = !!l.thirdParty;
  if (l.saved) {
    const charged = toCents(l.saved.line_total), foc = toCents(l.saved.foc_amount);
    return { gross: charged + foc, foc, charged, discount: toCents(l.saved.line_discount), thirdParty };
  }
  const qty = Math.max(0, Math.floor(Number(l.quantity) || 0));
  if (l.unit == null || qty <= 0) return { gross: 0, foc: 0, charged: 0, discount: 0, thirdParty };
  const gross = toCents(l.unit) * qty + toCents(l.topup);
  const takesFoc = l.choice === 'foc' || l.choice === 'legacy' || l.choice === 'exchange';
  const focQty = takesFoc ? Math.min(qty, Math.max(0, Math.floor(Number(l.foc_quantity) || 0))) : 0;
  const foc = focQty > 0 ? divRound(gross * focQty, qty) : 0;
  const charged = gross - foc;
  let discount = 0, voucherRefused = false;
  if (isVoucherChoice(l.choice) || l.choice === 'legacy') {
    const d = voucherDiscountCents(l.voucher, charged);
    if (d == null) voucherRefused = true; else discount = d;
  } else if (l.choice === 'manual') {
    const a = toCents(l.amount);
    discount = a > 0 ? Math.min(a, charged) : 0;
  } else if (l.choice === 'percentage') {
    const p = Number(l.percent);
    discount = p > 0 && p <= 100 ? percentOfCents(charged, p) : 0;
  }
  return { gross, foc, charged, discount, thirdParty, voucherRefused };
}

export interface InvoiceTotals {
  subtotal: number; focTotal: number; lineDiscounts: number; manual: number;
  /** What the invoice-level Discount Voucher is worked out on. */
  voucherBase: number; voucherDiscount: number; discountTotal: number; total: number;
}

/**
 * The invoice, in the order create_invoice applies its discounts (68, 99,
 * 384): the lines' own discounts; the manual discount on the whole subtotal,
 * third-party value included; the Discount Voucher on what is left of our own
 * products (their value, less the manual discount up to that value, less the
 * line discounts given on them, not those on third-party lines); the lot
 * capped at the subtotal. refresh_invoice_discount_total adds up an edited
 * invoice the same way since 384. All in cents.
 */
export function invoiceTotals(t: { lines: LineMoney[]; manual: number | string | null | undefined; invoiceVoucher?: DiscountVoucher | null }): InvoiceTotals {
  let subtotal = 0, third = 0, lineDiscounts = 0, ownLineDiscounts = 0, focTotal = 0;
  for (const l of t.lines) {
    subtotal += l.charged; focTotal += l.foc; lineDiscounts += l.discount;
    if (l.thirdParty) third += l.charged; else ownLineDiscounts += l.discount;
  }
  const manual = Math.max(0, toCents(t.manual));
  const discountable = subtotal - third;
  let discount = manual + lineDiscounts;
  const voucherBase = Math.max(0, discountable - Math.min(manual, discountable) - ownLineDiscounts);
  let voucherDiscount = 0;
  if (t.invoiceVoucher) {
    voucherDiscount = voucherDiscountCents(t.invoiceVoucher, voucherBase) ?? 0;
    discount += voucherDiscount;
  }
  const manualCapped = Math.min(manual, subtotal);
  discount = Math.min(discount - manual + manualCapped, subtotal);
  if (discount < 0) discount = 0;
  return { subtotal, focTotal, lineDiscounts, manual: manualCapped, voucherBase, voucherDiscount, discountTotal: discount, total: subtotal - discount };
}

// ── the birthday check ─────────────────────────────────────────────────────

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const isLeap = (y: number) => (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
const ISO = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Why a birthday discount cannot apply on this invoice, or null when it can.
 * The same test the server makes on the invoice's business date (Singapore):
 * "on the birthday" only on the date itself (29 February counts as 28 February
 * in other years), "in the birth month" anywhere in that month. The server
 * also allows one birthday-discount invoice per customer per year; it has the
 * final say, so this only warns.
 */
export function birthdayProblem(rule: BirthdayRule | null | undefined,
  p: { hasCustomer: boolean; dob?: string | null; businessDate?: string | null }): string | null {
  if (!p.hasCustomer) return 'Choose the customer first: a birthday discount is checked against their date of birth.';
  const dob = String(p.dob ?? '').slice(0, 10);
  if (!ISO.test(dob)) return "Add the customer's date of birth to give a birthday discount.";
  const day = String(p.businessDate ?? '').slice(0, 10);
  if (!ISO.test(day)) return null;
  const [, bm, bd] = dob.split('-').map(Number);
  const [y, m, d] = day.split('-').map(Number);
  const dated = `the invoice is dated ${d} ${MONTHS[m - 1]} ${y}`;
  if (rule === 'whole_month') {
    return bm === m ? null : `This birthday discount is for the birth month (${MONTHS[bm - 1]}); ${dated}.`;
  }
  if (rule === 'actual_date') {
    const target = bm === 2 && bd === 29 && !isLeap(y) ? 28 : bd;
    return bm === m && target === d ? null
      : `This birthday discount is for the birthday itself (${target} ${MONTHS[bm - 1]}); ${dated}.`;
  }
  return null;
}

// ── what the form sends ────────────────────────────────────────────────────

/** The discount part of a line in the form. */
export interface DiscountDraft {
  kind: LineKind;
  discount?: DiscountChoice;
  line_voucher_id?: string;
  foc_quantity?: number; foc_reason_id?: string; foc_reason?: string;
  /**
   * Every unit free ("All N free" chosen, or FOC just picked): the free
   * quantity then follows the quantity. Any other free quantity stays as
   * chosen while the quantity is typed, so a quantity typed digit by digit
   * never gives more away. Never sent.
   */
  foc_all?: boolean;
  /** Manual, in S$, and Percentage, as typed. */
  discount_amount?: string; discount_percent?: string;
  /** Internal, required for Manual and Percentage. */
  discount_reason?: string;
  /** A voucher saved before 384 with no type: sent back with none while it is unchanged. */
  discount_untyped?: boolean;
}

/**
 * The discount keys of one line of the invoice payload. FOC keys travel only
 * for FOC (and with a saved line that carries FOC and a voucher both, sent
 * back exactly as stored). A voucher of any category goes as its type and
 * line_voucher_id; Manual as line_discount_amount, Percentage as
 * line_discount_percent, each with line_discount_reason. A product line says
 * line_voucher_id: null when it has none, as it always did.
 */
export function lineDiscountPayload(d: DiscountDraft): Record<string, unknown> {
  const out: Record<string, unknown> = d.kind === 'product' ? { line_voucher_id: null } : {};
  const foc = (d.foc_quantity ?? 0) > 0
    ? { foc_quantity: d.foc_quantity, foc_reason_id: d.foc_reason_id || null, foc_reason: d.foc_reason || null } : {};
  const reason = (d.discount_reason ?? '').trim();
  switch (d.discount ?? '') {
    case 'foc': case 'exchange':
      return { ...out, ...foc };
    case 'legacy':
      return { ...out, ...foc, line_voucher_id: d.line_voucher_id || null };
    case 'voucher': case 'birthday': case 'staff':
      return { ...out, ...(d.discount_untyped ? {} : { line_discount_type: d.discount }), line_voucher_id: d.line_voucher_id || null };
    case 'manual':
      return { ...out, line_discount_type: 'manual', line_discount_amount: Number(d.discount_amount), line_discount_reason: reason };
    case 'percentage':
      return { ...out, line_discount_type: 'percentage', line_discount_percent: Number(d.discount_percent), line_discount_reason: reason };
    default:
      return out;
  }
}

const decimals = (s: string) => (s.split('.')[1] ?? '').length;

const DISCOUNT_FIELDS = ['discount', 'line_voucher_id', 'foc_quantity', 'foc_reason_id', 'foc_reason',
  'discount_amount', 'discount_percent', 'discount_reason', 'discount_untyped'] as const;
/** Whether two drafts carry the same discount (empty values alike, foc_all aside). */
export function sameDiscount(a: Partial<DiscountDraft> | null | undefined, b: Partial<DiscountDraft> | null | undefined): boolean {
  if (!a || !b) return false;
  const norm = (v: unknown) => v === undefined || v === null || v === '' || v === false || v === 0 ? '' : String(v);
  return DISCOUNT_FIELDS.every(k => norm(a[k]) === norm(b[k]));
}

/**
 * What stops this line's discount being saved, as a sentence staff can act
 * on, or null. `valueCents` is the line's value (what is charged before the
 * discount). `changed` says whether the saved line was changed in the form;
 * `saved` is the line as it was saved.
 */
export function lineDiscountProblem(d: DiscountDraft, o: { valueCents: number; changed: boolean; allowed: DiscountChoice[]; quantity: number; saved?: Partial<DiscountDraft> | null }): string | null {
  // A saved line left as it is goes back as stored, and the server keeps it
  // without checking it again: a credit package given away with Make FOC, a
  // voucher no longer offered, an old line with FOC and a voucher both.
  if (!o.changed) return null;
  const choice = d.discount ?? '';
  if (choice === 'legacy') return 'It still has both FOC and a voucher from before. Choose one discount for it.';
  if (choice === 'exchange' || choice === '') return null;
  // A line that takes no discount (a credit package or premium bundle) has no
  // Discount select, so the only one it can have is the FOC given with Make
  // FOC. It goes back as saved when something else on the line changes (the
  // Owner correcting its price): the server keeps it, and refusing it would
  // leave staff nothing to change. Anywhere else a discount the line may not
  // take is refused, saved or not (the server refuses it on a changed line).
  const keptMakeFoc = o.allowed.length === 0 && sameDiscount(d, o.saved);
  if (!o.allowed.includes(choice) && !keptMakeFoc) return `${DISCOUNT_CHOICE_LABELS[choice]} cannot be given on this line. Choose another discount.`;
  if (choice === 'foc') {
    const q = d.foc_quantity ?? 0;
    if (!(q > 0)) return 'Choose how many are free.';
    if (q > o.quantity) return 'The free quantity cannot be more than the quantity.';
    if (!d.foc_reason_id && !(d.foc_reason ?? '').trim()) return 'Give the FOC reason.';
    return null;
  }
  if (isVoucherChoice(choice)) {
    return d.line_voucher_id ? null : `Choose the ${choice === 'voucher' ? 'voucher' : `${choice} discount voucher`}.`;
  }
  const value = `S$${fromCents(o.valueCents).toFixed(2)}`;
  if (choice === 'manual') {
    const raw = String(d.discount_amount ?? '').trim();
    const a = Number(raw);
    if (!raw || !Number.isFinite(a) || a <= 0) return 'Enter the manual discount in S$, more than S$0.00.';
    if (decimals(raw) > 2) return 'Enter the manual discount to the cent.';
    if (toCents(a) > o.valueCents) return `The manual discount cannot be more than the line's value (${value}).`;
  } else {
    const raw = String(d.discount_percent ?? '').trim();
    const p = Number(raw);
    if (!raw || !Number.isFinite(p) || p <= 0 || p > 100) return 'Enter a percentage above 0 and no more than 100.';
    if (decimals(raw) > 3) return 'Use no more than three decimal places for the percentage.';
  }
  if (!(d.discount_reason ?? '').trim()) return `Give the reason for the ${choice === 'manual' ? 'manual' : 'percentage'} discount. It stays internal.`;
  return null;
}

// ── a saved line ───────────────────────────────────────────────────────────

/** The discount fields of a saved invoice line. */
export interface SavedLineDiscount {
  line_kind?: string | null;
  quantity?: number | string | null;
  line_voucher_id?: string | null; line_discount?: number | string | null;
  line_discount_type?: string | null; line_discount_percent?: number | string | null; line_discount_reason?: string | null;
  foc_quantity?: number | string | null; foc_reason_id?: string | null; foc_reason?: string | null;
}

const isLineDiscountType = (t: unknown): t is LineDiscountType => LINE_DISCOUNT_TYPES.includes(t as LineDiscountType);
/** A whole number of percent shows without decimals: 10, 12.5, 7.125. */
export const formatPercent = (p: number | string | null | undefined): string => String(Number(Number(p ?? 0).toFixed(3)));

/**
 * The form's discount fields for a saved line, so a correction starts from
 * exactly what was saved. A voucher saved before 384 shows under its
 * voucher's category (`categoryOf`) and goes back with no type until it is
 * changed. A line with FOC and a voucher both shows as such, read-only, until
 * one discount is chosen for it. Exchange credit stays as it is.
 */
export function restoreLineDiscount(it: SavedLineDiscount, categoryOf: (voucherId: string) => VoucherDiscountCategory | null): Partial<DiscountDraft> {
  const focQty = Number(it.foc_quantity ?? 0);
  const foc = focQty > 0 ? { foc_quantity: focQty, foc_reason_id: it.foc_reason_id ?? '', foc_reason: it.foc_reason ?? '',
    foc_all: it.quantity != null && focQty >= Number(it.quantity) } : {};
  const voucherId = it.line_voucher_id ?? '';
  const type = isLineDiscountType(it.line_discount_type) ? it.line_discount_type : null;
  const amount = Number(it.line_discount ?? 0);
  const blank = { line_voucher_id: '', discount_amount: '', discount_percent: '', discount_reason: '', discount_untyped: false };
  if (focQty > 0 && (voucherId || type)) return { ...blank, ...foc, discount: 'legacy', line_voucher_id: voucherId };
  if (focQty > 0 && amount > 0) return { ...blank, ...foc, discount: 'exchange' };
  if (focQty > 0) return { ...blank, ...foc, discount: 'foc' };
  if (type === 'manual') return { ...blank, discount: 'manual', discount_amount: amount.toFixed(2), discount_reason: it.line_discount_reason ?? '' };
  if (type === 'percentage') return { ...blank, discount: 'percentage', discount_percent: formatPercent(it.line_discount_percent), discount_reason: it.line_discount_reason ?? '' };
  if (type) return { ...blank, discount: type, line_voucher_id: voucherId };
  if (voucherId) return { ...blank, discount: categoryOf(voucherId) ?? 'voucher', line_voucher_id: voucherId, discount_untyped: true };
  if (amount > 0) return { ...blank, discount: 'exchange' };
  return { ...blank, discount: '' };
}

/**
 * A line's discount switched to `choice`. One discount per line, so whatever
 * the previous choice set is cleared, and choosing the saved discount again
 * brings back what was saved. An old line with FOC and a voucher both keeps
 * what it had of the one chosen for it: FOC its free quantity (no more than
 * the quantity) and reason, the voucher's category that voucher. FOC chosen
 * afresh starts with every unit free.
 */
export function switchDiscount<T extends DiscountDraft & { quantity: number; line_voucher_id: string }>(l: T, choice: DiscountChoice,
  saved: Partial<DiscountDraft> | null | undefined, categoryOf: (voucherId: string) => VoucherDiscountCategory | null): T {
  const cleared: T = { ...l, discount: choice, foc_quantity: 0, foc_reason_id: '', foc_reason: '', foc_all: false,
    line_voucher_id: '', discount_amount: '', discount_percent: '', discount_reason: '', discount_untyped: false };
  const qty = Math.max(0, Math.floor(Number(l.quantity) || 0));
  if (saved && (saved.discount ?? '') === choice) {
    const free = saved.foc_all && qty > 0 ? qty : saved.foc_quantity ?? 0;
    return { ...cleared, foc_quantity: free, foc_reason_id: saved.foc_reason_id ?? '', foc_reason: saved.foc_reason ?? '',
      foc_all: saved.foc_all ?? false, line_voucher_id: saved.line_voucher_id ?? '', discount_amount: saved.discount_amount ?? '',
      discount_percent: saved.discount_percent ?? '', discount_reason: saved.discount_reason ?? '', discount_untyped: saved.discount_untyped ?? false };
  }
  if (saved?.discount === 'legacy') {
    const free = saved.foc_quantity ?? 0;
    if (choice === 'foc' && free > 0) {
      const kept = qty > 0 ? Math.min(free, qty) : free;
      return { ...cleared, foc_quantity: kept, foc_reason_id: saved.foc_reason_id ?? '', foc_reason: saved.foc_reason ?? '',
        foc_all: qty > 0 && kept >= qty };
    }
    if (isVoucherChoice(choice) && saved.line_voucher_id && categoryOf(saved.line_voucher_id) === choice) {
      return { ...cleared, line_voucher_id: saved.line_voucher_id };
    }
  }
  return choice === 'foc' ? { ...cleared, foc_quantity: Math.max(1, qty), foc_all: true } : cleared;
}

/**
 * A line's quantity typed in. "All free" (foc_all) follows it; any other free
 * quantity stays as chosen, even above the quantity for a moment (the save
 * refuses that, and the free select shows it), so a quantity cleared and
 * retyped, or typed digit by digit, never makes more of the line free.
 */
export function withQuantity<T extends DiscountDraft & { quantity: number }>(l: T, quantity: number): T {
  return { ...l, quantity, ...(l.discount === 'foc' && l.foc_all && quantity > 0 ? { foc_quantity: quantity } : {}) };
}

/**
 * The line's discount as the customer's copy prints it, under the line:
 * "<voucher name> −S$x" for a voucher of any category, "Discount −S$x" for a
 * manual amount, "Discount 10% −S$x" for a percentage. Null when the line has
 * none, and for exchange credit, which the totals already name. Deliberately
 * takes no reason: the reason is internal and never printed.
 */
export function printedLineDiscount(it: SavedLineDiscount, voucherName: string, minus = '−'): string | null {
  const amount = Number(it.line_discount ?? 0);
  if (!(amount > 0)) return null;
  const type = isLineDiscountType(it.line_discount_type) ? it.line_discount_type : it.line_voucher_id ? 'voucher' : null;
  if (!type) return null;
  const money = `${minus}S$${amount.toFixed(2)}`;
  if (type === 'manual') return `Discount ${money}`;
  if (type === 'percentage') return it.line_discount_percent != null ? `Discount ${formatPercent(it.line_discount_percent)}% ${money}` : `Discount ${money}`;
  return `${voucherName || 'Voucher'} ${money}`;
}
