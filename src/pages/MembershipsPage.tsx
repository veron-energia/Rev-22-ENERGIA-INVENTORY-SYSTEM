import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Customer, Store, MembershipPlan, MembershipPlanStorePrice, CustomerMembership, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import { RefreshCw, Plus, Search, CreditCard, Store as StoreIcon, AlertTriangle, Pencil, Trash2, Ban, PlayCircle } from 'lucide-react';

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

const STATUS: Record<string, { cls: string; label: string }> = {
  pending_payment: { cls: 'badge-warning', label: 'Pending Payment' },
  active: { cls: 'badge-success', label: 'Active' },
  expiring_soon: { cls: 'badge-warning', label: 'Expiring Soon' },
  expired: { cls: 'badge-muted', label: 'Expired' },
  cancelled: { cls: 'badge-danger', label: 'Cancelled' },
  suspended: { cls: 'badge-danger', label: 'Suspended' },
};

const MembershipsPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  const [tab, setTab] = useState<'memberships' | 'plans'>('memberships');
  const [rows, setRows] = useState<CustomerMembership[]>([]);
  const [plans, setPlans] = useState<MembershipPlan[]>([]);
  const [prices, setPrices] = useState<MembershipPlanStorePrice[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<string>('all');
  const [err, setErr] = useState<string | null>(null);
  const [warn1, setWarn1] = useState(3);
  const [warn2, setWarn2] = useState(1);
  const [warnBusy, setWarnBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const [m, p, pr, c, s, aset] = await Promise.all([
      supabase.from('customer_memberships').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('membership_plans').select('*').is('deleted_at', null).order('duration_months'),
      supabase.from('membership_plan_store_prices').select('*').is('deleted_at', null),
      supabase.from('customers').select('*').is('deleted_at', null).order('full_name'),
      supabase.from('stores').select('*').is('deleted_at', null).order('name'),
      supabase.from('app_settings').select('membership_warn_months_1,membership_warn_months_2').maybeSingle(),
    ]);
    setRows((m.data as CustomerMembership[]) ?? []);
    setPlans((p.data as MembershipPlan[]) ?? []);
    setPrices((pr.data as MembershipPlanStorePrice[]) ?? []);
    setCustomers((c.data as Customer[]) ?? []);
    setStores((s.data as Store[]) ?? []);
    const w = aset.data as any;
    if (w) { setWarn1(Number(w.membership_warn_months_1 ?? 3)); setWarn2(Number(w.membership_warn_months_2 ?? 1)); }
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  // K: live status from dates (SG calendar months), so the page reflects
  // reality without waiting for a status-refresh migration.
  const liveStatus = (r: CustomerMembership): { key: string; label: string; cls: string } => {
    if (['cancelled','suspended','pending_payment'].includes(r.status))
      return { key: r.status, label: STATUS[r.status]?.label ?? r.status, cls: STATUS[r.status]?.cls ?? 'badge-muted' };
    if (!r.start_date || !r.expiry_date) return { key: r.status, label: STATUS[r.status]?.label ?? r.status, cls: 'badge-muted' };
    const today = new Date(new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' }));
    const start = new Date(r.start_date); const exp = new Date(r.expiry_date);
    if (start > today) return { key: 'future', label: 'Future Renewal', cls: 'badge-muted' };
    if (today > exp) return { key: 'expired', label: 'Expired', cls: 'badge-muted' };
    const m1 = new Date(exp); m1.setMonth(m1.getMonth() - warn1);
    const m2 = new Date(exp); m2.setMonth(m2.getMonth() - warn2);
    if (today >= m2) return { key: 'one_month', label: 'Expiring (1 month)', cls: 'badge-warning' };
    if (today >= m1) return { key: 'three_month', label: 'Expiring (3 months)', cls: 'badge-warning' };
    return { key: 'active', label: 'Active', cls: 'badge-success' };
  };
  const cName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';
  const cPhone = (id: string) => customers.find(c => c.id === id)?.phone ?? '';
  const pName = (id: string) => plans.find(p => p.id === id)?.name ?? '—';
  const sName = (id: string | null) => id ? (stores.find(s => s.id === id)?.name ?? '—') : null;

  // ---- Plan editor ----
  const [planOpen, setPlanOpen] = useState(false);
  const [editPlan, setEditPlan] = useState<MembershipPlan | null>(null);
  const [pf, setPf] = useState({ name: '', duration_months: 12, description: '', is_active: true });
  const [busy, setBusy] = useState(false);

  const openPlan = (p: MembershipPlan | null) => {
    setEditPlan(p);
    setPf(p ? { name: p.name, duration_months: p.duration_months, description: p.description ?? '', is_active: p.is_active }
           : { name: '', duration_months: 12, description: '', is_active: true });
    setPlanOpen(true); setErr(null);
  };
  const savePlan = async () => {
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc('upsert_membership_plan', {
      p_id: editPlan?.id ?? null, p_name: pf.name, p_duration_months: pf.duration_months,
      p_description: pf.description || null, p_is_active: pf.is_active,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setPlanOpen(false); load();
  };

  // ---- Price editor ----
  const [priceFor, setPriceFor] = useState<MembershipPlan | null>(null);
  const [pStore, setPStore] = useState(''); const [pFee, setPFee] = useState(0); const [pAvail, setPAvail] = useState(true);
  const savePrice = async () => {
    if (!priceFor || !pStore) { setErr('Select a store.'); return; }
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc('set_membership_plan_price', {
      p_plan_id: priceFor.id, p_store_id: pStore, p_fee: pFee, p_available: pAvail,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setPStore(''); setPFee(0); setPAvail(true); load();
  };

  const saveWarn = async () => {
    setWarnBusy(true); setErr(null);
    const { error } = await supabase.rpc('set_membership_warn_thresholds', { p_months_1: warn1, p_months_2: warn2 });
    setWarnBusy(false);
    if (error) setErr(error.message);
  };

  // ── Membership edit (Owner/Manager) ──
  const [editMem, setEditMem] = useState<CustomerMembership | null>(null);
  const [emMemberId, setEmMemberId] = useState('');
  const [emStore, setEmStore] = useState('');
  const [emStart, setEmStart] = useState('');
  const [emExpiry, setEmExpiry] = useState('');
  const [emReason, setEmReason] = useState('');
  const [emBusy, setEmBusy] = useState(false);
  const [emErr, setEmErr] = useState<string | null>(null);

  const openEditMembership = (r: CustomerMembership) => {
    setEditMem(r);
    setEmMemberId(r.member_id ?? '');
    setEmStore(r.store_id ?? '');
    setEmStart(r.start_date ?? '');
    setEmExpiry(r.expiry_date ?? '');
    setEmReason(''); setEmErr(null);
  };

  const saveMembership = async () => {
    if (!editMem) return;
    if (!emReason.trim()) { setEmErr('A reason is required.'); return; }
    setEmBusy(true); setEmErr(null);
    // 1. Member ID (only if changed and non-empty)
    if (emMemberId.trim() && emMemberId.trim() !== (editMem.member_id ?? '')) {
      const { error } = await supabase.rpc('set_membership_member_id', {
        p_membership_id: editMem.id, p_member_id: emMemberId.trim(), p_reason: emReason.trim() });
      if (error) { setEmBusy(false); setEmErr(error.message); return; }
    }
    // 2. store / dates
    const { error: e2 } = await supabase.rpc('edit_membership', {
      p_membership_id: editMem.id,
      p_store_id: emStore || null,
      p_start: emStart || null,
      p_expiry: emExpiry || null,
      p_reason: emReason.trim() });
    setEmBusy(false);
    if (e2) { setEmErr(e2.message); return; }
    setEditMem(null); load();
  };

  const changeStatus = async (status: 'active' | 'suspended' | 'cancelled') => {
    if (!editMem) return;
    let reason = emReason.trim();
    if ((status === 'suspended' || status === 'cancelled') && !reason) {
      reason = prompt(`Reason to ${status} this membership:`)?.trim() ?? '';
      if (!reason) return;
    }
    setEmBusy(true); setEmErr(null);
    const { error } = await supabase.rpc('set_membership_status', {
      p_membership_id: editMem.id, p_status: status, p_reason: reason || 'reactivated' });
    setEmBusy(false);
    if (error) { setEmErr(error.message); return; }
    setEditMem(null); load();
  };

  const delPlan = async (p: MembershipPlan) => {
    if (!confirm(`Delete plan "${p.name}"?`)) return;
    const { error } = await supabase.rpc('soft_delete_membership_plan', { p_id: p.id, p_restore: false });
    if (error) setErr(error.message); else load();
  };

  const q = search.trim().toLowerCase();
  const shown = rows.filter(r => {
    if (filter === 'missing_member_id' && r.member_id) return false;
    if (filter === 'missing_store' && r.store_id) return false;
    if (filter === 'complimentary' && !r.is_complimentary && (r.status as string) !== 'complimentary') return false;
    if (filter === 'expiring_soon') {
      const dl = r.expiry_date ? Math.round((new Date(r.expiry_date).getTime() - Date.now()) / 86400000) : null;
      if (!(dl != null && dl >= 0 && dl <= 90 && r.status === 'active')) return false;
    }
    const skipStatusMatch = ['all', 'missing_member_id', 'missing_store', 'complimentary', 'expiring_soon'];
    if (!skipStatusMatch.includes(filter) && r.status !== filter) return false;
    if (!q) return true;
    const c = customers.find(x => x.id === r.customer_id);
    return (!!c && (c.full_name.toLowerCase().includes(q) || c.phone.toLowerCase().includes(q)))
      || r.membership_no.toLowerCase().includes(q) || (r.member_id ?? '').toLowerCase().includes(q);
  });

  const storePrice = (planId: string) => prices.filter(p => p.plan_id === planId);

  return (
    <div>
      <div className="page-header">
        <div><h2>Memberships</h2><p>Membership plans and customer memberships.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          {canManage && tab === 'plans' && <button className="btn btn-primary" onClick={() => openPlan(null)}><Plus size={16} /> New Plan</button>}
        </div>
      </div>

      {err && <div className="alert alert-danger" style={{ marginBottom: 12 }}><span>⚠</span><div>{err}</div></div>}

      <div style={{ display: 'flex', gap: 6, marginBottom: 16, borderBottom: '1px solid var(--border)' }}>
        {([['memberships', 'Memberships'], ['plans', 'Plans']] as const).map(([v, l]) => (
          <button key={v} onClick={() => setTab(v)} style={{ padding: '8px 16px', background: 'none', border: 'none', borderBottom: tab === v ? '2px solid var(--primary)' : '2px solid transparent', color: tab === v ? 'var(--primary)' : 'var(--text-secondary)', fontWeight: tab === v ? 700 : 500, cursor: 'pointer' }}>{l}</button>
        ))}
      </div>

      {tab === 'memberships' && (
        <>
          <div style={{ display: 'flex', gap: 10, marginBottom: 12, flexWrap: 'wrap' }}>
            <div style={{ position: 'relative', flex: 1, minWidth: 240 }}>
              <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
              <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search customer, phone, membership no. or Member ID…" style={{ paddingLeft: 30 }} />
            </div>
          </div>
          <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }}>
            {(['all', 'pending_payment', 'active', 'expiring_soon', 'expired', 'suspended', 'cancelled', 'complimentary', 'missing_member_id', 'missing_store'] as const).map(v => (
              <button key={v} className={`btn btn-sm ${filter === v ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setFilter(v)}>
                {v === 'missing_member_id' ? 'Missing Member ID' : v === 'missing_store' ? 'Missing Store' : v === 'complimentary' ? 'Complimentary' : v === 'expiring_soon' ? 'Expiring Soon' : v === 'all' ? 'All' : (STATUS[v]?.label ?? v)}
              </button>
            ))}
          </div>

          <div className="card"><div className="table-wrap">
            {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
              : shown.length === 0 ? <div className="empty-state"><CreditCard size={32} style={{ opacity: 0.3 }} />
                  <p style={{ fontWeight: 600, marginTop: 8 }}>{rows.length === 0 ? 'No memberships yet' : 'No memberships match'}</p></div>
              : <table>
                  <thead><tr><th>Membership</th><th>Customer</th><th>Plan</th><th>Member ID</th><th>Store</th><th>Start</th><th>Expiry</th><th>Status</th><th>Source</th><th></th></tr></thead>
                  <tbody>{shown.map(r => (
                    <tr key={r.id}>
                      <td style={{ fontSize: 12.5 }}><strong>{r.membership_no}</strong></td>
                      <td>{cName(r.customer_id)}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{cPhone(r.customer_id)}</div></td>
                      <td style={{ fontSize: 12.5 }}>{pName(r.plan_id)}</td>
                      <td style={{ fontSize: 12.5 }}>{r.member_id ?? <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: 'var(--danger)' }}><AlertTriangle size={11} /> missing</span>}</td>
                      <td style={{ fontSize: 12.5 }}>{sName(r.store_id) ?? <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: 'var(--danger)' }}><AlertTriangle size={11} /> missing</span>}</td>
                      <td style={{ fontSize: 12.5 }}>{d(r.start_date)}</td>
                      <td style={{ fontSize: 12.5 }}>{d(r.expiry_date)}</td>
                      <td>{(() => { const ls = liveStatus(r); return <span className={`badge ${ls.cls}`}>{ls.label}</span>; })()}</td>
                      <td style={{ fontSize: 11.5, color: 'var(--text-muted)', textTransform: 'capitalize' }}>{r.source}{r.is_complimentary ? ' · comp' : ''}</td>
                      <td>{canManage && <button className="btn btn-secondary btn-sm" onClick={() => openEditMembership(r)}><Pencil size={12} /> Edit</button>}</td>
                    </tr>
                  ))}</tbody>
                </table>}
          </div></div>
        </>
      )}

      {tab === 'plans' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {canManage && (
            <div className="card" style={{ padding: 14 }}>
              <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 4 }}>Expiry warnings</div>
              <div style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
                Singapore calendar months before expiry. The second warning replaces the first; the first must be larger.
              </div>
              <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end', flexWrap: 'wrap' }}>
                <div className="form-group" style={{ marginBottom: 0, width: 130 }}>
                  <label>First (months)</label>
                  <input type="number" min={1} value={warn1} onChange={e => setWarn1(+e.target.value)} />
                </div>
                <div className="form-group" style={{ marginBottom: 0, width: 130 }}>
                  <label>Second (months)</label>
                  <input type="number" min={1} value={warn2} onChange={e => setWarn2(+e.target.value)} />
                </div>
                <button className="btn btn-primary btn-sm" style={{ marginBottom: 4 }} disabled={warnBusy} onClick={saveWarn}>
                  {warnBusy ? 'Saving…' : 'Save'}
                </button>
              </div>
            </div>
          )}
          {plans.length === 0 ? <div className="card"><div className="empty-state"><CreditCard size={32} style={{ opacity: 0.3 }} />
              <p style={{ fontWeight: 600, marginTop: 8 }}>No plans yet</p></div></div>
            : plans.map(p => (
              <div className="card" key={p.id} style={{ padding: 14 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 8 }}>
                  <div>
                    <div style={{ fontWeight: 700, fontSize: 15, display: 'flex', alignItems: 'center', gap: 8 }}>
                      {p.name}
                      {p.is_system && <span className="badge badge-muted" style={{ fontSize: 10 }}>Protected</span>}
                      {!p.is_active && <span className="badge badge-danger" style={{ fontSize: 10 }}>Inactive</span>}
                    </div>
                    <div style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 2 }}>
                      {p.duration_months} month{p.duration_months > 1 ? 's' : ''}{p.description ? ` · ${p.description}` : ''}
                    </div>
                  </div>
                  {canManage && !p.is_system && (
                    <div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => openPlan(p)}><Pencil size={12} /> Edit</button>
                      <button className="btn btn-secondary btn-sm" onClick={() => { setPriceFor(p); setPStore(''); setPFee(0); setPAvail(true); setErr(null); }}><StoreIcon size={12} /> Prices</button>
                      <button className="btn btn-danger btn-sm" onClick={() => delPlan(p)}><Trash2 size={12} /></button>
                    </div>
                  )}
                </div>
                {storePrice(p.id).length > 0 && (
                  <div style={{ marginTop: 10, display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                    {storePrice(p.id).map(pr => (
                      <span key={pr.id} className="badge badge-muted" style={{ fontSize: 11 }}>
                        {sName(pr.store_id)}: {money(pr.membership_fee)}{!pr.available_at_store ? ' (unavailable)' : ''}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            ))}
        </div>
      )}

      {planOpen && (
        <Modal title={editPlan ? 'Edit Plan' : 'New Plan'} maxWidth={440} onClose={() => setPlanOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setPlanOpen(false)}>Cancel</button>
            <button className="btn btn-primary" onClick={savePlan} disabled={busy}>{busy ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-group"><label>Plan name *</label><input value={pf.name} onChange={e => setPf({ ...pf, name: e.target.value })} placeholder="e.g. One-Year Membership" /></div>
            <div className="form-group"><label>Duration (calendar months) *</label><input type="number" min={1} value={pf.duration_months} onChange={e => setPf({ ...pf, duration_months: +e.target.value })} style={{ maxWidth: 140 }} /></div>
            <div className="form-group"><label>Description</label><input value={pf.description} onChange={e => setPf({ ...pf, description: e.target.value })} /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer' }}>
              <input type="checkbox" checked={pf.is_active} onChange={e => setPf({ ...pf, is_active: e.target.checked })} style={{ width: 'auto' }} /> Active
            </label>
          </div>
        </Modal>
      )}

      {priceFor && (
        <Modal title={`Store Prices — ${priceFor.name}`} maxWidth={460} onClose={() => setPriceFor(null)}
          footer={<button className="btn btn-secondary" onClick={() => setPriceFor(null)}>Done</button>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            {storePrice(priceFor.id).length > 0 && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {storePrice(priceFor.id).map(pr => (
                  <div key={pr.id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, padding: '4px 0', borderBottom: '1px solid var(--border)' }}>
                    <span>{sName(pr.store_id)}</span>
                    <span><strong>{money(pr.membership_fee)}</strong>{!pr.available_at_store ? ' · unavailable' : ''}</span>
                  </div>
                ))}
              </div>
            )}
            <div style={{ borderTop: '1px solid var(--border)', paddingTop: 10 }}>
              <div className="form-group"><label>Store</label>
                <select value={pStore} onChange={e => setPStore(e.target.value)}>
                  <option value="">— Select —</option>{stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select></div>
              <div className="form-grid-2">
                <div className="form-group" style={{ marginBottom: 0 }}><label>Fee</label><input type="number" min={0} step="0.01" value={pFee} onChange={e => setPFee(+e.target.value)} /></div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer', alignSelf: 'end', paddingBottom: 8 }}>
                  <input type="checkbox" checked={pAvail} onChange={e => setPAvail(e.target.checked)} style={{ width: 'auto' }} /> Available here
                </label>
              </div>
              <button className="btn btn-primary btn-sm" onClick={savePrice} disabled={busy} style={{ marginTop: 8 }}>{busy ? 'Saving…' : 'Set Price'}</button>
            </div>
          </div>
        </Modal>
      )}
      {editMem && (
        <Modal title={`Edit Membership — ${editMem.membership_no}`} maxWidth={480} onClose={() => setEditMem(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setEditMem(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveMembership} disabled={emBusy}>{emBusy ? 'Saving…' : 'Save Changes'}</button>
          </>}>
          <div className="form-grid">
            {emErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{emErr}</div></div>}
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              {cName(editMem.customer_id)} · {pName(editMem.plan_id)}
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Member ID</label>
              <input value={emMemberId} onChange={e => setEmMemberId(e.target.value)} placeholder="Assign or correct the physical Member ID" />
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>Globally unique; a customer keeps one permanent ID.</div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Store</label>
              <select value={emStore} onChange={e => setEmStore(e.target.value)}>
                <option value="">— none —</option>
                {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </div>
            <div className="form-grid-2">
              <div className="form-group" style={{ marginBottom: 0 }}><label>Start</label><input type="date" value={emStart} onChange={e => setEmStart(e.target.value)} /></div>
              <div className="form-group" style={{ marginBottom: 0 }}><label>Expiry</label><input type="date" value={emExpiry} onChange={e => setEmExpiry(e.target.value)} /></div>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Reason for change *</label>
              <input value={emReason} onChange={e => setEmReason(e.target.value)} placeholder="Required — recorded in the audit log" />
            </div>
            <div style={{ borderTop: '1px solid var(--border)', paddingTop: 10, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {editMem.status !== 'cancelled' && editMem.status !== 'suspended' && (
                <button className="btn btn-secondary btn-sm" disabled={emBusy} onClick={() => changeStatus('suspended')}><Ban size={12} /> Suspend</button>
              )}
              {editMem.status === 'suspended' && (
                <button className="btn btn-secondary btn-sm" disabled={emBusy} onClick={() => changeStatus('active')}><PlayCircle size={12} /> Reactivate</button>
              )}
              {editMem.status !== 'cancelled' && (
                <button className="btn btn-danger btn-sm" disabled={emBusy} onClick={() => changeStatus('cancelled')}><Trash2 size={12} /> Cancel Membership</button>
              )}
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default MembershipsPage;
