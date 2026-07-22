import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Customer, CustomerGender, isOwnerOrManager } from '../types';
import MembershipBadge from '../components/MembershipBadge';
import { Modal } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Users, RefreshCw, Eye, Phone, ChevronDown, ChevronRight } from 'lucide-react';

const blank = (c?: Customer) => ({
  full_name: c?.full_name ?? '', phone: c?.phone ?? '', email: c?.email ?? '',
  date_of_birth: c?.date_of_birth ?? '', gender: (c?.gender ?? '') as CustomerGender | '',
  gender_other: c?.gender_other ?? '', occupation: c?.occupation ?? '',
  notes: c?.notes ?? '', is_active: c?.is_active ?? true,
  referred_by: c?.referred_by ?? '',
});

const CustomersPage: React.FC = () => {
  const { profile } = useAuth();
  const canComplete = isOwnerOrManager(profile?.role);   // complete profile view: Owner/Manager only
  const [rows, setRows] = useState<Customer[]>([]);
  const [phoneHistory, setPhoneHistory] = useState<{ customer_id: string; phone: string; reason: string | null; created_at: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  // Phase 14 — customer source: filter + staff correction.
  const [sourceFilter, setSourceFilter] = useState('');
  const [sourceOpts, setSourceOpts] = useState<{ id: string; label: string; requires_details: boolean }[]>([]);
  const [srcFor, setSrcFor] = useState<Customer | null>(null);
  const [srcOptId, setSrcOptId] = useState('');
  const [srcDetails, setSrcDetails] = useState('');
  const [srcReason, setSrcReason] = useState('');
  const [srcErr, setSrcErr] = useState<string | null>(null);
  const [srcBusy, setSrcBusy] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blank());
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [profileFor, setProfileFor] = useState<Customer | null>(null);
  const [overviewFor, setOverviewFor] = useState<Customer | null>(null);
  const [overview, setOverview] = useState<any>(null);
  const [ovLoading, setOvLoading] = useState(false);
  const [profileStats, setProfileStats] = useState<any>(null);
  const [timeline, setTimeline] = useState<any[] | null>(null);
  const [expandedInv, setExpandedInv] = useState<Record<string, boolean>>({});
  const [phoneFor, setPhoneFor] = useState<Customer | null>(null);
  const [newPhone, setNewPhone] = useState('');
  const [phoneReason, setPhoneReason] = useState('');
  const [phoneErr, setPhoneErr] = useState<string | null>(null);
  const [phoneBusy, setPhoneBusy] = useState(false);
  const submitPhoneChange = async () => {
    if (!phoneFor) return;
    if (!newPhone.trim()) { setPhoneErr('Enter the new phone number.'); return; }
    if (!phoneReason.trim()) { setPhoneErr('A reason is required.'); return; }
    setPhoneBusy(true); setPhoneErr(null);
    const { error } = await supabase.rpc('change_customer_phone', { p_customer_id: phoneFor.id, p_new_phone: newPhone.trim(), p_reason: phoneReason.trim() });
    setPhoneBusy(false);
    if (error) { setPhoneErr(error.message); return; }
    setPhoneFor(null); load();
  };

  const load = useCallback(async () => {
    setLoading(true);
    const [cust, ph, srcs] = await Promise.all([
      supabase.from('customers').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('customer_phone_history').select('customer_id,phone,reason,created_at'),
      supabase.rpc('active_customer_source_options'),
    ]);
    setRows((cust.data as Customer[]) ?? []);
    setPhoneHistory((ph.data as any[]) ?? []);
    setSourceOpts((srcs.data as any[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openOverview = async (c: Customer) => {
    setOverviewFor(c); setOverview(null); setOvLoading(true);
    const { data } = await supabase.rpc('customer_overview', { p_customer_id: c.id });
    setOverview(data ?? null); setOvLoading(false);
  };
  const openProfile = async (c: Customer) => {
    setProfileFor(c); setProfileStats(null); setTimeline(null); setExpandedInv({});
    const { data } = await supabase.rpc('customer_profile_stats', { p_customer_id: c.id });
    setProfileStats(data ?? {});
    if (canComplete) {
      const { data: tl } = await supabase.rpc('customer_purchase_timeline', { p_customer_id: c.id });
      setTimeline((tl as any[]) ?? []);
    }
  };

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (c: Customer) => { setForm(blank(c)); setEditId(c.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    if (!form.full_name.trim()) { setErr('Name is required.'); return; }
    if (!form.phone.trim()) { setErr('Phone number is required (must be unique).'); return; }
    setSaving(true); setErr(null);
    const payload = {
      full_name: form.full_name.trim(), phone: form.phone.trim(),
      email: form.email.trim() || null,
      date_of_birth: form.date_of_birth || null,
      gender: form.gender || null,
      gender_other: form.gender === 'other' ? (form.gender_other.trim() || null) : null,
      occupation: form.occupation.trim() || null,
      notes: form.notes.trim() || null, is_active: form.is_active,
      referred_by: form.referred_by || null, is_referrer: true,
    };
    const res = editId
      ? await supabase.from('customers').update(payload).eq('id', editId)
      : await supabase.from('customers').insert(payload);
    if (res.error) {
      setErr(res.error.message.includes('duplicate') || res.error.message.includes('unique')
        ? 'A customer with this phone number already exists. Phone numbers must be unique.'
        : res.error.message);
      setSaving(false); return;
    }
    setSaving(false); setModalOpen(false); load();
  };

  const handleDelete = async (c: Customer) => {
    if (!confirm(`Delete "${c.full_name}"? They can be restored later.`)) return;
    await supabase.from('customers').update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', c.id);
    load();
  };

  const histByPhone = useMemo(() => {
    const m = new Map<string, string[]>();
    phoneHistory.forEach(h => { const a = m.get(h.customer_id) ?? []; a.push(h.phone); m.set(h.customer_id, a); });
    return m;
  }, [phoneHistory]);

  const filtered = rows.filter(c => {
    if (sourceFilter === '__none' && (c as any).source_option_id) return false;
    if (sourceFilter && sourceFilter !== '__none' && (c as any).source_option_id !== sourceFilter) return false;
    const q = search.trim().toLowerCase();
    if (!q) return true;
    const hist = histByPhone.get(c.id) ?? [];
    return c.full_name.toLowerCase().includes(q)
      || c.phone.toLowerCase().includes(q)
      || hist.some(p => p.toLowerCase().includes(q))
      || (c.email ?? '').toLowerCase().includes(q);
  });

  return (
    <div>
      <div className="page-header">
        <div><h2>Customers</h2><p>Customer database. Phone numbers are unique across all stores.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Customer</button>
        </div>
      </div>

      <div style={{ marginBottom: 14, position: 'relative', maxWidth: 360 }}>
        <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name, phone (incl. old), or email…" style={{ paddingLeft: 34 }} />
        <select value={sourceFilter} onChange={e => setSourceFilter(e.target.value)} style={{ maxWidth: 190, marginLeft: 8 }} title="Filter by customer source">
          <option value="">All sources</option>
          {sourceOpts.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}
          <option value="__none">No source recorded</option>
        </select>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><Users size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No customers yet</p></div>
          : (
            <table>
              <thead><tr><th>Name</th><th>Phone</th><th>Email</th><th>Source</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {filtered.map(c => (
                  <tr key={c.id}>
                    <td><strong>{c.full_name}</strong>{c.notes && <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{c.notes.slice(0, 40)}</div>}</td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 13 }}>{c.phone}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{c.email || '—'}</td>
                    <td style={{ fontSize: 12.5 }}>
                      {(c as any).source_label ?? <span style={{ color: 'var(--text-muted)' }}>—</span>}
                      {(c as any).source_details && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{(c as any).source_details}</div>}
                    </td>
                    <td>{c.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => openOverview(c)}><Eye size={13} /> View</button>
                      <button className="btn btn-secondary btn-sm" onClick={() => openProfile(c)}>Profile</button>
                      <button className="btn btn-secondary btn-sm btn-icon" title="Change phone" onClick={() => { setPhoneFor(c); setNewPhone(''); setPhoneReason(''); setPhoneErr(null); }}><Phone size={13} /></button>
                      <button className="btn btn-secondary btn-sm" title="Change customer source (old surveys keep their snapshot)"
                        onClick={() => { setSrcFor(c); setSrcOptId((c as any).source_option_id ?? ''); setSrcDetails((c as any).source_details ?? ''); setSrcReason(''); setSrcErr(null); }}>Source</button>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(c)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(c)}><Trash2 size={13} /></button>
                    </div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {modalOpen && (
        <Modal title={editId ? 'Edit Customer' : 'Add Customer'} maxWidth={460} onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Full Name *</label><input value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} autoFocus /></div>
              <div className="form-group"><label>Phone * (unique)</label><input value={form.phone} onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} placeholder="e.g. 91234567" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Email</label><input type="email" value={form.email} onChange={e => setForm(f => ({ ...f, email: e.target.value }))} placeholder="Optional" /></div>
              <div className="form-group"><label>Date of Birth</label><input type="date" value={form.date_of_birth} onChange={e => setForm(f => ({ ...f, date_of_birth: e.target.value }))} /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Gender</label>
                <select value={form.gender} onChange={e => setForm(f => ({ ...f, gender: e.target.value as CustomerGender | '' }))}>
                  <option value="">— Not specified —</option>
                  <option value="male">Male</option>
                  <option value="female">Female</option>
                  <option value="other">Other</option>
                </select>
              </div>
              <div className="form-group"><label>Occupation</label><input value={form.occupation} onChange={e => setForm(f => ({ ...f, occupation: e.target.value }))} placeholder="Optional" /></div>
            </div>
            {form.gender === 'other' && (
              <div className="form-group"><label>Please specify gender</label><input value={form.gender_other} onChange={e => setForm(f => ({ ...f, gender_other: e.target.value }))} placeholder="Free text" autoFocus /></div>
            )}
            <div className="form-group"><label>Notes</label><textarea rows={2} value={form.notes} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))} placeholder="Optional" /></div>
            <div className="form-group">
              <label>Referred by (optional)</label>
              <select value={form.referred_by} onChange={e => setForm(f => ({ ...f, referred_by: e.target.value }))}>
                <option value="">— No referrer —</option>
                {rows.filter(c => c.id !== editId).map(c => <option key={c.id} value={c.id}>{c.full_name} ({c.phone})</option>)}
              </select>
              <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>The customer who introduced this customer. Drives Tier 1 / Tier 2 commission.</span>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
          </div>
        </Modal>
      )}

      {overviewFor && (
        <Modal title={`${overviewFor.full_name}`} maxWidth={640} onClose={() => setOverviewFor(null)}
          footer={<button className="btn btn-secondary" onClick={() => setOverviewFor(null)}>Close</button>}>
          {ovLoading || !overview ? <div style={{ textAlign: 'center', padding: 30, color: 'var(--text-muted)' }}>Loading…</div> : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14, fontSize: 13 }}>
              <section>
                <div style={{ fontWeight: 700, marginBottom: 4 }}>Membership</div>
                {overview.membership_status?.is_member ? (
                  <div>
                    {overview.membership_status.plan_name} · Member ID <strong>{overview.member_id ?? 'missing'}</strong><br />
                    {overview.membership_status.start_date && <>Start {new Date(overview.membership_status.start_date).toLocaleDateString('en-GB')} → Expiry {overview.membership_status.expiry_date ? new Date(overview.membership_status.expiry_date).toLocaleDateString('en-GB') : '—'}</>}
                    {overview.membership_status.days_left != null && <> · {overview.membership_status.days_left} days left</>}
                    {overview.membership_status.warning && <div style={{ color: 'var(--danger)' }}>{overview.membership_status.warning}</div>}
                  </div>
                ) : <div style={{ color: 'var(--text-muted)' }}>No active membership</div>}
              </section>
              <section>
                <div style={{ fontWeight: 700, marginBottom: 4 }}>Affiliate</div>
                <div style={{ color: 'var(--text-muted)' }}>{overview.affiliate_state?.eligible ? 'Eligible' : (overview.affiliate_state?.block_reason ?? overview.affiliate_state?.state ?? '—')}</div>
              </section>
              {overview.memberships?.length > 1 && (
                <section>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Membership history</div>
                  {overview.memberships.map((m: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{m.membership_no} · {m.plan ?? '—'} · {m.status}{m.cancelled_at ? ` · cancelled (${m.cancel_reason ?? ''})` : ''}</div>)}
                </section>
              )}
              {overview.refunds?.length > 0 && (
                <section>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Refunds / cancellations</div>
                  {overview.refunds.map((r: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{r.invoice} · S${Number(r.amount).toFixed(2)} · {r.kind} · {r.reason}</div>)}
                </section>
              )}
              {overview.purchased_therapy?.length > 0 && (
                <section>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Purchased therapy</div>
                  {overview.purchased_therapy.map((t: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{t.no} · {t.package} · {String(t.status).replace('_', ' ')}{t.expiry ? ` · expires ${new Date(t.expiry).toLocaleDateString('en-GB')}` : ''}</div>)}
                </section>
              )}
              {overview.legacy_therapy?.length > 0 && (
                <section>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Legacy therapy</div>
                  {overview.legacy_therapy.map((t: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{t.no} · {t.package} · {t.status}</div>)}
                </section>
              )}
              {overview.deleted_invoices?.length > 0 && (
                <section>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Deleted invoice history</div>
                  {overview.deleted_invoices.map((iv: any, i: number) => <div key={i} style={{ color: 'var(--text-muted)', fontSize: 12 }}>{iv.invoice} · S${Number(iv.total).toFixed(2)} · deleted {new Date(iv.deleted_at).toLocaleDateString('en-GB')}</div>)}
                </section>
              )}
            </div>
          )}
        </Modal>
      )}
      {srcFor && (
        <Modal title={`Customer Source — ${srcFor.full_name}`} maxWidth={420} onClose={() => setSrcFor(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setSrcFor(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={srcBusy || !srcOptId} onClick={async () => {
              setSrcBusy(true); setSrcErr(null);
              const { error } = await supabase.rpc('set_customer_source', {
                p_customer_id: srcFor.id, p_option_id: srcOptId,
                p_details: srcDetails.trim() || null, p_reason: srcReason.trim() || null,
              });
              setSrcBusy(false);
              if (error) { setSrcErr(error.message); return; }
              setSrcFor(null); load();
            }}>{srcBusy ? 'Saving…' : 'Save Source'}</button>
          </>}>
          <div className="form-grid">
            {srcErr && <div className="alert alert-danger" style={{ fontSize: 12.5 }}>{srcErr}</div>}
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              This updates the customer's <b>current</b> source. Health-survey snapshots are permanent and stay unchanged; the change is audit-logged.
            </div>
            <div>
              <label>Source</label>
              <select value={srcOptId} onChange={e => { setSrcOptId(e.target.value); setSrcDetails(''); }}>
                <option value="">— Select —</option>
                {sourceOpts.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}
              </select>
            </div>
            {sourceOpts.find(o => o.id === srcOptId)?.requires_details && (
              <div><label>Details <span style={{ color: 'var(--danger)' }}>*</span></label>
                <input value={srcDetails} onChange={e => setSrcDetails(e.target.value)} /></div>
            )}
            <div><label>Reason for change</label>
              <input value={srcReason} onChange={e => setSrcReason(e.target.value)} placeholder="Optional — shown in the audit log" /></div>
          </div>
        </Modal>
      )}

      {phoneFor && (
        <Modal title={`Change Phone — ${phoneFor.full_name}`} maxWidth={420} onClose={() => setPhoneFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setPhoneFor(null)}>Cancel</button><button className="btn btn-primary" onClick={submitPhoneChange} disabled={phoneBusy}>{phoneBusy ? 'Saving…' : 'Change Number'}</button></>}>
          <div className="form-grid">
            {phoneErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{phoneErr}</div></div>}
            <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>Current number: <strong>{phoneFor.phone}</strong> — it will move into this customer's phone history.</div>
            <div className="form-group"><label>New Phone Number *</label><input value={newPhone} onChange={e => setNewPhone(e.target.value)} placeholder="e.g. 91234567" autoFocus /></div>
            <div className="form-group"><label>Reason *</label><input value={phoneReason} onChange={e => setPhoneReason(e.target.value)} placeholder="Why is the number changing?" /></div>
          </div>
        </Modal>
      )}

      {profileFor && (
        <Modal title={`Profile — ${profileFor.full_name}`} maxWidth={460} onClose={() => setProfileFor(null)}
          footer={<button className="btn btn-secondary" onClick={() => setProfileFor(null)}>Close</button>}>
          {!profileStats ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div> : (
            <div className="form-grid">
            <MembershipBadge customerId={profileFor.id} />
              {canComplete ? (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                  <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Paid purchases</div>
                    <div style={{ fontSize: 20, fontWeight: 700 }}>{profileStats.purchases ?? 0}</div>
                  </div>
                  <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Total spend</div>
                    <div style={{ fontSize: 20, fontWeight: 700 }}>S${Number(profileStats.total_spend ?? 0).toFixed(2)}</div>
                  </div>
                  <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Customers referred</div>
                    <div style={{ fontSize: 20, fontWeight: 700 }}>{profileStats.referred_count ?? 0}</div>
                  </div>
                  <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Referred by</div>
                    <div style={{ fontSize: 14, fontWeight: 600, marginTop: 4 }}>{profileStats.referrer_name ?? '—'}</div>
                  </div>
                </div>
              ) : (
                <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Limited view — financial, commission, and audit history are visible to Owners and Managers only.</div></div>
              )}
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', display: 'flex', flexWrap: 'wrap', gap: '4px 14px' }}>
                <span>Phone: {profileFor.phone}</span>
                {profileFor.email && <span>· {profileFor.email}</span>}
                {profileFor.date_of_birth && <span>· DOB: {new Date(profileFor.date_of_birth).toLocaleDateString()}</span>}
                {profileFor.gender && <span>· {profileFor.gender === 'other' ? (profileFor.gender_other || 'Other') : (profileFor.gender.charAt(0).toUpperCase() + profileFor.gender.slice(1))}</span>}
                {profileFor.occupation && <span>· {profileFor.occupation}</span>}
              </div>
              {canComplete && (() => {
                const hist = phoneHistory.filter(h => h.customer_id === profileFor.id).sort((a, b) => b.created_at.localeCompare(a.created_at));
                return hist.length > 0 ? (
                  <div>
                    <label>Phone history</label>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
                      {hist.map((h, i) => (
                        <div key={i} style={{ fontSize: 12, color: 'var(--text-secondary)', display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid var(--border)', paddingBottom: 3 }}>
                          <span style={{ fontFamily: 'var(--font-display)' }}>{h.phone}</span>
                          <span style={{ color: 'var(--text-muted)' }}>{h.reason || '—'} · {new Date(h.created_at).toLocaleDateString()}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null;
              })()}
              {canComplete && timeline && timeline.length > 0 && (
                <div>
                  <label>Purchase timeline</label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 6 }}>
                    {timeline.map((inv: any) => {
                      const open = !!expandedInv[inv.invoice_id];
                      const statusCls = inv.status === 'paid' ? 'badge-success' : inv.status === 'unpaid' ? 'badge-accent' : inv.status === 'cancelled' || inv.status === 'refunded' ? 'badge-danger' : 'badge-muted';
                      return (
                        <div key={inv.invoice_id} style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', overflow: 'hidden' }}>
                          <div onClick={() => setExpandedInv(s => ({ ...s, [inv.invoice_id]: !s[inv.invoice_id] }))}
                            style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 10px', cursor: 'pointer', background: 'var(--surface-2)' }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                              {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                              <span style={{ fontWeight: 600, fontSize: 13 }}>{inv.invoice_no}</span>
                              {inv.is_topup && <span className="badge badge-muted" style={{ fontSize: 10 }}>top-up</span>}
                              <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{inv.date ? new Date(inv.date).toLocaleDateString('en-GB') : '—'}</span>
                            </div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                              <span className={`badge ${statusCls}`} style={{ fontSize: 10, textTransform: 'capitalize' }}>{inv.status}</span>
                              <span style={{ fontWeight: 700, fontSize: 13 }}>S${Number(inv.total).toFixed(2)}</span>
                            </div>
                          </div>
                          {open && (
                            <div style={{ padding: '6px 10px 8px 30px' }}>
                              {(inv.items ?? []).map((it: any, j: number) => (
                                <div key={j} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, padding: '3px 0', borderBottom: j < inv.items.length - 1 ? '1px solid var(--border)' : 'none' }}>
                                  <span>
                                    <span style={{ color: 'var(--text-muted)', textTransform: 'capitalize' }}>{String(it.kind).replace('_', ' ')}</span> · {it.name}
                                    {it.qty > 1 && <span style={{ color: 'var(--text-muted)' }}> ×{it.qty}</span>}
                                    {it.price_mode && <span style={{ color: 'var(--text-muted)' }}> · {it.price_mode === 'member' ? 'M' : 'NM'}</span>}
                                  </span>
                                  <span style={{ fontWeight: 600 }}>S${Number(it.line_total).toFixed(2)}</span>
                                </div>
                              ))}
                              {Number(inv.save_earth) > 0 && <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4 }}>🌱 Save Earth: S${Number(inv.save_earth).toFixed(2)}</div>}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
              {canComplete && timeline && timeline.length === 0 && (
                <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No purchases yet.</div>
              )}
            </div>
          )}
        </Modal>
      )}
    </div>
  );
};

export default CustomersPage;
