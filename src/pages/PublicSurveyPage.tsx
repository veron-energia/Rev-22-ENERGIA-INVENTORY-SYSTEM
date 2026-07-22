import React, { useEffect, useState, useMemo } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { HealthSymptomOption } from '../types';
import SignaturePad from '../components/SignaturePad';
import { Leaf, CheckCircle2, AlertTriangle, RefreshCw } from 'lucide-react';

const sgToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' });

// Category order as printed on the form.
const CATS = ['Pain', 'Sleep', 'Stress', 'Immune System & Other Health Issues'];

const YesNo: React.FC<{ label: string; value: boolean | null; onChange: (v: boolean) => void }> = ({ label, value, onChange }) => (
  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, padding: '8px 0', borderBottom: '1px solid var(--border)' }}>
    <span style={{ fontSize: 13.5, flex: 1 }}>{label}</span>
    <span style={{ display: 'flex', gap: 6, flexShrink: 0 }}>
      <button type="button" className={`btn btn-sm ${value === true ? 'btn-primary' : 'btn-secondary'}`} onClick={() => onChange(true)}>Yes</button>
      <button type="button" className={`btn btn-sm ${value === false ? 'btn-primary' : 'btn-secondary'}`} onClick={() => onChange(false)}>No</button>
    </span>
  </div>
);

