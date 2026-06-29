import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store as StoreT, Profile, UserStoreAssignment, isOwnerOrManager, isOwnerOrAdmin, ROLE_LABELS } from '../types';
import { Modal, RoleGate } from '../components/ui';
import { Plus, Pencil, Trash2, Store, RefreshCw, Users2, X } from 'lucide-react';

const StoresPage: React.FC = () => {
  const { profile, assignments: myAssignments } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  const seesAll = isOwnerOrAdmin(profile?.role);

  const [rows, setRows] = useState<StoreT[]>([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState({ name: '', code: '', address: '', is_active: true });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  // Assignment management
  const [assignStore, setAssignStore] = useState<StoreT | null>(null);
  const [allUsers, setAllUsers] = useState<Profile[]>([]);
  const [storeAssignments, setStoreAssignments] = useState<UserStoreAssignment[]>([]);

  const load = useCallback(async () => {
    setLoading(true);
    // RLS automatically limits stores to those the user can access.
    const { data } = await supabase.from('stores').select('*').is('deleted_at', null).order('created_at');
    setRows((data as StoreT[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setForm({ name: '', code: '', address: '', is_active: true }); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (s: StoreT) => { setForm({ name: s.name, code: s.code, address: s.address ?? '', is_active: s.is_active }); setEditId(s.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    if (!form.name.trim() || !form.code.trim()) { setErr('Name and code are required.'); return; }
    setSaving(true); setErr(null);
    const payload = { name: form.name.trim(), code: form.code.trim(), address: form.address.trim() || null, is_active: form.is_active };
    const res = editId
      ? await supabase.from('stores').update(payload).eq('id', editId)
      : await supabase.from('stores').insert(payload);
    if (res.error) { setErr(res.error.message.includes('duplicate') ? 'That code already exists.' : res.error.message); setSaving(false); return; }
    setSaving(false); setModalOpen(false); load();
  };

  const handleDelete = async (s: StoreT) => {
    if (!confirm(`Delete "${s.name}"? It can be restored later.`)) return;
    await supabase.from('stores').update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', s.id);
    load();
  };

  // ── Assignments ──
  const openAssignments = async (s: StoreT) => {
    setAssignStore(s);
    const [{ data: users }, { data: assigns }] = await Promise.all([
      supabase.from('profiles').select('*').is('deleted_at', null).order('full_name'),
      supabase.from('user_store_assignments').select('*').eq('store_id', s.id),
    ]);
    setAllUsers((users as Profile[]) ?? []);
    setStoreAssignments((assigns as UserStoreAssignment[]) ?? []);
  };

  const toggleAssignment = async (userId: string) => {
    if (!assignStore) return;
    const existing = storeAssignments.find(a => a.user_id === userId);
    if (existing) {
      await supabase.from('user_store_assignments').delete().eq('id', existing.id);
    } else {
      await supabase.from('user_store_assignments').insert({ user_id: userId, store_id: assignStore.id });
    }
    // reload assignments
    const { data } = await supabase.from('user_store_assignments').select('*').eq('store_id', assignStore.id);
    setStoreAssignments((data as UserStoreAssignment[]) ?? []);
  };

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Stores</h2>
          <p>{seesAll ? 'All store locations. Assign managers, inventory managers, and staff to each store.' : 'Stores you are assigned to.'}</p>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <RoleGate allow={isOwnerOrManager}>
            <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Store</button>
          </RoleGate>
        </div>
      </div>

      {!seesAll && rows.length > 0 && (
        <div className="alert alert-info"><span>ℹ️</span><div>You're viewing the {rows.length} store{rows.length > 1 ? 's' : ''} you're assigned to.</div></div>
      )}

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : rows.length === 0 ? (
            <div className="empty-state"><Store size={34} style={{ opacity: 0.3, marginBottom: 10 }} /><p style={{ fontWeight: 600 }}>No stores {seesAll ? 'yet' : 'assigned to you'}</p></div>
          ) : (
            <table>
              <thead><tr><th>Store</th><th>Code</th><th>Address</th><th>Status</th>{canManage && <th></th>}</tr></thead>
              <tbody>
                {rows.map(s => (
                  <tr key={s.id}>
                    <td><strong>{s.name}</strong></td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{s.code}</td>
                    <td style={{ color: 'var(--text-secondary)', maxWidth: 280 }}>{s.address || '—'}</td>
                    <td>{s.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    {canManage && <td><div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => openAssignments(s)}><Users2 size={13} /> Staff</button>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(s)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(s)}><Trash2 size={13} /></button>
                    </div></td>}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Add / Edit modal */}
      {modalOpen && (
        <Modal title={editId ? 'Edit Store' : 'Add Store'} onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Name *</label><input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="Energia Rev22 (Adelphi)" autoFocus /></div>
              <div className="form-group"><label>Code *</label><input value={form.code} onChange={e => setForm(f => ({ ...f, code: e.target.value }))} placeholder="STORE-ADELPHI" /></div>
            </div>
            <div className="form-group"><label>Address</label><input value={form.address} onChange={e => setForm(f => ({ ...f, address: e.target.value }))} placeholder="Optional" /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
          </div>
        </Modal>
      )}

      {/* Assignments modal */}
      {assignStore && (
        <Modal title={`Staff — ${assignStore.name}`} maxWidth={460} onClose={() => setAssignStore(null)}
          footer={<button className="btn btn-primary" onClick={() => setAssignStore(null)}>Done</button>}>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 14 }}>
            Assign managers, inventory managers, and staff to this store. Owners and Admins always have access to every store.
          </p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {allUsers.filter(u => !isOwnerOrAdmin(u.role)).map(u => {
              const assigned = storeAssignments.some(a => a.user_id === u.id);
              return (
                <label key={u.id} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '9px 12px', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', cursor: 'pointer', background: assigned ? 'var(--primary-light)' : 'var(--surface)' }}>
                  <input type="checkbox" checked={assigned} onChange={() => toggleAssignment(u.id)} style={{ width: 'auto' }} />
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 13, fontWeight: 600 }}>{u.full_name}</div>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{ROLE_LABELS[u.role]}</div>
                  </div>
                </label>
              );
            })}
            {allUsers.filter(u => !isOwnerOrAdmin(u.role)).length === 0 && (
              <p style={{ fontSize: 13, color: 'var(--text-muted)', textAlign: 'center', padding: 16 }}>No assignable users yet. Create users in Users &amp; Roles first.</p>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
};

export default StoresPage;
