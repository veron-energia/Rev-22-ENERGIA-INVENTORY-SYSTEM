import React from 'react';

// ── Reusable presentational components for Phase 8 ──────────────────────────
// Small, style-consistent building blocks used across pages so the larger
// components (Invoices, Memberships, Customers, Dashboard, Reports) stay lean.

const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';
const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;

const MEMBERSHIP_STATUS: Record<string, { cls: string; label: string }> = {
  pending_payment: { cls: 'badge-accent', label: 'Pending Payment' },
  pending_activation: { cls: 'badge-accent', label: 'Pending Activation' },
  active: { cls: 'badge-success', label: 'Active' },
  expiring: { cls: 'badge-accent', label: 'Expiring Soon' },
  expired: { cls: 'badge-muted', label: 'Expired' },
  suspended: { cls: 'badge-danger', label: 'Suspended' },
  cancelled: { cls: 'badge-danger', label: 'Cancelled' },
  complimentary: { cls: 'badge-primary', label: 'Complimentary' },
};

export const MembershipStatusBadge: React.FC<{ status: string; complimentary?: boolean }> = ({ status, complimentary }) => {
  const key = complimentary ? 'complimentary' : status;
  const s = MEMBERSHIP_STATUS[key] ?? { cls: 'badge-muted', label: status };
  return <span className={`badge ${s.cls}`}>{s.label}</span>;
};

// Expiry warning — amber within 90d, red within 30d, none otherwise.
export const ExpiryWarning: React.FC<{ expiry?: string | null; daysLeft?: number | null }> = ({ expiry, daysLeft }) => {
  if (expiry == null && daysLeft == null) return null;
  const days = daysLeft ?? (expiry ? Math.round((new Date(expiry).getTime() - Date.now()) / 86400000) : null);
  if (days == null) return null;
  if (days < 0) return <span className="badge badge-muted">Expired {d(expiry)}</span>;
  if (days <= 30) return <span className="badge badge-danger">Expires in {days}d · {d(expiry)}</span>;
  if (days <= 90) return <span className="badge badge-accent">Expires in {days}d · {d(expiry)}</span>;
  return <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>{d(expiry)} · {days}d left</span>;
};

// Member ID chip — shows the ID or a "missing" warning.
export const MemberIdChip: React.FC<{ memberId?: string | null }> = ({ memberId }) =>
  memberId
    ? <span className="badge badge-muted" style={{ fontFamily: 'monospace' }}>{memberId}</span>
    : <span className="badge badge-danger">Missing Member ID</span>;

// Affiliate eligibility indicator.
export const AffiliateEligibility: React.FC<{ state: string; blockReason?: string | null }> = ({ state, blockReason }) => {
  const map: Record<string, { cls: string; label: string }> = {
    active: { cls: 'badge-success', label: 'Eligible' },
    suspended_manual: { cls: 'badge-danger', label: 'Suspended' },
    inactive_membership_expired: { cls: 'badge-accent', label: 'Expired Membership' },
    inactive_missing_member_id: { cls: 'badge-accent', label: 'Missing Member ID' },
    inactive_no_membership: { cls: 'badge-muted', label: 'No Membership' },
    not_activated: { cls: 'badge-muted', label: 'Not Activated' },
  };
  const s = map[state] ?? { cls: 'badge-muted', label: state };
  return (
    <span>
      <span className={`badge ${s.cls}`}>{s.label}</span>
      {blockReason && state !== 'active' && <span style={{ fontSize: 10.5, color: 'var(--text-muted)', marginLeft: 4 }}>{blockReason}</span>}
    </span>
  );
};

// Blocked commission amount indicator.
export const BlockedCommission: React.FC<{ amount: number }> = ({ amount }) =>
  Number(amount) > 0
    ? <span style={{ color: 'var(--danger)', fontWeight: 600 }}>{money(amount)}</span>
    : <span style={{ color: 'var(--text-muted)' }}>—</span>;

// Refund calculation preview (Method A / B) — pure display, no side effects.
export const RefundCalculation: React.FC<{ fee: number; priceDiff: number; method: 'deduct' | 'topup' }> = ({ fee, priceDiff, method }) => {
  const refund = method === 'deduct' ? Math.max(0, fee - priceDiff) : fee;
  const topup = method === 'deduct' ? (priceDiff > fee ? priceDiff - fee : 0) : priceDiff;
  return (
    <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
      <div>Membership fee: <strong>{money(fee)}</strong></div>
      <div>Member-price difference: <strong>{money(priceDiff)}</strong></div>
      <div style={{ marginTop: 4 }}>Refund to customer: <strong style={{ color: 'var(--primary)' }}>{money(refund)}</strong></div>
      {topup > 0 && <div>Top-up invoice: <strong style={{ color: 'var(--danger)' }}>{money(topup)}</strong></div>}
    </div>
  );
};

// Save Earth editor — checkbox + editable label/amount (per-invoice).
export const SaveEarthEditor: React.FC<{
  applied: boolean; label: string; amount: number; defaultLabel: string; defaultAmount: number;
  onChange: (applied: boolean, label: string, amount: number) => void;
}> = ({ applied, label, amount, defaultLabel, defaultAmount, onChange }) => (
  <div className="form-group" style={{ gridColumn: '1 / -1' }}>
    <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
      <input type="checkbox" checked={applied} style={{ width: 'auto' }}
        onChange={e => onChange(e.target.checked, e.target.checked ? defaultLabel : label, e.target.checked ? defaultAmount : amount)} />
      {defaultLabel} ({money(defaultAmount)})
    </label>
    {applied && (
      <div style={{ display: 'flex', gap: 6, marginTop: 6, flexWrap: 'wrap' }}>
        <input value={label} onChange={e => onChange(true, e.target.value, amount)} placeholder="Label for this invoice" style={{ flex: 1, minWidth: 160 }} />
        <input type="number" min={0} step={0.01} value={amount} onChange={e => onChange(true, label, Math.max(0, +e.target.value))} style={{ width: 110 }} />
      </div>
    )}
  </div>
);
