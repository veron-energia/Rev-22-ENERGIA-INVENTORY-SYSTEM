import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Profile, UserRole, ROLE_LABELS, isOwnerOrManager } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { Pencil, Users2, RefreshCw, UserPlus, Info } from 'lucide-react';

const ROLES: UserRole[] = ['owner', 'admin', 'manager', 'inventory_manager', 'staff'];

const UsersPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isOwnerOrManager(profile?.role)) return <NoAccess message="Only Owners and Managers can manage users and roles." />;

  const [rows, setRows] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [editUser, setEditUser] = useState<Profile | null>(null);
  const [form, setForm] = useState<{ full_name: string; role: UserRole; is_active: boolean }>({ full_name: '', role: 'staff', is_active: true });
  const [saving, setSaving] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.from('profiles').select('*').is('deleted_at', null).order('created_at');
    setRows((data as Profile[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openEdit = (u: Profile) => { setForm({ full_name: u.full_name, role: u.role, is_active: u.is_active }); setEditUser(u); };

  const handleSave = async () => {
    if (!editUser) return;
    setSaving(true);
    await supabase.from('profiles').update({
      full_name: form.full_name.trim(), role: form.role, is_active: form.is_active, updated_at: new Date().toISOString(),
    }).eq('id', editUser.id);
    setSaving(false);
    setEditUser(null);
    load();
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Users &amp; Roles</h2><p>Manage who can access the system and what they're allowed to do.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={() => setHelpOpen(true)}><UserPlus size={16} /> Add User</button>
        </div>
      </div>

      <div className="alert alert-info">
        <Info size={16} style={{ flexShrink: 0 }} />
        <div>New users are created in two steps for security: first an Auth login in the Supabase dashboard, then their role here. Click <strong>Add User</strong> for the exact steps.</div>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : rows.length === 0 ? (
            <div className="empty-state"><Users2 size={34} style={{ opacity: 0.3, marginBottom: 10 }} /><p style={{ fontWeight: 600 }}>No users yet</p></div>
          ) : (
            <table>
              <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {rows.map(u => (
                  <tr key={u.id}>
                    <td><strong>{u.full_name}</strong>{u.id === profile?.id && <span className="badge badge-primary" style={{ marginLeft: 8 }}>You</span>}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{u.email}</td>
                    <td><span className="badge badge-primary">{ROLE_LABELS[u.role]}</span></td>
                    <td>{u.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(u)} disabled={u.id === profile?.id && profile?.role !== 'owner'}>
                        <Pencil size={13} />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Edit role modal */}
      {editUser && (
        <Modal title={`Edit — ${editUser.full_name}`} maxWidth={420} onClose={() => setEditUser(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setEditUser(null)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            <div className="form-group"><label>Full Name</label><input value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} /></div>
            <div className="form-group">
              <label>Role</label>
              <select value={form.role} onChange={e => setForm(f => ({ ...f, role: e.target.value as UserRole }))}>
                {ROLES.map(r => <option key={r} value={r}>{ROLE_LABELS[r]}</option>)}
              </select>
            </div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} />
              <span style={{ fontSize: 13 }}>Active (can sign in and use the system)</span>
            </label>
            <div style={{ fontSize: 12, color: 'var(--text-muted)', background: 'var(--surface-2)', padding: 10, borderRadius: 'var(--radius-sm)' }}>
              Email is managed through the Supabase Auth account and can't be changed here.
            </div>
          </div>
        </Modal>
      )}

      {/* Add user help modal */}
      {helpOpen && (
        <Modal title="Add a New User" maxWidth={520} onClose={() => setHelpOpen(false)}
          footer={<button className="btn btn-primary" onClick={() => setHelpOpen(false)}>Got it</button>}>
          <div style={{ fontSize: 13.5, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
            <p style={{ marginBottom: 14 }}>For security, the frontend can't create login accounts directly. Create a user in two steps:</p>
            <ol style={{ paddingLeft: 20, display: 'flex', flexDirection: 'column', gap: 12 }}>
              <li>
                <strong>Create the login.</strong> In the Supabase dashboard go to <em>Authentication → Users → Add user</em>. Enter their email and a temporary password. Copy the new user's UUID.
              </li>
              <li>
                <strong>Create their profile.</strong> In the Supabase <em>SQL Editor</em>, run:
                <pre style={{ background: 'var(--surface-2)', padding: 12, borderRadius: 'var(--radius-sm)', fontSize: 11.5, overflowX: 'auto', marginTop: 6, fontFamily: 'var(--font-display)' }}>{`insert into public.profiles
  (id, full_name, email, role)
values
  ('PASTE-UUID', 'Their Name',
   'their@email.com', 'staff');`}</pre>
              </li>
              <li>
                <strong>Set their role &amp; store.</strong> They'll appear in this list — edit to adjust role, then assign them to a store on the Stores page (for Manager, Inventory Manager, or Staff).
              </li>
            </ol>
            <p style={{ marginTop: 14, fontSize: 12.5, color: 'var(--text-muted)' }}>
              A future enhancement can automate this with a secure Edge Function, but the two-step flow keeps the service role key safely out of the browser.
            </p>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default UsersPage;
