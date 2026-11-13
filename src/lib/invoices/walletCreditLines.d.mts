import type { WalletMethodLike } from './walletSources.mjs';

export const PACKAGE_LINE_LABELS: Readonly<Record<'credit_package' | 'premium_bundle', string>>;

/** The line a wallet payment adds to on the copies and the screen. */
export function walletLineLabel(paymentLabel: string | null | undefined, method?: WalletMethodLike | null): string;

/** An invoice_refunds row, as much of it as the copies need. */
export interface WalletRefundLike {
  payment_id?: string | null;
  amount?: number | string | null;
  credit_returned?: number | string | null;
  created_at?: string | null;
}

export interface WalletCreditLine {
  label: string;
  /** The credit used, net of corrections. */
  amount: number;
  /** 'S$327.00 returned to wallet 11/11/2026', one per refund that put credit back. */
  returned: string[];
}

export interface WalletCredit<P> {
  lines: WalletCreditLine[];
  credit: number;
  moneyPayments: P[];
  moneyPaid: number;
  moneyRefunded: number;
  totalLeft: number;
}

export function walletCredit<P extends { id?: string | null; amount?: unknown; entry_kind?: string | null }>(args: {
  payments: P[] | null | undefined;
  isWallet: (payment: P) => boolean;
  lineLabel: (payment: P) => string;
  refunds: WalletRefundLike[] | null | undefined;
  refunded?: unknown;
  total: unknown;
  day: (at: string) => string;
}): WalletCredit<P> | null;
