import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { MembershipPlan, MembershipPlanStorePrice } from '../types';
import { CreditCard, AlertTriangle, Clock, XCircle, CheckCircle2, RefreshCw, Plus, X } from 'lucide-react';

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

export interface FullMembershipStatus {
  is_member: boolean; status: string; membership_id?: string; membership_no?: string;
  member_id?: string | null; plan_id?: string; plan_name?: string;
  start_date?: string | null; expiry_date?: string | null; days_left?: number | null;
  warning?: string | null; is_complimentary?: boolean;
  has_future_renewal?: boolean; future_start?: string | null; future_expiry?: string | null;
}

/** Live membership panel for the invoice create flow. Reports status upward so
 *  the builder can price lines by mode. */
export const MembershipStatusPanel: React.FC<{
  customerId: string | null | undefined;
  onStatus?: (s: FullMembershipStatus | null) => void;
}> = ({ customerId, onStatus }) => {
  const [s, setS] = useState<FullMembershipStatus | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!customerId) { setS(null); onStatus?.(null); return; }
    let ok = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase.rpc('customer_membership_status', { p_customer_id: customerId });
      if (ok) { const st = (data as FullMembershipStatus) ?? null; setS(st); onStatus?.(st); setLoading(false); }
    })();
    return () => { ok = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [customerId]);

  if (!customerId) return null;
  if (loading) return <div style={{ fontSize: 12, color: 'var(--text-muted)' }}><RefreshCw size={11} className="spin" /> Checking membership…</div>;
  if (!s) return null;

  if (!s.is_member) {
    return (
      <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '8px 10px', background: 'var(--surface-2)', fontSize: 12.5, display: 'flex', alignItems: 'center', gap: 6 }}>
        <XCircle size={14} style={{ color: 'var(--text-muted)' }} />
        <span><strong>Non-member</strong> — Non-Member prices apply. Add a membership to this invoice for Member prices.</span>
      </div>
    );
  }

  const warnColor = s.warning === 'one_month' || s.warning === 'expired' ? 'var(--danger)' : '#b45309';
  return (
    <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '8px 10px', background: 'var(--success-light, var(--surface-2))', fontSize: 12.5 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
        <CheckCircle2 size={14} style={{ color: 'var(--success)' }} />
        <strong>Member</strong>
        <span>{s.plan_name}{s.is_complimentary ? ' (complimentary)' : ''}</span>
        <span className="badge badge-muted" style={{ fontSize: 10 }}>{s.membership_no}</span>
      </div>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', marginTop: 4, color: 'var(--text-secondary)' }}>
        <span>Member ID: <strong style={{ color: s.member_id ? 'inherit' : 'var(--danger)' }}>{s.member_id ?? 'missing'}</strong></span>
        <span>{d(s.start_date)} → {d(s.expiry_date)}</span>
        <span>{s.days_left} days left</span>
      </div>
      {s.warning && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 4, color: warnColor, fontWeight: 600 }}>
          {s.warning === 'expired' ? <AlertTriangle size={12} /> : <Clock size={12} />}
          {s.warning === 'expired' ? 'Membership has expired'
            : s.warning === 'one_month' ? 'Expires within 1 month — offer renewal'
            : 'Expires within 3 months — renewal available'}
        </div>
      )}
      {s.has_future_renewal && (
        <div style={{ marginTop: 4, color: 'var(--text-muted)' }}>
          Renewal already scheduled: {d(s.future_start)} → {d(s.future_expiry)}
        </div>
      )}
    </div>
  );
};

/** Membership add-to-invoice selector: store plans + fee, Member ID entry for
 *  new members, automatic reuse note for renewals. */
