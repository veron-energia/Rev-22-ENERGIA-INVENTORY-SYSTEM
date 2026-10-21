// The Commissions page's Rates window (AFFILIATES-M2). The four rates are
// typed as text, so a blank box stays blank instead of turning into 0, and a
// real 0 shows as "0". Nothing is saved until every box holds a number from 0
// to 100, something changed, and the person confirmed the old → new list.

export type RateKey = 't1_own' | 't1_third' | 't2_own' | 't2_third';
export type Rates = Record<RateKey, number>;
export type RatesDraft = Record<RateKey, string>;

export const RATE_KEYS: RateKey[] = ['t1_own', 't1_third', 't2_own', 't2_third'];

export const RATE_LABELS: Record<RateKey, string> = {
  t1_own: 'Tier 1 — Own',
  t1_third: 'Tier 1 — Third-party',
  t2_own: 'Tier 2 — Own',
  t2_third: 'Tier 2 — Third-party',
};

/** The app_settings row as the page reads it, or null when a rate is missing
 *  or not a number (the window then stays closed). */
export function ratesFromSettings(row: Record<string, unknown> | null | undefined): Rates | null {
  if (!row) return null;
  const pick = (k: string) => {
    const v = row[k];
    if (v === null || v === undefined || v === '') return NaN;
    return Number(v);
  };
  const r: Rates = {
    t1_own: pick('commission_tier1_own_rate'),
    t1_third: pick('commission_tier1_third_rate'),
    t2_own: pick('commission_tier2_own_rate'),
    t2_third: pick('commission_tier2_third_rate'),
  };
  return RATE_KEYS.every(k => Number.isFinite(r[k])) ? r : null;
}

/** A rate as the box shows it: 0 is "0", never blank. */
export function rateText(n: number): string {
  return Number.isFinite(n) ? String(n) : '';
}

export function draftFromRates(r: Rates): RatesDraft {
  return { t1_own: rateText(r.t1_own), t1_third: rateText(r.t1_third), t2_own: rateText(r.t2_own), t2_third: rateText(r.t2_third) };
}

/** One box: a number from 0 to 100 with at most 3 decimals, or why not. */
export function parseRate(text: string): { value: number | null; error: string | null } {
  const t = (text ?? '').trim();
  if (t === '') return { value: null, error: 'Enter a rate.' };
  if (!/^\d+(\.\d{1,3})?$/.test(t) && !/^\.\d{1,3}$/.test(t)) return { value: null, error: 'Enter a number, like 15 or 4.5.' };
  const n = Number(t);
  if (!Number.isFinite(n) || n < 0 || n > 100) return { value: null, error: 'Enter a rate from 0 to 100.' };
  return { value: n, error: null };
}

export interface RateChange { key: RateKey; label: string; from: number; to: number }

/** Every box checked against the saved rates: the problems (by box), the new
 *  rates when there are none, and what changed. */
export function checkRatesDraft(saved: Rates, draft: RatesDraft): {
  errors: Partial<Record<RateKey, string>>; rates: Rates | null; changes: RateChange[];
} {
  const errors: Partial<Record<RateKey, string>> = {};
  const out = {} as Rates;
  for (const k of RATE_KEYS) {
    const p = parseRate(draft[k]);
    if (p.error) errors[k] = p.error; else out[k] = p.value as number;
  }
  if (Object.keys(errors).length > 0) return { errors, rates: null, changes: [] };
  const changes = RATE_KEYS.filter(k => out[k] !== saved[k])
    .map(k => ({ key: k, label: RATE_LABELS[k], from: saved[k], to: out[k] }));
  return { errors, rates: out, changes };
}

/** The same four rates. */
export function sameRates(a: Rates, b: Rates): boolean {
  return RATE_KEYS.every(k => a[k] === b[k]);
}

/** The saved rates changed while the window was open (another Owner or
 *  Manager saved). A box the person left alone takes the new saved rate; a
 *  box they changed keeps what they typed. So a save never puts back a rate
 *  they did not touch. */
export function rebaseDraft(oldSaved: Rates, nowSaved: Rates, draft: RatesDraft): RatesDraft {
  const out = { ...draft };
  for (const k of RATE_KEYS) {
    if (parseRate(draft[k]).value === oldSaved[k]) out[k] = rateText(nowSaved[k]);
  }
  return out;
}

/** "Tier 2 — Own: 35% → 30%" */
export function changeLine(c: RateChange): string {
  return `${c.label}: ${c.from}% → ${c.to}%`;
}
