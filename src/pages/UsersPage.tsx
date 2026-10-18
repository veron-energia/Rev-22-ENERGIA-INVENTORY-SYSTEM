import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Profile, UserRole, ROLE_LABELS, isOwnerOrManager } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { Pencil, Users2, RefreshCw, UserPlus, Info, Search, Send, XCircle } from 'lucide-react';
import { InviteUserForm } from '../components/users/InviteUserForm';
import {
  cancelInvitation, resendInvitation, loadAssignableRoles, loadOrphanInvitations, type OrphanInvitation,
} from '../lib/userInvitations';
import {
  activeSaveRefused, isInvitee, loginChangeHint, loginChangeNote,
  contactRequired, contactsChanged, deactivateQuestion, promotionQuestion,
} from '../lib/staffLogin';
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
  /** An invitation whose login or profile was never made (ADMIN-AUTH-7): no profile to edit. */
  unfinished?: boolean;
}

const STATE_LABEL: Record<AdminRow['state'], string> = {
  active: 'Active',
  inactive: 'Inactive',
  pending_invitation: 'Pending invitation',
  cancelled_invitation: 'Cancelled invitation',
};

// The order roles are listed in. Which of them this administrator may give
// is the server's answer (assignable_roles), as on the invitation form.
const ROLE_ORDER: UserRole[] = ['owner', 'admin', 'manager', 'inventory_manager', 'staff'];

