import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Customer, CustomerGender, isOwnerOrManager } from '../types';
import MembershipBadge from '../components/MembershipBadge';
import { Modal } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Users, RefreshCw, Eye, Phone } from 'lucide-react';

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
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blank());
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [profileFor, setProfileFor] = useState<Customer | null>(null);
  const [profileStats, setProfileStats] = useState<any>(null);
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
    const [cust, ph] = await Promise.all([
      supabase.from('customers').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('customer_phone_history').select('customer_id,phone,reason,created_at'),
    ]);
    setRows((cust.data as Customer[]) ?? []);
    setPhoneHistory((ph.data as any[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openProfile = async (c: Customer) => {
    setProfileFor(c); setProfileStats(null);
    const { data } = await supabase.rpc('customer_profile_stats', { p_customer_id: c.id });
    setProfileStats(data ?? {});
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
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><Users size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No customers yet</p></div>
          : (
            <table>
              <thead><tr><th>Name</th><th>Phone</th><th>Email</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {filtered.map(c => (
                  <tr key={c.id}>
                    <td><strong>{c.full_name}</strong>{c.notes && <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{c.notes.slice(0, 40)}</div>}</td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 13 }}>{c.phone}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{c.email || '—'}</td>
                    <td>{c.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => openProfile(c)}><Eye size={13} /> Profile</button>
                      <button className="btn btn-secondary btn-sm btn-icon" title="Change phone" onClick={() => { setPhoneFor(c); setNewPhone(''); setPhoneReason(''); setPhoneErr(null); }}><Phone size={13} /></button>
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
            </div>
          )}
        </Modal>
      )}
    </div>
  );
};

export default CustomersPage;
