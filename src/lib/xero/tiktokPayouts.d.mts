/** One payout of tiktok_bank_payouts (375). Amounts in S$, dates YYYY-MM-DD (Singapore). */
export interface TikTokBankPayout {
  reference_id: string; paid_on: string; amount: number | string; status: string | null; transferred: boolean;
  /** The confirmed file the payout is taken from, and any other files giving it another amount. */
  file_name: string | null; disagreeing: { amount: number | string; file_name: string | null }[];
  /** The Wednesday on or before the day it was paid, and the Thursday before that. */
  wednesday: string; week_start: string;
  /** The app's own figure for that week (374), or null. */
  app_payout: number | string | null; app_rows: number | null;
  uncovered_days: string[]; left_out_count: number;
}
export interface TikTokBankPayouts {
  from: string; to: string; today: string; timezone: string;
  payouts: TikTokBankPayout[];
  wednesdays_without_payout: { wednesday: string; week_start: string; app_payout: number | string; app_rows: number; uncovered_days: string[]; left_out_count?: number }[];
  /** Payouts in the imported files with no date: in no export. */
  undated_payout_count?: number;
}
export interface BankPayoutPlan {
  from: string; to: string;
  exportable: (TikTokBankPayout & { cents: number })[];
  warnings: string[];
  /** Every payout between the dates, exportable or not. */
  payoutCount: number;
}

export const TIKTOK_XERO_CONTACT: string;
export function toCents(amount: number | string | null | undefined): number;
export function formatCents(cents: number): string;
export function sgd(cents: number): string;
export function dayLabel(iso: string): string;
export function weekLabel(week: { week_start: string; week_end: string }): string;
export function xeroDate(iso: string): string;
export function planBankPayouts(data: TikTokBankPayouts): BankPayoutPlan;
export function buildBankPayoutRows(plan: BankPayoutPlan, accountCode: string, taxType: string): {
  rows: Record<string, unknown>[]; headers: string[]; payouts: number; totalCents: number;
};
export function tiktokXeroFilename(from: string, to: string): string;
