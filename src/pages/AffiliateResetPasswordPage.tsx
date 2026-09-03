import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';

// Reached via the reset link (Supabase establishes a recovery session).
const AffiliateResetPasswordPage: React.FC = () => {
  const nav = useNavigate();
  const [pw, setPw] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const submit = async () => {
    setErr(null);
    if (pw.length < 8) { setErr('Password must be at least 8 characters.'); return; }
    if (pw !== confirm) { setErr('Passwords do not match.'); return; }
    setBusy(true);
    const { error } = await supabase.auth.updateUser({ password: pw });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    nav('/affiliate/dashboard', { replace: true });
  };

  return (
    <AffiliateAuthShell title="Set a New Password" subtitle="Choose a new password for your account">
      <Field label="New Password"><input className="input" type="password" value={pw} onChange={e => setPw(e.target.value)} /></Field>
      <Field label="Confirm Password"><input className="input" type="password" value={confirm} onChange={e => setConfirm(e.target.value)} onKeyDown={e => e.key === 'Enter' && submit()} /></Field>
      {err && <p style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Saving…' : 'Save Password'}</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateResetPasswordPage;
