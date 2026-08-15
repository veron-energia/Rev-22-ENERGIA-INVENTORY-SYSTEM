import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isOwnerOrManager } from '../types';
import { Modal } from './ui';
import { Download, RefreshCw, FileText, Check, Lock } from 'lucide-react';
import SurveyAttachments from './SurveyAttachments';

const d = (s?: string | null) => s ? new Date(s).toLocaleDateString('en-GB') : '—';
const yn = (v: boolean | null | undefined) => v === true ? 'Yes' : v === false ? 'No' : '—';

const ACIDITY: { v: 'red' | 'green' | 'blue'; label: string; color: string }[] = [
  { v: 'red', label: 'Red', color: '#dc2626' },
  { v: 'green', label: 'Green', color: '#16a34a' },
  { v: 'blue', label: 'Blue', color: '#2563eb' },
];

const SurveyDetailModal: React.FC<{ surveyId: string; onClose: () => void; onSaved: () => void }> = ({ surveyId, onClose, onSaved }) => {
  const { profile } = useAuth();
  // Staff (and Admin) may SEE the consultant section but not edit it.
  // Staff may correct a submission (migration 122) — they are the ones sitting
  // with the customer when a detail turns out to be wrong. The SOURCE stays
  // Owner/Manager-only, enforced by the database and reflected below.
  const readOnly = !profile?.id;
  const canEditSource = isOwnerOrManager(profile?.role);
  // The consultant section is clinical judgement: acidity result, health goals,
  // condition, recommendation, attachments and the notes timeline. The database
  // already refuses staff on review_health_survey() and add_consultant_note();
  // this hides it so they are not shown something they cannot use.
  const canConsult = isOwnerOrManager(profile?.role);
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const [acidity, setAcidity] = useState<string>('');
  const [goals, setGoals] = useState('');
  const [cond, setCond] = useState('');
  const [rec, setRec] = useState('');
  const [notes, setNotes] = useState<any[]>([]);
  const [noteBusy, setNoteBusy] = useState(false);
  const [allOptions, setAllOptions] = useState<any[]>([]);
  const [sourceOptions, setSourceOptions] = useState<any[]>([]);
  useEffect(() => {
    supabase.from('customer_source_options').select('*').order('label')
      .then(({ data }) => setSourceOptions((data as any[]) ?? []));
  }, []);
  useEffect(() => {
    supabase.from('health_symptom_options').select('*').eq('is_active', true)
      .order('category').order('sort_order')
      .then(({ data: o }) => setAllOptions((o as any[]) ?? []));
  }, []);
  const [noteSaved, setNoteSaved] = useState(false);

  // `initial` seeds the consultant fields on first load only, so an
  // attachment refresh never overwrites text the user is mid-way typing.
  const load = useCallback(async (initial = false) => {
    if (initial) setLoading(true);
    const { data: r, error } = await supabase.rpc('health_survey_detail', { p_survey_id: surveyId });
    if (error) { setErr(error.message); setLoading(false); return; }
    setData(r);
    const { data: nz } = await supabase.rpc('consultant_notes_for', { p_survey_id: surveyId, p_customer_id: null });
    setNotes((nz as any[]) ?? []);
    if (initial) {
      const s = (r as any)?.survey ?? {};
      setAcidity(s.acidity_result ?? '');
      setGoals(s.health_goals ?? '');
      setCond(s.remarks_condition ?? '');
      setRec(s.remarks_recommendation ?? '');
    }
    setLoading(false);
  }, [surveyId]);

  useEffect(() => { load(true); }, [load]);
  const reload = useCallback(() => { load(false); }, [load]);

  // Clearing after a save means the next consultation starts from a blank slate
  // rather than the previous visit's wording, which is what makes the timeline
  // a history rather than a single overwritten note.
  const clearConsultFields = () => { setGoals(''); setCond(''); setRec(''); };

  const save = async () => {
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc('review_health_survey', {
      p_survey_id: surveyId,
      p_acidity: acidity || null,
      p_health_goals: goals || null,
      p_condition: cond || null,
      p_recommendation: rec || null,
    });
    if (error) { setBusy(false); setErr(error.message); return; }

    // Saving a review also adds a timestamped entry to the timeline, so the
    // consultation is recorded even when the consultant does not press
    // "Submit as Note" separately.
    if (goals.trim() || cond.trim() || rec.trim() || acidity) {
      const { error: nErr } = await supabase.rpc('add_consultant_note', {
        p_survey_id: surveyId,
        p_customer_id: (data?.survey?.customer_id) ?? null,
        p_acidity: acidity || null,
        p_health_goals: goals || null,
        p_condition: cond || null,
        p_recommendation: rec || null,
        p_attachments: [],
      });
      if (nErr) { setBusy(false); setErr(`Saved, but the note could not be recorded: ${nErr.message}`); return; }
    }

    setBusy(false);
    setSaved(true); setTimeout(() => setSaved(false), 2000);
    clearConsultFields();
    load(false);
    onSaved();
  };

  // Each submit adds a NEW timestamped consultant note (running log), leaving
  // Save Review (which updates the single survey review) untouched.
  const submitNote = async () => {
    setNoteBusy(true); setErr(null);
    const { error } = await supabase.rpc('add_consultant_note', {
      p_survey_id: surveyId,
      p_customer_id: (data?.survey?.customer_id) ?? null,
      p_acidity: acidity || null,
      p_health_goals: goals || null,
      p_condition: cond || null,
      p_recommendation: rec || null,
      p_attachments: [],
    });
    setNoteBusy(false);
    if (error) { setErr(error.message); return; }
    setNoteSaved(true); setTimeout(() => setNoteSaved(false), 2000);
    clearConsultFields();
    load(false);
  };

  const downloadPdf = async () => {
    const { data: p, error } = await supabase.from('health_survey_pdfs').select('pdf_base64').eq('survey_id', surveyId).maybeSingle();
    if (error || !p?.pdf_base64) { setErr(error?.message ?? 'No signed PDF is stored for this submission.'); return; }
    const bin = atob(p.pdf_base64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const url = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
    const a = document.createElement('a');
    a.href = url; a.download = `${s?.survey_no ?? 'survey'}.pdf`;
    a.click(); URL.revokeObjectURL(url);
  };

  const s = data?.survey;
  // Owner/Manager can correct a submission — roadshow forms are filled in a
  // hurry on a phone and often carry typos.
  const [editing, setEditing] = useState(false);
  const [ed, setEd] = useState<any>({});
  const [edBusy, setEdBusy] = useState(false);
  const [edErr, setEdErr] = useState<string | null>(null);
  const openEdit = () => {
    setEd({
      source_option_id: (s as any)?.source_option_id ?? '',
      source_details: (s as any)?.source_details ?? '',
      has_medical_condition: !!(s as any)?.has_medical_condition,
      drinks_alcohol: !!(s as any)?.drinks_alcohol,
      smokes: !!(s as any)?.smokes,
      on_treatment: !!(s as any)?.on_treatment,
      treatment_list: (s as any)?.treatment_list ?? '',
      // option_id -> duration, seeded from what was declared.
      symptoms: Object.fromEntries(syms.map((x: any) => [String(x.option_id), x.duration_text ?? ''])),
      first_name: s?.first_name ?? '', last_name: s?.last_name ?? '',
      phone: s?.phone ?? '', email: s?.email ?? '',
      date_of_birth: s?.date_of_birth ? String(s.date_of_birth).slice(0, 10) : '',
      dob_y: s?.date_of_birth ? String(s.date_of_birth).slice(0, 4) : '',
      dob_m: s?.date_of_birth ? String(Number(String(s.date_of_birth).slice(5, 7))) : '',
      dob_d: s?.date_of_birth ? String(Number(String(s.date_of_birth).slice(8, 10))) : '',
      sex: s?.sex ?? '', occupation: s?.occupation ?? '', others_text: s?.others_text ?? '',
    });
    setEditing(true);
  };
  const saveEdit = async () => {
    setEdErr(null);
    if (!ed.first_name?.trim()) { setEdErr('A first name is required.'); return; }
    if ((ed.dob_y || ed.dob_m || ed.dob_d) && !ed.date_of_birth) {
      setEdErr('Choose the day, month and year — all three are needed for a date of birth.');
      return;
    }
    setEdBusy(true); setErr(null);
    const { error } = await supabase.rpc('update_survey_particulars', {
      p_survey_id: surveyId,
      p_first_name: ed.first_name.trim(), p_last_name: ed.last_name?.trim() || null,
      p_phone: ed.phone?.trim() || null, p_email: ed.email?.trim() || null,
      p_date_of_birth: ed.date_of_birth || null, p_sex: ed.sex || null,
      p_occupation: ed.occupation?.trim() || null, p_others_text: ed.others_text?.trim() || null,
      p_source_option_id: ed.source_option_id || null,
      p_source_details: ed.source_details?.trim() || null,
      p_has_medical_condition: !!ed.has_medical_condition,
      p_drinks_alcohol: !!ed.drinks_alcohol,
      p_smokes: !!ed.smokes,
      p_on_treatment: !!ed.on_treatment,
      p_treatment_list: ed.on_treatment ? (ed.treatment_list?.trim() || null) : null,
      p_symptoms: Object.entries(ed.symptoms ?? {}).map(([option_id, duration_text]) => ({
        option_id, duration_text: String(duration_text || '') || null,
      })),
    });
    setEdBusy(false);
    if (error) {
      // Shown inside the edit form: a save that fails silently is
      // indistinguishable from a form that does not work.
      setEdErr(error.message);
      return;
    }
    setEdErr(null);
    setEditing(false); load(false); onSaved();
  };

  const syms: any[] = data?.symptoms ?? [];
  // Show EVERY symptom on the form, ticked only where declared, so a
  // consultant can see at a glance what was asked and not just what was said.
  const declared = new Map<string, string>(
    syms.map((x: any) => [String(x.label), x.duration_text ?? '']));
  const byCategory = allOptions.reduce((acc: Record<string, any[]>, o: any) => {
    (acc[o.category] ??= []).push(o); return acc;
  }, {});

  const Field: React.FC<{ k: string; v: React.ReactNode; span?: number }> = ({ k, v, span }) => (
    <div style={{ minWidth: 0, gridColumn: span ? `span ${span}` : undefined }}>
      <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{k}</div>
      {/* minWidth:0 plus overflowWrap lets a long value wrap inside its cell;
          without both, a grid item refuses to shrink and spills over the next. */}
      <div style={{ fontSize: 13, fontWeight: 600, overflowWrap: 'anywhere' }}>{v || '—'}</div>
    </div>
  );

  return (
    <Modal title={s ? `${s.survey_no} — ${s.full_name}` : 'Survey'} maxWidth={760} onClose={onClose}
      footer={<>
        <button className="btn btn-secondary" onClick={onClose}>Close</button>
        {data?.has_pdf && <button className="btn btn-secondary" onClick={downloadPdf}><Download size={14} /> Signed PDF</button>}
        {canConsult && <button className="btn btn-secondary" onClick={submitNote} disabled={noteBusy}>{noteBusy ? 'Submitting…' : noteSaved ? <><Check size={14} /> Added</> : 'Submit as Note'}</button>}
        {canConsult && <button className="btn btn-primary" onClick={save} disabled={busy}>{busy ? 'Saving…' : saved ? <><Check size={14} /> Saved</> : 'Save Review'}</button>}
      </>}>
      {loading ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div> : !s ? <div className="empty-state">Not found</div> : (
        <div className="form-grid">
          {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}

          {/* Customer-declared particulars — correctable by an Owner or Manager */}
          {!readOnly && (
            <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
              {editing
                ? <div style={{ display: 'flex', gap: 6 }}>
                    <button className="btn btn-secondary btn-sm" onClick={() => setEditing(false)}>Cancel</button>
                    <button className="btn btn-primary btn-sm" onClick={saveEdit} disabled={edBusy}>
                      {edBusy ? 'Saving…' : 'Save details'}</button>
                  </div>
                : <button className="btn btn-secondary btn-sm" onClick={openEdit}>Edit details</button>}
            </div>
          )}

          {editing ? (
            <div className="form-grid">
              {edErr && (
                <div className="alert alert-danger" style={{ marginBottom: 0 }}>
                  <span>⚠</span><div>{edErr}</div>
                </div>
              )}
              <div className="form-grid-2">
                <div className="form-group" style={{ marginBottom: 0 }}><label>First Name *</label>
                  <input value={ed.first_name} onChange={e => setEd({ ...ed, first_name: e.target.value })} /></div>
                <div className="form-group" style={{ marginBottom: 0 }}><label>Last Name</label>
                  <input value={ed.last_name} onChange={e => setEd({ ...ed, last_name: e.target.value })} /></div>
              </div>
              <div className="form-grid-2">
                <div className="form-group" style={{ marginBottom: 0 }}><label>HP No.</label>
                  <input value={ed.phone} onChange={e => setEd({ ...ed, phone: e.target.value })} /></div>
                <div className="form-group" style={{ marginBottom: 0 }}><label>Email</label>
                  <input value={ed.email} onChange={e => setEd({ ...ed, email: e.target.value })} /></div>
              </div>
              <div className="form-grid-2">
                <div className="form-group" style={{ marginBottom: 0 }}><label>Date of Birth</label>
                  <div style={{ display: 'flex', gap: 6 }}>
                    {(() => {
                      // The three parts are held SEPARATELY. Deriving them from
                      // date_of_birth alone meant an incomplete date collapsed
                      // to '' on every change, so no selection ever stuck and
                      // the date could not be edited at all.
                      const yy = ed.dob_y ?? '';
                      const mm = ed.dob_m ?? '';
                      const dd = ed.dob_d ?? '';
                      const set = (y: string, m: string, dday: string) =>
                        setEd({
                          ...ed, dob_y: y, dob_m: m, dob_d: dday,
                          // Only a complete date is submitted; a partial one is
                          // kept on screen so the next choice can complete it.
                          date_of_birth: y && m && dday
                            ? `${y}-${String(m).padStart(2, '0')}-${String(dday).padStart(2, '0')}`
                            : '',
                        });
                      return <>
                        <select value={dd} onChange={e => set(yy, mm, e.target.value)} style={{ flex: '0 0 76px' }}>
                          <option value="">Day</option>
                          {Array.from({ length: 31 }, (_, i) => String(i + 1)).map(x => <option key={x} value={x}>{x}</option>)}
                        </select>
                        <select value={mm} onChange={e => set(yy, e.target.value, dd)} style={{ flex: 1 }}>
                          <option value="">Month</option>
                          {['January','February','March','April','May','June','July','August','September','October','November','December']
                            .map((mn, i) => <option key={mn} value={String(i + 1)}>{mn}</option>)}
                        </select>
                        <select value={yy} onChange={e => set(e.target.value, mm, dd)} style={{ flex: '0 0 90px' }}>
                          <option value="">Year</option>
                          {/* 120 years: at 100 the oldest selectable year was 1927,
                              so anyone born earlier simply had no option to choose. */}
                          {Array.from({ length: 120 }, (_, i) => String(new Date().getFullYear() - i)).map(x => <option key={x} value={x}>{x}</option>)}
                        </select>
                      </>;
                    })()}
                  </div>
                </div>
                <div className="form-group" style={{ marginBottom: 0 }}><label>Sex</label>
                  <select value={ed.sex} onChange={e => setEd({ ...ed, sex: e.target.value })}>
                    <option value="">— Not specified —</option>
                    <option value="female">Female</option>
                    <option value="male">Male</option>
                  </select></div>
              </div>
              <div className="form-grid-2">
                <div className="form-group" style={{ marginBottom: 0 }}><label>Occupation</label>
                  <input value={ed.occupation} onChange={e => setEd({ ...ed, occupation: e.target.value })} /></div>
                <div className="form-group" style={{ marginBottom: 0 }}><label>Others (symptoms)</label>
                  <input value={ed.others_text} onChange={e => setEd({ ...ed, others_text: e.target.value })} /></div>
              </div>

              <div className="form-grid-2">
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>How did you hear about us?{!canEditSource && ' (Owner/Manager only)'}</label>
                  <select value={ed.source_option_id} disabled={!canEditSource}
                    title={canEditSource ? undefined
                      : 'This records how the customer found us when they submitted, and can only be corrected by an Owner or Manager.'}
                    onChange={e => setEd({ ...ed, source_option_id: e.target.value })}>
                    <option value="">— Not specified —</option>
                    {sourceOptions.map((o: any) => <option key={o.id} value={o.id}>{o.label}</option>)}
                  </select></div>
                <div className="form-group" style={{ marginBottom: 0 }}><label>Source details</label>
                  <input value={ed.source_details}
                    onChange={e => setEd({ ...ed, source_details: e.target.value })}
                    placeholder="e.g. the event or referrer name" /></div>
              </div>

              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Declarations</label>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))', gap: 6, marginTop: 4 }}>
                  {([
                    ['has_medical_condition', 'Medical/physical condition'],
                    ['drinks_alcohol', 'Drinks alcohol'],
                    ['smokes', 'Smokes'],
                    ['on_treatment', 'On treatment'],
                  ] as const).map(([k, label]) => (
                    <label key={k} style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 13 }}>
                      <input type="checkbox" style={{ width: 'auto' }} checked={!!(ed as any)[k]}
                        onChange={e => setEd({ ...ed, [k]: e.target.checked })} />
                      {label}
                    </label>
                  ))}
                </div>
                {ed.on_treatment && (
                  <input style={{ marginTop: 6 }} value={ed.treatment_list}
                    onChange={e => setEd({ ...ed, treatment_list: e.target.value })}
                    placeholder="What treatment or medication?" />
                )}
              </div>
            </div>
          ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 10 }}>
            <Field k="HP No." v={s.phone} />
            <Field k="Sex" v={s.sex ? (s.sex === 'female' ? 'Female' : 'Male') : '—'} />
            <Field k="Date of Birth" v={d(s.date_of_birth)} />
            <Field k="Age" v={s.age} />
            <Field k="Occupation" v={s.occupation} />
            {/* An email is far longer than the other values, so it is given two
                columns and allowed to wrap rather than running into its neighbour. */}
            <Field k="Email" v={s.email} span={2} />
            <Field k="How did you hear about us?" v={(s as any).source_label ? `${(s as any).source_label}${(s as any).source_details ? ` — ${(s as any).source_details}` : ''}` : null} />
            <Field k="Event" v={s.event_name} />
            <Field k="Submitted" v={new Date(s.submitted_at).toLocaleString()} />
          </div>
          )}

          <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
            <div style={{ fontSize: 12, fontWeight: 700, marginBottom: 6 }}>Declarations</div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 8, fontSize: 12.5 }}>
              <span>Medical/physical condition: <strong>{yn(s.has_medical_condition)}</strong></span>
              <span>Drinks alcohol: <strong>{yn(s.drinks_alcohol)}</strong></span>
              <span>Smokes: <strong>{yn(s.smokes)}</strong></span>
              <span>On treatment: <strong>{yn(s.on_treatment)}</strong></span>
            </div>
            {s.treatment_list && <div style={{ fontSize: 12.5, marginTop: 6 }}>Listed: <strong>{s.treatment_list}</strong></div>}
          </div>

          <div>
            <label>Symptoms &amp; conditions ({editing ? Object.keys(ed.symptoms ?? {}).length : syms.length} of {allOptions.length} declared)</label>
            {allOptions.length === 0
              ? <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>The symptom checklist could not be loaded.</div>
              : <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(210px, 1fr))', gap: 12, marginTop: 6 }}>
                  {Object.entries(byCategory).map(([cat, opts]) => (
                    <div key={cat}>
                      <div style={{ fontSize: 11.5, fontWeight: 700, marginBottom: 4 }}>{cat}</div>
                      {(opts as any[]).map(o => {
                        // While editing, the tick is live and reads from the
                        // draft rather than from what was originally declared.
                        const on = editing
                          ? Object.prototype.hasOwnProperty.call(ed.symptoms ?? {}, String(o.id))
                          : declared.has(o.label);
                        const dur = editing ? (ed.symptoms ?? {})[String(o.id)] : declared.get(o.label);
                        if (editing) return (
                          <div key={o.id} style={{ display: 'flex', gap: 6, alignItems: 'center', padding: '1.5px 0' }}>
                            <input type="checkbox" style={{ width: 'auto' }} checked={on}
                              onChange={e => {
                                const next = { ...(ed.symptoms ?? {}) };
                                if (e.target.checked) next[String(o.id)] = dur ?? '';
                                else delete next[String(o.id)];
                                setEd({ ...ed, symptoms: next });
                              }} />
                            <span style={{ fontSize: 12, flex: 1 }}>{o.label}</span>
                            {on && (
                              <input value={dur ?? ''} placeholder="how long?"
                                style={{ width: 96, fontSize: 11, padding: '2px 5px' }}
                                onChange={e => setEd({ ...ed,
                                  symptoms: { ...(ed.symptoms ?? {}), [String(o.id)]: e.target.value } })} />
                            )}
                          </div>
                        );
                        return (
                          <div key={o.id} style={{ display: 'flex', gap: 6, alignItems: 'baseline',
                                                   fontSize: 12, padding: '1.5px 0',
                                                   color: on ? 'var(--text)' : 'var(--text-muted)' }}>
                            <span style={{ width: 13, flex: '0 0 13px', fontWeight: 700,
                                           color: on ? 'var(--primary)' : 'var(--border)' }}>
                              {on ? '☑' : '☐'}
                            </span>
                            <span style={{ fontWeight: on ? 600 : 400 }}>
                              {o.label}{on && dur ? ` · ${dur}` : ''}
                            </span>
                          </div>
                        );
                      })}
                    </div>
                  ))}
                </div>}
            {s.others_text && <div style={{ fontSize: 12.5, marginTop: 6 }}>Others: <strong>{s.others_text}</strong></div>}
          </div>

          <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
            Marketing consent — Newsletter: <strong>{s.consent_newsletter_email ? 'Email' : 'No'}</strong> ·
            Products/services: <strong>{[s.consent_marketing_email && 'Email', s.consent_marketing_sms && 'Text', s.consent_marketing_phone && 'Phone'].filter(Boolean).join(', ') || 'None'}</strong>
          </div>

          {s.signature_data && (
            <div>
              <label>Customer signature — signed {d(s.signed_date)}</label>
              <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', background: '#fff', padding: 6, display: 'inline-block' }}>
                <img src={s.signature_data} alt="Signature" style={{ height: 60 }} />
              </div>
            </div>
          )}

          {canConsult && <div style={{ borderTop: '1px solid var(--border)', paddingTop: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <FileText size={14} style={{ color: 'var(--primary)' }} />
              <strong style={{ fontSize: 13 }}>Consultant section</strong>
              {readOnly && <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, fontSize: 10.5, color: 'var(--text-muted)', border: '1px solid var(--border)', borderRadius: 999, padding: '1px 7px' }}><Lock size={9} /> View only — sign in to edit</span>}
              {s.reviewed_at && <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                last saved {new Date(s.reviewed_at).toLocaleString()}{data.reviewer ? ` by ${data.reviewer}` : ''}</span>}
            </div>

            <div className="form-group">
              <label>Acidity Test</label>
              <div style={{ display: 'flex', gap: 6 }}>
                {ACIDITY.map(a => (
                  <button key={a.v} type="button" disabled={readOnly}
                    onClick={() => setAcidity(acidity === a.v ? '' : a.v)}
                    style={{
                      padding: '6px 16px', borderRadius: 'var(--radius-sm)', cursor: readOnly ? 'default' : 'pointer',
                      border: `2px solid ${acidity === a.v ? a.color : 'var(--border)'}`,
                      background: acidity === a.v ? a.color : 'var(--surface)',
                      color: acidity === a.v ? '#fff' : 'var(--text-secondary)',
                      fontWeight: 700, fontSize: 12.5,
                    }}>{a.label}</button>
                ))}
              </div>
            </div>

            <div className="form-group">
              <label>Health Goals <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— consultant to guide in prioritising</span></label>
              <textarea rows={2} value={goals} onChange={e => setGoals(e.target.value)} disabled={readOnly} />
            </div>
            <div className="form-group">
              <label>Remarks — Condition</label>
              <textarea rows={2} value={cond} onChange={e => setCond(e.target.value)} disabled={readOnly} />
            </div>
            <div className="form-group">
              <label>Remarks — Recommendation</label>
              <textarea rows={2} value={rec} onChange={e => setRec(e.target.value)} disabled={readOnly} />
            </div>

            <SurveyAttachments
              surveyId={surveyId}
              storeId={s.store_id}
              attachments={data?.attachments ?? []}
              readOnly={readOnly}
              onChanged={reload}
            />

            {notes.length > 0 && (
              <div style={{ marginTop: 6 }}>
                <strong style={{ fontSize: 13 }}>Consultant notes timeline</strong>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 8 }}>
                  {notes.map((n: any) => (
                    <div key={n.id} style={{ borderLeft: '2px solid var(--primary)', paddingLeft: 10 }}>
                      <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 2 }}>
                        {new Date(n.created_at).toLocaleString('en-GB')} · {n.author ?? '—'}
                        {n.acidity_result && <span> · Acidity: <span style={{ textTransform: 'capitalize' }}>{n.acidity_result}</span></span>}
                      </div>
                      {n.health_goals && <div style={{ fontSize: 12.5 }}><span style={{ color: 'var(--text-muted)' }}>Goals:</span> {n.health_goals}</div>}
                      {n.remarks_condition && <div style={{ fontSize: 12.5 }}><span style={{ color: 'var(--text-muted)' }}>Condition:</span> {n.remarks_condition}</div>}
                      {n.remarks_recommendation && <div style={{ fontSize: 12.5 }}><span style={{ color: 'var(--text-muted)' }}>Recommendation:</span> {n.remarks_recommendation}</div>}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>}
        </div>
      )}
    </Modal>
  );
};

export default SurveyDetailModal;
