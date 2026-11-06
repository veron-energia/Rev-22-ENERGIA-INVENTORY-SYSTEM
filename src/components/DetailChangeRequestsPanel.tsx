import React, { useCallback, useEffect, useState } from 'react';
import { UserCog } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { detailsStep } from '../lib/affiliateDetails';

// 491 (3 Nov 2026): an affiliate's own change of name, phone or email that
// waits for an Owner or Manager: the login is verified, but the app cannot
// prove it belongs to the customer record it is joined to. 493 (6 Nov 2026):
// or they cannot open their current email, so only the new one was confirmed.
// Approve makes the change; Reject (with a reason the affiliate sees) changes
// nothing. Shown only when something waits.

interface Change {
  id: string; created_at: string; customer_id: string; customer_name: string | null;
  old: { first_name: string | null; last_name: string | null; phone: string | null; email: string | null; login_email: string | null };
  new: { first_name?: string; last_name?: string; phone?: string; email?: string };
  signed_up_with: { name: string | null; phone: string | null; email: string | null } | null;
  new_email_proven: boolean;
  current_inbox_lost?: boolean;
}

const FIELDS: [keyof Change['new'], string][] = [['first_name', 'First name'], ['last_name', 'Last name'], ['phone', 'Phone'], ['email', 'Email']];
// The email that changes is the login's; say so when the record holds another.
const emailNow = (c: Change) => {
  const { login_email: login, email: record } = c.old;
  if (!login) return record;
  return record && record.toLowerCase() !== login.toLowerCase() ? `${login} (customer record: ${record})` : login;
};
// An approval that could not be made, or a request already over: the request has
// left the list, and the person deciding is told why (the affiliate's own wording
// says "your email" and "start again").
const OVER: Record<string, string> = {
  email_not_changed: 'The email could not be changed, so nothing was changed: another login may have just taken that address. The affiliate can ask again.',
  not_saved: 'The change could not be saved, so nothing was changed. The affiliate can ask again.',
  no_request: 'This request is no longer open: the affiliate may have cancelled it, or someone else decided it.',
};
const missing = (e: { code?: string; message?: string } | null) =>
  !!e && (e.code === 'PGRST202' || /does not exist|could not find the function/i.test(e.message ?? ''));

const DetailChangeRequestsPanel: React.FC = () => {
  const [rows, setRows] = useState<Change[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ id: string; text: string; ok: boolean } | null>(null);

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc('affiliate_detail_change_requests');
    if (error) { if (!missing(error)) setErr(error.message); setRows([]); return; }
    setErr(null); setRows(((data as Change[]) ?? []));
  }, []);
  useEffect(() => { void load(); }, [load]);

  const decide = async (c: Change, approve: boolean) => {
    const note = (notes[c.id] ?? '').trim();
    if (!approve && !note) { setMsg({ id: c.id, ok: false, text: 'Please give a reason for rejecting it. The affiliate sees it.' }); return; }
    setBusy(c.id); setMsg(null);
    const r = await detailsStep({ action: 'decide', request_id: c.id, approve, note: note || null });
    setBusy(null);
    if (!r.ok) {
      const over = OVER[r.error ?? ''];
      setMsg({ id: c.id, ok: false, text: over ?? r.message ?? '' });
      if (over) await load();
      return;
    }
    setMsg({ id: c.id, ok: true, text: approve ? 'Approved: the change was made.' : 'Rejected: nothing was changed.' });
    await load();
  };

  if (err) return <div className="card" data-error="detail-changes" style={{ padding: 12, marginBottom: 12, borderColor: 'var(--danger)', color: 'var(--danger)', fontSize: 13.5 }}>The detail changes to check could not be loaded: {err}</div>;
  // What came of a request no longer listed; one still listed says it on its row.
  const left = msg && !rows.some(c => c.id === msg.id) ? msg : null;
  const leftNote = left && <p role={left.ok ? 'status' : 'alert'} style={{ fontSize: 13.5, color: left.ok ? 'var(--success)' : 'var(--danger)', marginBottom: 12 }}>{left.text}</p>;
  if (rows.length === 0) return leftNote;
  return (
    <div className="card" data-panel="detail-changes" style={{ padding: 16, marginBottom: 16 }}>
      <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 6, display: 'flex', gap: 8, alignItems: 'center' }}>
        <UserCog size={16} /> Detail changes to check ({rows.length})
      </h3>
      <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 12, lineHeight: 1.5 }}>
        These affiliates confirmed the change with a code, but the app cannot be sure it is them. Check with the person (for example at the counter) before approving.
      </p>
      {leftNote}
      {rows.map(c => (
        <div key={c.id} data-change={c.id} style={{ borderTop: '1px solid var(--border)', paddingTop: 12, marginTop: 12, fontSize: 13.5 }}>
          <div style={{ fontWeight: 600, marginBottom: 6 }}>{c.customer_name ?? 'Customer'} <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>· asked {new Date(c.created_at).toLocaleDateString('en-GB')}</span></div>
          {c.current_inbox_lost && (
            <div data-note="lost-inbox" className="alert alert-warning" style={{ marginBottom: 8, lineHeight: 1.5 }}>
              <span>They say they cannot open their current email{c.old.login_email ? <> (<b>{c.old.login_email}</b>)</> : null}, so only the new email was confirmed. Please check who this is before approving: anyone with their password could ask for this.</span>
            </div>
          )}
          <table className="table" style={{ width: '100%', fontSize: 13, marginBottom: 8 }}>
            <thead><tr><th></th><th>Now</th><th>Asked for</th></tr></thead>
            <tbody>
              {FIELDS.filter(([k]) => c.new[k] !== undefined).map(([k, name]) => (
                <tr key={k}><th scope="row" style={{ whiteSpace: 'nowrap' }}>{name}</th>
                  <td>{(k === 'email' ? emailNow(c) : c.old[k]) || '—'}</td>
                  <td><b>{c.new[k]}</b>{k === 'email' && c.new_email_proven ? ' (code confirmed)' : ''}</td></tr>
              ))}
            </tbody>
          </table>
          {c.signed_up_with && (
            <p style={{ color: 'var(--text-secondary)', marginBottom: 8 }}>
              Signed up with: {[c.signed_up_with.name, c.signed_up_with.phone, c.signed_up_with.email].filter(Boolean).join(' · ')}
            </p>
          )}
          <label htmlFor={`note-${c.id}`} style={{ display: 'block', fontSize: 12.5, fontWeight: 600, marginBottom: 4 }}>Note (needed to reject; the affiliate sees it)</label>
          <input id={`note-${c.id}`} className="input" value={notes[c.id] ?? ''} onChange={e => setNotes(n => ({ ...n, [c.id]: e.target.value }))} style={{ marginBottom: 8 }} />
          {msg?.id === c.id && <p role={msg.ok ? 'status' : 'alert'} style={{ color: msg.ok ? 'var(--success)' : 'var(--danger)', marginBottom: 8 }}>{msg.text}</p>}
          <div style={{ display: 'flex', gap: 8 }}>
            <button type="button" className="btn btn-primary btn-sm" disabled={busy === c.id} onClick={() => void decide(c, true)}>Approve</button>
            <button type="button" className="btn btn-secondary btn-sm" disabled={busy === c.id} onClick={() => void decide(c, false)}>Reject</button>
          </div>
        </div>
      ))}
    </div>
  );
};

export default DetailChangeRequestsPanel;
