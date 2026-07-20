import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, Customer, UnlimitedTherapyPackage, UnlimitedTherapyStorePrice, PurchasedTherapyEntitlement, isOwnerOrManager } from '../types';
import { Modal, DateModal, ReasonModal } from '../components/ui';
import { RefreshCw, Plus, Sparkles, Search, CalendarClock, Play, Ban, Archive, Pencil } from 'lucide-react';
import StorePriceEditor from '../components/StorePriceEditor';

const money = (n: number) => `S$${Number(n ?? 0).toFixed(2)}`;
const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';
const sgToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' });

const PSTATUS: Record<string, { cls: string; label: string }> = {
  pending_activation: { cls: 'badge-accent', label: 'Pending Activation' },
  scheduled: { cls: 'badge-primary', label: 'Scheduled' },
  active: { cls: 'badge-success', label: 'Active' },
  expired: { cls: 'badge-muted', label: 'Expired' },
  cancelled: { cls: 'badge-danger', label: 'Cancelled' },
  refunded: { cls: 'badge-danger', label: 'Refunded' },
};

const TherapyPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  const [tab, setTab] = useState<'purchased' | 'legacy' | 'packages'>('purchased');
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  const [ents, setEnts] = useState<PurchasedTherapyEntitlement[]>([]);
  const [legacy, setLegacy] = useState<any[]>([]);
  const [packages, setPackages] = useState<UnlimitedTherapyPackage[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState<string | null>(null);

  // activation modal
  const [actEnt, setActEnt] = useState<PurchasedTherapyEntitlement | null>(null);
  const [actDate, setActDate] = useState('');
  const [actReason, setActReason] = useState('');
  // package modal
  const [pkgModal, setPkgModal] = useState<UnlimitedTherapyPackage | null | 'new'>(null);
  const [pkgName, setPkgName] = useState(''); const [pkgMonths, setPkgMonths] = useState(12);
  const [pkgDesc, setPkgDesc] = useState(''); const [pkgActive, setPkgActive] = useState(true);
  const [priceFor, setPriceFor] = useState<{ id: string; name: string } | null>(null);
  const [reschedEnt, setReschedEnt] = useState<PurchasedTherapyEntitlement | null>(null);
  const [reschedDate, setReschedDate] = useState<string | null>(null);   // step 1 result -> step 2 asks reason
  const [refundEnt, setRefundEnt] = useState<PurchasedTherapyEntitlement | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setErr(null);
    const [pe, le, pk, st, cu] = await Promise.all([
      supabase.from('purchased_therapy_entitlements').select('*').order('created_at', { ascending: false }),
      supabase.from('therapy_entitlements').select('*').order('created_at', { ascending: false }),
      supabase.from('unlimited_therapy_packages').select('*').is('deleted_at', null).order('duration_months'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('id, full_name, phone').is('deleted_at', null),
    ]);
    if (pe.error && !/relation.*does not exist/.test(pe.error.message)) setErr(pe.error.message);
    setEnts((pe.data as PurchasedTherapyEntitlement[]) ?? []);
    setLegacy((le.data as any[]) ?? []);
    setPackages((pk.data as UnlimitedTherapyPackage[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const cName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';
  const cPhone = (id: string) => customers.find(c => c.id === id)?.phone ?? '';

  const openActivate = (e: PurchasedTherapyEntitlement) => { setActEnt(e); setActDate(sgToday()); setActReason(''); setErr(null); };
  const doActivate = async (future: boolean) => {
    if (!actEnt) return;
    setBusy(actEnt.id); setErr(null);
    const { error } = await supabase.rpc('activate_purchased_therapy', {
      p_entitlement_id: actEnt.id,
      p_activation_date: future ? actDate : null,
      p_reason: actReason || null,
    });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    setActEnt(null); load();
  };
  const doReschedule = (e: PurchasedTherapyEntitlement) => { setReschedEnt(e); setReschedDate(null); };
  const submitReschedule = async (e: PurchasedTherapyEntitlement, newDate: string, reason: string) => {
    setBusy(e.id);
    const { error } = await supabase.rpc('reschedule_purchased_therapy', { p_entitlement_id: e.id, p_new_date: newDate, p_reason: reason });
    setBusy(null);
    setReschedEnt(null); setReschedDate(null);
    if (error) { setErr(error.message); return; }
    load();
  };
  const doRefund = (e: PurchasedTherapyEntitlement) => setRefundEnt(e);
  const submitRefund = async (e: PurchasedTherapyEntitlement, reason: string) => {
    setBusy(e.id);
    const { error } = await supabase.rpc('refund_purchased_therapy', { p_entitlement_id: e.id, p_reason: reason });
    setBusy(null);
    setRefundEnt(null);
    if (error) { setErr(error.message); return; }
    load();
  };
  const activateLegacy = async (e: any) => {
    if (!confirm(`Activate legacy entitlement ${e.entitlement_no}? This cannot be undone.`)) return;
    setBusy(e.id);
    const { error } = await supabase.rpc('activate_legacy_therapy', { p_entitlement_id: e.id });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    load();
  };

  const openPkg = (p: UnlimitedTherapyPackage | 'new') => {
    setPkgModal(p);
    if (p === 'new') { setPkgName(''); setPkgMonths(12); setPkgDesc(''); setPkgActive(true); }
    else { setPkgName(p.name); setPkgMonths(p.duration_months); setPkgDesc(p.description ?? ''); setPkgActive(p.is_active); }
  };
  const savePkg = async () => {
    setBusy('pkg');
    const { error } = await supabase.rpc('upsert_unlimited_therapy_package', {
      p_id: pkgModal === 'new' ? null : (pkgModal as UnlimitedTherapyPackage).id,
      p_name: pkgName, p_duration_months: pkgMonths, p_description: pkgDesc || null, p_is_active: pkgActive,
    });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    setPkgModal(null); load();
  };

  const filteredEnts = useMemo(() => {
    const s = search.trim().toLowerCase();
    if (!s) return ents;
    return ents.filter(e => cName(e.customer_id).toLowerCase().includes(s) || cPhone(e.customer_id).includes(s) || e.entitlement_no.toLowerCase().includes(s) || e.package_name.toLowerCase().includes(s));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ents, search, customers]);

  return (
    <div>
      <div className="page-header">
        <div><h2>Therapy</h2><p>Unlimited Therapy packages are purchased on an invoice. Target-based qualification has been retired; historical entitlements are read-only.</p></div>
        <button className="btn btn-secondary" onClick={load}><RefreshCw size={16} /> Refresh</button>
      </div>
      {err && <div className="alert alert-danger"><span>⚠</span><div>{err}</div></div>}

      <div style={{ display: 'flex', gap: 4, borderBottom: '1px solid var(--border)', marginBottom: 16 }}>
        {([['purchased', 'Purchased'], ['legacy', 'Legacy Therapy'], ...(canManage ? [['packages', 'Packages']] : [])] as [typeof tab, string][]).map(([v, l]) => (
          <button key={v} onClick={() => setTab(v)}
            style={{ padding: '8px 16px', background: 'none', border: 'none', display: 'inline-flex', alignItems: 'center', gap: 6,
              borderBottom: tab === v ? '2px solid var(--primary)' : '2px solid transparent',
              color: tab === v ? 'var(--primary)' : 'var(--text-secondary)', fontWeight: tab === v ? 700 : 500, cursor: 'pointer', marginBottom: -1 }}>
            {v === 'legacy' && <Archive size={13} />}{l}
          </button>
        ))}
      </div>

      {tab === 'purchased' && (
        <>
          <div style={{ position: 'relative', marginBottom: 12, maxWidth: 380 }}>
            <Search size={15} style={{ position: 'absolute', left: 10, top: 10, opacity: 0.4 }} />
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search customer, phone, no. or package…" style={{ paddingLeft: 32 }} />
          </div>
          <div className="card">
            {loading ? <div style={{ textAlign: 'center', padding: 40 }}><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div>
            : filteredEnts.length === 0 ? <div className="empty-state" style={{ padding: 40 }}><Sparkles size={30} style={{ opacity: 0.3 }} /><p style={{ marginTop: 10 }}>No purchased therapy yet. Sell an Unlimited Therapy package on an invoice.</p></div>
            : (
              <div className="table-wrap">
                <table>
                  <thead><tr><th>No.</th><th>Customer</th><th>Package</th><th>Purchased</th><th>Deadline</th><th>Activation</th><th>Expiry</th><th>Status</th><th></th></tr></thead>
                  <tbody>
                    {filteredEnts.map(e => {
                      const stt = PSTATUS[e.status] ?? { cls: 'badge-muted', label: e.status };
                      const canAct = e.status === 'pending_activation' || e.status === 'scheduled';
                      return (
                        <tr key={e.id}>
                          <td style={{ fontWeight: 600 }}>{e.entitlement_no}</td>
                          <td><div>{cName(e.customer_id)}</div><div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{cPhone(e.customer_id)}</div></td>
                          <td>{e.package_name}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{e.duration_months} mo · {money(e.price_snapshot)}{e.price_mode ? ` · ${e.price_mode === 'member' ? 'M' : 'NM'}` : ''}</div></td>
                          <td style={{ fontSize: 12 }}>{d(e.purchase_date)}</td>
                          <td style={{ fontSize: 12 }}>{d(e.activation_deadline)}</td>
                          <td style={{ fontSize: 12 }}>{d(e.activation_date ?? e.scheduled_date)}</td>
                          <td style={{ fontSize: 12 }}>{d(e.expiry_date)}</td>
                          <td><span className={`badge ${stt.cls}`}>{stt.label}</span></td>
                          <td>
                            <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                              {canAct && <button className="btn btn-primary btn-sm" disabled={busy === e.id} onClick={() => openActivate(e)}><Play size={12} /> Activate</button>}
                              {canAct && <button className="btn btn-secondary btn-sm" disabled={busy === e.id} onClick={() => doReschedule(e)}><CalendarClock size={12} /></button>}
                              {canManage && canAct && <button className="btn btn-danger btn-sm" disabled={busy === e.id} onClick={() => doRefund(e)}><Ban size={12} /> Refund</button>}
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}

      {tab === 'legacy' && (
        <div className="card">
          <div style={{ padding: '10px 12px', borderBottom: '1px solid var(--border)', fontSize: 12.5, color: 'var(--text-muted)' }}>
            Read-only historical entitlements. The only permitted action is activating an eligible, unactivated entitlement within its existing deadline — no transfer, division, reassignment, date change, or new qualification.
          </div>
          {loading ? <div style={{ textAlign: 'center', padding: 40 }}><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div>
          : legacy.length === 0 ? <div className="empty-state" style={{ padding: 40 }}><Archive size={30} style={{ opacity: 0.3 }} /><p style={{ marginTop: 10 }}>No legacy therapy entitlements.</p></div>
          : (
            <div className="table-wrap">
              <table>
                <thead><tr><th>No.</th><th>Customer</th><th>Package</th><th>Qualified</th><th>Deadline</th><th>Status</th><th></th></tr></thead>
                <tbody>
                  {legacy.map(e => {
                    const canActivate = e.status === 'pending_activation' && sgToday() <= e.activation_deadline;
                    const expired = e.status === 'pending_activation' && sgToday() > e.activation_deadline;
                    return (
                      <tr key={e.id}>
                        <td style={{ fontWeight: 600 }}>{e.entitlement_no}</td>
                        <td>{cName(e.customer_id)}</td>
                        <td>{e.package_name}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{e.entitlement_kind}{e.duration_months ? ` · ${e.duration_months} mo` : ''}</div></td>
                        <td style={{ fontSize: 12 }}>{money(e.qualified_value)}</td>
                        <td style={{ fontSize: 12 }}>{d(e.activation_deadline)}{expired && <span style={{ color: 'var(--danger)', fontSize: 11 }}> · passed</span>}</td>
                        <td><span className="badge badge-muted">{e.status}</span></td>
                        <td>{canActivate && <button className="btn btn-primary btn-sm" disabled={busy === e.id} onClick={() => activateLegacy(e)}><Play size={12} /> Activate</button>}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {tab === 'packages' && canManage && (
        <>
          <div style={{ marginBottom: 12 }}><button className="btn btn-primary" onClick={() => openPkg('new')}><Plus size={16} /> New Package</button></div>
          <div className="card">
            {packages.length === 0 ? <div className="empty-state" style={{ padding: 40 }}><p>No packages yet.</p></div> : (
              <table>
                <thead><tr><th>Name</th><th>Duration</th><th>Description</th><th>Active</th><th></th></tr></thead>
                <tbody>
                  {packages.map(p => (
                    <tr key={p.id}>
                      <td style={{ fontWeight: 600 }}>{p.name}</td>
                      <td>{p.duration_months} months</td>
                      <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{p.description ?? '—'}</td>
                      <td>{p.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                      <td>
                        <div style={{ display: 'flex', gap: 4 }}>
                          <button className="btn btn-secondary btn-sm" onClick={() => setPriceFor({ id: p.id, name: p.name })}>M/NM Prices</button>
                          <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openPkg(p)}><Pencil size={13} /></button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}

      {actEnt && (
        <Modal title={`Activate — ${actEnt.entitlement_no}`} maxWidth={420} onClose={() => setActEnt(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setActEnt(null)}>Cancel</button>
            <button className="btn btn-secondary" disabled={busy === actEnt.id} onClick={() => doActivate(true)}>Schedule for date</button>
            <button className="btn btn-primary" disabled={busy === actEnt.id} onClick={() => doActivate(false)}>Activate now</button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              {cName(actEnt.customer_id)} · {actEnt.package_name} ({actEnt.duration_months} months)<br />
              Must activate by <strong>{d(actEnt.activation_deadline)}</strong>.
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Activation date (for scheduling)</label>
              <input type="date" value={actDate} min={sgToday()} max={actEnt.activation_deadline} onChange={e => setActDate(e.target.value)} />
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>"Activate now" starts today. "Schedule for date" uses the date above. Expiry = activation + {actEnt.duration_months} calendar months, locked on activation.</div>
            </div>
          </div>
        </Modal>
      )}

      {pkgModal && (
        <Modal title={pkgModal === 'new' ? 'New Therapy Package' : 'Edit Package'} maxWidth={440} onClose={() => setPkgModal(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setPkgModal(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={savePkg} disabled={busy === 'pkg'}>Save</button></>}>
          <div className="form-grid">
            <div className="form-group" style={{ marginBottom: 0 }}><label>Name *</label><input value={pkgName} onChange={e => setPkgName(e.target.value)} placeholder="e.g. Unlimited Therapy – 1 Year" /></div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Duration (calendar months) *</label><input type="number" min={1} value={pkgMonths} onChange={e => setPkgMonths(+e.target.value)} /></div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Description</label><input value={pkgDesc} onChange={e => setPkgDesc(e.target.value)} /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, cursor: 'pointer' }}>
              <input type="checkbox" checked={pkgActive} onChange={e => setPkgActive(e.target.checked)} style={{ width: 'auto' }} /> Active
            </label>
          </div>
        </Modal>
      )}

      {reschedEnt && reschedDate === null && (
        <DateModal title={`Reschedule — ${reschedEnt.entitlement_no}`} label="New scheduled date"
          initial={reschedEnt.scheduled_date ?? sgToday()} min={sgToday()} max={reschedEnt.activation_deadline}
          confirmLabel="Next" helpText={`Must be on or before the deadline ${d(reschedEnt.activation_deadline)}.`}
          onClose={() => setReschedEnt(null)} onSubmit={(dt) => setReschedDate(dt)} />
      )}
      {reschedEnt && reschedDate !== null && (
        <ReasonModal title="Reason for date change" label="Reason for the date change"
          confirmLabel="Save" onClose={() => { setReschedEnt(null); setReschedDate(null); }}
          onSubmit={(reason) => submitReschedule(reschedEnt, reschedDate, reason)} />
      )}
      {refundEnt && (
        <ReasonModal title={`Refund — ${refundEnt.entitlement_no}`} label="Refund reason"
          placeholder="Why is this being refunded? (allowed only before activation)"
          confirmLabel="Refund" onClose={() => setRefundEnt(null)}
          onSubmit={(reason) => submitRefund(refundEnt, reason)} />
      )}
      {priceFor && (
        <StorePriceEditor kind="therapy" targetId={priceFor.id} targetName={priceFor.name}
          stores={stores} onClose={() => setPriceFor(null)} />
      )}
    </div>
  );
};

export default TherapyPage;
