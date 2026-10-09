export interface ExchangeMethodLike {
  id: string;
  name: string;
  is_active?: boolean;
  deleted_at?: string | null;
  is_wallet_credit?: boolean;
}
export interface BundleLineLike {
  quantity: number | string;
  exchanged_at?: string | null;
  component_exchanged?: { product_id?: string; qty?: number; exchange_id?: string }[] | null;
}
export interface BundleQuoteItem {
  product_id: string;
  name: string;
  quantity: number;
}
export interface BundleQuote {
  /** Why the swap cannot be done; null when it can. */
  problem: string | null;
  credit: number;
  replacement: number;
  topup: number;
  nonrefundable: number;
  returned: BundleQuoteItem[];
  replacement_items: BundleQuoteItem[];
}
export function exchangePaymentMethods<T extends ExchangeMethodLike>(methods: T[] | null | undefined): T[];
export function componentsExchanged(line: BundleLineLike | null | undefined): string[];
export function bundleLineBlock(line: BundleLineLike | null | undefined, mode: 'bundle' | 'component' | string): string | null;
export function exchangePaymentRowProblem(
  rows: { payment_method_id?: string | null; amount?: number | string | null }[] | null | undefined,
  allowedIds: string[] | null | undefined,
  instalmentId: string,
): string | null;
export function exchangePaymentProblem(p: { due: number; received: number; exact: boolean }): string | null;
export function bundleQuoteFromRpc(data: unknown): BundleQuote | null;
export function affiliateHint(ctx: { affiliate?: string | null; affiliate_inherited_id?: string | null } | null | undefined): string;