/** An unfinished invitation, shown as a row beside the people. */
const orphanRow = (o: OrphanInvitation): AdminRow => ({
  user_id: `invitation-${o.invitation_id}`, full_name: o.full_name, email: o.email, role: o.role as UserRole,
  is_active: false, invitation_status: 'pending', state: 'pending_invitation',
  work_phone: null, personal_phone: null, personal_email: null, store_ids: [], store_names: [],
  invitation_id: o.invitation_id, invited_at: o.invited_at, invited_by_name: null,
  last_email_attempt_at: null, last_email_status: o.last_email_status, last_email_detail: null,
  resend_count: 0, cancelled_at: null, accepted_at: null, can_manage: true, unfinished: true,
});

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
  // The Edit window's own error, shown inside it.
  const [err, setErr] = useState<string | null>(null);
  // ADMIN-AUTH-6: the page's errors (Resend, Cancel, a failed list), shown on
  // the page. Before, they went into the Edit window's error and showed nowhere.
  const [pageErr, setPageErr] = useState<string | null>(null);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [orphanErr, setOrphanErr] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [adminRows, setAdminRows] = useState<AdminRow[]>([]);
  const [orphans, setOrphans] = useState<AdminRow[]>([]);
  const [assignable, setAssignable] = useState<UserRole[]>([]);
  const [search, setSearch] = useState('');
  const [stateFilter, setStateFilter] = useState<'all' | AdminRow['state']>('all');
  const [notice, setNotice] = useState<string | null>(null);
  const [actingOn, setActingOn] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setLoadErr(null);
    // user_admin_list() knows about invitations; the profiles table alone cannot
    // tell "invited last week, never accepted" from "deactivated last year".
    const [{ data: admin, error: adminError }, { data: profiles, error: profilesError }, unfinished] = await Promise.all([
      supabase.rpc('user_admin_list'),
      supabase.from('profiles').select('*').is('deleted_at', null).order('created_at'),
      loadOrphanInvitations(),
    ]);
    const failed = adminError ?? profilesError;
    if (failed) {
      // Say so, with Retry, rather than an empty page that reads "No users yet".
      setLoadErr(`Could not load users: ${failed.message}`);
      setAdminRows([]); setRows([]);
    } else {
      setAdminRows((admin as AdminRow[]) ?? []);
      setRows((profiles as Profile[]) ?? []);
    }
    if (unfinished.ok) {
      setOrphans(unfinished.rows.map(orphanRow));
      setOrphanErr(null);
    } else {
      setOrphans([]);
      setOrphanErr(`Invitations that were never finished could not be loaded: ${unfinished.message}`);
    }
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    let live = true;
    loadAssignableRoles().then(r => { if (live) setAssignable(r as UserRole[]); });
    return () => { live = false; };
  }, []);

  const openEdit = (u: Profile) => {
    setForm({
      full_name: u.full_name, role: u.role, is_active: u.is_active,
      work_phone: u.work_phone ?? '', personal_phone: u.personal_phone ?? '', personal_email: u.personal_email ?? '',
    });
    setErr(null);
    setEditUser(u);
  };

  // ADMIN-AUTH-12/-15: the roles this administrator may give (Admin is no
  // longer given, Q13), plus the person's own role so the list shows it.
  const roleOptions = useMemo(() => {
    if (!editUser) return [];
    const allowed = new Set<UserRole>(assignable);
    allowed.add(editUser.role);
    return ROLE_ORDER.filter(r => allowed.has(r));
  }, [assignable, editUser]);

  const handleSave = async () => {
    if (!editUser) return;
    setErr(null);
    if (!form.full_name.trim()) { setErr('Full name is required.'); return; }
    // Work/personal phone + personal email are required for Staff, Owner and
    // Manager, and checked when this save changes one of them (ADMIN-AUTH-12).
    // A save that only switches someone off or changes a role is not held up
    // by details that were never on file.
    const contactsTouched = contactsChanged(editUser, form);
    if (contactsTouched && contactRequired(form.role)) {
      if (!form.work_phone.trim()) { setErr('Work phone is required for this role.'); return; }
      if (!form.personal_phone.trim()) { setErr('Personal phone is required for this role.'); return; }
      if (!form.personal_email.trim()) { setErr('Personal email is required for this role.'); return; }
    }
    if (contactsTouched && form.personal_email.trim() && !/^\S+@\S+\.\S+$/.test(form.personal_email.trim())) {
      setErr('Personal email looks invalid.'); return;
    }
    // 412: switching Active signs a login out everywhere and blocks it, or
    // lifts that block. So Active is sent only when this dialog changed it,
    // and only onto the state the dialog was opened with: a save never puts
    // back a value someone else has changed since.
    const activeChanged = form.is_active !== editUser.is_active;
    // Risky changes ask first (ADMIN-AUTH-12).
    const shownName = form.full_name.trim();
    if (activeChanged && !form.is_active && !window.confirm(deactivateQuestion(shownName))) return;
    const promotion = promotionQuestion(shownName, editUser.role, form.role);
    if (promotion && !window.confirm(promotion)) return;
    setSaving(true);
    let update = supabase.from('profiles').update({
      full_name: form.full_name.trim(), role: form.role,
      ...(activeChanged ? { is_active: form.is_active } : {}),
      work_phone: form.work_phone.trim() || null, personal_phone: form.personal_phone.trim() || null,
      personal_email: form.personal_email.trim() || null, updated_at: new Date().toISOString(),
    }).eq('id', editUser.id);
    if (activeChanged) update = update.eq('is_active', editUser.is_active);
    // Ask for the saved row back. The database's rules decide whose profile
    // this login may edit, and a rule that does not allow it answers with no
    // error and no row (ADMIN-AUTH-2: a Manager's edits used to vanish that
    // way, deactivation included). No row back means nothing was saved.
    const { data: saved, error } = await update.select('id, is_active');
    setSaving(false);
    if (error) { setErr(error.message); return; }
    if (!saved || saved.length === 0) {
      // Refused by the rules, or Active changed by someone else meanwhile.
      let changedElsewhere = false;
      if (activeChanged) {
        const { data: current } = await supabase.from('profiles').select('is_active').eq('id', editUser.id).maybeSingle();
        changedElsewhere = !!current && (current as { is_active: boolean }).is_active !== editUser.is_active;
      }
      setErr(activeSaveRefused(editUser.full_name, changedElsewhere));
      if (changedElsewhere) load();
      return;
    }
    // Say what this save did to the login, from the row the database saved.
    const name = form.full_name.trim();
    const note = activeChanged
      ? loginChangeNote(name, editUser.is_active, (saved[0] as { is_active: boolean }).is_active)
      : '';
    setEditUser(null);
    setNotice(note ? `${name}'s profile was saved. ${note}` : `${name}'s profile was saved.`);
    load();
  };

  const doResend = async (row: AdminRow) => {
    if (!row.invitation_id || actingOn) return;
    setActingOn(row.invitation_id); setPageErr(null); setNotice(null);
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
    setPageErr(`Could not resend the invitation to ${row.email}: ${result.message}`);
    load();
  };

  const doCancel = async (row: AdminRow) => {
    if (!row.invitation_id || actingOn) return;
    const reason = window.prompt(
      `Cancel the invitation for ${row.full_name} (${row.email})?\n\n`
      + 'They will not be able to use the link that was emailed, even if they still have it. '
      + 'You can invite them again later.\n\n'
      + 'Reason (recorded):');
    if (reason === null) return;
    setActingOn(row.invitation_id); setPageErr(null); setNotice(null);
    const result = await cancelInvitation(row.invitation_id, reason);
    setActingOn(null);
    if (!result.ok) { setPageErr(`Could not cancel the invitation for ${row.full_name}: ${result.message}`); return; }
    setNotice(`The invitation for ${row.full_name} was cancelled. They are no longer listed; use Invite User to invite them again.`);
    load();
  };

  const allRows = useMemo(() => [...orphans, ...adminRows], [orphans, adminRows]);
  const hasCancelled = allRows.some(r => r.state === 'cancelled_invitation');

  const visibleRows = allRows.filter(r => {
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

  const editProfileOf = (u: AdminRow) => { const p = rows.find(r => r.id === u.user_id); if (p) openEdit(p); };
  const editDisabled = (u: AdminRow) =>
    !!u.unfinished || !u.can_manage || (u.user_id === profile?.id && profile?.role !== 'owner');

  if (!hasAccess) return <NoAccess message="Only Owners and Managers can manage users and roles." />;

  // An invited person becomes active by accepting their invitation; the box
  // is locked for them and the hint says why.
  const activeHint = editUser ? loginChangeHint(editUser.is_active, form.is_active, editUser.invitation_status) : '';

  return (
    <div>
      <div className="page-header">
        <div><h2>Users &amp; Roles</h2><p>Manage who can access the system and what they're allowed to do.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          {/* User-management fields only. There is deliberately no invitation
              link or token column: the server never returns one, and an export
              is the easiest place for a secret to end up on somebody's laptop. */}
          <ExcelExportButton
            rows={allRows.length ? allRows : rows} filename="users" sheetName="Users"
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
          <button className="btn btn-primary" onClick={() => { setNotice(null); setPageErr(null); setInviteOpen(true); }}>
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
      {pageErr && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{pageErr}</div></div>}
      {orphanErr && !loadErr && <div className="alert alert-warning" role="alert"><span>⚠</span><div>{orphanErr}</div></div>}

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
            {/* A cancelled invitee is removed from the list since 429; older ones may remain. */}
            {(hasCancelled || stateFilter === 'cancelled_invitation') &&
              <option value="cancelled_invitation">Cancelled invitation</option>}
          </select>
        </div>
      </div>

      <div className="card users-scope">
        {loadErr ? (
          <div className="empty-state" role="alert">
            <p style={{ fontWeight: 600, color: 'var(--danger)' }}>{loadErr}</p>
            <button className="btn btn-secondary" style={{ marginTop: 10 }} onClick={load}>
              <RefreshCw size={14} aria-hidden="true" /> Retry
            </button>
          </div>
        ) : (
        <>
        <div className="table-wrap users-desktop-only">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : visibleRows.length === 0 ? (
            <div className="empty-state">
              <Users2 size={34} style={{ opacity: 0.3, marginBottom: 10 }} />
              <p style={{ fontWeight: 600 }}>{allRows.length === 0 ? 'No users yet' : 'No user matches'}</p>
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
                          {/* Resend tries to finish it; an address whose login cannot be invited says so then. */}
                          {u.unfinished && <><br /><strong>Not set up yet.</strong> Use Resend to try again.</>}
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
                        {!u.unfinished && (
                          <button className="btn btn-secondary btn-sm btn-icon"
                                  aria-label={`Edit ${u.full_name}`}
                                  onClick={() => editProfileOf(u)}
                                  disabled={editDisabled(u)}>
                            <Pencil size={13} />
                          </button>
                        )}
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
                  {u.unfinished && <> · not set up yet</>}
                  {u.last_email_status === 'accepted_by_provider' && <> · email accepted by the provider</>}
                  {u.last_email_status === 'failed' && <> · email failed</>}
                </div>
              )}
              <div className="users-actions">
                <RowActions row={u} />
                {!u.unfinished && (
                  <button className="btn btn-secondary btn-sm"
                          onClick={() => editProfileOf(u)}
                          disabled={editDisabled(u)}>
                    <Pencil size={13} aria-hidden="true" /> Edit
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
        </>
        )}
      </div>

      {/* Edit role modal. confirmClose: a stray click outside asks before
          throwing away what was typed (ADMIN-AUTH-12). */}
      {editUser && (
        <Modal title={`Edit — ${editUser.full_name}`} maxWidth={480} confirmClose onClose={() => setEditUser(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setEditUser(null)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label htmlFor="edit-name">Full Name</label><input id="edit-name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} /></div>
              <div className="form-group">
                <label htmlFor="edit-role">Role</label>
                <select id="edit-role" value={form.role} disabled={roleOptions.length <= 1}
                        onChange={e => setForm(f => ({ ...f, role: e.target.value as UserRole }))}>
                  {roleOptions.map(r => <option key={r} value={r}>{ROLE_LABELS[r]}</option>)}
                </select>
              </div>
            </div>
            <div className="form-group">
              <label htmlFor="edit-email">Work Email <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— this is the Supabase Auth login address</span></label>
              <input id="edit-email" value={editUser.email} disabled style={{ background: 'var(--surface-2)' }} />
              <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>To change their actual login email, update it in the Supabase dashboard first.</span>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label htmlFor="edit-work-phone">Work Phone {contactRequired(form.role) && '*'}</label><input id="edit-work-phone" value={form.work_phone} onChange={e => setForm(f => ({ ...f, work_phone: e.target.value }))} placeholder="e.g. 8123 4567" /></div>
              <div className="form-group"><label htmlFor="edit-personal-phone">Personal Phone {contactRequired(form.role) && '*'}</label><input id="edit-personal-phone" value={form.personal_phone} onChange={e => setForm(f => ({ ...f, personal_phone: e.target.value }))} placeholder="Optional for this role" /></div>
            </div>
            <div className="form-group"><label htmlFor="edit-personal-email">Personal Email {contactRequired(form.role) && '*'}</label><input id="edit-personal-email" type="email" value={form.personal_email} onChange={e => setForm(f => ({ ...f, personal_email: e.target.value }))} placeholder="Not used for login" /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} disabled={isInvitee(editUser.invitation_status)}
                     onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} />
              <span style={{ fontSize: 13 }}>Active (can sign in and use the system)</span>
            </label>
            {activeHint && (
              <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: -6, display: 'block' }} role="note">
                {activeHint}
              </span>
            )}
            {contactRequired(form.role) && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Staff, Owners and Managers need a work phone, personal phone and personal email. They are checked when you change any of them. The work phone prints on invoices under "Authorised by."</div></div>}
          </div>
        </Modal>
      )}

      {inviteOpen && (
        <Modal title="Invite a User" maxWidth={620} confirmClose onClose={() => setInviteOpen(false)}>
          <InviteUserForm
            onInvited={() => { setNotice('Invitation sent. They appear below as Pending invitation.'); load(); }}
            onSaved={load}
            onClose={() => setInviteOpen(false)} />
        </Modal>
      )}

    </div>
  );
};

export default UsersPage;
