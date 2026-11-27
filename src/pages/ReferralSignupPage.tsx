import { phoneErrorMessage } from '../lib/customer-phones/normalize.mjs';
import React, { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import PhoneInput from '../components/PhoneInput';
import { calcomCancelUrl, calcomRescheduleUrl, referralBookingUrl } from '../lib/referral/bookingLink.mjs';
import { bookingWhen } from '../lib/referral/booking.mjs';
import { REFERRAL_NOTICE_VERSION, referralNotice } from '../lib/referral/notice.mjs';
import { EMAIL_MAX, NAME_MAX, signupInputProblem } from '../lib/referral/signupInput.mjs';
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
//
// A NEW registration goes straight to the booking page (392), not to
// energia.sg/ty, with its details and the referrer filled in so the
// appointment carries the affiliate's name. Existing customers are not sent
// there: the offer is for first timers, so somebody already on file stays put
// and is told nothing changed.
//
// 484 (the Owner, 1 Nov 2026): each form card tells the person, under the
// Phone field and above the button, what the affiliate who invited them will
// see (notice.mjs), and the sign-up says which notice was shown, so the
// database records that they were told. Only then does their phone number
// show in that affiliate's My Network. It is a notice, not consent: no tick
// box and no "agree".
//
// 529 (security audit of 17 Nov 2026, M3; the user, 19 Nov 2026): the database refuses a name
// longer than 100 characters (first and last together) or with a web address, '<', '>' or control
// characters, and an email that does not look like name@domain.tld or is longer than 254
// characters. The page checks the same rule (signupInput.mjs) before it calls, so the person is
// told at once what to fix; the database stays the judge, and its own refusals (these, and the
// limits per connection, per phone and for all links together) show as its message.

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

// 549: what referral_booking_lookup answers for somebody already on file.
// 'unknown' is the page's own: a database without 549, or no answer.
type BookingAnswer = {
  state: 'none' | 'needs_email' | 'booked' | 'try_later' | 'invalid' | 'unknown';
  start_at?: string;
  uid?: string | null;
};
const BOOKING_STATES = ['none', 'needs_email', 'booked', 'try_later', 'invalid'];

const ReferralSignupPage: React.FC = () => {
  const { referralCode } = useParams();
  const [info, setInfo] = useState<any>(null);
  const [f, setF] = useState({ first: '', last: '', phone: '', email: '' });
  const [phoneValid, setPhoneValid] = useState(false);
  const [hp, setHp] = useState(''); // honeypot
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  // The link could not be checked (no answer from the server, or an error):
  // not the same as a link that is not valid (AFFILIATES-7).
  const [unreachable, setUnreachable] = useState(false);
  const [checkTick, setCheckTick] = useState(0);
  const [booking, setBooking] = useState<BookingAnswer>({ state: 'unknown' });
  const [bookingEmail, setBookingEmail] = useState('');
  const [bookingErr, setBookingErr] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);
  const on = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.value });

  // 549 (the user, 27 Nov 2026): does somebody already on file have an
  // upcoming booking? The database decides. It gives the time and the
  // booking's cal.com id only when the phone AND the email typed both match
  // the booking ("Phone + email must match"), so a stranger who knows only the
  // number cannot see or change it. A database without 549, or any failure,
  // answers 'unknown', and the screen is as it was before.
  const lookUpBooking = async (email: string): Promise<BookingAnswer> => {
    try {
      const { data, error } = await supabase.rpc('referral_booking_lookup', {
        p_code: referralCode, p_phone: f.phone.trim(), p_email: email.trim() || null,
      });
      const answer = data as BookingAnswer | null;
      if (error || !answer || !BOOKING_STATES.includes(answer.state)) return { state: 'unknown' };
      return answer;
    } catch {
      return { state: 'unknown' };
    }
  };

  // The "enter the email you booked with" box: looks again, never registers again.
  const showMyBooking = async () => {
    setBookingErr(null);
    const email = bookingEmail.trim();
    if (!email) { setBookingErr('Please enter the email you booked with.'); return; }
    setChecking(true);
    const answer = await lookUpBooking(email);
    setChecking(false);
    if (answer.state === 'booked' || answer.state === 'none') { setBooking(answer); return; }
    if (answer.state === 'needs_email') {
      setBookingErr('That email does not match the booking. Check the confirmation cal.com sent you, or contact Energia.');
      return;
    }
    if (answer.state === 'try_later') {
      setBookingErr('Too many tries. Please try again in an hour, or check the confirmation cal.com sent you.');
      return;
    }
    setBookingErr('We could not check just now. Please try again, or check the confirmation cal.com sent you.');
  };

  useEffect(() => {
    let live = true;
    setUnreachable(false);
    (async () => {
      try {
        const { data, error } = await supabase.rpc('public_affiliate_referral_info', { p_code: referralCode });
        if (!live) return;
        // Only the server's own answer says whether the link is valid.
        if (error || !data) { setUnreachable(true); return; }
        setInfo(data);
      } catch {
        if (live) setUnreachable(true);
      }
    })();
    return () => { live = false; };
  }, [referralCode, checkTick]);

  const submit = async () => {
    setErr(null);
    if (!f.first.trim()) { setErr('Please enter your name.'); return; }
    if (!f.phone || !phoneValid) { setErr('Please enter a valid mobile/phone number.'); return; }
    const args = {
      p_code: referralCode, p_first_name: f.first.trim(), p_last_name: f.last.trim(),
      p_phone: f.phone.trim(), p_email: f.email.trim() || null, p_honeypot: hp || null,
    };
    // 529: what the database would refuse, checked on what is sent.
    const problem = signupInputProblem(args.p_first_name, args.p_last_name, args.p_email);
    if (problem) { setErr(problem); return; }
    setBusy(true);
    // 484: the same six keys and the version of the notice above the button.
    // A database without this function (484 not applied yet, or undone)
    // answers PGRST202; then, and only then, the six keys go to
    // affiliate_referral_signup, which registers the person without the mark.
    let { data, error } = await supabase.rpc('affiliate_referral_signup_with_notice', { ...args, p_notice: REFERRAL_NOTICE_VERSION });
    if (error?.code === 'PGRST202') ({ data, error } = await supabase.rpc('affiliate_referral_signup', args));
    if (error) { setBusy(false); setErr(phoneErrorMessage(error.message)); return; }
    const res = data as any;
    if (res?.ok === false) { setBusy(false); setErr(res.message || 'Registration could not be completed.'); return; }

    // A NEW registration goes to the booking page with its details and the
    // referrer filled in. Somebody already on file does not: the offer is for
    // first timers, and sending them there would tell them to claim a bundle
    // they are not entitled to. They stay here and are told that nothing was
    // changed. `busy` is deliberately left true on the redirect so the button
    // cannot be pressed twice while the browser navigates away.
    if (res?.outcome === 'already_registered') {
      // 549: look for an upcoming booking before the screen changes, so it
      // shows once, whole. An email that was typed but does not match is said.
      const answer = await lookUpBooking(f.email);
      setBooking(answer);
      setBookingEmail(f.email.trim());
      setBookingErr(answer.state === 'needs_email' && f.email.trim()
        ? 'The email you typed does not match the booking. Enter the email you booked with.' : null);
      setBusy(false);
      setDone(res?.message || 'You are already registered with Energia. Nothing was changed.');
      return;
    }
    window.location.href = referralBookingUrl({
      firstName: f.first, lastName: f.last, email: f.email, phone: f.phone,
      affiliateLabel: res?.affiliate_label,
    });
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

  if (unreachable && !info) return (
    <Shell><div className="rl-done" data-state="unreachable">
      <h2>We could not check this link</h2>
      <p>Please check your connection and try again.</p>
      <p style={{ marginTop: 14 }}>
        <button type="button" className="rl-cta" onClick={() => setCheckTick(t => t + 1)}>Try again</button>
      </p>
    </div></Shell>
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

  // Somebody already on file (the user, 27 Nov 2026), by what 549 answers:
  // - booked (phone AND email match an upcoming booking): its Singapore date and
  //   time, with cal.com's own pages to change the time or cancel;
  // - needs_email (an upcoming booking, but no or another email typed): asks
  //   for the email they booked with, and shows nothing about the booking;
  // - anything else: the same booking page a new registration goes to, with
  //   what they typed filled in. No referrer label, because this answer does
  //   not say whose customer they are and the link's affiliate may not be theirs.
  const changeUrl = booking.state === 'booked' ? calcomRescheduleUrl(booking.uid) : null;
  const cancelUrl = booking.state === 'booked' ? calcomCancelUrl(booking.uid) : null;
  if (done) return (
    <Shell><div className="rl-done">
      <h2>You are already registered</h2>
      <p>{done}</p>
      <p style={{ marginTop: 14 }}>
        <Link className="rl-link" to="/affiliate/join">Want to become an affiliate instead?</Link>
      </p>
      {booking.state === 'booked' ? (
        <div style={{ marginTop: 18 }} data-booking="booked">
          <p className="rl-booking-label">Your appointment</p>
          <p className="rl-booking-when">{bookingWhen(booking.start_at) || 'Booked'}</p>
          {changeUrl ? (
            <>
              <a className="rl-cta" data-action="change-time" href={changeUrl}>Change time</a>
              {cancelUrl && (
                <p style={{ marginTop: 12 }}>
                  <a className="rl-link" data-action="cancel-booking" href={cancelUrl}>Cancel appointment</a>
                </p>
              )}
            </>
          ) : (
            <div className="rl-cta-note">To change it, please contact Energia.</div>
          )}
        </div>
      ) : booking.state === 'needs_email' ? (
        <div style={{ marginTop: 18 }} data-booking="needs-email">
          <p><strong>You already have an appointment booked.</strong></p>
          <p>To see or change it, enter the email you booked with.</p>
          <div className="rl-field" style={{ textAlign: 'left', marginTop: 12 }}>
            <label className="rl-label" htmlFor="rl-booking-email">Email you booked with</label>
            <input id="rl-booking-email" type="email" value={bookingEmail} autoComplete="email" maxLength={EMAIL_MAX}
              onChange={e => setBookingEmail(e.target.value)} />
          </div>
          {bookingErr && <p className="rl-error">{bookingErr}</p>}
          <button className="rl-cta" disabled={checking} onClick={showMyBooking}>
            {checking ? 'Checking…' : 'Show my appointment'}
          </button>
          <div className="rl-cta-note">Or check the confirmation cal.com sent you: it has your date and time, with links to reschedule or cancel.</div>
        </div>
      ) : (
        <div style={{ marginTop: 18 }}>
          <a className="rl-cta" data-action="book-first-visit"
            href={referralBookingUrl({ firstName: f.first, lastName: f.last, email: f.email, phone: f.phone })}>
            Book your first-time appointment
          </a>
          <div className="rl-cta-note">Already booked? The confirmation cal.com sent you has your date and time, with links to reschedule or cancel.</div>
        </div>
      )}
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
          <input id={`${idp}-first`} value={f.first} onChange={on('first')} autoComplete="given-name" maxLength={NAME_MAX} />
        </div>
        <div className="rl-field">
          <label className="rl-label" htmlFor={`${idp}-last`}>Last Name</label>
          <input id={`${idp}-last`} value={f.last} onChange={on('last')} autoComplete="family-name" maxLength={NAME_MAX} />
        </div>
      </div>
      <div className="rl-field">
        <label className="rl-label" htmlFor={`${idp}-email`}>Email</label>
        <input id={`${idp}-email`} type="email" value={f.email} onChange={on('email')} autoComplete="email" maxLength={EMAIL_MAX} />
      </div>
      <div className="rl-field">
        <label className="rl-label">Phone <span className="rl-req">*</span></label>
        <PhoneInput value={f.phone} onChange={(e164, valid) => { setF(s => ({ ...s, phone: e164 })); setPhoneValid(valid); }} />
      </div>
      <p className="rl-notice" id={`${idp}-notice`} data-notice={REFERRAL_NOTICE_VERSION}>{referralNotice(info?.affiliate_name)}</p>
      {err && <p className="rl-error">{err}</p>}
      <button className="rl-cta" disabled={busy} onClick={submit} aria-describedby={`${idp}-notice`}>
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
