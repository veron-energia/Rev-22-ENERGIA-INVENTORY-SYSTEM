import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { PaymentMethod, isOwnerOrManager } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { Plus, Pencil, Trash2, CreditCard, RefreshCw } from 'lucide-react';

const PaymentMethodsPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isOwnerOrManager(profile?.role)) return <NoAccess message="Only Owners and Managers can manage payment methods." />;

  const [rows, setRows] = useState<PaymentMethod[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [active, setActive] = useState(true);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.from('payment_methods').select('*').is('deleted_at', null).order('created_at');
    setRows((data as PaymentMethod[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setName(''); setActive(true); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (m: PaymentMethod) => { setName(m.name); setActive(m.is_active); setEditId(m.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    if (!name.trim()) { setErr('Name is required.'); return; }
    setSaving(true); setErr(null);
    const payload = { name: name.trim(), is_active: active };
    const res = editId
      ? await supabase.from('payment_methods').update(payload).eq('id', editId)
      : await supabase.from('payment_methods').insert(payload);
    if (res.error) { setErr(res.error.message.includes('duplicate') ? 'That payment method already exists.' : res.error.message); setSaving(false); return; }
    setSaving(false); setModalOpen(false); load();
  };

  const handleDelete = async (m: PaymentMethod) => {
    if (!confirm(`Delete "${m.name}"?`)) return;
    await supabase.from('payment_methods').update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', m.id);
    load();
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Payment Methods</h2><p>Methods available when recording invoice payments. Invoices can split across multiple methods.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Method</button>
        </div>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : rows.length === 0 ? (
            <div className="empty-state"><CreditCard size={34} style={{ opacity: 0.3, marginBottom: 10 }} /><p style={{ fontWeight: 600 }}>No payment methods yet</p></div>
          ) : (
            <table>
              <thead><tr><th>Method</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {rows.map(m => (
                  <tr key={m.id}>
                    <td><strong>{m.name}</strong></td>
                    <td>{m.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(m)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(m)}><Trash2 size={13} /></button>
                    </div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {modalOpen && (
        <Modal title={editId ? 'Edit Payment Method' : 'Add Payment Method'} maxWidth={400} onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-group"><label>Name *</label><input value={name} onChange={e => setName(e.target.value)} placeholder="e.g. PayNow" autoFocus /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={active} onChange={e => setActive(e.target.checked)} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default PaymentMethodsPage;
