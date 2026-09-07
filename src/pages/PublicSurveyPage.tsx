import React, { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { HealthSymptomOption } from '../types';
import SignaturePad from '../components/SignaturePad';
import PhoneInput from '../components/PhoneInput';
import LeaveFormDialog from '../components/survey/LeaveFormDialog';
import { useNavigationGuard } from '../hooks/useNavigationGuard';
import {
  FIELD_ORDER, makeInitialForm, parseDob, isSurveyDirty, validateSurvey, mapServerError,
  type SurveyField, type SurveyFormState,
} from '../lib/survey/form.mjs';
import { Leaf, CheckCircle2, AlertTriangle, RefreshCw } from 'lucide-react';
import '../styles/survey.css';

const sgToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' });

// Category order as printed on the form.
const CATS = ['Pain', 'Sleep', 'Stress', 'Immune System & Other Health Issues'];
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

// Defer to after the DOM has painted the new error, then scroll/focus it.
const afterPaint = (cb: () => void) => {
  if (typeof window !== 'undefined' && typeof window.requestAnimationFrame === 'function') {
    window.requestAnimationFrame(cb);
  } else {
    setTimeout(cb, 0);
  }
};

const prefersReducedMotion = () =>
  typeof window !== 'undefined' && typeof window.matchMedia === 'function'
    ? window.matchMedia('(prefers-reduced-motion: reduce)').matches
    : false;

const Label: React.FC<{
  htmlFor?: string;
  id?: string;
  required?: boolean;
  optional?: boolean;
  children: React.ReactNode;
}> = ({ htmlFor, id, required, optional, children }) => (
  <label htmlFor={htmlFor} id={id}>
    {children}
    {required && (
      <>
        <span className="survey-req" aria-hidden="true">*</span>
        <span className="survey-sr-only"> (required)</span>
      </>
    )}
    {optional && <span className="survey-optional">(optional)</span>}
  </label>
);

const FieldError: React.FC<{ id: string; message?: string }> = ({ id, message }) =>
  message ? (
    <p id={id} className="survey-field-error">
      <AlertTriangle size={13} aria-hidden="true" />
      {message}
    </p>
  ) : null;

const YesNo: React.FC<{ label: string; value: boolean | null; onChange: (v: boolean) => void }> = ({ label, value, onChange }) => {
  const labelId = useId();
  return (
    <div className="survey-yesno" role="group" aria-labelledby={labelId}>
      <span id={labelId}>{label}</span>
      <span className="survey-yesno-btns">
        <button type="button" aria-pressed={value === true}
          className={`btn btn-sm ${value === true ? 'btn-primary' : 'btn-secondary'}`}
          onClick={() => onChange(true)}>Yes</button>
        <button type="button" aria-pressed={value === false}
          className={`btn btn-sm ${value === false ? 'btn-primary' : 'btn-secondary'}`}
          onClick={() => onChange(false)}>No</button>
      </span>
    </div>
  );
};

const PublicSurveyPage: React.FC = () => {
  const { token = '' } = useParams();
  const [link, setLink] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [options, setOptions] = useState<HealthSymptomOption[]>([]);
  const [sourceOptions, setSourceOptions] = useState<{ id: string; label: string; requires_details: boolean }[]>([]);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);

  // "Today" is an initial value — captured once so it never reads as an edit.
  const initialSignedDate = useMemo(() => sgToday(), []);
  const initialForm = useMemo(() => makeInitialForm(initialSignedDate), [initialSignedDate]);
  const [f, setF] = useState<SurveyFormState>(() => makeInitialForm(initialSignedDate));

  // Day / month / year are chosen separately: a native date picker is awkward
  // on a phone for a date of birth decades in the past.
  const [dob, setDob] = useState({ d: '', m: '', y: '' });
  const dobResult = useMemo(() => parseDob(dob), [dob]);

  const [phoneValid, setPhoneValid] = useState(false);
  const [phoneTouched, setPhoneTouched] = useState(false);
  const [ticks, setTicks] = useState<Record<string, { on: boolean; duration: string }>>({});

  const [errors, setErrors] = useState<Partial<Record<SurveyField, string>>>({});
  const [serverKeys, setServerKeys] = useState<SurveyField[]>([]);
  const [submitAttempted, setSubmitAttempted] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [identityError, setIdentityError] = useState<string | null>(null);
  const [leaveOpen, setLeaveOpen] = useState(false);
  const skipFirstEdit = useRef(true);

  const fieldRefs = useRef<Partial<Record<SurveyField, HTMLElement | null>>>({});
  const identityAlertRef = useRef<HTMLDivElement>(null);
  const formErrorRef = useRef<HTMLDivElement>(null);
  const registerField = (name: SurveyField) => (el: HTMLElement | null) => { fieldRefs.current[name] = el; };

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

  // Date of birth drives the ISO value and the (still editable) age. An
  // impossible date stays out of the payload — it is never rolled forward.
  useEffect(() => {
    setF(prev => {
      let age = prev.age;
      if (dobResult.status === 'valid') {
        const d = new Date(dobResult.iso + 'T00:00:00');
        const now = new Date();
        let a = now.getFullYear() - d.getFullYear();
        const mm = now.getMonth() - d.getMonth();
        if (mm < 0 || (mm === 0 && now.getDate() < d.getDate())) a--;
        if (a >= 0 && a < 130) age = String(a);
      } else if (dobResult.status === 'empty') {
        age = '';
      }
      if (prev.date_of_birth === dobResult.iso && prev.age === age) return prev;
      return { ...prev, date_of_birth: dobResult.iso, age };
    });
  }, [dobResult]);

  const byCat = useMemo(() => {
    const m: Record<string, HealthSymptomOption[]> = {};
    options.forEach(o => { (m[o.category] ||= []).push(o); });
    return m;
  }, [options]);

  const toggle = (id: string) => setTicks(t => ({ ...t, [id]: { on: !t[id]?.on, duration: t[id]?.duration ?? '' } }));
  const setDur = (id: string, d: string) => setTicks(t => ({ ...t, [id]: { on: t[id]?.on ?? true, duration: d } }));

  // When the QR link carries an Event, the source is known — the customer came
  // through that event. The question is skipped and the submission auto-uses the
  // Roadshow/Event source with the event name as details.
  const eventSource = link?.event_name
    ? sourceOptions.find(o => /event|roadshow/i.test(o.label))
    : undefined;
  const effSourceId = eventSource?.id ?? f.source_option_id;
  const effSourceDetails = eventSource ? String(link.event_name) : f.source_details;
  const selectedSource = sourceOptions.find(o => o.id === f.source_option_id);

  // ---- Unsaved‑changes protection -------------------------------------
  const dirty = useMemo(
    () => isSurveyDirty({ form: f, dob, ticks, phoneTouched }, initialForm),
    [f, dob, ticks, phoneTouched, initialForm],
  );
  const guardActive = done === null && (dirty || busy);
  const onBlockedPop = useCallback(() => setLeaveOpen(true), []);
  const { confirmLeave } = useNavigationGuard({ when: guardActive, onBlockedPop });

  useEffect(() => { if (!guardActive) setLeaveOpen(false); }, [guardActive]);

  const onDialogStay = useCallback(() => setLeaveOpen(false), []);
  const onDialogLeave = useCallback(() => { setLeaveOpen(false); confirmLeave(); }, [confirmLeave]);

  // ---- Validation ----------------------------------------------------
  const requireSource = !eventSource;
  const sourceRequiresDetails = !!selectedSource?.requires_details;
  const validateNow = useCallback((): Partial<Record<SurveyField, string>> => validateSurvey({
    form: f,
    dob: dobResult,
    phoneValid,
    requireSource,
    sourceRequiresDetails,
  }), [f, dobResult, phoneValid, requireSource, sourceRequiresDetails]);

  // After the first attempt, keep inline messages in step as answers change —
  // without ever scrolling or moving focus while the customer types. Server‑
  // reported field errors are carried until that field is next edited. Bails out
  // when nothing changed so this never feeds back into itself.
  useEffect(() => {
    if (!submitAttempted) return;
    setErrors(prev => {
      const next = validateNow();
      for (const k of serverKeys) if (!next[k] && prev[k]) next[k] = prev[k];
      const keys = new Set([...Object.keys(prev), ...Object.keys(next)]);
      let same = true;
      keys.forEach(k => { if (prev[k as SurveyField] !== next[k as SurveyField]) same = false; });
      return same ? prev : next;
    });
  }, [submitAttempted, validateNow, serverKeys]);

  // Any edit dismisses server / network messages from the previous attempt.
  useEffect(() => {
    if (skipFirstEdit.current) { skipFirstEdit.current = false; return; }
    setServerKeys(k => (k.length ? [] : k));
    setIdentityError(p => (p ? null : p));
    setFormError(p => (p ? null : p));
  }, [f, dob]);

  const scrollTo = (el: HTMLElement | null) => {
    if (!el) return;
    el.scrollIntoView({ behavior: prefersReducedMotion() ? 'auto' : 'smooth', block: 'center' });
  };

  const focusField = (name: SurveyField) => {
    const el = fieldRefs.current[name];
    if (!el) return;
    scrollTo(el);
    // Prefer the primary control: a text/number input (the phone number field,
    // not its country <select>), otherwise a select/textarea, otherwise the
    // focusable group itself (the signature area).
    const target = el.matches('input, select, textarea')
      ? el
      : (el.querySelector<HTMLElement>('input:not([type="hidden"]), [tabindex]')
        ?? el.querySelector<HTMLElement>('select, textarea')
        ?? el);
    try { target.focus({ preventScroll: true }); } catch { target.focus(); }
  };

  const handleServerError = (raw: string) => {
    const mapped = mapServerError(raw);
    if (mapped.field) {
      const fld = mapped.field;
      setErrors(prev => ({ ...prev, [fld]: mapped.message }));
      setServerKeys(k => (k.includes(fld) ? k : [...k, fld]));
      focusField(fld);
    } else if (mapped.scope === 'identity') {
      setIdentityError(mapped.message);
      afterPaint(() => { scrollTo(identityAlertRef.current); identityAlertRef.current?.focus(); });
    } else {
      setFormError(mapped.message);
      afterPaint(() => { scrollTo(formErrorRef.current); formErrorRef.current?.focus(); });
    }
  };

  const submit = async () => {
    if (busy) return;
    setSubmitAttempted(true);
    setFormError(null);
    setIdentityError(null);

    const localErrors = validateNow();
    setErrors(localErrors);
    const firstBad = FIELD_ORDER.find(k => localErrors[k]);
    if (firstBad) { focusField(firstBad); return; }

    const fullName = [f.first_name.trim(), f.last_name.trim()].filter(Boolean).join(' ');
    const symptoms = Object.entries(ticks).filter(([, v]) => v.on)
      .map(([id, v]) => ({ option_id: id, duration_text: v.duration }));

    setBusy(true);

    // Build the signed PDF in the browser and send it with the submission, so
    // the signed record is frozen exactly as the customer saw it. Loaded on
    // demand to keep the form light on mobile data. A PDF failure never blocks.
    let pdf: string | null = null;
    try {
      const { buildSurveyPdf } = await import('../lib/surveyPdf');
      pdf = buildSurveyPdf({
        store_name: link.store_name,
        event_name: f.event_name || link.event_name,
        full_name: fullName,
        date_of_birth: f.date_of_birth,
        age: f.age,
        sex: f.sex,
        phone: f.phone,
        email: f.email,
        occupation: f.occupation,
        source_label: sourceOptions.find(o => o.id === effSourceId)?.label ?? null,
        source_details: effSourceDetails,
        has_medical_condition: f.has_medical_condition,
        drinks_alcohol: f.drinks_alcohol,
        smokes: f.smokes,
        on_treatment: f.on_treatment,
        treatment_list: f.treatment_list,
        others_text: f.others_text,
        consent_newsletter_email: f.consent_newsletter_email,
        consent_marketing_email: f.consent_marketing_email,
        consent_marketing_sms: f.consent_marketing_sms,
        consent_marketing_phone: f.consent_marketing_phone,
        signature_data: f.signature_data,
        signed_date: f.signed_date,
        symptoms: Object.entries(ticks).filter(([, v]) => v.on).map(([id, v]) => {
          const o = options.find(x => x.id === id)!;
          return { category: o.category, label: o.label, duration_text: v.duration };
        }),
      });
    } catch {
      pdf = null;
    }

    try {
      const { data, error } = await supabase.rpc('submit_health_survey', {
        p_token: token,
        p_payload: {
          ...f,
          full_name: fullName,
          source_option_id: effSourceId,
          source_details: effSourceDetails,
          device_info: navigator.userAgent?.slice(0, 250) ?? null,
        },
        p_symptoms: symptoms,
        p_pdf_base64: pdf,
      });
      if (error) {
        handleServerError(error.message);
        return;
      }
      setDone((data as any)?.survey_no ?? '');
    } catch {
      setFormError(
        'We could not reach the server. Please check your connection and try again — '
        + 'your answers are still here.',
      );
      afterPaint(() => { scrollTo(formErrorRef.current); formErrorRef.current?.focus(); });
    } finally {
      setBusy(false);
    }
  };

  const shell = (children: React.ReactNode) => (
    <div className="survey-page">
      <div className="survey-shell">{children}</div>
    </div>
  );

  if (loading) return shell(
    <div className="card" style={{ padding: 40, textAlign: 'center' }}>
      <RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} aria-label="Loading" />
    </div>
  );

  if (!link?.valid) return shell(
    <div className="card" style={{ padding: 32, textAlign: 'center' }}>
      <AlertTriangle size={32} style={{ color: 'var(--danger)' }} aria-hidden="true" />
      <h3 style={{ marginTop: 12 }}>Survey unavailable</h3>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginTop: 6 }}>{link?.reason ?? 'This link is not valid.'}</p>
    </div>
  );

  if (done !== null) return shell(
    <div className="card" style={{ padding: 32, textAlign: 'center' }}>
      <CheckCircle2 size={40} style={{ color: 'var(--success)' }} aria-hidden="true" />
      <h3 style={{ marginTop: 12 }}>Thank you!</h3>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginTop: 6 }}>
        Your New Customer Form has been received.{done ? <> Your reference is <strong>{done}</strong>.</> : null}
      </p>
      <p style={{ color: 'var(--text-muted)', fontSize: 12.5, marginTop: 10 }}>Please hand the device back to our consultant.</p>
    </div>
  );

  const errorCount = Object.keys(errors).length;

  return shell(
    <form
      className="card"
      style={{ padding: '24px 20px' }}
      noValidate
      onSubmit={e => { e.preventDefault(); void submit(); }}
    >
      {/* Header */}
      <div style={{ textAlign: 'center', marginBottom: 18 }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, color: 'var(--primary)' }}>
          <Leaf size={22} aria-hidden="true" /><span style={{ fontWeight: 800, fontSize: 20 }}>energia</span>
        </div>
        <h2 style={{ margin: '8px 0 2px', fontSize: 18 }}>New Customer Form</h2>
        <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
          {link.store_name}{link.event_name ? ` · ${link.event_name}` : ''}
        </div>
        <div style={{ fontSize: 12.5, color: 'var(--text-secondary)', marginTop: 6 }}>
          Welcome to Energia. Please complete this form so our consultant can understand your wellness needs.
        </div>
        <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 8 }}>
          Fields marked <span className="survey-req" aria-hidden="true">*</span> are required.
        </div>
      </div>

      {/* Personal details */}
      <section className="survey-section" aria-labelledby="sec-personal">
        <h3 id="sec-personal">Personal details</h3>
        <div className="survey-section-hint">How our consultant can reach you.</div>

        {identityError && (
          <div className="survey-identity-alert" role="alert" tabIndex={-1} ref={identityAlertRef}>
            <AlertTriangle size={16} aria-hidden="true" />
            <span>{identityError}</span>
          </div>
        )}

        <div className="form-grid">
          <div className="form-grid-2">
            <div className={`form-group ${errors.first_name ? 'survey-invalid' : ''}`} ref={registerField('first_name')}>
              <Label htmlFor="sv-first-name" required>First Name</Label>
              <input id="sv-first-name" autoComplete="given-name" value={f.first_name}
                aria-invalid={errors.first_name ? true : undefined}
                aria-describedby={errors.first_name ? 'err-first-name' : undefined}
                onChange={e => setF({ ...f, first_name: e.target.value })} />
              <FieldError id="err-first-name" message={errors.first_name} />
            </div>
            <div className="form-group">
              <Label htmlFor="sv-last-name" optional>Last Name</Label>
              <input id="sv-last-name" autoComplete="family-name" value={f.last_name}
                onChange={e => setF({ ...f, last_name: e.target.value })} />
            </div>
          </div>

          <div className="form-grid-2">
            <div className={`form-group ${errors.date_of_birth ? 'survey-invalid' : ''}`} ref={registerField('date_of_birth')}>
              <Label id="sv-dob-label" optional>Date of Birth</Label>
              <div className="survey-dob-row" role="group" aria-labelledby="sv-dob-label"
                aria-describedby={errors.date_of_birth ? 'err-dob' : undefined}>
                <select aria-label="Day of birth" aria-invalid={errors.date_of_birth ? true : undefined}
                  value={dob.d} onChange={e => setDob(s => ({ ...s, d: e.target.value }))}>
                  <option value="">Day</option>
                  {Array.from({ length: 31 }, (_, i) => String(i + 1)).map(d => <option key={d} value={d}>{d}</option>)}
                </select>
                <select aria-label="Month of birth" aria-invalid={errors.date_of_birth ? true : undefined}
                  value={dob.m} onChange={e => setDob(s => ({ ...s, m: e.target.value }))}>
                  <option value="">Month</option>
                  {MONTHS.map((mn, i) => <option key={mn} value={String(i + 1)}>{mn}</option>)}
                </select>
                <select aria-label="Year of birth" aria-invalid={errors.date_of_birth ? true : undefined}
                  value={dob.y} onChange={e => setDob(s => ({ ...s, y: e.target.value }))}>
                  <option value="">Year</option>
                  {Array.from({ length: 100 }, (_, i) => String(new Date().getFullYear() - i)).map(y => <option key={y} value={y}>{y}</option>)}
                </select>
              </div>
              <FieldError id="err-dob" message={errors.date_of_birth} />
            </div>
            <div className="form-group">
              <Label htmlFor="sv-age" optional>Age</Label>
              <input id="sv-age" type="number" inputMode="numeric" min={0} value={f.age}
                onChange={e => setF({ ...f, age: e.target.value })} />
            </div>
          </div>

          <div className="form-group">
            <Label id="sv-sex-label" optional>Sex</Label>
            <div className="survey-choice-row" role="group" aria-labelledby="sv-sex-label">
              {(['female', 'male'] as const).map(s => (
                <button key={s} type="button" aria-pressed={f.sex === s}
                  className={`btn btn-sm ${f.sex === s ? 'btn-primary' : 'btn-secondary'}`}
                  onClick={() => setF({ ...f, sex: s })}>
                  {s === 'female' ? 'Female' : 'Male'}
                </button>
              ))}
            </div>
          </div>

          <div className="form-grid-2">
            <div className={`form-group ${errors.phone ? 'survey-invalid' : ''}`} ref={registerField('phone')}>
              <Label htmlFor="sv-phone" required>HP No.</Label>
              <PhoneInput id="sv-phone" value={f.phone}
                onChange={(e164, valid) => {
                  setF(s => ({ ...s, phone: e164 }));
                  setPhoneValid(valid);
                  setPhoneTouched(true);
                }} />
              <FieldError id="err-phone" message={errors.phone} />
            </div>
            <div className={`form-group ${errors.email ? 'survey-invalid' : ''}`} ref={registerField('email')}>
              <Label htmlFor="sv-email" required>Email</Label>
              <input id="sv-email" type="email" inputMode="email" autoComplete="email" value={f.email}
                aria-invalid={errors.email ? true : undefined}
                aria-describedby={errors.email ? 'err-email' : undefined}
                onChange={e => setF({ ...f, email: e.target.value })} />
              <FieldError id="err-email" message={errors.email} />
            </div>
          </div>

          {!eventSource && (
            <div className={`form-group ${errors.source_option_id ? 'survey-invalid' : ''}`} ref={registerField('source_option_id')}>
              <Label htmlFor="sv-source" required>How did you hear about us?</Label>
              <select id="sv-source" value={f.source_option_id}
                aria-invalid={errors.source_option_id ? true : undefined}
                aria-describedby={errors.source_option_id ? 'err-source' : undefined}
                onChange={e => setF({ ...f, source_option_id: e.target.value, source_details: '' })}>
                <option value="">— Please choose —</option>
                {sourceOptions.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}
              </select>
              <FieldError id="err-source" message={errors.source_option_id} />
              {selectedSource?.requires_details && (
                <div className={errors.source_details ? 'survey-invalid' : ''} ref={registerField('source_details')} style={{ marginTop: 8 }}>
                  <Label htmlFor="sv-source-details" required>Please tell us more</Label>
                  <input id="sv-source-details" value={f.source_details}
                    aria-invalid={errors.source_details ? true : undefined}
                    aria-describedby={errors.source_details ? 'err-source-details' : undefined}
                    onChange={e => setF({ ...f, source_details: e.target.value })} />
                  <FieldError id="err-source-details" message={errors.source_details} />
                </div>
              )}
            </div>
          )}

          <div className="form-grid-2">
            <div className="form-group">
              <Label htmlFor="sv-occupation" optional>Occupation</Label>
              <input id="sv-occupation" autoComplete="organization-title" value={f.occupation}
                onChange={e => setF({ ...f, occupation: e.target.value })} />
            </div>
            {!link.event_name && (
              <div className="form-group">
                <Label htmlFor="sv-event" optional>Event</Label>
                <input id="sv-event" value={f.event_name} placeholder="Optional"
                  onChange={e => setF({ ...f, event_name: e.target.value })} />
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Health information */}
      <section className="survey-section" aria-labelledby="sec-health">
        <h3 id="sec-health">Health information</h3>
        <div className="survey-section-hint">Please answer Yes or No.</div>
        <YesNo label="Do you have any medical or physical condition to declare?" value={f.has_medical_condition} onChange={v => setF({ ...f, has_medical_condition: v })} />
        <YesNo label="Do you drink alcohol?" value={f.drinks_alcohol} onChange={v => setF({ ...f, drinks_alcohol: v })} />
        <YesNo label="Do you smoke?" value={f.smokes} onChange={v => setF({ ...f, smokes: v })} />
        <YesNo label="Are you now taking any medical / physiotherapy treatment or medicine / pain killer?" value={f.on_treatment} onChange={v => setF({ ...f, on_treatment: v })} />
        {f.on_treatment && (
          <div className="form-group" style={{ marginTop: 12 }}>
            <Label htmlFor="sv-treatment" optional>If Yes, please list</Label>
            <input id="sv-treatment" value={f.treatment_list} onChange={e => setF({ ...f, treatment_list: e.target.value })} />
          </div>
        )}
      </section>

      {/* Symptoms & duration */}
      <section className="survey-section" aria-labelledby="sec-symptoms">
        <h3 id="sec-symptoms">Symptoms &amp; duration</h3>
        <div className="survey-section-hint">Tick any that apply, then note how long you&apos;ve had it. All optional.</div>
        {options.length === 0 && !loading && (
          <div className="alert alert-warning" style={{ marginBottom: 10 }}>
            <span aria-hidden="true">⚠</span>
            <div>The symptom checklist could not be loaded, so it is not shown below.
              Please describe any symptoms in &quot;Others&quot; instead, and let us know so we can fix it.</div>
          </div>
        )}
        {CATS.filter(c => byCat[c]?.length).map(cat => (
          <div key={cat} className="survey-symptom-cat">
            <h4>{cat}</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              {byCat[cat].map(o => {
                const t = ticks[o.id];
                return (
                  <div key={o.id} className="survey-symptom-row">
                    <label>
                      <input type="checkbox" checked={!!t?.on} onChange={() => toggle(o.id)} />
                      <span>{o.label}</span>
                    </label>
                    {t?.on && (
                      <input className="survey-duration" value={t.duration}
                        aria-label={`How long have you had: ${o.label}`}
                        onChange={e => setDur(o.id, e.target.value)} placeholder="Duration (e.g. 2 weeks)" />
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        ))}
        <div className="form-group" style={{ marginTop: 6 }}>
          <Label htmlFor="sv-others" optional>Others (please indicate)</Label>
          <input id="sv-others" value={f.others_text} onChange={e => setF({ ...f, others_text: e.target.value })} />
        </div>
      </section>

      {/* Privacy & consent */}
      <section className="survey-section" aria-labelledby="sec-privacy">
        <h3 id="sec-privacy">Privacy &amp; consent</h3>

        {/* Note — verbatim from the printed form */}
        <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 12, fontSize: 12.5, marginBottom: 12 }}>
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

          <div style={{ fontSize: 12.5, marginBottom: 2 }}>1. Our organisation&apos;s monthly Newsletter via the following channel:</div>
          <label className="survey-consent">
            <input type="checkbox" checked={f.consent_newsletter_email} onChange={e => setF({ ...f, consent_newsletter_email: e.target.checked })} />
            <span>Email</span>
          </label>

          <div style={{ fontSize: 12.5, marginTop: 8, marginBottom: 2 }}>
            2. Information sent by our organisation about our organisation&apos;s products and services, including updates on
            our latest promotions and new products and services, via the following channels:
          </div>
          <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap' }}>
            {([['consent_marketing_email', 'Email'], ['consent_marketing_sms', 'Text Message'], ['consent_marketing_phone', 'Phone Call']] as const).map(([k, lbl]) => (
              <label key={k} className="survey-consent">
                <input type="checkbox" checked={f[k]} onChange={e => setF({ ...f, [k]: e.target.checked })} />
                <span>{lbl}</span>
              </label>
            ))}
          </div>
        </div>
      </section>

      {/* Signature & submission */}
      <section className="survey-section" aria-labelledby="sec-sign">
        <h3 id="sec-sign">Signature &amp; submission</h3>
        <div className="form-grid">
          <div className="form-grid-2">
            <div
              className={`form-group survey-signature-group ${errors.signature_data ? 'survey-invalid' : ''}`}
              ref={registerField('signature_data')}
              tabIndex={-1}
              role="group"
              aria-labelledby="sv-sign-label"
              aria-describedby={errors.signature_data ? 'err-sign' : 'sv-sign-hint'}
            >
              <Label id="sv-sign-label" required>Signature</Label>
              <div id="sv-sign-hint" className="survey-section-hint" style={{ marginBottom: 6 }}>
                Use your finger or mouse to sign in the box.
              </div>
              <SignaturePad value={f.signature_data} onChange={v => setF({ ...f, signature_data: v })} />
              <FieldError id="err-sign" message={errors.signature_data} />
            </div>
            <div className="form-group">
              <Label htmlFor="sv-signed-date" optional>Date</Label>
              <input id="sv-signed-date" type="date" value={f.signed_date}
                onChange={e => setF({ ...f, signed_date: e.target.value })} />
            </div>
          </div>

          {submitAttempted && errorCount > 0 && (
            <div className="survey-error-summary" role="alert" aria-live="assertive">
              <AlertTriangle size={16} aria-hidden="true" />
              <span>
                Please fix the {errorCount === 1 ? 'highlighted field' : `${errorCount} highlighted fields`} above,
                then submit again.
              </span>
            </div>
          )}

          {formError && (
            <div className="survey-form-error" role="alert" tabIndex={-1} ref={formErrorRef}>
              <AlertTriangle size={16} aria-hidden="true" />
              <span>{formError}</span>
            </div>
          )}

          <button type="submit" className="btn btn-primary survey-submit" disabled={busy} aria-busy={busy}>
            {busy ? 'Submitting…' : 'Submit Survey'}
          </button>
          {busy && (
            <div className="survey-submitting-note" aria-live="polite">
              Sending your form — please keep this page open.
            </div>
          )}
          <div style={{ fontSize: 11, color: 'var(--text-muted)', textAlign: 'center' }}>
            Rev 22 Pte Ltd · Your information is kept confidential and used only as described above.
          </div>
        </div>
      </section>

      <LeaveFormDialog open={leaveOpen} submitting={busy} onStay={onDialogStay} onLeave={onDialogLeave} />
    </form>
  );
};

export default PublicSurveyPage;
