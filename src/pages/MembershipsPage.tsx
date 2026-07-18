import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Customer, Store, MembershipPlan, MembershipPlanStorePrice, CustomerMembership, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import { RefreshCw, Plus, Search, CreditCard, Store as StoreIcon, AlertTriangle, Pencil, Trash2 } from 'lucide-react';

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

  const load = useCallback(async () => {
    setLoading(true);
    const [m, p, pr, c, s] = await Promise.all([
      supabase.from('customer_memberships').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('membership_plans').select('*').is('deleted_at', null).order('duration_months'),
      supabase.from('membership_plan_store_prices').select('*').is('deleted_at', null),
      supabase.from('customers').select('*').is('deleted_at', null).order('full_name'),
      supabase.from('stores').select('*').is('deleted_at', null).order('name'),
    ]);
    setRows((m.data as CustomerMembership[]) ?? []);
    setPlans((p.data as MembershipPlan[]) ?? []);
    setPrices((pr.data as MembershipPlanStorePrice[]) ?? []);
    setCustomers((c.data as Customer[]) ?? []);
    setStores((s.data as Store[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

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

  const delPlan = async (p: MembershipPlan) => {
    if (!confirm(`Delete plan "${p.name}"?`)) return;
    const { error } = await supabase.rpc('soft_delete_membership_plan', { p_id: p.id, p_restore: false });
    if (error) setErr(error.message); else load();
  };

  const q = search.trim().toLowerCase();
  const shown = rows.filter(r => {
    if (filter === 'missing_member_id' && r.member_id) return false;
    if (filter === 'missing_store' && r.store_id) return false;
    if (filter !== 'all' && filter !== 'missing_member_id' && filter !== 'missing_store' && r.status !== filter) return false;
    if (!q) return true;
    const c = customers.find(x => x.id === r.customer_id);
    return (!!c && (c.full_name.toLowerCase().includes(q) || c.phone.toLowerCase().includes(q)))
      || r.membership_no.toLowerCase().includes(q) || (r.member_id ?? '').toLowerCase().includes(q);
  });

  const storePrice = (planId: string) => prices.filter(p => p.plan_id === planId);

  return (
    <div>
      <div className="page-header">
        <div><h2>Memberships</h2><p>Membership plans and customer memberships. Pricing connects to invoices in a later phase.</p></div>
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
            {(['all', 'active', 'expiring_soon', 'expired', 'pending_payment', 'suspended', 'cancelled', 'missing_member_id', 'missing_store'] as const).map(v => (
              <button key={v} className={`btn btn-sm ${filter === v ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setFilter(v)}>
                {v === 'missing_member_id' ? 'Missing Member ID' : v === 'missing_store' ? 'Missing Store' : (STATUS[v]?.label ?? 'All')}
              </button>
            ))}
          </div>

          <div className="card"><div className="table-wrap">
            {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
              : shown.length === 0 ? <div className="empty-state"><CreditCard size={32} style={{ opacity: 0.3 }} />
                  <p style={{ fontWeight: 600, marginTop: 8 }}>{rows.length === 0 ? 'No memberships yet' : 'No memberships match'}</p></div>
              : <table>
                  <thead><tr><th>Membership</th><th>Customer</th><th>Plan</th><th>Member ID</th><th>Store</th><th>Start</th><th>Expiry</th><th>Status</th><th>Source</th></tr></thead>
                  <tbody>{shown.map(r => (
                    <tr key={r.id}>
                      <td style={{ fontSize: 12.5 }}><strong>{r.membership_no}</strong></td>
                      <td>{cName(r.customer_id)}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{cPhone(r.customer_id)}</div></td>
                      <td style={{ fontSize: 12.5 }}>{pName(r.plan_id)}</td>
                      <td style={{ fontSize: 12.5 }}>{r.member_id ?? <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: 'var(--danger)' }}><AlertTriangle size={11} /> missing</span>}</td>
                      <td style={{ fontSize: 12.5 }}>{sName(r.store_id) ?? <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: 'var(--danger)' }}><AlertTriangle size={11} /> missing</span>}</td>
                      <td style={{ fontSize: 12.5 }}>{d(r.start_date)}</td>
                      <td style={{ fontSize: 12.5 }}>{d(r.expiry_date)}</td>
                      <td><span className={`badge ${STATUS[r.status]?.cls ?? 'badge-muted'}`}>{STATUS[r.status]?.label ?? r.status}</span></td>
                      <td style={{ fontSize: 11.5, color: 'var(--text-muted)', textTransform: 'capitalize' }}>{r.source}{r.is_complimentary ? ' · comp' : ''}</td>
                    </tr>
                  ))}</tbody>
                </table>}
          </div></div>
        </>
      )}

      {tab === 'plans' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
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
    </div>
  );
};

export default MembershipsPage;
