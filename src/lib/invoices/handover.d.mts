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
/** 547: a special, consignment or rental line and its goods. */
export interface GoodsSpecial {
  invoice_item_id: string;
  line_kind: 'special_product' | 'rental';
  special_product_id: string | null;
  /** The special product's name; a rental's ends "(rental)". */
  name: string;
  is_consignment: boolean;
  /** A consignment sale may be recorded as Delivered (its supplier brought it). */
  can_deliver: boolean;
  /** Units on the line. */
  quantity: number;
  collected: number;
  delivered: number;
  /** With the customer and not recorded as returned. */
  out: number;
  to_collect: number;
}
export interface GoodsHistoryItem {
  product_id: string;
  name: string | null;
  quantity: number;
  good: number;
  damaged: number;
  not_returned: number;
  /** 547: a special, consignment or rental item, by its invoice line. */
  special: boolean;
  invoice_item_id: string | null;
  how: 'collected' | 'delivered' | string | null;
  returned: number;
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
  /** 547 */
  specials: GoodsSpecial[];
  special_collected_total: number;
  special_delivered_total: number;
  special_out_total: number;
  special_to_collect_total: number;
  /** Staff of the store may record special items Collected / Delivered now (unpaid, part-paid or paid). */
  can_collect_special: boolean;
  /** An Owner or Manager may record special items returned now. */
  can_record_special_return: boolean;
}
export type HandoverAnswer = 'none' | 'items' | null;
export type HandoverPick = Record<string, number>;
export type SpecialHow = 'collected' | 'delivered';
export type HandoverPayload = { none: true }
  | { items: { product_id: string; qty: number }[]; specials?: { invoice_item_id: string; qty: number; how: SpecialHow }[] };
export type ReturnField = 'good' | 'damaged' | 'not_returned';
export type ReturnEntries = Record<string, { good: number; damaged: number; not_returned: number }>;
export type ReturnItem = { product_id: string; good: number; damaged: number; not_returned: number }
  | { invoice_item_id: string; returned: number };

export function goodsFromRpc(data: unknown): GoodsStatus | null;
export function collectable(goods: GoodsStatus | null | undefined): GoodsProduct[];
export function collectableProducts(goods: GoodsStatus | null | undefined): GoodsProduct[];
export function returnableProducts(goods: GoodsStatus | null | undefined): GoodsProduct[];
export function collectableSpecials(goods: GoodsStatus | null | undefined): GoodsSpecial[];
export function returnableSpecials(goods: GoodsStatus | null | undefined): GoodsSpecial[];
export function canHandOver(goods: GoodsStatus | null | undefined): boolean;
export function canRecordReturn(goods: GoodsStatus | null | undefined): boolean;
export function setSpecialPick(pick: HandoverPick, invoiceItemId: string, value: string | number): HandoverPick;
export function setSpecialHow(pick: HandoverPick, invoiceItemId: string, how: SpecialHow): HandoverPick;
export function specialHow(pick: HandoverPick, invoiceItemId: string): SpecialHow;
export function specialPicked(pick: HandoverPick, invoiceItemId: string): number;
export function pickedSpecials(goods: GoodsStatus | null | undefined, pick: HandoverPick): { special: GoodsSpecial; qty: number; how: SpecialHow }[];
export function setSpecialReturn(entries: ReturnEntries, invoiceItemId: string, value: string | number): ReturnEntries;
export function specialReturned(entries: ReturnEntries, invoiceItemId: string): number;
export function copyReadsGoods(status: string | null | undefined): boolean;
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
  collected: { name: string; qty: number }[]; delivered?: { name: string; qty: number }[]; toCollect: { name: string; qty: number }[] };
export function copyTermsText(status: string | null | undefined, goods?: GoodsStatus | null): string | undefined;
export interface CopyCollectionItem { name: string; qty: number }
/** An unpaid or part-paid copy's goods, as lists (547: or a paid one's with a special item to collect). */
export interface CopyCollection { collected: CopyCollectionItem[]; delivered?: CopyCollectionItem[]; toCollect: CopyCollectionItem[] }
export function copyCollection(status: string | null | undefined, goods: GoodsStatus | null | undefined): CopyCollection | null;
export function collectionText(c: CopyCollection): string[];
export function copyCollectionLines(status: string | null | undefined, goods: GoodsStatus | null | undefined): string[] | null;
export function collectionLineFitted(label: string, items: CopyCollectionItem[], width: number,
  measure: (text: string) => number): string;
export function collectionSummary(c: CopyCollection): string;
export function historyLine(entry: GoodsHistoryEntry): string;
export function historySource(entry: GoodsHistoryEntry, goods?: GoodsStatus | null): string;
export function goodsOutBadge(qty: number | null | undefined): { label: string; title: string } | null;
export function goodsRefusal(message: string | null | undefined): string | null;
