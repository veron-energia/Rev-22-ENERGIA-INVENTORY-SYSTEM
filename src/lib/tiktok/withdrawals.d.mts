export const WITHDRAWAL_HEADERS: Record<string, string[]>;
export interface WithdrawalRow {
  transaction_type: string; reference_id: string; request_time?: string; amount?: string; status?: string; success_time?: string;
}
export function readWithdrawalRecords(
  grids: { name: string; grid: string[][] }[], skipSheet?: string,
): { sheetName: string; rows: WithdrawalRow[] } | null;
export function describeWithdrawals(rows: WithdrawalRow[]): string;
export function describeBalanceCounts(payouts: number, others: number): string;
