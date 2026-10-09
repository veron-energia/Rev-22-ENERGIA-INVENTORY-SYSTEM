/** One row of xero_sales_events (411). Amounts in S$ (signed), dates YYYY-MM-DD (Singapore). */
export interface XeroSalesEvent {
  event_kind: 'receipt' | 'correction_replacement' | 'correction_reversal' | 'refund'
    | 'legacy_refund_left_out' | 'refund_unsourced' | string;
  event_id: string; invoice_id: string; invoice_no: string | null; store_id: string;
  /** The Xero document number; null for the kinds that are never exported. */
  document_number: string | null;
  document_date: string; amount: number | string; recorded_at?: string | null;
  customer_id: string | null; contact_name: string | null; contact_email: string | null; contact_address: string | null;
}
export interface XeroSalesExportRecord {
  id: string; exported_at: string; exported_by: string; from_date: string; to_date: string;
  store_id: string | null; covered_store_ids: string[]; document_count: number; net_total: number | string;
}
export interface XeroSalesDownload {
  event_kind: string; event_id: string; document_number: string; document_date: string;
  amount: number | string; exported_at: string; times: number;
}
export interface XeroSalesVanished {
  event_kind: string; event_id: string; document_number: string; document_date: string; amount: number | string;
  exported_at: string; now_date: string | null; now_amount: number | string | null;
  /** Listed for another store now (its invoice was moved); now_store_id when the caller can see that store. */
  moved?: boolean; now_store_id?: string | null;
}
/** xero_sales_export_review (411). */
export interface XeroSalesReview {
  recorded_since: string | null;
  exports: XeroSalesExportRecord[];
  downloads: XeroSalesDownload[];
  vanished: XeroSalesVanished[];
  missed: XeroSalesEvent[];
}
export interface XeroSalesPlan {
  include: XeroSalesEvent[];
  /** Documents already downloaded that the person asked for again (sent marked "redownload"). */
  again: XeroSalesEvent[];
  legacy: XeroSalesEvent[];
  already: { event: XeroSalesEvent; download: XeroSalesDownload }[];
  changed: { event: XeroSalesEvent; download: XeroSalesDownload }[];
  late: XeroSalesEvent[];
  missed: XeroSalesEvent[];
  vanished: XeroSalesVanished[];
  moved: XeroSalesVanished[];
  exports: XeroSalesExportRecord[];
  recordedSince: string | null;
  /** The dates start on or before the first recorded download (or none is recorded). */
  unrecorded: boolean;
  needsReview: boolean;
}

export const EXPORTABLE_KINDS: string[];
export function amountCents(amount: number | string | null | undefined): bigint;
export function formatCents(cents: bigint): string;
export function sgd(cents: bigint): string;
export function dayLabel(iso: string | null | undefined): string;
export function momentLabel(ts: string | null | undefined): string;
export function singaporeDay(ts: string | null | undefined): string | null;
export function expectedDocumentNumber(event: Pick<XeroSalesEvent, 'event_kind' | 'event_id' | 'invoice_no'>): string | null;
export function eventKey(e: { event_kind: string; event_id: string }): string;
export function planXeroSalesExport(
  events: XeroSalesEvent[], review: XeroSalesReview | null,
  options?: { skipDownloaded?: boolean; addMissed?: boolean; from?: string | null },
): XeroSalesPlan;
export function totalCents(events: { amount: number | string }[]): bigint;
