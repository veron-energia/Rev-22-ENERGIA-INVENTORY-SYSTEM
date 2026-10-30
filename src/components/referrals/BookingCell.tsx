import React from 'react';
import { bookingView } from '../../lib/referral/booking.mjs';
import type { BookingFields } from '../../lib/referral/booking.mjs';

/**
 * A customer's cal.com booking (480, the Owner, 29 Oct 2026), as the Downline
 * and the affiliate portal's My Network show it: the date and time of an
 * upcoming booking; a past one they came to in grey; a missed one with a red
 * "Miss" badge; "No booking" in red. "—" when the database does not say (one
 * from before 480). The day, the time and the badge each stay whole: a narrow
 * column puts the time (and the badge) under the day, never breaks inside one.
 */
const BookingCell: React.FC<{ row: BookingFields }> = ({ row }) => {
  const b = bookingView(row);
  if (b.state === 'unknown') return <span data-booking="unknown" style={{ color: 'var(--text-muted)' }}>—</span>;
  if (b.state === 'none') return <span data-booking="none" style={{ color: 'var(--danger)', fontWeight: 600, whiteSpace: 'nowrap' }}>No booking</span>;
  const when = (
    <>
      <span style={{ whiteSpace: 'nowrap' }}>{b.day},</span>{' '}<span style={{ whiteSpace: 'nowrap' }}>{b.time}</span>
    </>
  );
  if (b.state === 'miss') {
    return (
      <span data-booking="miss">
        <span style={{ color: 'var(--text-secondary)' }}>{when}</span>{' '}
        <span className="badge badge-danger" style={{ whiteSpace: 'nowrap' }}>Miss</span>
      </span>
    );
  }
  return <span data-booking={b.state} style={{ color: b.state === 'came' ? 'var(--text-secondary)' : undefined }}>{when}</span>;
};

export default BookingCell;
