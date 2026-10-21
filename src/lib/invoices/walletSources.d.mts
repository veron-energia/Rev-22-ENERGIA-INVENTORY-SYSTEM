export type WalletSource = 'credit_package' | 'premium_bundle' | 'other';
export const WALLET_SOURCES: readonly (readonly [WalletSource, string])[];
export const WALLET_CATEGORIES: readonly (readonly [string, string])[];

/** A payment method as the pages read it (payment_methods). */
export interface WalletMethodLike {
  id?: string;
  name?: string | null;
  is_wallet_credit?: boolean | null;
  wallet_category?: string | null;
  wallet_source?: string | null;
}
/** One method of invoice_wallet_availability(). */
export interface WalletAvailabilityMethod {
  payment_method_id: string;
  name: string;
  wallet_category: string | null;
  wallet_source: string | null;
  pays_from: string;
  available: number | string;
  held: number | string;
  rank: number;
}
export interface WalletAvailability {
  invoice_id?: string;
  customer_id?: string | null;
  payable?: boolean;
  credit_line?: boolean;
  default_method_id?: string | null;
  methods?: WalletAvailabilityMethod[];
}
/** customer_credit_balances(), with 443's sources and purchases. */
export interface WalletBalances {
  customer_id?: string | null;
  categories?: Record<string, number | string | null> | null;
  available_total?: number | string | null;
  sources?: Record<string, Record<string, number | string | null>> | null;
  purchases?: {
    source: string; name?: string | null; invoice_id?: string | null; invoice_no?: string | null;
    bought_on?: string | null; received?: boolean | null;
    paid?: number | string; bonus?: number | string; legacy?: number | string; total?: number | string;
  }[] | null;
}

export function sourceName(source: string | null | undefined): string;
export function methodPaysFrom(method: WalletMethodLike | null | undefined): string | null;
export function paymentSourceSuffix(sources: readonly string[] | null | undefined, method: WalletMethodLike | null | undefined): string;
export function paymentMethodLabel(name: string | null | undefined, sources: readonly string[] | null | undefined,
  method: WalletMethodLike | null | undefined): string;
export function heldForMethod(method: WalletMethodLike | null | undefined, balances: WalletBalances | null | undefined): number;
export function walletMethodOptions(args: {
  methods: readonly WalletMethodLike[] | null | undefined;
  availability: WalletAvailability | null | undefined;
  balances: WalletBalances | null | undefined;
  money?: (n: number) => string;
}): { value: string; label: string; disabled: boolean }[];
export function creditPackageFirstNote(args: {
  methodId: string; methods: readonly WalletMethodLike[] | null | undefined;
  availability: WalletAvailability | null | undefined; money?: (n: number) => string;
  /** The payment's other rows: what they put on Credit Package methods is taken off. */
  otherLines?: readonly { payment_method_id?: string | null; amount?: number | string | null }[] | null;
}): string | null;
export function walletBySource(balances: WalletBalances | null | undefined):
  { source: WalletSource; name: string; total: number; parts: [string, number][] }[] | null;
export function walletSourceTiles(balances: WalletBalances | null | undefined):
  { source: WalletSource; name: string; total: number; parts: [string, number][] }[] | null;
export function purchasesBySource(balances: WalletBalances | null | undefined): {
  source: WalletSource; name: string;
  items: { name: string; invoiceNo: string | null; boughtOn: string | null; received: boolean; parts: [string, number][]; total: number }[];
}[];
