import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { Customer } from '../types';
import { Modal } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Users, RefreshCw } from 'lucide-react';

const blank = (c?: Customer) => ({
  full_name: c?.full_name ?? '', phone: c?.phone ?? '', email: c?.email ?? '',
  address: c?.address ?? '', notes: c?.notes ?? '', is_active: c?.is_active ?? true,
});

const CustomersPage: React.FC = () => {
  const [rows, setRows] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blank());
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.from('customers').select('*').is('deleted_at', null).order('created_at', { ascending: false });
    setRows((data as Customer[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (c: Customer) => { setForm(blank(c)); setEditId(c.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    if (!form.full_name.trim()) { setErr('Name is required.'); return; }
    if (!form.phone.trim()) { setErr('Phone number is required (must be unique).'); return; }
    setSaving(true); setErr(null);
    const payload = {
      full_name: form.full_name.trim(), phone: form.phone.trim(),
      email: form.email.trim() || null, address: form.address.trim() || null,
      notes: form.notes.trim() || null, is_active: form.is_active,
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

  const filtered = rows.filter(c => {
    const q = search.toLowerCase();
    return !q || c.full_name.toLowerCase().includes(q) || c.phone.includes(q) || (c.email ?? '').toLowerCase().includes(q);
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
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name, phone, email…" style={{ paddingLeft: 34 }} />
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
            <div className="form-group"><label>Email</label><input type="email" value={form.email} onChange={e => setForm(f => ({ ...f, email: e.target.value }))} placeholder="Optional" /></div>
            <div className="form-group"><label>Address</label><input value={form.address} onChange={e => setForm(f => ({ ...f, address: e.target.value }))} placeholder="Optional" /></div>
            <div className="form-group"><label>Notes</label><textarea rows={2} value={form.notes} onChange={e => setForm(f => ({ ...f, notes: e.target.value }))} placeholder="Optional" /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default CustomersPage;
