import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Affiliate, Customer, isManagerOrAbove } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Star, RefreshCw } from 'lucide-react';

const blank = (a?: Affiliate) => ({
  name: a?.name ?? '', phone: a?.phone ?? '', email: a?.email ?? '',
  customer_id: a?.customer_id ?? '', commission_value: a?.commission_value ?? 0,
  is_active: a?.is_active ?? true,
});

const AffiliatesPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isManagerOrAbove(profile?.role)) return <NoAccess message="Only Owners, Admins, and Managers can manage affiliates." />;

  const [rows, setRows] = useState<Affiliate[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blank());
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [a, c] = await Promise.all([
      supabase.from('affiliates').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('customers').select('*').is('deleted_at', null).order('full_name'),
    ]);
    setRows((a.data as Affiliate[]) ?? []);
    setCustomers((c.data as Customer[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (a: Affiliate) => { setForm(blank(a)); setEditId(a.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    if (!form.name.trim()) { setErr('Name is required.'); return; }
    if (form.commission_value < 0 || form.commission_value > 100) { setErr('Commission % must be between 0 and 100.'); return; }
    setSaving(true); setErr(null);
    const payload = {
      name: form.name.trim(), phone: form.phone.trim() || null, email: form.email.trim() || null,
      customer_id: form.customer_id || null, commission_type: 'percentage',
      commission_value: form.commission_value, is_active: form.is_active,
    };
    const res = editId
      ? await supabase.from('affiliates').update(payload).eq('id', editId)
      : await supabase.from('affiliates').insert(payload);
    if (res.error) { setErr(res.error.message); setSaving(false); return; }
    setSaving(false); setModalOpen(false); load();
  };

  const handleDelete = async (a: Affiliate) => {
    if (!confirm(`Delete affiliate "${a.name}"?`)) return;
    await supabase.from('affiliates').update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', a.id);
    load();
  };

  const customerName = (id: string | null) => id ? (customers.find(c => c.id === id)?.full_name ?? '—') : '—';
  const filtered = rows.filter(a => { const q = search.toLowerCase(); return !q || a.name.toLowerCase().includes(q) || (a.phone ?? '').includes(q); });

  return (
    <div>
      <div className="page-header">
        <div><h2>Affiliates</h2><p>Affiliate list with commission settings. Commission is earned when a referred invoice is paid.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Affiliate</button>
        </div>
      </div>

      <div style={{ marginBottom: 14, position: 'relative', maxWidth: 360 }}>
        <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name or phone…" style={{ paddingLeft: 34 }} />
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><Star size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No affiliates yet</p></div>
          : (
            <table>
              <thead><tr><th>Name</th><th>Phone</th><th>Linked Customer</th><th style={{ textAlign: 'right' }}>Commission</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {filtered.map(a => (
                  <tr key={a.id}>
                    <td><strong>{a.name}</strong></td>
                    <td style={{ fontSize: 13 }}>{a.phone || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{customerName(a.customer_id)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 700 }}>{a.commission_value}%</td>
                    <td>{a.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(a)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(a)}><Trash2 size={13} /></button>
                    </div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {modalOpen && (
        <Modal title={editId ? 'Edit Affiliate' : 'Add Affiliate'} maxWidth={460} onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-group"><label>Affiliate Name *</label><input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus /></div>
            <div className="form-grid-2">
              <div className="form-group"><label>Phone</label><input value={form.phone} onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} placeholder="Optional" /></div>
              <div className="form-group"><label>Commission %</label><input type="number" min={0} max={100} step={0.5} value={form.commission_value || ''} onChange={e => setForm(f => ({ ...f, commission_value: +e.target.value }))} placeholder="e.g. 5" /></div>
            </div>
            <div className="form-group"><label>Email</label><input type="email" value={form.email} onChange={e => setForm(f => ({ ...f, email: e.target.value }))} placeholder="Optional" /></div>
            <div className="form-group">
              <label>Link to Customer (optional)</label>
              <select value={form.customer_id} onChange={e => setForm(f => ({ ...f, customer_id: e.target.value }))}>
                <option value="">— None —</option>
                {customers.map(c => <option key={c.id} value={c.id}>{c.full_name} ({c.phone})</option>)}
              </select>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default AffiliatesPage;
