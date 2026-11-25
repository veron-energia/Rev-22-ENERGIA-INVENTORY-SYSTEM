/**
 * Who may change commission rates, as migration 535 decides it in the
 * database (security audit of 17 Nov 2026, finding M12; the user's decisions
 * of 24 Nov 2026). The pages use these only to show a form read-only, disable
 * a box and say why, and to stop a value the server would refuse before it is
 * sent; the database checks every change again and its message is still shown
 * when a refusal gets through (another tab, stale data).
 *
 *   1. Only an Owner changes the four affiliate commission rates (the
 *      Commissions page's Rates window). An Admin is not an Owner. Managers
 *      still see the rates.
 *   2. An invoice keeps the rates it first earned at: a rate change applies to
 *      invoices that first earn commission after it (the page says so).
 *   3. A credit package's or premium bundle's own rates (Tier 1, Tier 2, Staff
 *      commission) are none, or 0 to 100, and only an Owner sets or changes
 *      them. A Manager still edits everything else, and their save sends the
 *      three rates back as stored.
 */
import type { UserRole } from '../../types';

/** 535 (M12): the sentences the database refuses with. The role ones are code 42501. */
export const COMMISSION_RATE_MESSAGES = {
  ratesOwnerOnly: 'Only an Owner can change the commission rates.',
  ownRatesOwnerOnly: "Only an Owner can set a package's or bundle's own commission rates.",
  tier1Range: "A package's or bundle's Tier 1 rate must be between 0 and 100.",
  tier2Range: "A package's or bundle's Tier 2 rate must be between 0 and 100.",
  staffRange: "A package's or bundle's Staff commission rate must be between 0 and 100.",
} as const;

/** Shorter notes for beside a read-only form or a disabled box. */
export const COMMISSION_RATE_NOTES = {
  ownRatesReadOnly: 'Only an Owner sets these rates.',
  keptRates: 'Applies to invoices that first earn commission from now on. An invoice that has already earned keeps the rates it earned at, also when it is corrected, reconciled or paid in instalments.',
} as const;

/** 535 (M12, 24 Nov 2026) rule 1: changing the four affiliate commission rates. */
export const canChangeCommissionRates = (role?: UserRole | null): boolean => role === 'owner';

/** 535 (M12, 24 Nov 2026) rule 3: setting or changing a package's or bundle's own rates. */
export const canSetOwnCommissionRates = (role?: UserRole | null): boolean => role === 'owner';

/** A package's or bundle's own rates as the form holds them: text, '' for none. */
export type OwnRatesDraft = { tier1_rate: string; tier2_rate: string; staff_commission_rate: string };
export const OWN_RATE_KEYS = ['tier1_rate', 'tier2_rate', 'staff_commission_rate'] as const;
const RANGE_MESSAGE: Record<(typeof OWN_RATE_KEYS)[number], string> = {
  tier1_rate: COMMISSION_RATE_MESSAGES.tier1Range,
  tier2_rate: COMMISSION_RATE_MESSAGES.tier2Range,
  staff_commission_rate: COMMISSION_RATE_MESSAGES.staffRange,
};

/** The text of a stored own rate for the form: '' for none. */
export const ownRateText = (v: unknown): string => (v === null || v === undefined || v === '' ? '' : String(v));

/** What the form sends for an own rate: null for a blank box, else the number. */
export const ownRateValue = (t: string | null | undefined): number | null => {
  const s = (t ?? '').trim();
  return s === '' ? null : Number(s);
};

/** 535 (M12) rule 3: the first box outside 0 to 100 (or not a number), with the
 *  server's sentence; null when every box is blank or within 0 to 100. */
export function ownRatesError(d: OwnRatesDraft): string | null {
  for (const k of OWN_RATE_KEYS) {
    const v = ownRateValue(d[k]);
    if (v !== null && (!Number.isFinite(v) || v < 0 || v > 100)) return RANGE_MESSAGE[k];
  }
  return null;
}

/**
 * 538 (security audit of 17 Nov 2026, M12; the user, 25 Nov 2026: "Keep each line's type",
 * "Owner repair, recorded"): an invoice line keeps the commission kind it first earned as, and
 * only an Owner corrects an invoice's kept rates and line kinds, with a reason, after a preview.
 */
