export function sgToday(now?: Date): string;
export function isPastValidUntil(validUntil: string | null | undefined, today?: string): boolean;
export function dayText(value: string | null | undefined): string;
export function dayNumbers(value: string | null | undefined): string;
export function priceProblem(text: string | number | null | undefined): string | null;
export function unsavedStoreNames(
  stores: { id: string; name: string }[],
  drafts: Record<string, { m: string; avail: boolean }>,
  saved: { store_id: string; selling_price: number | string | null; available_at_store?: boolean | null }[],
): string[];
export function listText(items: string[]): string;
export interface VoucherDeleteAnswer {
  voucher_id?: string; name?: string; deleted?: boolean; already_deleted?: boolean; needs_confirmation?: boolean;
  holders_customers?: number; holders_units?: number;
  store_stock?: { store_id: string; store_name: string; quantity: number }[]; store_stock_total?: number;
  used_in?: { promotions?: number; premium_bundles?: number; credit_packages?: number; therapy_packages?: number };
  used_in_total?: number;
}
export function voucherDependents(answer: VoucherDeleteAnswer | null | undefined): string[];
export function serviceStoreRows(
  stores: { id: string; name: string }[],
  rows: Record<string, { available: boolean; override: string }>,
): { problem: string | null; rows: { store_id: string; is_available: boolean; price_override: number | null }[] };
export function lengtheningCount(rows: { change_days: number | null; shortens?: boolean; needs_country?: boolean }[]): number;
export function outcomeUnknown(error: { code?: string | null } | null | undefined): boolean;
export function splitRequestKey(kind: 'credit_package' | 'premium_bundle', storeId: string, itemId: string): string;
export function heldSplitRequest(key: string): string | null;
export function holdSplitRequest(key: string, id: string): void;
export function releaseSplitRequest(key: string): void;
export function splitRequestUsed(error: { code?: string | null; message?: string | null } | null | undefined): boolean;
