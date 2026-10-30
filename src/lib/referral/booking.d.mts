export type BookingState = 'upcoming' | 'came' | 'miss' | 'none';
/** The two keys 480 adds to every Downline and My Network row. */
export interface BookingFields {
  booking_at?: string | null;
  booking_state?: BookingState | string | null;
}
/** The Singapore day ("Sat 31 Oct 2026") and time ("2:00 pm"); null when it is no moment. */
export function bookingParts(ts: string | null | undefined): { day: string; time: string } | null;
/** "Sat 31 Oct 2026, 2:00 pm" in Singapore; '' when it is no moment. */
export function bookingWhen(ts: string | null | undefined): string;
export const BOOKING_STATUS_LABELS: Record<BookingState, string>;
export interface BookingView {
  state: BookingState | 'unknown';
  /** The date and time; '' for none and unknown. */
  text: string;
  /** The same in two parts ("Sat 31 Oct 2026", "2:00 pm"); '' for none and unknown. */
  day: string;
  time: string;
  /** Upcoming, Came, Miss, No booking; '' unknown. */
  label: string;
}
export function bookingView(row: BookingFields | null | undefined): BookingView;