export const COMMISSION_BASIS_MESSAGES = {
  ownerOnly: "Only an Owner can correct an invoice's kept commission rates or line kinds.",
  reason: 'Give the reason for the correction.',
  notEarned: 'This invoice has earned no affiliate commission yet, so it keeps no rates or line kinds to correct.',
  rate: 'A rate is tier1_own, tier1_third, tier2_own or tier2_third, each a number from 0 to 100.',
  line: 'That line is not on this invoice, or it is a package, a bundle or a late fee (they have no kind of their own).',
  kind: "A line's kind is own, third_party or no_commission.",
  nothing: 'Nothing would change: these are the rates and kinds this invoice keeps.',
} as const;

/** 538 (M12, 25 Nov 2026): the kinds a line keeps, as the window names them. */
export const LINE_KINDS = ['own', 'third_party', 'no_commission'] as const;
export type LineKind = (typeof LINE_KINDS)[number];
export const LINE_KIND_LABELS: Record<LineKind, string> = {
  own: 'Own', third_party: 'Third party', no_commission: 'No commission',
};

/** 538 (M12, 25 Nov 2026): the four kept rates, as the server names them. */
export const KEPT_RATE_KEYS = ['tier1_own', 'tier1_third', 'tier2_own', 'tier2_third'] as const;
export type KeptRateKey = (typeof KEPT_RATE_KEYS)[number];
export const KEPT_RATE_LABELS: Record<KeptRateKey, string> = {
  tier1_own: 'Tier 1 — Own', tier1_third: 'Tier 1 — Third party', tier2_own: 'Tier 2 — Own', tier2_third: 'Tier 2 — Third party',
};

/** 538 (M12, 25 Nov 2026): who corrects an invoice's kept rates and line kinds (an Admin is not an Owner). */
export const canCorrectCommissionBasis = (role?: UserRole | null): boolean => role === 'owner';

/** 538: what the window sends: only the rates and kinds that differ from what is kept. A rate box
 *  that is blank or not a number from 0 to 100 gives an error in the server's words. */
export function basisChanges(
  kept: { rates: Partial<Record<KeptRateKey, number>> | null; lines: { invoice_item_id: string; kind: string }[] },
  draft: { rates: Partial<Record<KeptRateKey, string>>; kinds: Record<string, string> },
): { rates: Partial<Record<KeptRateKey, number>>; kinds: { invoice_item_id: string; kind: string }[]; error: string | null } {
  const rates: Partial<Record<KeptRateKey, number>> = {};
  for (const k of KEPT_RATE_KEYS) {
    const t = (draft.rates[k] ?? '').trim();
    const v = Number(t);
    if (t === '' || !Number.isFinite(v) || v < 0 || v > 100) return { rates: {}, kinds: [], error: COMMISSION_BASIS_MESSAGES.rate };
    if (Number(kept.rates?.[k]) !== v) rates[k] = v;
  }
  const kinds = kept.lines
    .filter(l => draft.kinds[l.invoice_item_id] && draft.kinds[l.invoice_item_id] !== l.kind)
    .map(l => ({ invoice_item_id: l.invoice_item_id, kind: draft.kinds[l.invoice_item_id] }));
  return { rates, kinds, error: null };
}

/** 538 (M12): the kinds worth offering on a line, as earn_invoice_commission uses them. A voucher
 *  line earns as own whatever its kind, and a promotion line by its own and third-party split, so
 *  on those only no_commission (leaving the line out) changes anything: own or no_commission. Every
 *  other line (a product, special product, rental, therapy, event ticket) earns at its kind's rate:
 *  all three. A kind already kept is always listed, so the box shows what is kept. */
export function kindsOffered(lineKind: string, kept?: string | null): LineKind[] {
  const base: LineKind[] = lineKind === 'voucher' || lineKind === 'promotion' ? ['own', 'no_commission'] : [...LINE_KINDS];
  return kept && (LINE_KINDS as readonly string[]).includes(kept) && !base.includes(kept as LineKind)
    ? LINE_KINDS.filter(k => base.includes(k) || k === kept) : base;
}

/** 538 (M12): a request id for one save: a v4 uuid (the server takes a uuid), from
 *  crypto.randomUUID, else built from crypto.getRandomValues. */
export function newRequestId(): string {
  const c = globalThis.crypto as Crypto | undefined;
  if (c?.randomUUID) return c.randomUUID();
  const b = new Uint8Array(16);
  if (c?.getRandomValues) c.getRandomValues(b); else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
  b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map(x => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
