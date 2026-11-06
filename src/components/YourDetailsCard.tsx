import React, { useEffect, useState } from 'react';
import PhoneInput from './PhoneInput';
import { usePortalRpc } from '../lib/affiliatePortal';
import { detailsMessage, detailsStep, type DetailsChanges, type PortalDetails } from '../lib/affiliateDetails';
import { supabase } from '../lib/supabase';

// 491 (3 Nov 2026): the Account page's Your details. An affiliate changes
// their own name, phone and email: at once when their email is not verified
// and their own sign-up made their record; otherwise with a code emailed to
// their current address (and one to a new email), and, when the app cannot
// prove the login is that customer's, after Energia staff approve it.
// The email here is the login's: the one shown as Verified, that codes go to
// and that they sign in with (the record may hold another address; saving
// a new email changes both). Before 6 Nov 2026 this box held the record's, so
// that address could not be chosen: "Nothing has changed".
// 493 (6 Nov 2026): someone who cannot open their current email (also before
// verifying it) asks with a code to the new email, and Energia staff approve.

const label: React.CSSProperties = { display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 };
const linkButton: React.CSSProperties = { background: 'none', border: 0, padding: 0, color: 'var(--primary)', fontWeight: 600, fontSize: 13.5, minHeight: 32, cursor: 'pointer', textAlign: 'left', overflowWrap: 'anywhere' };
const Note: React.FC<{ tone?: 'ok' | 'error' | 'plain'; children: React.ReactNode; role?: string }> = ({ tone = 'plain', children, role }) => (
  <p role={role ?? (tone === 'error' ? 'alert' : 'status')} style={{ fontSize: 13.5, lineHeight: 1.6, marginBottom: 12,
    color: tone === 'error' ? 'var(--danger)' : tone === 'ok' ? 'var(--success)' : 'var(--text-secondary)', fontWeight: tone === 'plain' ? 400 : 600 }}>
    {children}
  </p>
);

