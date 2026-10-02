export type WalletKind = 'paid' | 'bonus' | 'legacy' | 'promotional' | 'exchange';
export const WALLET_KINDS: readonly (readonly [WalletKind, string])[];
export const NO_CREDIT_LINE_STATUSES: readonly string[];
export const CREDIT_BALANCE_TIMEOUT_MS: number;

/** customer_credit_balances(p_customer_id), as the server returns it. */
export interface CreditBalances {
  customer_id?: string | null;
  categories?: Partial<Record<WalletKind, number | string | null>> | null;
  available_total?: number | string | null;
}
export interface CreditBalanceLine { label: string; amount: string; detail: string | null }
export interface PaymentLike { amount?: number | string | null; entry_kind?: string | null; payment_method_id?: string | null }

export function signedPaymentAmount(p: PaymentLike | null | undefined): number;
export function paymentsTotal(payments: readonly PaymentLike[] | null | undefined): number;
export function paidWithWalletCredit(payments: readonly PaymentLike[] | null | undefined, walletMethodIds: Iterable<string> | null | undefined): boolean;
export function singaporeDateLabel(now?: Date): string;
export function shouldShowCreditBalance(args: { customerId: string | null | undefined; status: string | null | undefined; balanceTotal: number | null | undefined; paidWithWallet: boolean }): boolean;
export function creditBalanceLine(balance: CreditBalances, now?: Date): CreditBalanceLine;
export const CREDIT_KIND_SEPARATOR: string;
export function wrapCreditDetail(detail: string | null | undefined, maxWidth: number, measure: (text: string) => number): string[];
export function creditBalanceHtml(line: CreditBalanceLine | null | undefined): string;
/** Defines fitCreditBalance() for the print window. */
export const CREDIT_BALANCE_FIT_SCRIPT: string;
export function isCreditAccessRefusal(error: unknown): boolean;
export interface CreditBalanceReadArgs {
  invoice: { customer_id?: string | null; status?: string | null } | null | undefined;
  payments: readonly PaymentLike[] | null | undefined;
  walletMethodIds: Iterable<string> | null | undefined;
  fetchBalances: (customerId: string) => PromiseLike<{ data: unknown; error: unknown }>;
  now?: Date | (() => Date);
  timeoutMs?: number;
}
export function readCreditBalanceForInvoice(args: CreditBalanceReadArgs): Promise<{ line: CreditBalanceLine | null; unreadable: boolean }>;
export function creditBalanceForInvoice(args: CreditBalanceReadArgs): Promise<CreditBalanceLine | null>;
