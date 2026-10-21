export function linkExpiryFromDay(day: string | null | undefined): string | null;
export function sgDate(value: string | null | undefined): string;
export function sgDateTime(value: string | null | undefined): string;
export function plainDate(value: string | null | undefined): string;
export function linkStatus(
  link: { expires_at: string | null; is_active: boolean } | null | undefined,
  now?: Date,
): 'active' | 'inactive' | 'expired';
