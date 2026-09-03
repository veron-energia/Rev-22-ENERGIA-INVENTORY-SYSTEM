import React, { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';

// Landing page after the user clicks the email verification link. The user now
// has an authenticated session with a verified email; we call the backend to
// complete onboarding (which re-checks the verified email server-side).
const AffiliateVerifyPage: React.FC = () => {
  const nav = useNavigate();
  const { refreshProfile } = useAuth();
  const [state, setState] = useState<'working' | 'need_details' | 'pending' | 'error' | 'suspended'>('working');
  const [msg, setMsg] = useState<string | null>(null);
  const [f, setF] = useState({ first: '', last: '', phone: '' });

  const complete = async (first: string, last: string, phone: string) => {
    setState('working'); setMsg(null);
    const { data: sess } = await supabase.auth.getSession();
    if (!sess.session) { setState('error'); setMsg('Your verification session has expired. Please sign in.'); return; }
    const { data, error } = await supabase.rpc('complete_affiliate_onboarding',
      { p_first_name: first, p_last_name: last, p_phone: phone, p_agree: true });
    if (error) { setState('error'); setMsg(error.message); return; }
    const res = data as any;
    if (res?.status === 'pending_verification') { setState('pending'); setMsg(res.message); return; }
    await refreshProfile();
    if (res?.status === 'suspended') { setState('suspended'); return; }
    nav('/affiliate/dashboard', { replace: true });
  };

  useEffect(() => {
    let saved: any = null;
    try { saved = JSON.parse(localStorage.getItem('energia_aff_onboarding') || 'null'); } catch { /* ignore */ }
    if (saved?.phone) { complete(saved.first || '', saved.last || '', saved.phone); }
    else { setState('need_details'); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (state === 'working') return <AffiliateAuthShell title="Finishing setup…" subtitle="Please wait a moment"><p style={{ textAlign: 'center', color: 'var(--text-muted)' }}>Completing your affiliate account…</p></AffiliateAuthShell>;

  if (state === 'pending') return (
    <AffiliateAuthShell title="Identity verification needed">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>{msg}</p>
      <div style={{ textAlign: 'center', marginTop: 16 }}><Link to="/affiliate/login" style={{ color: 'var(--primary)', fontWeight: 600 }}>Back to login</Link></div>
    </AffiliateAuthShell>
  );

  if (state === 'suspended') return (
    <AffiliateAuthShell title="Account suspended">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        Your account is linked, but your affiliate status is currently suspended. You can view your history, but new referrals are disabled. Please contact Energia.
      </p>
      <button className="btn btn-primary" style={{ width: '100%', marginTop: 14 }} onClick={() => nav('/affiliate/dashboard', { replace: true })}>Go to Portal</button>
    </AffiliateAuthShell>
  );

  if (state === 'error') return (
    <AffiliateAuthShell title="Something went wrong">
      <p style={{ color: 'var(--danger)', fontSize: 13.5, marginBottom: 14 }}>{msg}</p>
      <Link to="/affiliate/login" className="btn btn-secondary" style={{ width: '100%' }}>Back to login</Link>
    </AffiliateAuthShell>
  );

  // need_details
  return (
    <AffiliateAuthShell title="Confirm your details" subtitle="Just a couple of details to finish">
      <Field label="First Name"><input className="input" value={f.first} onChange={e => setF({ ...f, first: e.target.value })} /></Field>
      <Field label="Last Name"><input className="input" value={f.last} onChange={e => setF({ ...f, last: e.target.value })} /></Field>
      <Field label="Phone Number"><input className="input" value={f.phone} onChange={e => setF({ ...f, phone: e.target.value })} placeholder="+65…" /></Field>
      <button className="btn btn-primary" style={{ width: '100%' }} onClick={() => complete(f.first, f.last, f.phone)}>Finish Setup</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateVerifyPage;
