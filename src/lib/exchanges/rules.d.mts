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
  /** 424: the returned bundle's value today, and what was paid for it (null before 424). */
  todays_value: number | null;
  paid: number | null;
  returned: BundleQuoteItem[];
  replacement_items: BundleQuoteItem[];
}
export function exchangePaymentMethods<T extends ExchangeMethodLike>(methods: T[] | null | undefined): T[];
export function componentsExchanged(line: BundleLineLike | null | undefined): string[];
export function bundleLineBlock(line: BundleLineLike | null | undefined, mode: 'bundle' | 'items' | string): string | null;
export function exchangePaymentRowProblem(
  rows: { payment_method_id?: string | null; amount?: number | string | null }[] | null | undefined,
  allowedIds: string[] | null | undefined,
  instalmentId: string,
): string | null;
export function exchangePaymentProblem(p: { due: number; received: number; exact: boolean }): string | null;
/** 455: a server message with the mode it names in the page's words (Bundle component is now Items). */
export function exchangeServerWords(text: string): string;
export function bundleQuoteFromRpc(data: unknown): BundleQuote | null;
export function affiliateHint(ctx: { affiliate?: string | null; affiliate_inherited_id?: string | null } | null | undefined): string;

/** 424: what a returned item counts for: today's price, what was paid, and the lower of the two. */
export interface CreditFigures {
  todays: number | null;
  paid: number | null;
  credit: number | null;
}
export interface CreditPreviewOption extends CreditFigures { quantity: number; }
export interface CreditPreviewComponent { product_id: string; quantity: number; options: CreditPreviewOption[]; }
export interface CreditPreviewLine extends CreditFigures {
  invoice_item_id: string;
  line_kind: string;
  quantity: number;
  components: CreditPreviewComponent[];
}
export interface CreditPreview { lines: CreditPreviewLine[]; }
export function creditPreviewFromRpc(data: unknown): CreditPreview | null;
export function previewLine(preview: CreditPreview | null | undefined, lineId: string | null | undefined): CreditPreviewLine | null;
export function productLinesCredit(preview: CreditPreview | null | undefined, lineIds: string[] | null | undefined):
  { todays: number; paid: number; credit: number | null; missing: boolean };
export function componentCredit(preview: CreditPreview | null | undefined, lineId: string | null | undefined,
  productId: string | null | undefined, qty: number): CreditFigures | null;
export function creditBasisText(fig: CreditFigures | null | undefined, share?: boolean): string;
/** 455: an item of a bundle ticked to return, and how many of it. */
export interface ItemPick { invoice_item_id: string; product_id: string; quantity: number; }
export function itemsCredit(preview: CreditPreview | null | undefined, lineIds: string[] | null | undefined,
  picks: ItemPick[] | null | undefined): { todays: number; paid: number; credit: number | null; missing: boolean };
export function itemPicksProblem(picks: ItemPick[] | null | undefined,
  lines: (BundleLineLike & { id: string })[] | null | undefined,
  held: Record<string, { product_id: string; quantity: number }[]> | null | undefined,
  nameOf?: (productId: string) => string): string | null;
export function itemsProductType(productIds: string[] | null | undefined,
  typeOf: (productId: string) => string | null | undefined): string | null;
export function exchangeDay(e: { exchange_date?: string | null; created_at?: string | null } | null | undefined): string;
export function displayDay(day: string | null | undefined): string;
/** 424: the day an exchange may be dated, and the day its sale counts on. */
export function saleDay(invoice: { business_date?: string | null; created_at?: string | null } | null | undefined): string;
export function exchangeDateFloor(today: string, originalDay: string | null | undefined): string;
export function exchangeDateProblem(day: string | null | undefined, today: string, originalDay: string | null | undefined): string | null;
export function exchangeDateHint(day: string | null | undefined, today: string): string;
export function instalmentLabelFrom(
  rows: { payment_method_id?: string | null; amount?: number | string | null; instalment?: { method_id?: string | null; months?: number | string | null } | null }[] | null | undefined,
  instalmentId: string,
): { method_id: string; months: number } | null;
