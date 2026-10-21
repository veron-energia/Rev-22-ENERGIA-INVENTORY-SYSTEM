import { phoneErrorMessage } from '../lib/customer-phones/normalize.mjs';
import React, { useEffect, useState, useRef } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';
import PhoneInput, { isPhoneValid } from '../components/PhoneInput';
import { sessionFromEmailLink, takeEmailLinkError } from '../lib/affiliateEmail';

// Where a signed-in login without an affiliate account finishes its sign-up
// (complete_affiliate_onboarding), with the details it already gave, and then
// goes to the dashboard. Since 437 (the Owner, 20 Oct 2026) it is reached:
//   * straight after Create Account (the Join page signs in, then comes here);
//   * on the next sign-in of someone stuck after signing up (the login page
//     and the portal guard send a login with no affiliate account here);
//   * from an emailed link: the Account page's verification email, or an old
//     sign-up link. A session opened from one also marks the email verified
//     (confirm_affiliate_email), and the person lands on the Account page,
//     which says so, or says the link could not verify it. A link Supabase
//     refused (expired, or already used) is said here, with Sign in.
// It never waits on staff: the server answers with an account, or "rejected".
// Whether the login is a member of staff is the server's answer
// (STAFF_ACCOUNT), not the page's: straight after Create Account the app may
// still hold the staff login it was signed in with a moment before.
const ONBOARDING_KEY = 'energia_aff_onboarding';

