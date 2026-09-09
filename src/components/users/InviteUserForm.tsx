import React, { useEffect, useMemo, useRef, useState } from 'react';
import { AlertTriangle, CheckCircle2, Search, UserPlus } from 'lucide-react';
import { supabase } from '../../lib/supabase';
import { ROLE_LABELS, UserRole } from '../../types';
import {
  inviteUser, loadAssignableRoles, loadAssignableStoreIds, newRequestId,
  type InviteOutcome, type InviteRole,
} from '../../lib/userInvitations';
import './users.css';

/**
 * Inviting an internal user.
 *
 * The administrator never sets or sees a password. They describe the person and
 * the access; the recipient chooses their own password from a link.
 *
 * Every restriction shown here is also enforced on the server. The role list is
 * what the database says this administrator may assign, not a list filtered in
 * the browser — hiding an option is a courtesy, not a control.
 */

interface Store { id: string; name: string }

const CONTACTS_REQUIRED: UserRole[] = ['staff', 'owner', 'manager'];

export const InviteUserForm: React.FC<{ onInvited: () => void; onClose: () => void }> =
  ({ onInvited, onClose }) => {
  const [roles, setRoles] = useState<InviteRole[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [storeSearch, setStoreSearch] = useState('');
  const [loadingOptions, setLoadingOptions] = useState(true);

  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<InviteRole | ''>('');
  const [workPhone, setWorkPhone] = useState('');
  const [personalPhone, setPersonalPhone] = useState('');
  const [personalEmail, setPersonalEmail] = useState('');
  const [storeIds, setStoreIds] = useState<string[]>([]);

  const [busy, setBusy] = useState(false);
  const [fieldError, setFieldError] = useState<{ field: string; message: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<InviteOutcome | null>(null);

  // One request id per attempt. It is kept across a failure so a retry of the
  // SAME invitation cannot create a second person, and replaced only once an
  // invitation has actually been made.
  const requestId = useRef(newRequestId());

  useEffect(() => {
    let live = true;
    (async () => {
      const [assignable, storeIdsAllowed, { data }] = await Promise.all([
        loadAssignableRoles(),
        loadAssignableStoreIds(),
        supabase.from('stores').select('id, name').order('name'),
      ]);
      if (!live) return;
      setRoles(assignable);
      const all = (data as Store[] | null) ?? [];
      // Only stores this administrator may hand out. The server checks again.
      setStores(all.filter(s => storeIdsAllowed.includes(s.id)));
      setLoadingOptions(false);
    })();
    return () => { live = false; };
  }, []);

  const contactsRequired = role !== '' && CONTACTS_REQUIRED.includes(role as UserRole);
  const visibleStores = useMemo(() => {
    const q = storeSearch.trim().toLowerCase();
    return q ? stores.filter(s => s.name.toLowerCase().includes(q)) : stores;
  }, [stores, storeSearch]);

  const errFor = (field: string) => fieldError?.field === field ? fieldError.message : null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (busy) return;                       // a second click during a request does nothing
    setError(null); setFieldError(null);

    if (!fullName.trim()) return setFieldError({ field: 'full_name', message: 'Enter their full name.' });
    if (!email.trim()) return setFieldError({ field: 'email', message: 'Enter the login email address.' });
    if (!role) return setFieldError({ field: 'role', message: 'Choose a role.' });
    if (contactsRequired) {
      if (!workPhone.trim()) return setFieldError({ field: 'work_phone', message: 'Work phone is required for this role.' });
      if (!personalPhone.trim()) return setFieldError({ field: 'personal_phone', message: 'Personal phone is required for this role.' });
      if (!personalEmail.trim()) return setFieldError({ field: 'personal_email', message: 'Personal email is required for this role.' });
    }

    setBusy(true);
    const outcome = await inviteUser({
      fullName: fullName.trim(), email: email.trim(), role: role as InviteRole,
      workPhone: workPhone.trim(), personalPhone: personalPhone.trim(),
      personalEmail: personalEmail.trim(), storeIds,
    }, requestId.current);
    setBusy(false);

    // Nothing is cleared on failure: everything typed is still here to correct.
    if (outcome.kind === 'field_error') return setFieldError({ field: outcome.field, message: outcome.message });
    if (outcome.kind === 'forbidden' || outcome.kind === 'email_in_use'
        || outcome.kind === 'already_invited' || outcome.kind === 'failed'
        || outcome.kind === 'rate_limited') {
      return setError(outcome.message);
    }

    requestId.current = newRequestId();     // this invitation is made; a new one needs a new id
    setResult(outcome);
    onInvited();
  };

  if (result && result.kind === 'invited') {
    return (
      <div className="users-scope">
        <div className="alert alert-success" role="status">
          <CheckCircle2 size={15} aria-hidden="true" />
          <div>
            <strong>{fullName.trim()} has been invited.</strong>{' '}
            They will appear as <em>Pending invitation</em> until they set their own password.
          </div>
        </div>
        {result.delivery === 'accepted_by_provider' ? (
          <p className="users-hint">
            The invitation email was accepted for delivery to <strong>{result.email}</strong>.
            That is the email provider accepting the request — it is not confirmation that it
            reached their inbox. If they do not receive it, use <em>Resend</em>.
          </p>
        ) : (
          <div className="alert alert-warning" role="status">
            <AlertTriangle size={15} aria-hidden="true" />
            <div>
              <strong>The account was created but the email did not go out.</strong>{' '}
              {result.detail}{' '}Their invitation is saved — use <em>Resend</em> from the list.
              Do not create them again.
            </div>
          </div>
        )}
        <button className="btn btn-primary" style={{ marginTop: 12 }} onClick={onClose}>Done</button>
      </div>
    );
  }

  return (
    <form className="users-scope" onSubmit={submit} noValidate>
      {loadingOptions && <p className="users-hint">Loading…</p>}

      {!loadingOptions && roles.length === 0 && (
        <div className="alert alert-warning" role="status">
          <AlertTriangle size={15} aria-hidden="true" />
          <div>Your role cannot create user accounts. Ask an Owner to invite this person.</div>
        </div>
      )}

      {error && (
        <div className="alert alert-danger" role="alert">
          <AlertTriangle size={15} aria-hidden="true" /><div>{error}</div>
        </div>
      )}

      <div className="users-form-grid">
        <div className="form-group">
          <label htmlFor="inv-name">Full name *</label>
          <input id="inv-name" value={fullName} onChange={e => setFullName(e.target.value)}
                 aria-invalid={!!errFor('full_name')} aria-describedby={errFor('full_name') ? 'err-name' : undefined} />
          {errFor('full_name') && <p id="err-name" className="users-field-error">{errFor('full_name')}</p>}
        </div>

        <div className="form-group">
          <label htmlFor="inv-role">Role *</label>
          <select id="inv-role" value={role} onChange={e => setRole(e.target.value as InviteRole)}
                  aria-invalid={!!errFor('role')}>
            <option value="">Choose a role…</option>
            {roles.map(r => <option key={r} value={r}>{ROLE_LABELS[r as UserRole]}</option>)}
          </select>
          {errFor('role') && <p className="users-field-error">{errFor('role')}</p>}
          {roles.length > 0 && roles.length < 5 && (
            <p className="users-hint">These are the roles your own role can assign.</p>
          )}
        </div>
      </div>

      <div className="form-group">
        <label htmlFor="inv-email">Login email *</label>
        <input id="inv-email" type="email" value={email} onChange={e => setEmail(e.target.value)}
               autoComplete="off" aria-invalid={!!errFor('email')}
               aria-describedby="inv-email-hint" />
        <p id="inv-email-hint" className="users-hint">
          <strong>The invitation goes to this address</strong>, and it is the address they will
          sign in with. It is not their personal contact email — those are separate fields below,
          and neither is copied into the other.
        </p>
        {errFor('email') && <p className="users-field-error">{errFor('email')}</p>}
      </div>

      <fieldset className="users-fieldset">
        <legend>Contact details {contactsRequired ? '(required for this role)' : '(optional for this role)'}</legend>
        <div className="users-form-grid">
          <div className="form-group">
            <label htmlFor="inv-work">Work phone {contactsRequired && '*'}</label>
            <input id="inv-work" type="tel" inputMode="tel" value={workPhone}
                   onChange={e => setWorkPhone(e.target.value)} placeholder="e.g. 8123 4567"
                   aria-invalid={!!errFor('work_phone')} />
            {errFor('work_phone') && <p className="users-field-error">{errFor('work_phone')}</p>}
          </div>
          <div className="form-group">
            <label htmlFor="inv-personal">Personal phone {contactsRequired && '*'}</label>
            <input id="inv-personal" type="tel" inputMode="tel" value={personalPhone}
                   onChange={e => setPersonalPhone(e.target.value)}
                   aria-invalid={!!errFor('personal_phone')} />
            {errFor('personal_phone') && <p className="users-field-error">{errFor('personal_phone')}</p>}
          </div>
        </div>
        <div className="form-group">
          <label htmlFor="inv-pemail">Personal email {contactsRequired && '*'}</label>
          <input id="inv-pemail" type="email" value={personalEmail}
                 onChange={e => setPersonalEmail(e.target.value)} autoComplete="off"
                 aria-invalid={!!errFor('personal_email')} />
          <p className="users-hint">A contact address for records. No invitation is sent here.</p>
          {errFor('personal_email') && <p className="users-field-error">{errFor('personal_email')}</p>}
        </div>
      </fieldset>

      <fieldset className="users-fieldset">
        <legend>Stores</legend>
        {stores.length === 0 ? (
          <p className="users-hint">You have no stores to assign.</p>
        ) : (
          <>
            <div className="form-group">
              <label htmlFor="inv-store-search">Search stores</label>
              <div className="users-search">
                <Search size={14} aria-hidden="true" />
                <input id="inv-store-search" type="search" value={storeSearch}
                       onChange={e => setStoreSearch(e.target.value)} placeholder="Filter by name" />
              </div>
            </div>
            <div className="users-store-list" role="group" aria-label="Store assignment">
              {visibleStores.map(s => (
                <label key={s.id} className="users-inline">
                  <input type="checkbox" checked={storeIds.includes(s.id)}
                         onChange={e => setStoreIds(ids =>
                           e.target.checked ? [...ids, s.id] : ids.filter(x => x !== s.id))} />
                  <span>{s.name}</span>
                </label>
              ))}
              {visibleStores.length === 0 && <p className="users-hint">No store matches that search.</p>}
            </div>
            <p className="users-hint" aria-live="polite">
              {storeIds.length} store{storeIds.length === 1 ? '' : 's'} selected
            </p>
            {errFor('store_ids') && <p className="users-field-error">{errFor('store_ids')}</p>}
          </>
        )}
      </fieldset>

      <div className="users-actions">
        <button type="button" className="btn btn-secondary" onClick={onClose} disabled={busy}>Cancel</button>
        <button type="submit" className="btn btn-primary" disabled={busy || roles.length === 0}>
          <UserPlus size={15} aria-hidden="true" /> {busy ? 'Sending invitation…' : 'Send invitation'}
        </button>
      </div>
      <p className="users-hint">
        You will not set or see their password. They choose it themselves from the link in the email.
      </p>
    </form>
  );
};
