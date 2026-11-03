import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';

// 491 (3 Nov 2026): PayNow goes to the phone on the customer record, and an
// affiliate can now change that phone themselves. The payout window says so
// when they did since their last payout, until the next payout is recorded.

interface PhoneChange { changed_at: string; old_phone: string | null; new_phone: string }

const SelfPhoneChangeNote: React.FC<{ customerId: string }> = ({ customerId }) => {
  const [change, setChange] = useState<PhoneChange | null>(null);
  useEffect(() => {
    let live = true;
    setChange(null);
    supabase.rpc('affiliate_self_phone_change', { p_customer_id: customerId }).then(({ data, error }) => {
      // Before 491 (or for a role that may not read it) there is nothing to say.
      if (live && !error && data) setChange(data as PhoneChange);
    });
    return () => { live = false; };
  }, [customerId]);
  if (!change) return null;
  return (
    <div className="alert alert-warning" role="alert" data-note="self-phone-change">
      The affiliate changed their phone number themselves on {new Date(change.changed_at).toLocaleDateString('en-GB')}:
      {' '}{change.old_phone || '—'} → <b>{change.new_phone}</b>. Before paying by PayNow, check the number with them.
    </div>
  );
};

export default SelfPhoneChangeNote;
