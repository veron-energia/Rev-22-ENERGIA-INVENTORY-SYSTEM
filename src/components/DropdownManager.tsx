import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { Brand, Category, Supplier } from '../types';
import { Modal } from './ui';
import { Pencil, Trash2, RotateCcw } from 'lucide-react';

type Kind = 'brands' | 'categories' | 'suppliers';

// Owner/Manager-only management of the product dropdown lists. Add / edit /
// deactivate / soft-delete / restore. Hard delete is blocked server-side when
// the record is still used by a product.
const DropdownManager: React.FC<{ kind: Kind; onClose?: () => void; onChanged: () => void; embedded?: boolean }> = ({ kind, onClose, onChanged, embedded }) => {
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<any>({});
  const [err, setErr] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const label = kind === 'brands' ? 'Brand' : kind === 'categories' ? 'Category' : 'Supplier';

  const load = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.from(kind).select('*').order('name');
    setRows((data as any[]) ?? []);
    setLoading(false);
  }, [kind]);
  useEffect(() => { load(); }, [load]);

  const blank = () => kind === 'suppliers'
    ? { name: '', contact_person: '', phone: '', email: '', address: '', notes: '', is_active: true }
    : { name: '', is_active: true };

  const startAdd = () => { setForm(blank()); setEditId(null); setErr(null); };
  const startEdit = (r: any) => {
    setForm(kind === 'suppliers'
      ? { name: r.name, contact_person: r.contact_person ?? '', phone: r.phone ?? '', email: r.email ?? '', address: r.address ?? '', notes: r.notes ?? '', is_active: r.is_active }
      : { name: r.name, is_active: r.is_active });
    setEditId(r.id); setErr(null);
  };

  const save = async () => {
    if (!form.name?.trim()) { setErr('Name is required.'); return; }
    setSaving(true); setErr(null);
    const payload: any = kind === 'suppliers'
      ? { name: form.name.trim(), contact_person: form.contact_person?.trim() || null, phone: form.phone?.trim() || null,
          email: form.email?.trim() || null, address: form.address?.trim() || null, notes: form.notes?.trim() || null, is_active: form.is_active }
      : { name: form.name.trim(), is_active: form.is_active };
    const res = editId
      ? await supabase.from(kind).update({ ...payload, updated_at: new Date().toISOString() }).eq('id', editId)
      : await supabase.from(kind).insert(payload);
    setSaving(false);
    if (res.error) { setErr(res.error.message); return; }
    setForm(blank()); setEditId(null); load(); onChanged();
  };

  const softDelete = async (r: any) => {
    if (!confirm(`Soft-delete ${label.toLowerCase()} "${r.name}"? It stays on historical products but can't be picked for new ones.`)) return;
    const { error } = await supabase.from(kind).update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', r.id);
    if (error) alert(error.message); else { load(); onChanged(); }
  };
  const restore = async (r: any) => {
    const { error } = await supabase.from(kind).update({ deleted_at: null, is_active: true }).eq('id', r.id);
    if (error) alert(error.message); else { load(); onChanged(); }
  };
  const toggleActive = async (r: any) => {
    const { error } = await supabase.from(kind).update({ is_active: !r.is_active, updated_at: new Date().toISOString() }).eq('id', r.id);
    if (error) alert(error.message); else { load(); onChanged(); }
  };

  const inner = (
      <div className="form-grid">
        {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}

        {/* Add / edit form */}
        <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 12 }}>
          <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 8 }}>{editId ? `Edit ${label}` : `Add ${label}`}</div>
          <div className={kind === 'suppliers' ? 'form-grid' : ''}>
            <div className="form-group" style={{ marginBottom: kind === 'suppliers' ? undefined : 0 }}>
              <label>Name *</label>
              <input value={form.name ?? ''} onChange={e => setForm((f: any) => ({ ...f, name: e.target.value }))} autoFocus />
            </div>
            {kind === 'suppliers' && (
              <>
                <div className="form-grid-2">
                  <div className="form-group"><label>Contact Person</label><input value={form.contact_person ?? ''} onChange={e => setForm((f: any) => ({ ...f, contact_person: e.target.value }))} /></div>
                  <div className="form-group"><label>Phone</label><input value={form.phone ?? ''} onChange={e => setForm((f: any) => ({ ...f, phone: e.target.value }))} /></div>
                </div>
                <div className="form-grid-2">
                  <div className="form-group"><label>Email</label><input value={form.email ?? ''} onChange={e => setForm((f: any) => ({ ...f, email: e.target.value }))} /></div>
                  <div className="form-group"><label>Address</label><input value={form.address ?? ''} onChange={e => setForm((f: any) => ({ ...f, address: e.target.value }))} /></div>
                </div>
                <div className="form-group"><label>Notes</label><input value={form.notes ?? ''} onChange={e => setForm((f: any) => ({ ...f, notes: e.target.value }))} /></div>
              </>
            )}
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
            <button className="btn btn-primary btn-sm" onClick={save} disabled={saving}>{saving ? 'Saving…' : editId ? 'Save' : 'Add'}</button>
            {editId && <button className="btn btn-secondary btn-sm" onClick={startAdd}>Cancel edit</button>}
          </div>
        </div>

        {/* List */}
        <div className="table-wrap" style={{ maxHeight: 300, overflowY: 'auto' }}>
          <table>
            <thead><tr><th>Name</th>{kind === 'suppliers' && <th>Contact</th>}<th>Status</th><th></th></tr></thead>
            <tbody>
              {loading ? <tr><td colSpan={4} style={{ textAlign: 'center', padding: 16, color: 'var(--text-muted)' }}>Loading…</td></tr>
                : rows.length === 0 ? <tr><td colSpan={4} style={{ textAlign: 'center', padding: 16, color: 'var(--text-muted)' }}>None yet</td></tr>
                : rows.map(r => (
                  <tr key={r.id} style={{ opacity: r.deleted_at ? 0.5 : 1 }}>
                    <td><strong>{r.name}</strong></td>
                    {kind === 'suppliers' && <td style={{ fontSize: 12 }}>{r.contact_person || '—'}{r.phone ? ` · ${r.phone}` : ''}</td>}
                    <td>
                      {r.deleted_at ? <span className="badge badge-danger">Deleted</span>
                        : r.is_active ? <span className="badge badge-success">Active</span>
                        : <span className="badge badge-muted">Inactive</span>}
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: 4 }}>
                        {r.deleted_at ? (
                          <button className="btn btn-secondary btn-sm" onClick={() => restore(r)}><RotateCcw size={12} /> Restore</button>
                        ) : (
                          <>
                            <button className="btn btn-secondary btn-sm btn-icon" onClick={() => startEdit(r)}><Pencil size={12} /></button>
                            <button className="btn btn-secondary btn-sm" onClick={() => toggleActive(r)}>{r.is_active ? 'Deactivate' : 'Activate'}</button>
                            <button className="btn btn-danger btn-sm btn-icon" onClick={() => softDelete(r)}><Trash2 size={12} /></button>
                          </>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Inactive items stay on existing products but can't be chosen for new ones. A {label.toLowerCase()} still used by a product can't be permanently removed — deactivate it instead.</div>
      </div>
  );

  if (embedded) return inner;
  return (
    <Modal title={`Manage ${label}s`} maxWidth={kind === 'suppliers' ? 620 : 460} onClose={onClose ?? (() => {})}
      footer={<button className="btn btn-secondary" onClick={onClose}>Close</button>}>
      {inner}
    </Modal>
  );
};

export default DropdownManager;
