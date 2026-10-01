/** One Wednesday of tiktok_xero_payouts (374). Amounts in S$, dates YYYY-MM-DD (Singapore). */
export interface TikTokPayoutWeek {
  payout_date: string; week_start: string; week_end: string; finished: boolean;
  row_count: number; revenue: number | string; fee: number | string; expense: number | string;
  payout: number | string; tiktok_net: number | string;
  unknown_count: number; balance_movement_count?: number; other_currency_count: number;
  left_out_count: number; left_out_settlement: number | string;
  /** Days of the week that no confirmed settlement file reaches. */
  uncovered_days?: string[];
}
export interface TikTokPayoutMonth {
  year: number; month: number; period_start: string; period_end: string; today: string; timezone: string;
  weeks: TikTokPayoutWeek[]; undated_count: number; income: number | string;
  /** The month's Total Income for every store, from tiktok_settlement_totals. */
  month_income?: number | string;
}
export type TikTokPayoutStatus = 'export' | 'not_finished' | 'nothing';
export interface PlannedPayoutWeek extends TikTokPayoutWeek {
  cents: { sales: number; fees: number; ads: number; payout: number };
  status: TikTokPayoutStatus;
  warnings: string[];
}
export interface TikTokPayoutPlan {
  year: number; month: number;
  weeks: PlannedPayoutWeek[]; exportable: PlannedPayoutWeek[]; monthWarnings: string[];
  exportCents: number; monthIncomeCents: number;
}
export interface TikTokXeroCodes { salesCode: string; feesCode: string; adsCode: string; taxType: string }

export const TIKTOK_XERO_CONTACT: string;
export function toCents(amount: number | string | null | undefined): number;
export function formatCents(cents: number): string;
export function sgd(cents: number): string;
export function dayLabel(iso: string): string;
export function weekLabel(week: { week_start: string; week_end: string }): string;
export function xeroDate(iso: string): string;
export function planTikTokPayouts(data: TikTokPayoutMonth): TikTokPayoutPlan;
export function neededCodes(plan: TikTokPayoutPlan, payoutDates?: string[]): ('salesCode' | 'feesCode' | 'adsCode')[];
export function buildTikTokPayoutRows(plan: TikTokPayoutPlan, codes: TikTokXeroCodes, payoutDates?: string[]): {
  rows: Record<string, unknown>[]; headers: string[];
  weeks: number; documents: number; creditNotes: number; total: string;
};
export function tiktokXeroFilename(year: number, month: number): string;