const PublicSurveyPage: React.FC = () => {
  const { token = '' } = useParams();
  const [link, setLink] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [options, setOptions] = useState<HealthSymptomOption[]>([]);
  const [sourceOptions, setSourceOptions] = useState<{ id: string; label: string; requires_details: boolean }[]>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);

  const [f, setF] = useState<any>({
    full_name: '', date_of_birth: '', age: '', sex: '', phone: '', email: '', occupation: '',
    source_option_id: '', source_details: '',
    event_name: '',
    has_medical_condition: null, drinks_alcohol: null, smokes: null, on_treatment: null,
    treatment_list: '', others_text: '',
    consent_newsletter_email: false, consent_marketing_email: false,
    consent_marketing_sms: false, consent_marketing_phone: false,
    signature_data: '', signed_date: sgToday(),
  });
  const [ticks, setTicks] = useState<Record<string, { on: boolean; duration: string }>>({});

  useEffect(() => {
    (async () => {
      const [info, opts, srcs] = await Promise.all([
        supabase.rpc('survey_link_info', { p_token: token }),
        supabase.from('health_symptom_options').select('*').eq('is_active', true).order('sort_order'),
        supabase.rpc('active_customer_source_options'),
      ]);
      setLink(info.data ?? { valid: false, reason: 'This survey link could not be checked.' });
      setOptions((opts.data as HealthSymptomOption[]) ?? []);
      setSourceOptions((srcs.data as { id: string; label: string; requires_details: boolean }[]) ?? []);
      setLoading(false);
    })();
  }, [token]);

  // Age follows date of birth, but stays editable.
  useEffect(() => {
    if (!f.date_of_birth) return;
    const d = new Date(f.date_of_birth);
    if (isNaN(d.getTime())) return;
    const now = new Date();
    let a = now.getFullYear() - d.getFullYear();
    const m = now.getMonth() - d.getMonth();
    if (m < 0 || (m === 0 && now.getDate() < d.getDate())) a--;
    if (a >= 0 && a < 130) setF((x: any) => ({ ...x, age: String(a) }));
  }, [f.date_of_birth]);

  const byCat = useMemo(() => {
    const m: Record<string, HealthSymptomOption[]> = {};
    options.forEach(o => { (m[o.category] ||= []).push(o); });
    return m;
  }, [options]);

  const toggle = (id: string) => setTicks(t => ({ ...t, [id]: { on: !t[id]?.on, duration: t[id]?.duration ?? '' } }));
  const setDur = (id: string, d: string) => setTicks(t => ({ ...t, [id]: { on: t[id]?.on ?? true, duration: d } }));

  // When the QR link carries an Event, the source is known — the customer
  // came through that event. The question is skipped and the submission
  // auto-uses the Roadshow/Event source with the event name as details.
  const eventSource = link?.event_name
    ? sourceOptions.find(o => /event|roadshow/i.test(o.label))
    : undefined;
  const effSourceId = eventSource?.id ?? f.source_option_id;
  const effSourceDetails = eventSource ? String(link.event_name) : f.source_details;

  const submit = async () => {
    setErr(null);
    if (!f.full_name.trim()) { setErr('Please enter your name.'); return; }
    if (!f.phone.trim()) { setErr('Please enter your mobile number.'); return; }
    if (!f.email.trim()) { setErr('Please enter your email address.'); return; }
    if (!eventSource) {
      if (!f.source_option_id) { setErr('Please tell us how you heard about us.'); return; }
      const srcOpt = sourceOptions.find(o => o.id === f.source_option_id);
      if (srcOpt?.requires_details && !f.source_details.trim()) { setErr(`Please add a few details for "${srcOpt.label}".`); return; }
    }
    if (!f.signature_data) { setErr('Please sign in the signature box.'); return; }

    const symptoms = Object.entries(ticks).filter(([, v]) => v.on)
      .map(([id, v]) => ({ option_id: id, duration_text: v.duration }));

    setBusy(true);

    // Build the signed PDF in the browser and send it with the submission,
    // so the signed record is frozen exactly as the customer saw it.
    // Loaded on demand to keep the form light on mobile data.
    let pdf: string | null = null;
    try {
      const { buildSurveyPdf } = await import('../lib/surveyPdf');
      pdf = buildSurveyPdf({
        store_name: link.store_name,
        event_name: f.event_name || link.event_name,
        ...f,
        source_option_id: effSourceId, source_details: effSourceDetails,
        source_label: sourceOptions.find(o => o.id === effSourceId)?.label ?? null,
        symptoms: Object.entries(ticks).filter(([, v]) => v.on).map(([id, v]) => {
          const o = options.find(x => x.id === id)!;
          return { category: o.category, label: o.label, duration_text: v.duration };
        }),
      });
    } catch {
      pdf = null;   // never block a submission because the PDF failed
    }

    const { data, error } = await supabase.rpc('submit_health_survey', {
      p_token: token,
      p_payload: { ...f, source_option_id: effSourceId, source_details: effSourceDetails, device_info: navigator.userAgent?.slice(0, 250) ?? null },
      p_symptoms: symptoms,
      p_pdf_base64: pdf,
    });
    setBusy(false);
    if (error) {
      setErr(error.message.includes('DUPLICATE_PHONE')
        ? 'This mobile number is already registered with us. This form is for new customers — please speak to our staff and they will help you.'
        : error.message);
      return;
    }
    setDone((data as any)?.survey_no ?? '');
  };

  const shell = (children: React.ReactNode) => (
    <div style={{ minHeight: '100vh', background: 'var(--surface-2)', padding: '24px 16px' }}>
      <div style={{ maxWidth: 720, margin: '0 auto' }}>{children}</div>
    </div>
  );

  if (loading) return shell(<div className="card" style={{ padding: 40, textAlign: 'center' }}><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>);

  if (!link?.valid) return shell(
    <div className="card" style={{ padding: 32, textAlign: 'center' }}>
      <AlertTriangle size={32} style={{ color: 'var(--danger)' }} />
      <h3 style={{ marginTop: 12 }}>Survey unavailable</h3>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginTop: 6 }}>{link?.reason ?? 'This link is not valid.'}</p>
    </div>
  );

  if (done !== null) return shell(
    <div className="card" style={{ padding: 32, textAlign: 'center' }}>
      <CheckCircle2 size={40} style={{ color: 'var(--success)' }} />
      <h3 style={{ marginTop: 12 }}>Thank you!</h3>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginTop: 6 }}>
        Your New Customer Form has been received.{done ? <> Your reference is <strong>{done}</strong>.</> : null}
      </p>
      <p style={{ color: 'var(--text-muted)', fontSize: 12.5, marginTop: 10 }}>Please hand the device back to our consultant.</p>
    </div>
  );

  return shell(
    <div className="card" style={{ padding: '24px 20px' }}>
      {/* Header */}
      <div style={{ textAlign: 'center', marginBottom: 18 }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, color: 'var(--primary)' }}>
          <Leaf size={22} /><span style={{ fontWeight: 800, fontSize: 20 }}>energia</span>
        </div>
        <h2 style={{ margin: '8px 0 2px', fontSize: 18 }}>New Customer Form</h2>
        <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
          {link.store_name}{link.event_name ? ` · ${link.event_name}` : ''}
        </div>
        <div style={{ fontSize: 12.5, color: 'var(--text-secondary)', marginTop: 6 }}>
          Welcome to Energia. Please complete this form so our consultant can understand your wellness needs.
        </div>
      </div>

      {err && <div className="alert alert-danger" style={{ marginBottom: 14 }}><span>⚠</span><div>{err}</div></div>}

      <div className="form-grid">
        {/* Identity */}
        <div className="form-group"><label>Name *</label><input value={f.full_name} onChange={e => setF({ ...f, full_name: e.target.value })} /></div>
        <div className="form-grid-2">
          <div className="form-group"><label>Date of Birth</label><input type="date" value={f.date_of_birth} onChange={e => setF({ ...f, date_of_birth: e.target.value })} /></div>
          <div className="form-group"><label>Age</label><input type="number" min={0} value={f.age} onChange={e => setF({ ...f, age: e.target.value })} /></div>
        </div>
        <div className="form-group">
          <label>Sex</label>
          <div style={{ display: 'flex', gap: 6 }}>
            {(['female', 'male'] as const).map(s => (
              <button key={s} type="button" className={`btn btn-sm ${f.sex === s ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setF({ ...f, sex: s })}>
                {s === 'female' ? 'Female' : 'Male'}
              </button>
            ))}
          </div>
        </div>
        <div className="form-grid-2">
          <div className="form-group"><label>HP No. *</label><input value={f.phone} onChange={e => setF({ ...f, phone: e.target.value })} inputMode="tel" /></div>
          <div className="form-group"><label>Email *</label><input type="email" value={f.email} onChange={e => setF({ ...f, email: e.target.value })} required /></div>
        </div>
        {!eventSource && (
          <div className="form-group">
            <label>How did you hear about us? *</label>
            <select value={f.source_option_id} onChange={e => setF({ ...f, source_option_id: e.target.value, source_details: '' })} required>
              <option value="">— Please choose —</option>
              {sourceOptions.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}
            </select>
            {sourceOptions.find(o => o.id === f.source_option_id)?.requires_details && (
              <input style={{ marginTop: 6 }} placeholder="Please tell us more *" value={f.source_details}
                onChange={e => setF({ ...f, source_details: e.target.value })} required />
            )}
          </div>
        )}
        <div className="form-grid-2">
          <div className="form-group"><label>Occupation</label><input value={f.occupation} onChange={e => setF({ ...f, occupation: e.target.value })} /></div>
          {!link.event_name && <div className="form-group"><label>Event</label><input value={f.event_name} onChange={e => setF({ ...f, event_name: e.target.value })} placeholder="Optional" /></div>}
        </div>

        {/* Declarations */}
        <div>
          <YesNo label="Do you have any medical or physical condition to declare?" value={f.has_medical_condition} onChange={v => setF({ ...f, has_medical_condition: v })} />
          <YesNo label="Do you drink alcohol?" value={f.drinks_alcohol} onChange={v => setF({ ...f, drinks_alcohol: v })} />
          <YesNo label="Do you smoke?" value={f.smokes} onChange={v => setF({ ...f, smokes: v })} />
          <YesNo label="Are you now taking any medical / physiotherapy treatment or medicine / pain killer?" value={f.on_treatment} onChange={v => setF({ ...f, on_treatment: v })} />
        </div>
        {f.on_treatment && (
          <div className="form-group"><label>If Yes, please list</label><input value={f.treatment_list} onChange={e => setF({ ...f, treatment_list: e.target.value })} /></div>
        )}

        {/* Symptoms */}
        <div>
          <label>Do you have the following symptoms or conditions? (Please tick)</label>
          <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 8 }}>Tick any that apply, then note how long you've had it.</div>
          {CATS.filter(c => byCat[c]?.length).map(cat => (
            <div key={cat} style={{ marginBottom: 14 }}>
              <div style={{ fontWeight: 700, fontSize: 13, borderBottom: '1px solid var(--border)', paddingBottom: 4, marginBottom: 6 }}>{cat}</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {byCat[cat].map(o => {
                  const t = ticks[o.id];
                  return (
                    <div key={o.id} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <label style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1, cursor: 'pointer', fontSize: 13 }}>
                        <input type="checkbox" checked={!!t?.on} onChange={() => toggle(o.id)} style={{ width: 'auto' }} />
                        <span>{o.label}</span>
                      </label>
                      {t?.on && (
                        <input value={t.duration} onChange={e => setDur(o.id, e.target.value)}
                          placeholder="Duration" style={{ width: 130, fontSize: 12.5, padding: '4px 8px' }} />
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
          <div className="form-group"><label>Others (please indicate)</label><input value={f.others_text} onChange={e => setF({ ...f, others_text: e.target.value })} /></div>
        </div>

        {/* Note — verbatim from the printed form */}
        <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 12, fontSize: 12.5 }}>
          <strong>Note:</strong> The Health &amp; Wellness Analysis is NOT a diagnostic health procedure but serves only
          as a guide to the observation of an individual state of health.
          <div style={{ color: 'var(--danger)', marginTop: 4 }}>
            It is not recommended for any one with <u>electronic heart pacemaker</u> or <u>a pregnant woman</u>.
          </div>
        </div>

        {/* Privacy Policy — verbatim from the printed form */}
        <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 12 }}>
          <div style={{ fontWeight: 700, fontSize: 13, marginBottom: 6 }}>Privacy Policy</div>
          <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
            You agree that <strong>Rev 22 Pte Ltd</strong> may collect, use and disclose your personal data, which you
            have provided in this form, for providing marketing material that you have agreed to receive, in accordance
            with the Personal Data Protection Act 2012.
          </div>
          <div style={{ fontSize: 12.5, marginTop: 8, marginBottom: 6 }}>Please tick the relevant boxes below if you agree to receive the following:</div>

          <div style={{ fontSize: 12.5, marginBottom: 4 }}>1. Our organisation's monthly Newsletter via the following channel:</div>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, marginBottom: 10, cursor: 'pointer' }}>
            <input type="checkbox" checked={f.consent_newsletter_email} onChange={e => setF({ ...f, consent_newsletter_email: e.target.checked })} style={{ width: 'auto' }} />
            <span>Email</span>
          </label>

          <div style={{ fontSize: 12.5, marginBottom: 4 }}>
            2. Information sent by our organisation about our organisation's products and services, including updates on
            our latest promotions and new products and services, via the following channels:
          </div>
          <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
            {([['consent_marketing_email', 'Email'], ['consent_marketing_sms', 'Text Message'], ['consent_marketing_phone', 'Phone Call']] as const).map(([k, lbl]) => (
              <label key={k} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer' }}>
                <input type="checkbox" checked={f[k]} onChange={e => setF({ ...f, [k]: e.target.checked })} style={{ width: 'auto' }} />
                <span>{lbl}</span>
              </label>
            ))}
          </div>
        </div>

        {/* Signature */}
        <div className="form-grid-2">
          <div className="form-group">
            <label>Signature *</label>
            <SignaturePad value={f.signature_data} onChange={v => setF({ ...f, signature_data: v })} />
          </div>
          <div className="form-group"><label>Date</label><input type="date" value={f.signed_date} onChange={e => setF({ ...f, signed_date: e.target.value })} /></div>
        </div>

        <button className="btn btn-primary" onClick={submit} disabled={busy} style={{ padding: '12px', fontSize: 15 }}>
          {busy ? 'Submitting…' : 'Submit Survey'}
        </button>
        <div style={{ fontSize: 11, color: 'var(--text-muted)', textAlign: 'center' }}>
          Rev 22 Pte Ltd · Your information is kept confidential and used only as described above.
        </div>
      </div>
    </div>
  );
};

export default PublicSurveyPage;
