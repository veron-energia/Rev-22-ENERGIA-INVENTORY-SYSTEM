import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, AffiliateRow, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import { RefreshCw, Search, UserPlus, Ban, PlayCircle, Store as StoreIcon, Users, X } from 'lucide-react';

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';

const STATE: Record<string, { cls: string; label: string }> = {
  active: { cls: 'badge-success', label: 'Active' },
  suspended_manual: { cls: 'badge-danger', label: 'Suspended' },
  inactive: { cls: 'badge-muted', label: 'Inactive' },
  not_activated: { cls: 'badge-muted', label: 'Not Activated' },
};

type FilterKey = 'all' | 'eligible' | 'active' | 'inactive' | 'suspended' | 'blocked' | 'missing_store';

const AffiliatesPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  const [rows, setRows] = useState<AffiliateRow[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState<FilterKey>('all');
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [storeModal, setStoreModal] = useState<AffiliateRow | null>(null);
  const [storeSel, setStoreSel] = useState('');
  const [downlineFor, setDownlineFor] = useState<AffiliateRow | null>(null);
  const [downlineRows, setDownlineRows] = useState<any[]>([]);

  const load = useCallback(async () => {
    setLoading(true); setErr(null);
    const [dir, st] = await Promise.all([
      supabase.rpc('affiliate_directory'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
    ]);
    if (dir.error) setErr(dir.error.message);
    setRows((dir.data as AffiliateRow[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const act = async (fn: string, args: any, label: string) => {
    setBusy(label); setErr(null);
    const { error } = await supabase.rpc(fn, args);
    setBusy(null);
    if (error) { setErr(error.message); return false; }
    await load();
    return true;
  };

  const activate = (r: AffiliateRow) => act('activate_affiliate', { p_customer_id: r.customer_id, p_store_id: r.store_id }, r.customer_id);
  const reactivate = (r: AffiliateRow) => act('reactivate_affiliate', { p_customer_id: r.customer_id }, r.customer_id);
  const suspend = (r: AffiliateRow) => {
    const reason = prompt('Reason to suspend this affiliate:')?.trim();
    if (!reason) return;
    act('suspend_affiliate', { p_customer_id: r.customer_id, p_reason: reason }, r.customer_id);
  };
  const saveStore = async () => {
    if (!storeModal) return;
    const okDone = await act('set_affiliate_store', { p_customer_id: storeModal.customer_id, p_store_id: storeSel || null }, storeModal.customer_id);
    if (okDone) setStoreModal(null);
  };

  const openDownline = async (r: AffiliateRow) => {
    setDownlineFor(r);
    const { data } = await supabase.from('customers')
      .select('id, full_name, phone, referred_by').eq('referred_by', r.customer_id);
    setDownlineRows((data as any[]) ?? []);
  };

  const filtered = useMemo(() => rows.filter(r => {
    const s = q.trim().toLowerCase();
    if (s && !(r.full_name?.toLowerCase().includes(s) || r.phone?.toLowerCase().includes(s))) return false;
    switch (filter) {
      case 'eligible': return r.affiliate_state === 'active';
      case 'active': return r.affiliate_state === 'active';
      case 'inactive': return r.affiliate_state === 'inactive' || r.affiliate_state === 'not_activated';
      case 'suspended': return r.manually_suspended;
      case 'blocked': return Number(r.blocked_commission) > 0;
      case 'missing_store': return r.has_profile && !r.store_id;
      default: return true;
    }
  }), [rows, q, filter]);

  const counts = useMemo(() => ({
    all: rows.length,
    eligible: rows.filter(r => r.affiliate_state === 'active').length,
    inactive: rows.filter(r => r.affiliate_state === 'inactive' || r.affiliate_state === 'not_activated').length,
    suspended: rows.filter(r => r.manually_suspended).length,
    blocked: rows.filter(r => Number(r.blocked_commission) > 0).length,
    missing_store: rows.filter(r => r.has_profile && !r.store_id).length,
  }), [rows]);

  const filterBtn = (key: FilterKey, label: string, n?: number) => (
    <button className={filter === key ? 'btn btn-primary btn-sm' : 'btn btn-secondary btn-sm'} onClick={() => setFilter(key)}>
      {label}{n !== undefined ? ` (${n})` : ''}
    </button>
  );

  return (
    <div>
      <div className="page-header">
        <div><h2>Affiliates</h2><p>Direct-referral affiliate programme. New affiliates are activated by an Owner or Manager.</p></div>
        <button className="btn btn-secondary" onClick={load}><RefreshCw size={16} /> Refresh</button>
      </div>

      {err && <div className="alert alert-danger"><span>⚠</span><div>{err}</div></div>}

      <div className="card" style={{ padding: 12, marginBottom: 12 }}>
        <div style={{ position: 'relative', marginBottom: 10 }}>
          <Search size={15} style={{ position: 'absolute', left: 10, top: 10, opacity: 0.4 }} />
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search customer or phone…" style={{ paddingLeft: 32 }} />
        </div>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {filterBtn('all', 'All', counts.all)}
          {filterBtn('eligible', 'Eligible', counts.eligible)}
          {filterBtn('active', 'Active')}
          {filterBtn('inactive', 'Inactive', counts.inactive)}
          {filterBtn('suspended', 'Suspended', counts.suspended)}
          {filterBtn('blocked', 'Blocked Commission', counts.blocked)}
          {filterBtn('missing_store', 'Missing Store', counts.missing_store)}
        </div>
      </div>

      <div className="card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: 40 }}><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div>
        ) : filtered.length === 0 ? (
          <div className="empty-state" style={{ padding: 40 }}><Users size={32} style={{ opacity: 0.3 }} /><p style={{ marginTop: 10 }}>No affiliates match.</p></div>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <table className="data-table">
              <thead><tr>
                <th>Customer</th><th>Affiliate</th><th>Store</th>
                <th>Referrals</th><th>Downline</th><th>Lifetime</th><th>Payable</th><th>Blocked</th><th>Last</th><th></th>
              </tr></thead>
              <tbody>
                {filtered.map(r => {
                  const stt = STATE[r.affiliate_state] ?? { cls: 'badge-muted', label: r.affiliate_state };
                  return (
                    <tr key={r.customer_id}>
                      <td><div style={{ fontWeight: 600 }}>{r.full_name}</div><div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{r.phone}</div></td>
                      <td><span className={`badge ${stt.cls}`}>{stt.label}</span>{r.block_reason && r.affiliate_state !== 'active' && <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>{r.block_reason}</div>}</td>
                      <td style={{ fontSize: 12 }}>{r.store_name ?? <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                      <td style={{ textAlign: 'center' }}>{r.direct_referrals}</td>
                      <td style={{ textAlign: 'center' }}>{r.downline}</td>
                      <td>{money(r.lifetime_earned)}</td>
                      <td>{money(r.unpaid_payable)}</td>
                      <td>{Number(r.blocked_commission) > 0 ? <span style={{ color: 'var(--danger)' }}>{money(r.blocked_commission)}</span> : '—'}</td>
                      <td style={{ fontSize: 12 }}>{d(r.last_commission_date)}</td>
                      <td>
                        {canManage && (
                          <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                            {!r.has_profile && <button className="btn btn-primary btn-sm" disabled={busy === r.customer_id} onClick={() => activate(r)}><UserPlus size={12} /> Activate</button>}
                            {r.has_profile && r.manually_suspended && <button className="btn btn-secondary btn-sm" disabled={busy === r.customer_id} onClick={() => reactivate(r)}><PlayCircle size={12} /> Reactivate</button>}
                            {r.has_profile && !r.manually_suspended && <button className="btn btn-secondary btn-sm" disabled={busy === r.customer_id} onClick={() => suspend(r)}><Ban size={12} /> Suspend</button>}
                            {r.has_profile && <button className="btn btn-secondary btn-sm" onClick={() => { setStoreModal(r); setStoreSel(r.store_id ?? ''); }}><StoreIcon size={12} /></button>}
                            <button className="btn btn-secondary btn-sm" onClick={() => openDownline(r)}><Users size={12} /></button>
                          </div>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {storeModal && (
        <Modal title={`Assign Store — ${storeModal.full_name}`} maxWidth={380} onClose={() => setStoreModal(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setStoreModal(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveStore} disabled={busy === storeModal.customer_id}>Save</button></>}>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Affiliate store</label>
            <select value={storeSel} onChange={e => setStoreSel(e.target.value)}>
              <option value="">— none —</option>
              {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
        </Modal>
      )}

      {downlineFor && (
        <Modal title={`Direct Referrals — ${downlineFor.full_name}`} maxWidth={440} onClose={() => setDownlineFor(null)}
          footer={<button className="btn btn-secondary" onClick={() => setDownlineFor(null)}>Close</button>}>
          {downlineRows.length === 0 ? <p style={{ color: 'var(--text-muted)' }}>No direct referrals.</p> : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {downlineRows.map(c => (
                <div key={c.id} style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid var(--border)', paddingBottom: 6 }}>
                  <span>{c.full_name}</span><span style={{ color: 'var(--text-muted)', fontSize: 12 }}>{c.phone}</span>
                </div>
              ))}
            </div>
          )}
        </Modal>
      )}
    </div>
  );
};

export default AffiliatesPage;
