import { phoneErrorMessage } from '../lib/customer-phones/normalize.mjs';
import React, { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import PhoneInput from '../components/PhoneInput';
import '../styles/referral-landing.css';

// Public /r/:referralCode — creates a CUSTOMER under the affiliate. It does NOT
// create a login or an affiliate. The insert is done by a scoped SECURITY
// DEFINER RPC; the browser never writes to customers directly.
//
// This used to be the same compact card as the affiliate sign-in screens. It is
// now the giveaway pitch from energia.sg/free, because the person opening an
// affiliate's link has usually never heard of Energia and a bare form asks them
// to register for nothing in particular. The wording, the prices and the FAQ
// below are taken from that page so the two do not drift apart.
//
// The signup call, the honeypot and the phone validation are unchanged.

/** Where a NEW registration is sent. Existing customers are not sent here: the
 *  page tells people to book a free therapy, and the offer is for first timers,
 *  so somebody already on file stays put and is told nothing changed. */
const THANK_YOU_URL = 'https://energia.sg/ty';

const HERO_IMG = 'https://energia.sg/wp-content/uploads/2025/01/6719068c50fcd_mockup-1024x758.png.webp';
const LOGO_IMG = 'https://energia.sg/wp-content/uploads/2021/03/Energia-Logo-Rectangle-Two.png.webp';

const INCLUDED = [
  {
    title: 'Power Recharge Therapy (20 min)',
    body: 'Rejuvenate your body and mind with our invigorating Power Recharge Therapy. Experience a surge of energy and vitality as our therapies restore balance to your system.',
  },
  {
    title: 'Power Foot Detox Therapy (20 min)',
    body: 'Cleanse your body from within with our revitalizing Power Detox Therapy. Rid your system of toxins and feel refreshed and renewed.',
  },
  {
    title: 'Acugraph Energy Analysis (20 min)',
    body: 'The AcuGraph Energy Analysis measures energy flow in 12 major organs, including the lungs, heart, stomach, liver, kidneys, intestines and more. It helps identify imbalances in your body’s meridians.',
  },
];

const BONUSES = [
  {
    tag: 'BONUS #1',
    title: "The Natural and Effective Remedies for a Good Night's Sleep",
    body: 'Say goodbye to restless nights and discover the secrets to a peaceful and rejuvenating sleep. Explore natural remedies and techniques to improve your sleep quality and wake up feeling refreshed.',
  },
  {
    tag: 'BONUS #2',
    title: 'The Healing Power Of Your Body',
    body: 'Dive into the world of natural healing and discover the incredible potential of your body to restore and rejuvenate itself. Learn practical tips and techniques to enhance your overall well-being.',
  },
];

const FAQ = [
  ['Why are you doing this?', 'The reason why we are doing this is to build our brand, and also because we believe that by letting you try our therapy for free, some of you might choose to become our long term clients.'],
  ['How long would this promotion last?', 'Once 130 bundles have been given away, we would end this promotion. So do claim your free bundle now.'],
  ['How long is the therapy?', 'Each therapy is 20 minutes, so if you do all 3 in a day together with the acugraph analysis, it will take about 60 to 90 minutes in total.'],
  ['Will you hardsell me into anything?', 'No, we do not hardsell. This is really a free giveaway from us. Just come and enjoy and experience our therapies for free.'],
  ['Is this a scam?', 'Absolutely not. We have been in business for more than 15 years already. You can come to our outlet and try the therapy yourself.'],
  ['Is this really free?', 'Yes. It is absolutely free. No risk, no obligations, no hardsell, no catch, no gimmicks. You do not have to pay a single cent.'],
  ['Is this only for people based in Singapore?', 'Our shop is at 1 Coleman Street #B1-37, The Adelphi, Singapore 179803, near City Hall MRT. We can only do the therapy for people currently in Singapore, but you can still register to receive our e-books for free.'],
  ['How do I claim my free bundle?', 'After you register you will land on our calendar page, where you can book an appointment to come in for the therapy.'],
] as const;

const ReferralSignupPage: React.FC = () => {
  const { referralCode } = useParams();
  const [info, setInfo] = useState<any>(null);
  const [f, setF] = useState({ first: '', last: '', phone: '', email: '' });
  const [phoneValid, setPhoneValid] = useState(false);
  const [hp, setHp] = useState(''); // honeypot
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const on = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.value });

  useEffect(() => {
    supabase.rpc('public_affiliate_referral_info', { p_code: referralCode })
      .then(({ data }) => setInfo(data ?? { valid: false }));
  }, [referralCode]);

  const submit = async () => {
    setErr(null);
    if (!f.first.trim()) { setErr('Please enter your name.'); return; }
    if (!f.phone || !phoneValid) { setErr('Please enter a valid mobile/phone number.'); return; }
    setBusy(true);
    const { data, error } = await supabase.rpc('affiliate_referral_signup', {
      p_code: referralCode, p_first_name: f.first.trim(), p_last_name: f.last.trim(),
      p_phone: f.phone.trim(), p_email: f.email.trim() || null, p_honeypot: hp || null,
    });
    if (error) { setBusy(false); setErr(phoneErrorMessage(error.message)); return; }
    const res = data as any;
    if (res?.ok === false) { setBusy(false); setErr(res.message || 'Registration could not be completed.'); return; }

    // A NEW registration goes to the thank-you page, which is where the booking
    // link and the gift instructions live. Somebody already on file does not:
    // the offer is for first timers, and sending them there would tell them to
    // claim a bundle they are not entitled to. They stay here and are told that
    // nothing was changed. `busy` is deliberately left true on the redirect so
    // the button cannot be pressed twice while the browser navigates away.
    if (res?.outcome === 'already_registered') {
      setBusy(false);
      setDone(res?.message || 'You are already registered with Energia. Nothing was changed.');
      return;
    }
    window.location.href = THANK_YOU_URL;
  };

  const Shell: React.FC<{ children: React.ReactNode }> = ({ children }) => (
    <div className="rl-page">
      <div className="rl-wrap rl-section">
        <img className="rl-logo" src={LOGO_IMG} alt="Energia" />
        {children}
      </div>
      <p className="rl-foot">1 Coleman Street #B1-37, The Adelphi, Singapore 179803 · near City Hall MRT</p>
    </div>
  );

  if (info && !info.valid) return (
    <Shell><div className="rl-done">
      <h2>This link is not valid</h2>
      <p>Please check the link you were given, or contact Energia.</p>
    </div></Shell>
  );

  if (info && info.accepting === false) return (
    <Shell><div className="rl-done">
      <h2>Not accepting registrations</h2>
      <p>This link is not accepting new registrations right now. Please contact Energia.</p>
    </div></Shell>
  );

  if (done) return (
    <Shell><div className="rl-done">
      <h2>You are already registered</h2>
      <p>{done}</p>
      <p style={{ marginTop: 14 }}>
        <Link className="rl-link" to="/affiliate/join">Want to become an affiliate instead?</Link>
      </p>
    </div></Shell>
  );

  // The form appears twice, at the top and again at the close. Both share the
  // same state, so typing in one fills the other — but the ids must differ, or
  // the second card's labels focus the first card's inputs and jump the reader
  // back up the page.
  const renderForm = (idp: string) => (
    <div className="rl-form-card">
      <h2 className="rl-form-title">Claim My FREE Energia Giveaway Bundle <span className="rl-accent">(Worth $216)</span></h2>
      <div className="rl-row2">
        <div className="rl-field">
          <label className="rl-label" htmlFor={`${idp}-first`}>First Name <span className="rl-req">*</span></label>
          <input id={`${idp}-first`} value={f.first} onChange={on('first')} autoComplete="given-name" />
        </div>
        <div className="rl-field">
          <label className="rl-label" htmlFor={`${idp}-last`}>Last Name</label>
          <input id={`${idp}-last`} value={f.last} onChange={on('last')} autoComplete="family-name" />
        </div>
      </div>
      <div className="rl-field">
        <label className="rl-label" htmlFor={`${idp}-email`}>Email</label>
        <input id={`${idp}-email`} type="email" value={f.email} onChange={on('email')} autoComplete="email" />
      </div>
      <div className="rl-field">
        <label className="rl-label">Phone <span className="rl-req">*</span></label>
        <PhoneInput value={f.phone} onChange={(e164, valid) => { setF(s => ({ ...s, phone: e164 })); setPhoneValid(valid); }} />
      </div>
      {err && <p className="rl-error">{err}</p>}
      <button className="rl-cta" disabled={busy} onClick={submit}>
        {busy ? 'Registering…' : 'YES! I WANT THIS FREE BUNDLE'}
      </button>
      <p className="rl-cta-note">Limited slots. First come, first served.</p>
    </div>
  );

  return (
    <div className="rl-page">
      {/* ── hero ───────────────────────────────────────────────────────── */}
      <div className="rl-wrap rl-section">
        <img className="rl-logo" src={LOGO_IMG} alt="Energia" />
        <h1 className="rl-h1">
          ENERGIA’S <span className="rl-accent">FREE GIVEAWAY</span> TOTAL VALUE WORTH <span className="rl-accent">$216</span>
        </h1>
        {info?.affiliate_name && (
          <div className="rl-invited-row"><span className="rl-invited">You’ve been invited by {info.affiliate_name}</span></div>
        )}
        <p className="rl-lede">Each person who registers will get 1 Energia Giveaway Bundle.</p>
        <p className="rl-lede-soft">Offer valid only for first timers and not existing clients of Rev22 Energia.</p>
        <img className="rl-hero-img" src={HERO_IMG} alt="The Energia giveaway bundle" loading="lazy" />
        {renderForm('rl-top')}
      </div>

      {/* ── what you get ───────────────────────────────────────────────── */}
      <div className="rl-band">
        <div className="rl-wrap rl-section">
          <h2 className="rl-h2">WHAT YOU WILL GET FOR FREE</h2>
          <div className="rl-grid3">
            {INCLUDED.map(t => (
              <div className="rl-card" key={t.title}>
                <h3>{t.title}</h3>
                <p className="rl-price"><span className="rl-was">$72</span><span className="rl-now">$0</span></p>
                <p>{t.body}</p>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* ── bonuses ────────────────────────────────────────────────────── */}
      <div className="rl-wrap rl-section">
        <h2 className="rl-h2">WITH E-BOOK BONUSES</h2>
        <p className="rl-lede-soft">from Energia’s founder, Veronica Tan</p>
        <div className="rl-grid2">
          {BONUSES.map(b => (
            <div className="rl-card" key={b.tag}>
              <p className="rl-bonus-tag">{b.tag}</p>
              <h3>{b.title}</h3>
              <p>{b.body}</p>
            </div>
          ))}
        </div>
      </div>

      {/* ── faq ────────────────────────────────────────────────────────── */}
      <div className="rl-band">
        <div className="rl-wrap rl-section">
          <h2 className="rl-h2">FREQUENTLY ASKED QUESTIONS</h2>
          <div className="rl-faq">
            {FAQ.map(([q, a]) => (
              <details key={q}><summary>{q}</summary><p>{a}</p></details>
            ))}
          </div>
        </div>
      </div>

      {/* ── close ──────────────────────────────────────────────────────── */}
      <div className="rl-wrap rl-section">
        <h2 className="rl-h2">READY TO EXPERIENCE OUR THERAPY FOR FREE?</h2>
        {renderForm('rl-end')}
        <p className="rl-cta-note" style={{ marginTop: 18 }}>
          <Link className="rl-link" to="/affiliate/join">Want to become an affiliate instead?</Link>
        </p>
      </div>

      {/* Honeypot: hidden from real users, once for the page. */}
      <input tabIndex={-1} autoComplete="off" value={hp} onChange={e => setHp(e.target.value)}
        style={{ position: 'absolute', left: '-9999px', width: 1, height: 1 }} aria-hidden="true" />

      <p className="rl-foot">1 Coleman Street #B1-37, The Adelphi, Singapore 179803 · near City Hall MRT</p>
    </div>
  );
};
export default ReferralSignupPage;
