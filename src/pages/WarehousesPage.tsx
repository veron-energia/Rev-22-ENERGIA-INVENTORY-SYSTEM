import React, { useEffect, useState, useCallback } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Warehouse as WarehouseT, isManagerOrAbove } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { Plus, Pencil, Trash2, Warehouse, RefreshCw, RotateCcw } from 'lucide-react';
import { canManagePlaces } from '../lib/permissions/products';

const WarehousesPage: React.FC = () => {
  const { profile } = useAuth();
  // Read allowed for manager+, write for owner/manager
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isManagerOrAbove(profile?.role);
  const canManage = canManagePlaces(profile?.role);

  const [rows, setRows] = useState<WarehouseT[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState({ name: '', code: '', address: '', phone: '', is_active: true });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // A deleted warehouse is hidden, not removed: "Show deleted" lists it with
  // Restore.
  const [showDeleted, setShowDeleted] = useState(false);
  const [pageErr, setPageErr] = useState<string | null>(null);
  const [flash, setFlash] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const q = supabase.from('warehouses').select('*');
    const { data, error } = await (showDeleted ? q.not('deleted_at', 'is', null) : q.is('deleted_at', null)).order('created_at');
    setPageErr(error ? `Couldn't read the warehouses: ${error.message}. Refresh to try again.` : null);
    setRows((data as WarehouseT[]) ?? []);
    setLoading(false);
  }, [showDeleted]);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setForm({ name: '', code: '', address: '', phone: '', is_active: true }); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (w: WarehouseT) => { setForm({ name: w.name, code: w.code, address: w.address ?? '', phone: w.phone ?? '', is_active: w.is_active }); setEditId(w.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    if (!form.name.trim() || !form.code.trim()) { setErr('Name and code are required.'); return; }
    if (!form.address.trim()) { setErr('Address is required (used on printed warehouse invoices).'); return; }
    if (!form.phone.trim()) { setErr('Phone number is required (used on printed warehouse invoices).'); return; }
    setSaving(true); setErr(null);
    const payload = { name: form.name.trim(), code: form.code.trim(), address: form.address.trim() || null, phone: form.phone.trim() || null, is_active: form.is_active };
    const res = editId
      ? await supabase.from('warehouses').update(payload).eq('id', editId)
      : await supabase.from('warehouses').insert(payload);
    // A store or warehouse that still holds stock cannot be switched off: the
    // database says what is left there (the Owner, 9 Oct 2026).
    if (res.error) { setErr(res.error.code === '23505' ? 'That code already exists.' : res.error.message); setSaving(false); return; }
    setSaving(false); setModalOpen(false); load();
  };

  // Delete hides the warehouse. The database refuses while it still holds
  // stock or has stock on the way, and says what (the Owner, 9 Oct 2026).
  const handleDelete = async (w: WarehouseT) => {
    if (!confirm(`Delete "${w.name}"? It will be hidden. You can bring it back with "Show deleted".`)) return;
    setBusyId(w.id); setPageErr(null); setFlash(null);
    const { error } = await supabase.rpc('soft_delete_warehouse', { p_warehouse_id: w.id });
    setBusyId(null);
    if (error) { setPageErr(error.message); return; }
    setFlash(`${w.name} was deleted.`);
    load();
  };

  const handleRestore = async (w: WarehouseT) => {
    setBusyId(w.id); setPageErr(null); setFlash(null);
    const { error } = await supabase.rpc('restore_warehouse', { p_warehouse_id: w.id });
    setBusyId(null);
    if (error) { setPageErr(error.message); return; }
    setFlash(`${w.name} is back and active.`);
    load();
  };

  if (!hasAccess) return <NoAccess />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Warehouses</h2><p>Stock enters the system at a warehouse, then transfers out to stores.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={rows} filename="warehouses" sheetName="Warehouses"
            columns={[
              { header: 'Warehouse', value: (w: any) => w.name },
              { header: 'Code', value: (w: any) => w.code ?? '' },
              { header: 'Status', value: (w: any) => w.is_active ? 'Active' : 'Inactive' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          {canManage && <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Warehouse</button>}
        </div>
      </div>

      <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 13, cursor: 'pointer', marginBottom: 12 }}>
        <input type="checkbox" checked={showDeleted} onChange={e => { setShowDeleted(e.target.checked); setFlash(null); }} style={{ width: 'auto' }} />
        Show deleted
      </label>
      {pageErr && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{pageErr}</div></div>}
      {flash && <div className="alert alert-info" role="status"><span>✓</span><div>{flash}</div></div>}

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : rows.length === 0 ? (
            <div className="empty-state"><Warehouse size={34} style={{ opacity: 0.3, marginBottom: 10 }} /><p style={{ fontWeight: 600 }}>{showDeleted ? 'No deleted warehouses' : 'No warehouses yet'}</p></div>
          ) : (
            <table>
              <thead><tr><th>Warehouse</th><th>Code</th><th>Address</th><th>Phone</th><th>Status</th>{canManage && <th></th>}</tr></thead>
              <tbody>
                {rows.map(w => (
                  <tr key={w.id}>
                    <td><strong>{w.name}</strong></td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{w.code}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{w.address || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)', fontSize: 12.5 }}>{w.phone || '—'}</td>
                    <td>{w.deleted_at ? <span className="badge badge-danger">Deleted</span>
                      : w.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    {canManage && <td>{w.deleted_at
                      ? <button className="btn btn-secondary btn-sm" disabled={busyId === w.id} onClick={() => handleRestore(w)}><RotateCcw size={13} /> Restore</button>
                      : <div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm btn-icon" title="Edit" onClick={() => openEdit(w)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" title="Delete" disabled={busyId === w.id} onClick={() => handleDelete(w)}><Trash2 size={13} /></button>
                    </div>}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {modalOpen && (
        <Modal title={editId ? 'Edit Warehouse' : 'Add Warehouse'} onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Name *</label><input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="Main Warehouse" autoFocus /></div>
              <div className="form-group"><label>Code *</label><input value={form.code} onChange={e => setForm(f => ({ ...f, code: e.target.value }))} placeholder="WH-MAIN" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Address *</label><input value={form.address} onChange={e => setForm(f => ({ ...f, address: e.target.value }))} placeholder="e.g. 1 Coleman St, Singapore" /></div>
              <div className="form-group"><label>Phone *</label><input value={form.phone} onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} placeholder="e.g. 6337 2768" /></div>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
            {editId && !form.is_active && (
              <p style={{ fontSize: 12.5, color: 'var(--text-muted)', margin: 0 }}>
                A warehouse that still holds stock, or has stock on the way, cannot be switched off. Move or correct that stock first.
              </p>)}
          </div>
        </Modal>
      )}
    </div>
  );
};

export default WarehousesPage;
