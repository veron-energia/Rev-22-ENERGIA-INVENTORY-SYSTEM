export interface GoodsProduct {
  product_id: string;
  name: string;
  /** On the invoice: product lines, promotion contents and picks. */
  required: number;
  collected: number;
  to_collect: number;
  /** With the customer and not yet returned or written off. */
  out: number;
  /** In the invoice's store now. */
  in_store: number;
  /** The promotions it comes through, if any. */
  via: string[];
}
export interface GoodsHistoryItem {
  product_id: string;
  name: string | null;
  quantity: number;
  good: number;
  damaged: number;
  not_returned: number;
}
export interface GoodsHistoryEntry {
  id: string;
  kind: 'handover' | 'nothing_taken' | 'return' | string;
  source: 'payment' | 'button' | 'return' | string;
  created_at: string;
  created_by_name: string | null;
  reason: string | null;
  items: GoodsHistoryItem[];
}
export interface GoodsStatus {
  invoice_id: string;
  invoice_no: string;
  status: string;
  store_id: string | null;
  store_name: string | null;
  /** Not yet paid in full: goods taken now count as handed over early. */
  open: boolean;
  fulfil_from_warehouse: boolean;
  required_total: number;
  collected_total: number;
  to_collect_total: number;
  out_total: number;
  can_hand_over: boolean;
  can_record_return: boolean;
  products: GoodsProduct[];
  history: GoodsHistoryEntry[];
}
export type HandoverAnswer = 'none' | 'items' | null;
export type HandoverPick = Record<string, number>;
export type HandoverPayload = { none: true } | { items: { product_id: string; qty: number }[] };
export type ReturnField = 'good' | 'damaged' | 'not_returned';
export type ReturnEntries = Record<string, { good: number; damaged: number; not_returned: number }>;
export interface ReturnItem { product_id: string; good: number; damaged: number; not_returned: number }

export function goodsFromRpc(data: unknown): GoodsStatus | null;
export function collectable(goods: GoodsStatus | null | undefined): GoodsProduct[];
export function returnable(goods: GoodsStatus | null | undefined): GoodsProduct[];
export function needsHandoverAnswer(goods: GoodsStatus | null | undefined, payTotal: number, outstanding: number): boolean;
export function emptyPick(): HandoverPick;
export function setPick(pick: HandoverPick, productId: string, value: string | number): HandoverPick;
export function pickedItems(goods: GoodsStatus | null | undefined, pick: HandoverPick): { product: GoodsProduct; qty: number }[];
export function handoverProblem(goods: GoodsStatus | null | undefined, answer: HandoverAnswer, pick: HandoverPick,
  options?: { button?: boolean }): string | null;
export function handoverPayload(goods: GoodsStatus | null | undefined, answer: HandoverAnswer, pick: HandoverPick): HandoverPayload;
export function emptyReturn(): ReturnEntries;
export function setReturn(entries: ReturnEntries, productId: string, field: ReturnField, value: string | number): ReturnEntries;
export function returnProblem(goods: GoodsStatus | null | undefined, entries: ReturnEntries, reason: string): string | null;
export function returnPayload(goods: GoodsStatus | null | undefined, entries: ReturnEntries): ReturnItem[];
export function collectionLists(goods: GoodsStatus | null | undefined): {
  collected: { name: string; qty: number }[]; toCollect: { name: string; qty: number }[] };
export function copyTermsText(status: string | null | undefined): string | undefined;
export interface CopyCollectionItem { name: string; qty: number }
/** An unpaid or part-paid copy's goods, as lists. */
export interface CopyCollection { collected: CopyCollectionItem[]; toCollect: CopyCollectionItem[] }
export function copyCollection(status: string | null | undefined, goods: GoodsStatus | null | undefined): CopyCollection | null;
export function collectionText(c: CopyCollection): string[];
export function copyCollectionLines(status: string | null | undefined, goods: GoodsStatus | null | undefined): string[] | null;
export function collectionLineFitted(label: string, items: CopyCollectionItem[], width: number,
  measure: (text: string) => number): string;
export function collectionSummary(c: CopyCollection): string;
export function historyLine(entry: GoodsHistoryEntry): string;
export function historySource(entry: GoodsHistoryEntry): string;
export function goodsOutBadge(qty: number | null | undefined): { label: string; title: string } | null;
export function goodsRefusal(message: string | null | undefined): string | null;
