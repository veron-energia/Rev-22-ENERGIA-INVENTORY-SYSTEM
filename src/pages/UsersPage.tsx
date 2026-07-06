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
  const [form, setForm] = useState<{ full_name: string; role: UserRole; is_active: boolean; work_phone: string; personal_phone: string; personal_email: string }>({
    full_name: '', role: 'staff', is_active: true, work_phone: '', personal_phone: '', personal_email: '',
  });
  const [err, setErr] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.from('profiles').select('*').is('deleted_at', null).order('created_at');
    setRows((data as Profile[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openEdit = (u: Profile) => {
    setForm({
      full_name: u.full_name, role: u.role, is_active: u.is_active,
      work_phone: u.work_phone ?? '', personal_phone: u.personal_phone ?? '', personal_email: u.personal_email ?? '',
    });
    setErr(null);
    setEditUser(u);
  };

  // Work/personal phone + personal email are required for Staff, Owner, and
  // Manager (per spec). Admin and Inventory Manager are not required yet.
  const contactRequired = (r: UserRole) => r === 'staff' || r === 'owner' || r === 'manager';

  const handleSave = async () => {
    if (!editUser) return;
    setErr(null);
    if (!form.full_name.trim()) { setErr('Full name is required.'); return; }
    if (contactRequired(form.role)) {
      if (!form.work_phone.trim()) { setErr('Work phone is required for this role.'); return; }
      if (!form.personal_phone.trim()) { setErr('Personal phone is required for this role.'); return; }
      if (!form.personal_email.trim()) { setErr('Personal email is required for this role.'); return; }
      if (!/^\S+@\S+\.\S+$/.test(form.personal_email.trim())) { setErr('Personal email looks invalid.'); return; }
    }
    setSaving(true);
    const { error } = await supabase.from('profiles').update({
      full_name: form.full_name.trim(), role: form.role, is_active: form.is_active,
      work_phone: form.work_phone.trim() || null, personal_phone: form.personal_phone.trim() || null,
      personal_email: form.personal_email.trim() || null, updated_at: new Date().toISOString(),
    }).eq('id', editUser.id);
    setSaving(false);
    if (error) { setErr(error.message); return; }
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
              <thead><tr><th>Name</th><th>Work Email</th><th>Work Phone</th><th>Role</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {rows.map(u => (
                  <tr key={u.id}>
                    <td><strong>{u.full_name}</strong>{u.id === profile?.id && <span className="badge badge-primary" style={{ marginLeft: 8 }}>You</span>}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{u.email}</td>
                    <td style={{ color: 'var(--text-secondary)', fontSize: 12.5 }}>{u.work_phone || '—'}</td>
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
        <Modal title={`Edit — ${editUser.full_name}`} maxWidth={480} onClose={() => setEditUser(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setEditUser(null)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Full Name</label><input value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} /></div>
              <div className="form-group">
                <label>Role</label>
                <select value={form.role} onChange={e => setForm(f => ({ ...f, role: e.target.value as UserRole }))}>
                  {ROLES.map(r => <option key={r} value={r}>{ROLE_LABELS[r]}</option>)}
                </select>
              </div>
            </div>
            <div className="form-group">
              <label>Work Email <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— this is the Supabase Auth login address</span></label>
              <input value={editUser.email} disabled style={{ background: 'var(--surface-2)' }} />
              <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>To change their actual login email, update it in the Supabase dashboard first.</span>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Work Phone {contactRequired(form.role) && '*'}</label><input value={form.work_phone} onChange={e => setForm(f => ({ ...f, work_phone: e.target.value }))} placeholder="e.g. 8123 4567" /></div>
              <div className="form-group"><label>Personal Phone {contactRequired(form.role) && '*'}</label><input value={form.personal_phone} onChange={e => setForm(f => ({ ...f, personal_phone: e.target.value }))} placeholder="Optional for this role" /></div>
            </div>
            <div className="form-group"><label>Personal Email {contactRequired(form.role) && '*'}</label><input type="email" value={form.personal_email} onChange={e => setForm(f => ({ ...f, personal_email: e.target.value }))} placeholder="Not used for login" /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} />
              <span style={{ fontSize: 13 }}>Active (can sign in and use the system)</span>
            </label>
            {contactRequired(form.role) && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Work phone, personal phone, and personal email are required for Staff, Owner, and Manager. Work phone appears on printed invoices under "Authorised by."</div></div>}
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