/** onChanged: a change was made or asked for, for what else the page shows of it. */
const YourDetailsCard: React.FC<{ onChanged?: () => void }> = ({ onChanged }) => {
  const { data: d, err, retry } = usePortalRpc<PortalDetails>('affiliate_portal_details');
  const [editing, setEditing] = useState(false);
  const [lostInbox, setLostInbox] = useState(false);
  const [f, setF] = useState({ first: '', last: '', phone: '', email: '' });
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);
  const [code, setCode] = useState('');
  const [step, setStep] = useState<{ id: string; purpose: 'current' | 'new'; to: string } | null>(null);
  const [resendAt, setResendAt] = useState(0);
  const [now, setNow] = useState(Date.now());

  // An open request from an earlier visit: back at its code, or waiting.
  const open = d?.request && ['awaiting_code', 'pending_staff'].includes(d.request.status) ? d.request : null;
  useEffect(() => {
    if (open?.status === 'awaiting_code' && open.code_for && open.code_to && !step) {
      setStep({ id: open.id, purpose: open.code_for, to: open.code_to });
    }
  }, [open, step]);
  useEffect(() => {
    if (!step) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [step]);

  if (err) return <div className="card" data-section="your-details" style={{ padding: 18, marginBottom: 20 }}><Note tone="error">Your details could not be loaded: {err}</Note>
    <button type="button" className="btn btn-secondary" onClick={retry} style={{ minHeight: 44 }}>Try again</button></div>;
  if (!d) return null;

  const loginEmail = d.login_email ?? d.email ?? '';
  const startEdit = (lost = false) => {
    setF({ first: d.first_name ?? '', last: d.last_name ?? '', phone: d.phone ?? '', email: loginEmail });
    setLostInbox(lost); setMsg(null); setEditing(true);
  };
  const changesOf = (): DetailsChanges => {
    const c: DetailsChanges = {};
    if (f.first.trim() !== (d.first_name ?? '')) c.first_name = f.first;
    if (f.last.trim() !== (d.last_name ?? '')) c.last_name = f.last;
    if (f.phone.trim() !== (d.phone ?? '')) c.phone = f.phone;
    if (f.email.trim().toLowerCase() !== loginEmail.toLowerCase()) c.email = f.email;
    return c;
  };
  // A minute before another code may be asked for (the server keeps it too).
  const startWait = () => { const t0 = Date.now(); setNow(t0); setResendAt(t0 + 60_000); };
  // After any step: refresh, and the session when the login's email may have changed.
  const done = async (text: string, emailChanged: boolean) => {
    setStep(null); setCode(''); setEditing(false); setLostInbox(false); setMsg({ tone: 'ok', text });
    if (emailChanged) await supabase.auth.refreshSession().catch(() => undefined);
    retry();
    onChanged?.();
  };
  const run = async (body: Record<string, unknown>, emailChanging: boolean) => {
    setBusy(true); setMsg(null);
    const r = await detailsStep(body);
    setBusy(false);
    if (!r.ok) {
      if (['expired', 'too_many_tries', 'no_request'].includes(r.error ?? '')) { setStep(null); setCode(''); retry(); }
      setMsg({ tone: 'error', text: r.message ?? '' }); return;
    }
    if (r.next === 'code' && r.request_id && r.purpose && r.code_to) {
      setStep({ id: r.request_id, purpose: r.purpose, to: r.code_to }); setCode(''); setEditing(false);
      startWait(); return;
    }
    if (r.next === 'pending_staff') { await done('Thank you. Your change was sent to Energia staff, who will check it.', false); return; }
    if (r.status === 'cancelled') { await done('The change was cancelled. Nothing was changed.', false); return; }
    if (r.status === 'applied') { await done('Your details were changed.', emailChanging); return; }
  };
  const save = () => {
    const c = changesOf();
    if (lostInbox) {
      if (!('email' in c)) { setMsg({ tone: 'error', text: detailsMessage('new_email_required') }); return; }
      void run({ action: 'start', changes: c, lost_inbox: true }, true);
      return;
    }
    if (Object.keys(c).length === 0) { setMsg({ tone: 'error', text: 'Nothing has changed.' }); return; }
    void run({ action: 'start', changes: c }, 'email' in c);
  };
  const submitCode = () => {
    if (!step) return;
    if (!/^[0-9]{6}$/.test(code.trim())) { setMsg({ tone: 'error', text: 'Please enter the 6-digit code.' }); return; }
    void run({ action: 'verify', request_id: step.id, code: code.trim() }, true);
  };
  const resend = () => { if (step) { startWait(); void run({ action: 'resend', request_id: step.id }, false); } };
  const cancel = (id: string) => void run({ action: 'cancel', request_id: id }, false);

  const route = d.route;
  const wait = Math.max(0, Math.ceil((resendAt - now) / 1000));
  const lastRejected = d.request?.status === 'rejected' ? d.request : null;

  return (
    <div className="card portal-break" data-section="your-details" data-route={route} style={{ padding: 18, marginBottom: 20 }}>
      <h3 style={{ fontSize: 15, fontWeight: 600, marginBottom: 8 }}>Your details</h3>
      {msg && <Note tone={msg.tone}>{msg.text}</Note>}
      {lastRejected && !msg && !open && (
        <Note tone="error">Energia staff did not approve your last change{lastRejected.decision_note ? `: ${lastRejected.decision_note}` : '.'}</Note>
      )}

      {step ? (
        <div data-state="code">
          <Note>{step.purpose === 'new'
            ? <>Now enter the 6-digit code Energia sent to your new email, <b>{step.to}</b>.</>
            : <>Energia sent a 6-digit code to <b>{step.to}</b>. Enter it to confirm the change. It works for 10 minutes.</>}</Note>
          <label htmlFor="details-code" style={label}>Code</label>
          <input id="details-code" className="input" value={code} onChange={e => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
            inputMode="numeric" autoComplete="one-time-code" maxLength={6} style={{ maxWidth: 180, letterSpacing: 4, marginBottom: 12 }} />
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button type="button" className="btn btn-primary" disabled={busy} onClick={submitCode} style={{ minHeight: 44 }}>{busy ? 'Checking…' : 'Confirm'}</button>
            <button type="button" className="btn btn-secondary" disabled={busy || wait > 0} onClick={resend} style={{ minHeight: 44 }}>
              {wait > 0 ? `Send a new code (${wait}s)` : 'Send a new code'}</button>
            <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => cancel(step.id)} style={{ minHeight: 44 }}>Cancel</button>
          </div>
        </div>
      ) : open?.status === 'pending_staff' ? (
        <div data-state="waiting">
          <Note>Your change is waiting for Energia staff to check it. It will be made once they approve it.
            {open.new_email && <> After that, sign in with <b>{open.new_email}</b>.</>}</Note>
          <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => cancel(open.id)} style={{ minHeight: 44 }}>Cancel the change</button>
        </div>
      ) : editing ? (
        <div data-state="edit">
          <div className="portal-form-grid-2">
            <div style={{ marginBottom: 12 }}><label htmlFor="details-first" style={label}>First Name</label>
              <input id="details-first" className="input" value={f.first} onChange={e => setF(s => ({ ...s, first: e.target.value }))} autoComplete="given-name" /></div>
            <div style={{ marginBottom: 12 }}><label htmlFor="details-last" style={label}>Last Name</label>
              <input id="details-last" className="input" value={f.last} onChange={e => setF(s => ({ ...s, last: e.target.value }))} autoComplete="family-name" /></div>
          </div>
          <div style={{ marginBottom: 12 }}><label style={label}>Phone Number</label>
            <PhoneInput value={f.phone} onChange={phone => setF(s => ({ ...s, phone }))} /></div>
          <div style={{ marginBottom: 12 }}><label htmlFor="details-email" style={label}>Email</label>
            <input id="details-email" className="input" type="email" value={f.email} onChange={e => setF(s => ({ ...s, email: e.target.value }))} autoComplete="email" /></div>
          {lostInbox
            ? <Note>Energia will email a code to your new email. Then Energia staff check the change before it is made, so they may ask you to show who you are.</Note>
            : <>
                {route === 'code' && <Note>Energia will email a code to <b>{d.login_email}</b> before changing anything{f.email.trim().toLowerCase() !== loginEmail.toLowerCase() ? ', and one to your new email' : ''}.</Note>}
                {route === 'staff' && <Note>Energia will email a code to <b>{d.login_email}</b>. Then Energia staff check the change before it is made.</Note>}
              </>}
          {(route === 'code' || route === 'staff') && (
            <p style={{ marginBottom: 12 }}>
              <button type="button" data-action="lost-inbox" onClick={() => { setLostInbox(v => !v); setMsg(null); }} style={linkButton}>
                {lostInbox ? 'I can open it after all' : `I can't open ${d.login_email}`}
              </button>
            </p>
          )}
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button type="button" className="btn btn-primary" disabled={busy} onClick={save} style={{ minHeight: 44 }}>{busy ? 'Saving…' : 'Save changes'}</button>
            <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => { setEditing(false); setLostInbox(false); setMsg(null); }} style={{ minHeight: 44 }}>Cancel</button>
          </div>
        </div>
      ) : (
        <div data-state="show">
          <div className="portal-kv"><span className="k">Name</span><span className="v">{[d.first_name, d.last_name].filter(Boolean).join(' ') || '—'}</span></div>
          <div className="portal-kv"><span className="k">Phone</span><span className="v">{d.phone || '—'}</span></div>
          <div className="portal-kv"><span className="k">Email</span><span className="v">{loginEmail || '—'}</span></div>
          <div style={{ marginTop: 12 }}>
            {route === 'verify_first' && <>
              <Note>Please verify your email first (see Verify your email). Then you can change your details here.</Note>
              <button type="button" data-action="lost-inbox" onClick={() => startEdit(true)} style={linkButton}>{`I can't open ${d.login_email}`}</button>
            </>}
            {route === 'closed' && <Note>Your details cannot be changed here. Please ask Energia staff.</Note>}
            {(route === 'free' || route === 'code' || route === 'staff') && (
              <button type="button" className="btn btn-secondary" onClick={() => startEdit()} style={{ minHeight: 44 }}>Change my details</button>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

export default YourDetailsCard;
