export function toCents(value: unknown): number;
export function centsToNumber(cents: number): number;
export function formatCents(cents: number): string;
export const CATEGORY: {
  SALE: 'sale'; SALE_REFUND: 'sale_refund'; FEE: 'fee'; FEE_REVERSAL: 'fee_reversal';
  AD_EXPENSE: 'ad_expense'; EXPENSE_REVERSAL: 'expense_reversal';
  BALANCE_MOVEMENT: 'balance_movement'; UNKNOWN: 'unknown';
};
export const REVIEW_CATEGORIES: string[];
export function classifyTransaction(transactionType: unknown, opts?: { adjustmentCents?: number }): string;
export interface SourceRow {
  transactionType?: unknown; totalRevenue?: unknown; totalFees?: unknown;
  adjustmentAmount?: unknown; totalSettlementAmount?: unknown; category?: string;
}
export function rowEffect(row: SourceRow): { revenue: number; fee: number; expense: number; category: string };
export function summarise(rows: SourceRow[]): {
  rows: number; revenue: number; fee: number; expense: number; settlement: number;
  income: number; tiktokNetSettlement: number; byCategory: Record<string, number>; review: SourceRow[];
};
