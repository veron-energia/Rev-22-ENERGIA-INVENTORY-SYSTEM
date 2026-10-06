export type PaymentQrField = 'qr_paynow_url' | 'qr_grabpay_url' | 'qr_atome_url';
export interface PaymentQrKind { field: PaymentQrField; match: string; label: string }
export const PAYMENT_QR_KINDS: readonly PaymentQrKind[];

/** A payment_methods row, or as much of it as matters here. */
export interface PaymentQrMethod { name?: string | null; is_wallet_credit?: boolean | null }
/** A stores row, or as much of it as matters here. */
export interface PaymentQrStore {
  id: string;
  name?: string | null;
  is_active?: boolean | null;
  deleted_at?: string | null;
  created_at?: string | null;
  qr_paynow_url?: string | null;
  qr_grabpay_url?: string | null;
  qr_atome_url?: string | null;
}
export interface PaymentQrImage {
  url: string;
  storeId: string;
  storeName: string;
  /** The invoice's own store has none, so this is another store's. */
  borrowed: boolean;
}
export interface PaymentQrChoice {
  field: PaymentQrField;
  /** PayNow, GrabPay or Atome. */
  label: string;
  /** The method as staff picked it, e.g. "Atome full payment". */
  methodName: string;
  /** Null when no active store has an image of this kind. */
  image: PaymentQrImage | null;
}

export function paymentQrKind(method: PaymentQrMethod | null | undefined): PaymentQrKind | null;
export function paymentQrImage(field: string, storeId: string | null | undefined,
  stores: readonly PaymentQrStore[] | null | undefined): PaymentQrImage | null;
export function paymentQrFor(method: PaymentQrMethod | null | undefined, storeId: string | null | undefined,
  stores: readonly PaymentQrStore[] | null | undefined): PaymentQrChoice | null;
export function paymentQrAmount(amount: number | string | null | undefined): string | null;
