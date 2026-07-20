import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { CreditCard, AlertTriangle, CheckCircle2, Clock, XCircle } from 'lucide-react';

const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

export interface MembershipStatus {
  is_member: boolean;
  status: string;
  membership_no?: string;
  member_id?: string | null;
  plan_name?: string;
  start_date?: string | null;
  expiry_date?: string | null;
  days_left?: number | null;
  warning?: string | null;
  is_complimentary?: boolean;
}

// Fetches and shows a customer's membership status. Used on the invoice detail,
// customer page and membership page. Self-contained so it can be dropped in
// anywhere a customer id is known, with no wiring into the host page's state.
const MembershipBadge: React.FC<{ customerId: string | null | undefined; compact?: boolean }> = ({ customerId, compact }) => {
  const [s, setS] = useState<MembershipStatus | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!customerId) { setS(null); return; }
    let ok = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase.rpc('customer_membership_status', { p_customer_id: customerId });
      if (ok) { setS((data as MembershipStatus) ?? null); setLoading(false); }
    })();
    return () => { ok = false; };
  }, [customerId]);

  if (!customerId || loading || !s) return null;

  if (!s.is_member) {
    return (
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 12, color: 'var(--text-muted)' }}>
        <XCircle size={13} /> Non-member
      </span>
    );
  }

  const warnColor = s.warning === 'expired' ? 'var(--danger)'
    : s.warning === 'one_month' ? 'var(--danger)'
    : s.warning === 'three_month' ? 'var(--warning, #b45309)' : 'var(--success)';

  if (compact) {
    return (
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 12, color: 'var(--success)', fontWeight: 600 }}>
        <CheckCircle2 size={13} /> Member{s.member_id ? ` · ${s.member_id}` : ''}
        {s.warning && s.warning !== 'expired' && (
          <span style={{ color: warnColor, marginLeft: 4 }}>({s.days_left}d left)</span>
        )}
      </span>
    );
  }

  return (
    <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10, background: 'var(--surface-2)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
        <CreditCard size={15} style={{ color: 'var(--success)' }} />
        <strong style={{ fontSize: 13 }}>{s.plan_name}</strong>
        {s.is_complimentary && <span className="badge badge-muted" style={{ fontSize: 10 }}>Complimentary</span>}
        <span className={`badge ${s.status === 'active' ? 'badge-success' : s.status === 'expiring_soon' ? 'badge-warning' : 'badge-muted'}`} style={{ fontSize: 10 }}>
          {s.status.replace('_', ' ')}
        </span>
      </div>
      <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap', marginTop: 6, fontSize: 12, color: 'var(--text-secondary)' }}>
        <span>Member ID: <strong style={{ color: s.member_id ? 'inherit' : 'var(--danger)' }}>{s.member_id ?? 'missing'}</strong></span>
        <span>No: <strong>{s.membership_no}</strong></span>
        <span>Expires: <strong>{d(s.expiry_date)}</strong></span>
      </div>
      {s.warning && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 6, fontSize: 12, color: warnColor, fontWeight: 600 }}>
          {s.warning === 'expired' ? <><AlertTriangle size={13} /> Membership has expired</>
            : s.warning === 'one_month' ? <><Clock size={13} /> Expires within 1 month ({s.days_left} days)</>
            : <><Clock size={13} /> Expires within 3 months ({s.days_left} days)</>}
        </div>
      )}
    </div>
  );
};

export default MembershipBadge;