export const MembershipSelector: React.FC<{
  storeId: string;
  memberStatus: FullMembershipStatus | null;
  value: { plan_id: string; member_id: string; fee: number; plan_name: string; owned_id?: string | null } | null;
  onChange: (v: { plan_id: string; member_id: string; fee: number; plan_name: string; owned_id?: string | null } | null) => void;
  customerId?: string;
}> = ({ storeId, memberStatus, value, onChange, customerId }) => {
  const [plans, setPlans] = useState<MembershipPlan[]>([]);
  const [prices, setPrices] = useState<MembershipPlanStorePrice[]>([]);
  const [ownedId, setOwnedId] = useState<string | null>(null);
  const [idErr, setIdErr] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const [p, pr] = await Promise.all([
        supabase.from('membership_plans').select('*').is('deleted_at', null).eq('is_active', true).eq('is_system', false).order('duration_months'),
        supabase.from('membership_plan_store_prices').select('*').is('deleted_at', null).eq('store_id', storeId),
      ]);
      setPlans((p.data as MembershipPlan[]) ?? []);
      setPrices((pr.data as MembershipPlanStorePrice[]) ?? []);
    })();
  }, [storeId]);

  const isRenewal = !!memberStatus?.is_member;
  // A customer can hold a permanent Member ID without an active membership
  // (expired / suspended / cancelled / complimentary / legacy). That ID is
  // reused — never re-entered, never replaced.
  useEffect(() => {
    let ok = true;
    (async () => {
      if (memberStatus?.member_id) { if (ok) setOwnedId(memberStatus.member_id); return; }
      if (!customerId) { if (ok) setOwnedId(null); return; }
      const { data } = await supabase.from('member_ids').select('member_id').eq('customer_id', customerId).maybeSingle();
      if (ok) setOwnedId((data as any)?.member_id ?? null);
    })();
    return () => { ok = false; };
  }, [memberStatus, customerId]);

  const feeFor = (planId: string) => {
    const r = prices.find(x => x.plan_id === planId && x.available_at_store && x.is_active);
    return r ? Number(r.membership_fee) : null;
  };
  const sellable = plans.filter(p => feeFor(p.id) !== null);

  const checkId = async (id: string) => {
    setIdErr(null);
    if (!id.trim() || !value) return;
    const { data } = await supabase.rpc('member_id_available', { p_member_id: id.trim(), p_customer_id: null });
    // p_customer_id null → treated as "someone else holds it?" check is done server-side at create; here just warn on obvious clash
    if (data === false) setIdErr('That Member ID is already taken.');
  };

  if (value) {
    const plan = plans.find(p => p.id === value.plan_id);
    const fee = feeFor(value.plan_id);
    return (
      <div style={{ border: '1px solid var(--primary)', borderRadius: 'var(--radius-sm)', padding: '8px 10px', fontSize: 12.5, display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <CreditCard size={14} style={{ color: 'var(--primary)' }} />
          <strong>{plan?.name ?? 'Membership'}</strong>
          <span>{fee != null ? money(fee) : '—'}</span>
          {isRenewal
            ? <span className="badge badge-success" style={{ fontSize: 10 }}>Renewal · keeps {ownedId ?? 'existing ID'}</span>
            : ownedId
            ? <span className="badge badge-success" style={{ fontSize: 10 }}>Reuses existing Member ID {ownedId}</span>
            : <span className="badge badge-muted" style={{ fontSize: 10 }}>New member{value.member_id ? ` · ${value.member_id}` : ' · Member ID pending'}</span>}
        </div>
        <button className="btn btn-secondary btn-sm btn-icon" onClick={() => onChange(null)} title="Remove membership line"><X size={12} /></button>
      </div>
    );
  }

  return (
    <div style={{ border: '1px dashed var(--border)', borderRadius: 'var(--radius-sm)', padding: '8px 10px' }}>
      <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 6, display: 'flex', alignItems: 'center', gap: 6 }}>
        <CreditCard size={13} /> {isRenewal ? 'Renew membership' : 'Sell a membership'}
      </div>
      {sellable.length === 0 ? (
        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>No plans are priced/available at this store.</div>
      ) : (
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'flex-end' }}>
          <div className="form-group" style={{ marginBottom: 0, flex: 1, minWidth: 180 }}>
            <select defaultValue="" onChange={e => {
              const pid = e.target.value; if (!pid) return;
              onChange({ plan_id: pid, member_id: '', fee: feeFor(pid) ?? 0,
                plan_name: plans.find(p => p.id === pid)?.name ?? 'Membership', owned_id: ownedId });
            }}>
              <option value="">— Add membership… —</option>
              {sellable.map(p => (
                <option key={p.id} value={p.id}>{p.name} — {money(feeFor(p.id)!)}{isRenewal ? ' (renewal)' : ''}</option>
              ))}
            </select>
          </div>
        </div>
      )}
      {idErr && <div style={{ fontSize: 11.5, color: 'var(--danger)', marginTop: 4 }}>{idErr}</div>}
      {isRenewal && <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>Renewal starts the day after the current expiry and keeps the same Member ID.</div>}
    </div>
  );
};

/** Member ID input row shown once a NEW membership is on the invoice. */
export const MemberIdField: React.FC<{
  value: string; onChange: (v: string) => void; isRenewal: boolean; ownedId?: string | null;
}> = ({ value, onChange, isRenewal, ownedId }) => {
  if (isRenewal) return null;
  return (
    <div className="form-group" style={{ marginBottom: 0 }}>
      <label>Physical Member ID {value ? '' : '(can also be entered before payment)'}</label>
      <input value={value} onChange={e => onChange(e.target.value)} placeholder="e.g. card number" style={{ maxWidth: 220 }} />
      <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>
        Globally unique, permanently assigned. Payment is blocked until a Member ID is reserved.
      </div>
    </div>
  );
};

export default MembershipStatusPanel;
