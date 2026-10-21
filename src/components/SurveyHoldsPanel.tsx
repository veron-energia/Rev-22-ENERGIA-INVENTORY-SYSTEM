import React, { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Modal } from './ui';
import { CustomerSearchSelect } from './SearchSelect';
import { ClipboardList, Link2, UserPlus, XCircle } from 'lucide-react';

/** A customer a waiting QR form may belong to (health_survey_holds_list, 433). */
export interface HoldCandidate {
  customer_id: string; full_name: string; phone: string | null; email: string | null;
  date_of_birth: string | null; created_at: string; deleted: boolean;
  phone_matches: boolean; email_matches: boolean; name_matches: boolean;
  /** The customer's own survey, if they have one: a customer has only one. */
  survey_no: string | null;
  /**
   * 419 (Q10): that survey is a consultant's record the customer has not
   * signed, so the form's answers can go into it. Missing before 419.
   */
  survey_takes_form?: boolean | null;
}

/** A QR form the server held for staff instead of making a second customer (433). */
export interface HeldForm {
  survey_id: string; survey_no: string; submitted_at: string;
  store_name: string | null; event_name: string | null;
  full_name: string; date_of_birth: string | null; sex: string | null;
  phone: string | null; email: string | null; occupation: string | null; source_label: string | null;
  reason: 'phone_in_use' | 'email_in_use' | 'phone_and_email_in_use' | 'several_name_matches';
  held_at: string;
  candidates: HoldCandidate[];
}

const REASON: Record<HeldForm['reason'], string> = {
  phone_in_use: 'Its phone number belongs to a customer under another name.',
  email_in_use: 'Its email belongs to a customer with another phone number.',
  phone_and_email_in_use: 'Its phone number and email are already on file under another name.',
  several_name_matches: 'Its name matches more than one customer with this phone number.',
};

/** The server's refusal, in words staff can act on here. */
const explain = (message: string) =>
  /CUSTOMER_PHONE_LIMIT/.test(message)
    ? 'This phone number already belongs to 3 customers, so no new customer can be made with it. '
      + 'Attach the form to one of them, or ask an Owner or Manager to close it.'
    : message;
/** Someone else dealt with the form meanwhile: the list is out of date. */
const stale = (message: string) => /already been dealt with|already attached to a customer|not waiting to be matched/.test(message);

const when = (s: string) => new Date(s).toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short' });
const day = (s: string | null) => (s ? new Date(`${s}T00:00:00`).toLocaleDateString('en-GB') : '—');

type Action =
  | { kind: 'attach'; form: HeldForm; customer: HoldCandidate | null }
  | { kind: 'create'; form: HeldForm }
  | { kind: 'close'; form: HeldForm };

/**
 * Health Surveys → To match. QR forms the server was unsure about wait here
 * with no customer: its phone or email belongs to a customer under another
 * name, or its name matches several. Staff attach each to the customer it
 * belongs to, or make a new customer from it (any staff); an Owner or Manager
 * may close one without attaching it. Until then the form counts as no visit
 * and no TikTok attendance, so it should be matched the same day.
 */
