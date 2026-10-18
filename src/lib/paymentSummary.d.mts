export function paymentSummaryDefaultRange(today: string): { from: string; to: string };
export function daysBetween(from: string, to: string): string[];
export function dayFirst(iso: string): string;
export const TOTAL_HEADER: string;
export const WALLET_TOTAL_HEADER: string;
export function walletHeader(name: string): string;
export function buildPaymentSummary(input: {
  methods: { payment_method_id: string; method_name: string; is_wallet_credit?: boolean | null }[];
  rows: { pay_date: string; payment_method_id: string; method_name?: string; amount: number | string }[];
  from: string;
  to: string;
}): { headers: string[]; body: Record<string, string | number>[]; moneyTaken: number; walletUsed: number };