const AffiliateVerifyPage: React.FC = () => {
  const nav = useNavigate();
  const { refreshProfile, profile } = useAuth();
  const [state, setState] = useState<'working' | 'need_details' | 'pending' | 'error' | 'suspended' | 'rejected' | 'staff'
    | 'signed_out' | 'link_refused'>('working');
  // The session came from an emailed link: the working screen says so.
  const [viaLink, setViaLink] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [f, setF] = useState({ first: '', last: '', phone: '' });
  // Guard so React StrictMode / re-renders can't fire onboarding twice. The DB
  // one-pending-claim index is the authoritative protection; this is secondary.
  const attempted = useRef(false);

  const complete = async (first: string, last: string, phone: string, typed = false) => {
    setF({ first, last, phone });
    // Only what the person typed is checked here. Details that arrived with
    // the account are the server's to check — it holds its own copy, answers
    // an existing affiliate without needing any, and says DETAILS_REQUIRED
    // when it genuinely has none.
    if (typed && (!first.trim() || !isPhoneValid(phone))) { setState('need_details'); setMsg('Enter your name and a valid international phone number.'); return; }
    setState('working'); setMsg(null);
    const { data: sess } = await supabase.auth.getSession();
    if (!sess.session) { setState('signed_out'); setMsg(null); return; }
    const fromLink = sessionFromEmailLink(sess.session.access_token);
    setViaLink(fromLink);
    const { data, error } = await supabase.rpc('complete_affiliate_onboarding',
      { p_first_name: first, p_last_name: last, p_phone: phone, p_agree: true });
    if (error) {
      if (/DETAILS_REQUIRED/.test(error.message)) { setState('need_details'); setMsg(null); return; }
      // A login is either Staff or an Affiliate, never both: the server
      // refuses a staff login before it writes anything.
      if (/STAFF_ACCOUNT/.test(error.message)) { setState('staff'); setMsg(null); return; }
      setState('error'); setMsg(phoneErrorMessage(error.message)); return;              // keep saved state to allow retry
    }
    const res = data as any;

    // Definitive backend response — safe to clear the saved onboarding details.
    try { localStorage.removeItem(ONBOARDING_KEY); } catch { /* ignore */ }

    // A server from before 437 could still park the sign-up for staff.
    if (res?.status === 'pending_verification') { setState('pending'); setMsg(res.message); return; }
    if (res?.status === 'rejected') { setState('rejected'); setMsg(res.message); return; }
    // 437: opened from an emailed link (the Account page's verification
    // email): the email is verified now. Nothing waits on it; if it fails,
    // the Account page says so and offers a new link.
    let verifiedNow = false;
    let verifyFailed = false;
    if (fromLink) {
      const { data: v, error: vErr } = await supabase.rpc('confirm_affiliate_email');
      verifiedNow = !vErr && (v as any)?.verified === true && (v as any)?.already !== true;
      verifyFailed = !!vErr || (v as any)?.verified !== true;
    }
    await refreshProfile();
    if (res?.status === 'suspended') { setState('suspended'); return; }
    if (verifiedNow) { nav('/affiliate/account', { replace: true, state: { emailVerified: true } }); return; }
    if (verifyFailed) { nav('/affiliate/account', { replace: true, state: { emailVerifyFailed: true } }); return; }
    nav('/affiliate/dashboard', { replace: true });
  };

  useEffect(() => {
    if (attempted.current) return;
    attempted.current = true;
    // The app was opened with a link Supabase refused (expired, or already
    // used). Supabase keeps any session already here, so say so rather than
    // carry on as an ordinary visit.
    if (takeEmailLinkError('/affiliate/verify')) { setState('link_refused'); return; }
    (async () => {
      // Where the details come from, in order: the account itself — stored at
      // sign-up, present in whichever browser the link opens in — then this
      // browser's copy of the form, then nothing. The verification link on a
      // phone usually opens in the mail app's browser, not the one the form
      // was filled in, which is why the browser's copy was so often missing
      // and the person was asked again.
      const { data: sess } = await supabase.auth.getSession();
      const meta = (sess.session?.user?.user_metadata ?? {}) as Record<string, unknown>;
      let saved: any = null;
      try { saved = JSON.parse(localStorage.getItem(ONBOARDING_KEY) || 'null'); } catch { /* ignore */ }
      const pick = (a: unknown, b: unknown) => String((typeof a === 'string' && a.trim()) ? a : (b ?? ''));
      await complete(pick(meta.first_name, saved?.first), pick(meta.last_name, saved?.last), pick(meta.phone, saved?.phone));
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (state === 'working') return viaLink
    ? <AffiliateAuthShell title="Verifying your email…" subtitle="Please wait a moment"><p style={{ textAlign: 'center', color: 'var(--text-muted)' }}>Checking the link we emailed you…</p></AffiliateAuthShell>
    : <AffiliateAuthShell title="Finishing setup…" subtitle="Please wait a moment"><p style={{ textAlign: 'center', color: 'var(--text-muted)' }}>Completing your affiliate account…</p></AffiliateAuthShell>;

  if (state === 'link_refused') return (
    <AffiliateAuthShell title="This link has expired">
      <p data-state="link-refused" style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        This link has expired or was already used. Sign in and send a new one from your Account page.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 14 }}>
        <Link className="btn btn-primary" style={{ width: '100%', textAlign: 'center' }} to="/affiliate/login">Sign in</Link>
        <Link className="btn btn-secondary" style={{ width: '100%', textAlign: 'center' }} to="/affiliate/account">Go to Account</Link>
      </div>
    </AffiliateAuthShell>
  );

  if (state === 'signed_out') return (
    <AffiliateAuthShell title="Please sign in">
      <p data-state="signed-out" style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        Your session has expired. Sign in to finish setting up your affiliate account.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 14 }}>
        <Link className="btn btn-primary" style={{ width: '100%', textAlign: 'center' }} to="/affiliate/login">Sign in</Link>
        <Link className="btn btn-secondary" style={{ width: '100%', textAlign: 'center' }} to="/affiliate/forgot-password">Reset password</Link>
      </div>
    </AffiliateAuthShell>
  );

  if (state === 'pending') return (
    <AffiliateAuthShell title="Identity verification needed">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>{msg}</p>
      <div style={{ textAlign: 'center', marginTop: 16 }}><Link to="/affiliate/login" style={{ color: 'var(--primary)', fontWeight: 600 }}>Back to login</Link></div>
    </AffiliateAuthShell>
  );

  if (state === 'staff') return (
    <AffiliateAuthShell title="You are signed in as staff">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        You are signed in as <b>{profile?.full_name ?? profile?.email ?? 'a staff member'}</b>. An
        Energia staff login cannot also be an affiliate account, so nothing has been created.
      </p>
      <p style={{ fontSize: 13, color: 'var(--text-muted)', lineHeight: 1.6, marginTop: 10 }}>
        To join as an affiliate, sign out and sign up with a personal email address. If an affiliate
        record should exist against an existing customer, an Owner or Manager can set that up.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 14 }}>
        <button type="button" className="btn btn-primary" style={{ width: '100%' }}
          onClick={async () => { await supabase.auth.signOut(); nav('/affiliate/join', { replace: true }); }}>
          Sign out and join as an affiliate
        </button>
        <Link className="btn btn-secondary" style={{ width: '100%', textAlign: 'center' }} to="/">
          Back to the app
        </Link>
      </div>
    </AffiliateAuthShell>
  );

  if (state === 'rejected') return (
    <AffiliateAuthShell title="Account verification unsuccessful">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        Your Affiliate account-linking request could not be verified. Please contact Energia for assistance.
      </p>
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
      <button className="btn btn-primary" style={{ width: '100%', marginBottom: 10 }} onClick={() => setState('need_details')}>Edit name or phone number</button>
      <Link to="/affiliate/login" className="btn btn-secondary" style={{ width: '100%' }}>Back to login</Link>
    </AffiliateAuthShell>
  );

  // need_details
  return (
    <AffiliateAuthShell title="Confirm your details" subtitle="Just a couple of details to finish">
      {msg && <p role="alert" style={{ color: 'var(--danger)' }}>{msg}</p>}
      <Field label="First Name"><input className="input" value={f.first} onChange={e => setF({ ...f, first: e.target.value })} /></Field>
      <Field label="Last Name"><input className="input" value={f.last} onChange={e => setF({ ...f, last: e.target.value })} /></Field>
      <Field label="Phone Number"><PhoneInput value={f.phone} onChange={(e164) => setF({ ...f, phone: e164 })} /></Field>
      <button className="btn btn-primary" style={{ width: '100%' }} onClick={() => complete(f.first, f.last, f.phone, true)}>Finish Setup</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateVerifyPage;