const SurveyHoldsPanel: React.FC<{
  forms: HeldForm[];
  /** Owner or Manager: may close a form without attaching it. */
  canClose: boolean;
  /** Called after a form was attached, made into a customer or closed. */
  onChanged: () => void;
}> = ({ forms, canClose, onChanged }) => {
  const [action, setAction] = useState<Action | null>(null);
  const [note, setNote] = useState('');
  const [otherId, setOtherId] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const open = (a: Action) => { setAction(a); setNote(''); setOtherId(''); setErr(null); setDone(null); };
  const close = () => { if (!busy) setAction(null); };

  const confirm = async () => {
    if (!action) return;
    setBusy(true); setErr(null);
    let res: { data?: any; error: { message: string } | null };
    if (action.kind === 'attach') {
      res = await supabase.rpc('attach_held_health_survey', {
        p_survey_id: action.form.survey_id, p_customer_id: action.customer?.customer_id ?? otherId, p_note: note.trim(),
      });
    } else if (action.kind === 'create') {
      res = await supabase.rpc('create_customer_from_held_survey', {
        p_survey_id: action.form.survey_id, p_note: note.trim() || null,
      });
    } else {
      res = await supabase.rpc('close_held_health_survey', {
        p_survey_id: action.form.survey_id, p_reason: note.trim(),
      });
    }
    setBusy(false);
    if (res.error) {
      setErr(explain(res.error.message));
      if (stale(res.error.message)) onChanged();
      return;
    }
    const f = action.form;
    const into = action.kind === 'attach' ? (res.data as any)?.signed_into_survey_no as string | undefined : undefined;
    setDone(action.kind === 'attach'
      ? (into
          // 419 (Q10): the answers went into the customer's unsigned record.
          ? `The answers on ${f.survey_no} went into ${action.customer?.full_name ?? 'the customer'}'s survey ${into}, which is now signed.`
          : action.customer ? `${f.survey_no} is now ${action.customer.full_name}'s survey.` : `${f.survey_no} is now attached to the customer you chose.`)
      : action.kind === 'create' ? `A new customer was made from ${f.survey_no}, and the form is theirs.`
      : `${f.survey_no} was closed without a customer.`);
    setAction(null);
    onChanged();
  };

  const needsNote = action?.kind === 'attach' || action?.kind === 'close';
  const ready = !!action && (!needsNote || note.trim() !== '')
    && !(action.kind === 'attach' && !action.customer && !otherId);

  return (
    <div>
      <div className="alert alert-info" style={{ marginBottom: 12 }}>
        <span>ℹ️</span>
        <div>
          A QR form waits here instead of making a second customer when its phone or email belongs to a
          customer under another name. Attach it to the customer it belongs to, or make a new customer from
          it (for example a family member sharing the phone). Until then it counts as no visit and no TikTok
          attendance, so please match it the same day.
        </div>
      </div>
      {done && <div className="alert alert-info" role="status" style={{ marginBottom: 12 }}><span>✓</span><div>{done}</div></div>}

      {forms.length === 0 ? (
        <div className="card"><div className="empty-state">
          <ClipboardList size={32} style={{ opacity: 0.3 }} />
          <p style={{ fontWeight: 600, marginTop: 8 }}>No forms are waiting</p>
        </div></div>
      ) : forms.map(f => (
        <div key={f.survey_id} className="card" data-hold={f.survey_id} style={{ marginBottom: 12, padding: 14 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, flexWrap: 'wrap', marginBottom: 8 }}>
            <div>
              <span className="badge badge-accent">{f.survey_no}</span>{' '}
              <strong>{f.full_name}</strong>
              <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2 }}>
                Received {when(f.submitted_at)}{f.store_name ? ` · ${f.store_name}` : ''}{f.event_name ? ` · ${f.event_name}` : ''}
              </div>
            </div>
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)', maxWidth: 420 }}>{REASON[f.reason]}</div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(170px, 1fr))', gap: '4px 16px',
                        fontSize: 12.5, marginBottom: 10 }}>
            <div><span style={{ color: 'var(--text-muted)' }}>Phone</span> {f.phone || '—'}</div>
            <div style={{ overflowWrap: 'anywhere' }}><span style={{ color: 'var(--text-muted)' }}>Email</span> {f.email || '—'}</div>
            <div><span style={{ color: 'var(--text-muted)' }}>Date of birth</span> {day(f.date_of_birth)}</div>
            <div><span style={{ color: 'var(--text-muted)' }}>Sex</span> {f.sex === 'female' ? 'Female' : f.sex === 'male' ? 'Male' : '—'}</div>
            <div><span style={{ color: 'var(--text-muted)' }}>Occupation</span> {f.occupation || '—'}</div>
            <div><span style={{ color: 'var(--text-muted)' }}>Heard about us</span> {f.source_label || '—'}</div>
          </div>

          <div className="table-wrap">
            <table>
              <thead><tr><th>May belong to</th><th>Contact</th><th>Date of birth</th><th>Same</th><th>Survey</th><th></th></tr></thead>
              <tbody>{f.candidates.map(c => {
                // 419 (Q10): a consultant's record the customer has not signed
                // takes the form's answers; any other survey is their one survey.
                const blocked = c.deleted ? 'This customer record was retired.'
                  : c.survey_no && !c.survey_takes_form
                    ? `This customer already has a survey (${c.survey_no}); a customer can have only one.` : null;
                return (
                  <tr key={c.customer_id}>
                    <td style={{ fontWeight: 600 }}>{c.full_name}{c.deleted && <span className="badge badge-muted" style={{ marginLeft: 6 }}>Retired</span>}</td>
                    <td style={{ fontSize: 12, color: 'var(--text-muted)', overflowWrap: 'anywhere' }}>{[c.phone, c.email].filter(Boolean).join(' · ') || '—'}</td>
                    <td style={{ fontSize: 12 }}>{day(c.date_of_birth)}</td>
                    <td style={{ fontSize: 11.5 }}>
                      {c.phone_matches && <span className="badge badge-success" style={{ marginRight: 4 }}>Phone</span>}
                      {c.email_matches && <span className="badge badge-success" style={{ marginRight: 4 }}>Email</span>}
                      {c.name_matches && <span className="badge badge-success">Name</span>}
                    </td>
                    <td style={{ fontSize: 12 }}>{c.survey_no ?? '—'}
                      {c.survey_no && c.survey_takes_form && (
                        <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Not signed yet: the form's answers go into it</div>
                      )}</td>
                    <td style={{ textAlign: 'right' }}>
                      <button className="btn btn-primary btn-sm" disabled={!!blocked} title={blocked ?? undefined}
                        data-attach={c.customer_id}
                        onClick={() => open({ kind: 'attach', form: f, customer: c })}>
                        <Link2 size={12} /> Attach
                      </button>
                    </td>
                  </tr>
                );
              })}</tbody>
            </table>
          </div>

          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginTop: 10 }}>
            <button className="btn btn-secondary btn-sm" data-other={f.survey_id}
              onClick={() => open({ kind: 'attach', form: f, customer: null })}>
              <Link2 size={12} /> Attach to another customer…
            </button>
            <button className="btn btn-secondary btn-sm" data-create={f.survey_id}
              onClick={() => open({ kind: 'create', form: f })}>
              <UserPlus size={12} /> New customer from this form
            </button>
            {canClose && (
              <button className="btn btn-secondary btn-sm" data-close={f.survey_id}
                onClick={() => open({ kind: 'close', form: f })}>
                <XCircle size={12} /> Close without attaching
              </button>
            )}
          </div>
        </div>
      ))}

      {action && (
        <Modal
          title={action.kind === 'attach' ? `Attach ${action.form.survey_no}`
            : action.kind === 'create' ? `New customer from ${action.form.survey_no}` : `Close ${action.form.survey_no}`}
          maxWidth={520} onClose={close} confirmClose={note.trim() !== '' || !!otherId}
          footer={<>
            <button className="btn btn-secondary" onClick={close} disabled={busy}>Cancel</button>
            <button className="btn btn-primary" data-confirm onClick={confirm} disabled={busy || !ready}>
              {busy ? 'Saving…' : action.kind === 'attach' ? 'Attach' : action.kind === 'create' ? 'Make customer' : 'Close form'}
            </button>
          </>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            {action.kind === 'attach' && action.customer && !action.customer.survey_takes_form && (
              <p style={{ margin: 0, fontSize: 13.5 }}>
                The form <strong>{action.form.full_name}</strong> sent becomes <strong>{action.customer.full_name}</strong>'s
                health survey. Their name and phone stay as they are; empty details (email, date of birth, sex,
                occupation, how they heard about us) are filled from the form.
              </p>
            )}
            {action.kind === 'attach' && action.customer?.survey_takes_form && (
              <p style={{ margin: 0, fontSize: 13.5 }} data-takes-form>
                <strong>{action.customer.full_name}</strong> has a consultant's survey ({action.customer.survey_no}) they
                have not signed. The answers, signature and signed PDF of the form <strong>{action.form.full_name}</strong> sent
                go into it. The consultant's notes, findings and files stay, and where the two differ the customer's own
                answers are kept. Their name and phone stay as they are.
              </p>
            )}
            {action.kind === 'attach' && !action.customer && (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Customer</label>
                <CustomerSearchSelect value={otherId} onChange={setOtherId} />
              </div>
            )}
            {action.kind === 'create' && (
              <p style={{ margin: 0, fontSize: 13.5 }}>
                A new customer is made from this form: <strong>{action.form.full_name}</strong>
                {action.form.phone ? `, ${action.form.phone}` : ''}{action.form.email ? `, ${action.form.email}` : ''}.
                Use this when the person is not the customer shown, for example a family member sharing the phone.
              </p>
            )}
            {action.kind === 'close' && (
              <p style={{ margin: 0, fontSize: 13.5 }}>
                The form is taken off this list without a customer and kept as it is. The person can send the form again.
              </p>
            )}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>
                {action.kind === 'attach' ? 'How did you confirm this is the same person? *'
                  : action.kind === 'create' ? 'Note (optional)' : 'Reason *'}
              </label>
              <textarea rows={2} value={note} onChange={e => setNote(e.target.value)} data-note
                placeholder={action.kind === 'attach' ? 'e.g. Checked her NRIC at the counter'
                  : action.kind === 'create' ? 'e.g. Daughter of the customer on this phone' : 'e.g. Sent twice'} />
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default SurveyHoldsPanel;
