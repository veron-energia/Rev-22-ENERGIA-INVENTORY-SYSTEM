import React, { useEffect, useState, useCallback } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Profile, UserRole, ROLE_LABELS, isOwnerOrManager } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { Pencil, Users2, RefreshCw, UserPlus, Info, Search, Send, XCircle } from 'lucide-react';
import { InviteUserForm } from '../components/users/InviteUserForm';
import { cancelInvitation, resendInvitation } from '../lib/userInvitations';
import '../components/users/users.css';

/** One row of user_admin_list(): the account state and the invitation state, side by side. */
interface AdminRow {
  user_id: string; full_name: string; email: string; role: UserRole;
  is_active: boolean; invitation_status: string | null;
  state: 'active' | 'inactive' | 'pending_invitation' | 'cancelled_invitation';
  work_phone: string | null; personal_phone: string | null; personal_email: string | null;
  store_ids: string[]; store_names: string[];
  invitation_id: string | null; invited_at: string | null; invited_by_name: string | null;
  last_email_attempt_at: string | null; last_email_status: string | null; last_email_detail: string | null;
  resend_count: number; cancelled_at: string | null; accepted_at: string | null;
  can_manage: boolean;
}

const STATE_LABEL: Record<AdminRow['state'], string> = {
  active: 'Active',
  inactive: 'Inactive',
  pending_invitation: 'Pending invitation',
  cancelled_invitation: 'Cancelled invitation',
};

const ROLES: UserRole[] = ['owner', 'admin', 'manager', 'inventory_manager', 'staff'];

const UsersPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isOwnerOrManager(profile?.role);
  const [rows, setRows] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [editUser, setEditUser] = useState<Profile | null>(null);
  const [form, setForm] = useState<{ full_name: string; role: UserRole; is_active: boolean; work_phone: string; personal_phone: string; personal_email: string }>({
    full_name: '', role: 'staff', is_active: true, work_phone: '', personal_phone: '', personal_email: '',
  });
  const [err, setErr] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [adminRows, setAdminRows] = useState<AdminRow[]>([]);
  const [search, setSearch] = useState('');
  const [stateFilter, setStateFilter] = useState<'all' | AdminRow['state']>('all');
  const [notice, setNotice] = useState<string | null>(null);
  const [actingOn, setActingOn] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    // user_admin_list() knows about invitations; the profiles table alone cannot
    // tell "invited last week, never accepted" from "deactivated last year".
    const [{ data: admin, error: adminError }, { data: profiles }] = await Promise.all([
      supabase.rpc('user_admin_list'),
      supabase.from('profiles').select('*').is('deleted_at', null).order('created_at'),
    ]);
    setRows((profiles as Profile[]) ?? []);
    if (adminError) {
      // The migration may not be applied yet. Say so rather than showing an
      // empty page that looks like "no users".
      setErr(`Invitation details are unavailable: ${adminError.message}`);
      setAdminRows([]);
    } else {
      setAdminRows((admin as AdminRow[]) ?? []);
    }
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

  const doResend = async (row: AdminRow) => {
    if (!row.invitation_id || actingOn) return;
    setActingOn(row.invitation_id); setErr(null); setNotice(null);
    const result = await resendInvitation(row.invitation_id);
    setActingOn(null);
    if (result.kind === 'invited') {
      setNotice(result.delivery === 'accepted_by_provider'
        ? `The invitation to ${row.email} was accepted for delivery. That is the provider accepting `
          + 'the request, not confirmation it reached their inbox.'
        : `The invitation to ${row.email} could not be sent. ${result.detail ?? ''}`);
      load();
      return;
    }
    setErr(result.message);
  };

  const doCancel = async (row: AdminRow) => {
    if (!row.invitation_id || actingOn) return;
    const reason = window.prompt(
      `Cancel the invitation for ${row.full_name} (${row.email})?\n\n`
      + 'They will not be able to use the link that was emailed, even if they still have it.\n\n'
      + 'Reason (recorded):');
    if (reason === null) return;
    setActingOn(row.invitation_id); setErr(null); setNotice(null);
    const result = await cancelInvitation(row.invitation_id, reason);
    setActingOn(null);
    if (!result.ok) { setErr(result.message); return; }
    setNotice(`The invitation for ${row.full_name} was cancelled.`);
    load();
  };

  const visibleRows = adminRows.filter(r => {
    if (stateFilter !== 'all' && r.state !== stateFilter) return false;
    const q = search.trim().toLowerCase();
    if (!q) return true;
    return r.full_name.toLowerCase().includes(q)
        || (r.email ?? '').toLowerCase().includes(q)
        || (r.store_names ?? []).some(n => n.toLowerCase().includes(q));
  });

  const when = (iso: string | null) =>
    iso ? new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '—';

  const StateBadge: React.FC<{ row: AdminRow }> = ({ row }) => {
    if (row.state === 'pending_invitation') return <span className="users-chip users-chip-pending">Pending invitation</span>;
    if (row.state === 'cancelled_invitation') return <span className="users-chip users-chip-cancelled">Cancelled invitation</span>;
    if (row.state === 'active') return <span className="badge badge-success">Active</span>;
    return <span className="badge badge-muted">Inactive</span>;
  };

  const RowActions: React.FC<{ row: AdminRow }> = ({ row }) => {
    if (!row.can_manage) return <span className="users-hint">Not yours to manage</span>;
    if (row.state !== 'pending_invitation') return null;
    return (
      <span style={{ display: 'inline-flex', gap: 6 }}>
        <button className="btn btn-secondary btn-sm" disabled={actingOn === row.invitation_id}
                onClick={() => void doResend(row)}>
          <Send size={13} aria-hidden="true" /> {actingOn === row.invitation_id ? 'Working…' : 'Resend'}
        </button>
        <button className="btn btn-secondary btn-sm" disabled={actingOn === row.invitation_id}
                onClick={() => void doCancel(row)}>
          <XCircle size={13} aria-hidden="true" /> Cancel
        </button>
      </span>
    );
  };

  if (!hasAccess) return <NoAccess message="Only Owners and Managers can manage users and roles." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Users &amp; Roles</h2><p>Manage who can access the system and what they're allowed to do.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          {/* User-management fields only. There is deliberately no invitation
              link or token column: the server never returns one, and an export
              is the easiest place for a secret to end up on somebody's laptop. */}
          <ExcelExportButton
            rows={adminRows.length ? adminRows : rows} filename="users" sheetName="Users"
            columns={[
              { header: 'Name', value: (u: any) => u.full_name ?? '' },
              { header: 'Login email', value: (u: any) => u.email ?? '' },
              { header: 'Role', value: (u: any) => ROLE_LABELS[u.role as UserRole] ?? u.role ?? '' },
              { header: 'Status', value: (u: any) =>
                  u.state ? STATE_LABEL[u.state as AdminRow['state']] : (u.is_active ? 'Active' : 'Inactive') },
              { header: 'Stores', value: (u: any) => (u.store_names ?? []).join(', ') },
              { header: 'Work phone', value: (u: any) => u.work_phone ?? '' },
              { header: 'Invited on', value: (u: any) => u.invited_at ? new Date(u.invited_at).toLocaleDateString('en-GB') : '' },
              { header: 'Invited by', value: (u: any) => u.invited_by_name ?? '' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={() => { setNotice(null); setInviteOpen(true); }}>
            <UserPlus size={16} /> Invite User
          </button>
        </div>
      </div>

      <div className="alert alert-info">
        <Info size={16} style={{ flexShrink: 0 }} />
        <div>
          Invite someone by email and they set their own password from the link. You never see or
          set it. They stay <strong>Pending invitation</strong> — with no access at all — until they
          have finished setting it up.
        </div>
      </div>

      {notice && <div className="alert alert-success" role="status"><span>✓</span><div>{notice}</div></div>}

      <div className="users-scope" style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'flex-end', margin: '12px 0' }}>
        <div className="form-group" style={{ marginBottom: 0, flex: '1 1 220px', minWidth: 0 }}>
          <label htmlFor="user-search">Search</label>
          <div className="users-search">
            <Search size={14} aria-hidden="true" />
            <input id="user-search" type="search" value={search} placeholder="Name, email or store"
                   onChange={e => setSearch(e.target.value)} />
          </div>
        </div>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label htmlFor="user-state">Status</label>
          <select id="user-state" value={stateFilter} onChange={e => setStateFilter(e.target.value as never)}>
            <option value="all">All</option>
            <option value="active">Active</option>
            <option value="pending_invitation">Pending invitation</option>
            <option value="inactive">Inactive</option>
            <option value="cancelled_invitation">Cancelled invitation</option>
          </select>
        </div>
      </div>

      <div className="card users-scope">
        <div className="table-wrap users-desktop-only">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : visibleRows.length === 0 ? (
            <div className="empty-state">
              <Users2 size={34} style={{ opacity: 0.3, marginBottom: 10 }} />
              <p style={{ fontWeight: 600 }}>{adminRows.length === 0 ? 'No users yet' : 'No user matches'}</p>
            </div>
          ) : (
            <table>
              <thead><tr>
                <th scope="col">Name</th><th scope="col">Login email</th><th scope="col">Role</th>
                <th scope="col">Stores</th><th scope="col">Status</th><th scope="col">Invitation</th>
                <th scope="col"></th>
              </tr></thead>
              <tbody>
                {visibleRows.map(u => (
                  <tr key={u.user_id}>
                    <td>
                      <strong>{u.full_name}</strong>
                      {u.user_id === profile?.id && <span className="badge badge-primary" style={{ marginLeft: 8 }}>You</span>}
                    </td>
                    <td style={{ color: 'var(--text-secondary)' }}>{u.email}</td>
                    <td><span className="badge badge-primary">{ROLE_LABELS[u.role]}</span></td>
                    <td style={{ fontSize: 12 }}>
                      {u.store_names.length ? u.store_names.join(', ') : <span className="users-hint">None</span>}
                    </td>
                    <td><StateBadge row={u} /></td>
                    <td style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                      {u.state === 'pending_invitation' || u.state === 'cancelled_invitation' ? (
                        <>
                          Invited {when(u.invited_at)}
                          {u.invited_by_name && <> by {u.invited_by_name}</>}
                          {u.last_email_attempt_at && (
                            <><br />Last email {when(u.last_email_attempt_at)} —{' '}
                              {u.last_email_status === 'accepted_by_provider'
                                ? 'accepted by the provider'
                                : u.last_email_status === 'not_attempted' ? 'not attempted' : 'failed'}
                            </>
                          )}
                          {u.resend_count > 0 && <><br />Resent {u.resend_count}×</>}
                          {u.cancelled_at && <><br />Cancelled {when(u.cancelled_at)}</>}
                        </>
                      ) : u.accepted_at ? <>Accepted {when(u.accepted_at)}</> : '—'}
                    </td>
                    <td>
                      <span style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}>
                        <RowActions row={u} />
                        <button className="btn btn-secondary btn-sm btn-icon"
                                aria-label={`Edit ${u.full_name}`}
                                onClick={() => { const p = rows.find(r => r.id === u.user_id); if (p) openEdit(p); }}
                                disabled={!u.can_manage || (u.user_id === profile?.id && profile?.role !== 'owner')}>
                          <Pencil size={13} />
                        </button>
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* One card per person once the table is too wide for the screen. */}
        <div className="users-cards" style={{ padding: 12 }}>
          {visibleRows.map(u => (
            <div className="users-card" key={u.user_id}>
              <div className="users-card-name">{u.full_name}</div>
              <div className="users-hint">{u.email}</div>
              <div className="users-card-stats">
                <span className="users-chip">{ROLE_LABELS[u.role]}</span>
                <StateBadge row={u} />
                {u.store_names.slice(0, 3).map(n => <span className="users-chip" key={n}>{n}</span>)}
              </div>
              {(u.state === 'pending_invitation' || u.state === 'cancelled_invitation') && (
                <div className="users-hint" style={{ marginTop: 6 }}>
                  Invited {when(u.invited_at)}{u.invited_by_name && <> by {u.invited_by_name}</>}
                  {u.last_email_status === 'accepted_by_provider' && <> · email accepted by the provider</>}
                  {u.last_email_status === 'failed' && <> · email failed</>}
                </div>
              )}
              <div className="users-actions">
                <RowActions row={u} />
                <button className="btn btn-secondary btn-sm"
                        onClick={() => { const p = rows.find(r => r.id === u.user_id); if (p) openEdit(p); }}
                        disabled={!u.can_manage || (u.user_id === profile?.id && profile?.role !== 'owner')}>
                  <Pencil size={13} aria-hidden="true" /> Edit
                </button>
              </div>
            </div>
          ))}
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

      {inviteOpen && (
        <Modal title="Invite a User" maxWidth={620} onClose={() => setInviteOpen(false)}>
          <InviteUserForm
            onInvited={() => { setNotice('Invitation sent. They appear below as Pending invitation.'); load(); }}
            onClose={() => setInviteOpen(false)} />
        </Modal>
      )}

    </div>
  );
};

export default UsersPage;
