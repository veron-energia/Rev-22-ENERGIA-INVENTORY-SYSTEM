export type PromotionStatus = 'Active' | 'Ended' | 'Not started' | 'Inactive';
export interface PromotionDatesLike {
  is_active?: boolean | null;
  deleted_at?: string | null;
  start_date?: string | null;
  end_date?: string | null;
}
export function promotionStatus(p: PromotionDatesLike | null | undefined, today: string): PromotionStatus;
export function promotionOnSale(p: PromotionDatesLike | null | undefined, today: string): boolean;
export function promotionStatusBadge(status: PromotionStatus | string): string;
export function displayDateOnly(value: string | null | undefined): string;
