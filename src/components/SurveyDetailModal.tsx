import PhoneInput from './PhoneInput';
import { phoneErrorMessage } from '../lib/customer-phones/normalize.mjs';
import React, { useEffect, useState, useCallback, useMemo, useRef } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isOwnerOrManager } from '../types';
import { Modal } from './ui';
import { Download, RefreshCw, FileText, Check } from 'lucide-react';
import SurveyAttachments from './SurveyAttachments';
import { plainDate, sgDateTime } from '../lib/survey/links.mjs';
import {
  DECLARATIONS, seedParticulars, particularsChanges, particularsNeedReason, dobChangeAllowed, answerLabel,
  type ParticularsDraft,
} from '../lib/survey/particulars.mjs';
import { savedReview, reviewState } from '../lib/survey/review.mjs';

const ACIDITY: { v: 'red' | 'green' | 'blue'; label: string; color: string }[] = [
  { v: 'red', label: 'Red', color: '#dc2626' },
  { v: 'green', label: 'Green', color: '#16a34a' },
  { v: 'blue', label: 'Blue', color: '#2563eb' },
];
const DECLARATION_LABEL: Record<string, string> = {
  has_medical_condition: 'Medical/physical condition',
  drinks_alcohol: 'Drinks alcohol',
  smokes: 'Smokes',
  on_treatment: 'On treatment',
};
const sexLabel = (v?: string | null) => (v === 'female' ? 'Female' : v === 'male' ? 'Male' : v === 'other' ? 'Other' : '—');
const LAST_STORE_KEY = 'energia.surveys.lastStore';

/** The customer a survey is being started for (no survey yet). */
export interface SurveyCustomer { customer_id: string; full_name: string; phone?: string | null; email?: string | null }
/** A store the person may start a survey at (my_assigned_stores). */
export interface SurveyStoreOption { store_id: string; store_name: string }

/**
 * The health survey window. With a survey it shows the survey; with only a
 * customer (Start survey) it shows the same window, and the survey is made by
 * the first real save: Edit details, Save Review, a note or a file
 * (CUSTOMERS-5). Opening a customer no longer makes an empty record, which
 * kept the customer from filling in the QR form.
 */
const SurveyDetailModal: React.FC<{
  surveyId: string | null;
  customer?: SurveyCustomer | null;
  stores?: SurveyStoreOption[];
  onClose: () => void;
  onSaved: () => void;
}> = ({ surveyId, customer, stores = [], onClose, onSaved }) => {
  const { profile } = useAuth();
  // The source is an Owner's or Manager's to change (the server says so too).
  const canEditSource = isOwnerOrManager(profile?.role);
  // The consultant section is clinical judgement: acidity result, health goals,
  // condition, recommendation, attachments and the notes timeline. The database
  // refuses staff on review_health_survey(), add_consultant_note() and the
  // files; this hides it so they are not shown something they cannot use.
  const canConsult = isOwnerOrManager(profile?.role);
  const [sid, setSid] = useState<string | null>(surveyId);
  // The survey being shown, also once Start survey's first save made it;
  // loads read it here so they never use an older one.
  const sidRef = useRef<string | null>(surveyId);
  const [data, setData] = useState<any>(null);
  const [cust, setCust] = useState<any>(null);
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
  const [noteSaved, setNoteSaved] = useState(false);

  // M1: the store a new survey belongs to, when the person has more than one.
  const [storeId, setStoreId] = useState<string>(() => {
    let last = '';
    try { last = window.localStorage.getItem(LAST_STORE_KEY) ?? ''; } catch { /* no storage */ }
    if (stores.some(s => s.store_id === last)) return last;
    return stores.length === 1 ? stores[0].store_id : '';
  });
  useEffect(() => {
    if (!storeId && stores.length === 1) setStoreId(stores[0].store_id);
  }, [stores, storeId]);

  useEffect(() => {
    supabase.from('customer_source_options').select('*').order('label')
      .then(({ data }) => setSourceOptions((data as any[]) ?? []));
  }, []);
  useEffect(() => {
    supabase.from('health_symptom_options').select('*').eq('is_active', true)
      .order('category').order('sort_order')
      .then(({ data: o }) => setAllOptions((o as any[]) ?? []));
  }, []);

  const s = data?.survey;
  const customerId: string | null = s?.customer_id ?? customer?.customer_id ?? null;

  // The boxes show the review as saved (K1): on opening, and again after each
  // save, so a second press has nothing new to save.
  const seedReview = (survey: any) => {
    const r = savedReview(survey);
    setAcidity(r.acidity ?? ''); setGoals(r.goals ?? ''); setCond(r.cond ?? ''); setRec(r.rec ?? '');
  };

  const load = useCallback(async (reseed = false) => {
    const sid = sidRef.current;
    if (!sid) {
      // No survey yet: the customer's own details, for the window and for
      // Edit details (a new survey starts from them).
      if (customer?.customer_id) {
        const { data: c, error } = await supabase.from('customers')
          .select('id, first_name, last_name, full_name, phone, email, date_of_birth, gender, occupation')
          .eq('id', customer.customer_id).maybeSingle();
        if (error) setErr(error.message);
        setCust(c ?? null);
      }
      setLoading(false);
      return;
    }
    if (reseed) setLoading(true);
    const { data: r, error } = await supabase.rpc('health_survey_detail', { p_survey_id: sid });
    if (error) { setErr(error.message); setLoading(false); return; }
    setData(r);
    const survey = (r as any)?.survey;
    if (reseed) seedReview(survey);
    const { data: nz } = await supabase.rpc('consultant_notes_for', { p_survey_id: sid, p_customer_id: null });
    setNotes((nz as any[]) ?? []);
    if (survey?.customer_id) {
      // The customer's own date of birth: changing one already filled in is
      // an Owner's or Manager's (Q9), whatever the survey shows.
      const { data: c } = await supabase.from('customers')
        .select('id, date_of_birth').eq('id', survey.customer_id).maybeSingle();
      setCust(c ?? null);
    }
    setLoading(false);
  }, [customer?.customer_id]);

  useEffect(() => { load(true); }, [load]);
  const reload = useCallback(() => { load(false); }, [load]);

  /** The survey, made now if the customer has none yet (CUSTOMERS-5). */
  const ensureSurvey = async (): Promise<string> => {
    if (sidRef.current) return sidRef.current;
    if (!customer?.customer_id) throw new Error('No customer chosen.');
    if (stores.length > 1 && !storeId) throw new Error('Choose the store for this survey first.');
    const { data: id, error } = await supabase.rpc('upsert_consultant_survey', {
      p_customer_id: customer.customer_id,
      p_store_id: storeId || null,
    });
    if (error) throw new Error(error.message);
    if (storeId) { try { window.localStorage.setItem(LAST_STORE_KEY, storeId); } catch { /* no storage */ } }
    sidRef.current = id as string;
    setSid(id as string);
    // The new survey is shown at once (the review boxes keep what was typed).
    await load(false);
    onSaved();
    return id as string;
  };

  const saved0 = useMemo(() => savedReview(s), [s]);
  const review = reviewState(saved0, { acidity, goals, cond, rec });

  const save = async () => {
    if (!review.canSave) return;
    setBusy(true); setErr(null);
    let id: string;
    try { id = await ensureSurvey(); } catch (e: any) { setBusy(false); setErr(e.message); return; }
    const { error } = await supabase.rpc('review_health_survey', {
      p_survey_id: id,
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
        p_survey_id: id,
        p_customer_id: customerId,
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
    // K1: the boxes now show what was saved; nothing is emptied.
    await load(true);
    onSaved();
  };

  // Each submit adds a NEW timestamped consultant note (running log), leaving
  // the saved review (Save Review) as it is.
  const submitNote = async () => {
    setNoteBusy(true); setErr(null);
    let id: string;
    try { id = await ensureSurvey(); } catch (e: any) { setNoteBusy(false); setErr(e.message); return; }
    const { error } = await supabase.rpc('add_consultant_note', {
      p_survey_id: id,
      p_customer_id: customerId,
      p_acidity: acidity || null,
      p_health_goals: goals || null,
      p_condition: cond || null,
      p_recommendation: rec || null,
      p_attachments: [],
    });
    setNoteBusy(false);
    if (error) { setErr(error.message); return; }
    setNoteSaved(true); setTimeout(() => setNoteSaved(false), 2000);
    // The boxes go back to the saved review (K1), ready for the next note.
    await load(true);
  };

  const downloadPdf = async () => {
    const id = sidRef.current;
    if (!id) return;
    const { data: p, error } = await supabase.from('health_survey_pdfs').select('pdf_base64').eq('survey_id', id).maybeSingle();
    if (error) { setErr(`The signed PDF could not be opened: ${error.message}`); return; }
    if (!p?.pdf_base64) { setErr('The signed PDF could not be opened. It may belong to a store you are not assigned to.'); return; }
    const bin = atob(p.pdf_base64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const url = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
    const a = document.createElement('a');
    a.href = url; a.download = `${s?.survey_no ?? 'survey'}.pdf`;
    a.click(); URL.revokeObjectURL(url);
  };

  const syms: any[] = data?.symptoms ?? [];

  // ---- Edit details (CUSTOMERS-4): only what changed is sent ----
  const [editing, setEditing] = useState(false);
  const [seed, setSeed] = useState<ParticularsDraft | null>(null);
  const [ed, setEd] = useState<any>({});
  const [reason, setReason] = useState('');
  const [edBusy, setEdBusy] = useState(false);
  const [edErr, setEdErr] = useState<string | null>(null);
  const openEdit = () => {
    // A survey is edited from what it holds; a customer with no survey yet
    // from their own details, which is what the new survey starts with.
    const base = s ?? (cust ? {
      first_name: cust.first_name, last_name: cust.last_name, phone: cust.phone, email: cust.email,
      date_of_birth: cust.date_of_birth, sex: cust.gender, occupation: cust.occupation,
    } : {});
    const first = seedParticulars(base, s ? syms : []);
    setSeed(first);
    const dob = first.date_of_birth;
    setEd({
      ...first,
      dob_y: dob ? dob.slice(0, 4) : '',
      dob_m: dob ? String(Number(dob.slice(5, 7))) : '',
      dob_d: dob ? String(Number(dob.slice(8, 10))) : '',
    });
    setReason(''); setEdErr(null);
    setEditing(true);
  };
  const changes = editing && seed ? particularsChanges(seed, ed) : {};
  const hasCustomer = !!customerId;
  const needReason = editing && particularsNeedReason(changes, { hasCustomer, customerDob: cust?.date_of_birth ?? null });
  const saveEdit = async () => {
    setEdErr(null);
    if (('first_name' in changes || 'last_name' in changes) && !String(ed.first_name ?? '').trim()) {
      setEdErr('A first name is required.'); return;
    }
    if ((ed.dob_y || ed.dob_m || ed.dob_d) && !ed.date_of_birth) {
      setEdErr('Choose the day, month and year — all three are needed for a date of birth.');
      return;
    }
    if (!dobChangeAllowed(changes, { hasCustomer, customerDob: cust?.date_of_birth ?? null, role: profile?.role ?? null })) {
      setEdErr('Only an Owner or Manager can change a date of birth that is already filled in.');
      return;
    }
    if (needReason && !reason.trim()) {
      setEdErr('Give a reason for this change. It is kept in the history.');
      return;
    }
    if (Object.keys(changes).length === 0) { setEditing(false); return; }
    setEdBusy(true); setErr(null);
    let id: string;
    try { id = await ensureSurvey(); } catch (e: any) { setEdBusy(false); setEdErr(e.message); return; }
    const { error } = await supabase.rpc('update_survey_particulars_v2', {
      p_survey_id: id, p_changes: changes, p_reason: reason.trim() || null,
    });
    setEdBusy(false);
    if (error) {
      // Shown inside the edit form: a save that fails silently is
      // indistinguishable from a form that does not work.
      setEdErr(phoneErrorMessage(error.message));
      return;
    }
    setEdErr(null);
    setEditing(false);
    await load(false);
    onSaved();
  };

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

  const startMode = !sid && !!customer;
  const title = s ? `${s.survey_no} — ${s.full_name}` : startMode ? `New survey — ${customer!.full_name}` : 'Survey';

  return (
    <Modal title={title} maxWidth={760} onClose={onClose}
      footer={<>
        <button className="btn btn-secondary" onClick={onClose}>Close</button>
        {data?.has_pdf && <button className="btn btn-secondary" onClick={downloadPdf}><Download size={14} /> Signed PDF</button>}
        {/* The boxes show the saved review after a save, and Save Review has
            already added it as a note: Submit as Note waits for a change, so
            the same note is not added twice. */}
        {canConsult && <button className="btn btn-secondary" data-submit-note onClick={submitNote}
          disabled={noteBusy || !review.changed || !(goals.trim() || cond.trim() || rec.trim() || acidity)}
          title={!review.changed ? 'This is the saved review; change a box to add a new note.' : undefined}>
          {noteBusy ? 'Submitting…' : noteSaved ? <><Check size={14} /> Added</> : 'Submit as Note'}</button>}
        {canConsult && <button className="btn btn-primary" data-save-review onClick={save} disabled={busy || !review.canSave}
          title={review.blanks ? 'Empty boxes do not clear a saved review.' : !review.changed ? 'Nothing has changed since the last save.' : undefined}>
          {busy ? 'Saving…' : saved ? <><Check size={14} /> Saved</> : 'Save Review'}</button>}
      </>}>
      {loading || (sid && !data && !err) ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div>
        : !s && !startMode ? (
          // CUSTOMERS-14: say why the survey did not open, instead of "Not found".
          <div className="form-grid">
            {err
              ? <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>The survey could not be opened: {err}</div></div>
              : <div className="empty-state">This survey was not found.</div>}
          </div>
        ) : (
        <div className="form-grid">
          {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}

          {startMode && (
            <div className="alert alert-info" data-start-note style={{ marginBottom: 0 }}>
              <span>ℹ️</span>
              <div>{customer!.full_name} has no health survey yet. It is made the first time you save something
                here: their details, a review, a note or a file. Until then they can still fill in the QR form.</div>
            </div>
          )}
          {startMode && stores.length > 1 && (
            <div className="form-group" style={{ marginBottom: 0, maxWidth: 320 }}>
              <label htmlFor="survey-store">Store for this survey *</label>
              <select id="survey-store" value={storeId} onChange={e => setStoreId(e.target.value)}>
                <option value="">— Choose —</option>
                {stores.map(st => <option key={st.store_id} value={st.store_id}>{st.store_name}</option>)}
              </select>
            </div>
          )}

          {/* The customer's particulars: any member of staff who opens surveys corrects them. */}
          <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
            {editing
              ? <div style={{ display: 'flex', gap: 6 }}>
                  <button className="btn btn-secondary btn-sm" onClick={() => setEditing(false)}>Cancel</button>
                  <button className="btn btn-primary btn-sm" data-save-details onClick={saveEdit} disabled={edBusy}>
                    {edBusy ? 'Saving…' : 'Save details'}</button>
                </div>
              : <button className="btn btn-secondary btn-sm" data-edit-details onClick={openEdit}>Edit details</button>}
          </div>

          {editing ? (
            <div className="form-grid">
              {edErr && (
                <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}>
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
                  <PhoneInput value={ed.phone} onChange={phone => setEd((x: any) => ({ ...x, phone }))} /></div>
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
                        <select aria-label="Day of birth" value={dd} onChange={e => set(yy, mm, e.target.value)} style={{ flex: '0 0 76px' }}>
                          <option value="">Day</option>
                          {Array.from({ length: 31 }, (_, i) => String(i + 1)).map(x => <option key={x} value={x}>{x}</option>)}
                        </select>
                        <select aria-label="Month of birth" value={mm} onChange={e => set(yy, e.target.value, dd)} style={{ flex: 1 }}>
                          <option value="">Month</option>
                          {['January','February','March','April','May','June','July','August','September','October','November','December']
                            .map((mn, i) => <option key={mn} value={String(i + 1)}>{mn}</option>)}
                        </select>
                        <select aria-label="Year of birth" value={yy} onChange={e => set(e.target.value, mm, dd)} style={{ flex: '0 0 90px' }}>
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
                    <option value="other">Other</option>
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
                {/* Yes, No or Not answered, as stored: an answer never given
                    stays Not answered unless someone changes it. */}
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))', gap: 6, marginTop: 4 }}>
                  {DECLARATIONS.map(k => (
                    <label key={k} style={{ display: 'flex', flexDirection: 'column', gap: 2, fontSize: 12.5 }}>
                      {DECLARATION_LABEL[k]}
                      <select data-declaration={k}
                        value={ed[k] === true ? 'yes' : ed[k] === false ? 'no' : ''}
                        onChange={e => setEd({ ...ed, [k]: e.target.value === 'yes' ? true : e.target.value === 'no' ? false : null })}>
                        <option value="">Not answered</option>
                        <option value="yes">Yes</option>
                        <option value="no">No</option>
                      </select>
                    </label>
                  ))}
                </div>
                {ed.on_treatment === true && (
                  <input style={{ marginTop: 6 }} value={ed.treatment_list}
                    onChange={e => setEd({ ...ed, treatment_list: e.target.value })}
                    placeholder="What treatment or medication?" />
                )}
              </div>

              {needReason && (
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label htmlFor="survey-edit-reason">Reason for the change *</label>
                  <input id="survey-edit-reason" data-edit-reason value={reason} onChange={e => setReason(e.target.value)}
                    placeholder="e.g. Checked her IC at the counter" />
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 2 }}>
                    A new phone number or a changed date of birth goes onto the customer, and the reason is kept in the history.
                  </div>
                </div>
              )}
            </div>
          ) : s ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 10 }}>
            <Field k="HP No." v={s.phone} />
            <Field k="Sex" v={sexLabel(s.sex)} />
            <Field k="Date of Birth" v={plainDate(s.date_of_birth)} />
            <Field k="Age" v={s.age} />
            <Field k="Occupation" v={s.occupation} />
            {/* An email is far longer than the other values, so it is given two
                columns and allowed to wrap rather than running into its neighbour. */}
            <Field k="Email" v={s.email} span={2} />
            <Field k="How did you hear about us?" v={(s as any).source_label ? `${(s as any).source_label}${(s as any).source_details ? ` — ${(s as any).source_details}` : ''}` : null} />
            <Field k="Event" v={s.event_name} />
            <Field k="Submitted" v={sgDateTime(s.submitted_at)} />
          </div>
          ) : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 10 }}>
            <Field k="HP No." v={cust?.phone ?? customer?.phone} />
            <Field k="Sex" v={sexLabel(cust?.gender)} />
            <Field k="Date of Birth" v={plainDate(cust?.date_of_birth)} />
            <Field k="Occupation" v={cust?.occupation} />
            <Field k="Email" v={cust?.email ?? customer?.email} span={2} />
          </div>
          )}

          {s && <>
          <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
            <div style={{ fontSize: 12, fontWeight: 700, marginBottom: 6 }}>Declarations</div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 8, fontSize: 12.5 }}>
              {DECLARATIONS.map(k => (
                <span key={k}>{DECLARATION_LABEL[k]}: <strong>{answerLabel(s[k])}</strong></span>
              ))}
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
              <label>Customer signature — signed {plainDate(s.signed_date)}</label>
              <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', background: '#fff', padding: 6, display: 'inline-block' }}>
                <img src={s.signature_data} alt="Signature" style={{ height: 60 }} />
              </div>
            </div>
          )}
          {data?.pdf_other_store && (
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }} data-pdf-other-store>
              A signed PDF is stored, but it belongs to a store you are not assigned to, so it cannot be opened here.
            </div>
          )}
          </>}

          {canConsult && <div style={{ borderTop: '1px solid var(--border)', paddingTop: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <FileText size={14} style={{ color: 'var(--primary)' }} />
              <strong style={{ fontSize: 13 }}>Consultant section</strong>
              {s?.reviewed_at && <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                last saved {sgDateTime(s.reviewed_at)}{data.reviewer ? ` by ${data.reviewer}` : ''}</span>}
            </div>

            <div className="form-group">
              <label>Acidity Test</label>
              <div style={{ display: 'flex', gap: 6 }}>
                {ACIDITY.map(a => (
                  <button key={a.v} type="button"
                    aria-pressed={acidity === a.v}
                    onClick={() => setAcidity(acidity === a.v ? '' : a.v)}
                    style={{
                      padding: '6px 16px', borderRadius: 'var(--radius-sm)', cursor: 'pointer',
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
              <textarea rows={2} data-review="goals" value={goals} onChange={e => setGoals(e.target.value)} />
            </div>
            <div className="form-group">
              <label>Remarks — Condition</label>
              <textarea rows={2} data-review="cond" value={cond} onChange={e => setCond(e.target.value)} />
            </div>
            <div className="form-group">
              <label>Remarks — Recommendation</label>
              <textarea rows={2} data-review="rec" value={rec} onChange={e => setRec(e.target.value)} />
            </div>
            {review.blanks && (
              <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: -6, marginBottom: 8 }} data-review-blanks>
                The boxes are empty. Saving would not clear the saved review, so Save Review is off.
              </div>
            )}

            <SurveyAttachments
              surveyId={sid}
              storeId={s?.store_id ?? null}
              attachments={data?.attachments ?? []}
              onChanged={reload}
              getTarget={async () => {
                const id = await ensureSurvey();
                const { data: r } = await supabase.rpc('health_survey_detail', { p_survey_id: id });
                return { surveyId: id, storeId: (r as any)?.survey?.store_id ?? null };
              }}
            />

            {notes.length > 0 && (
              <div style={{ marginTop: 6 }}>
                <strong style={{ fontSize: 13 }}>Consultant notes timeline</strong>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 8 }}>
                  {notes.map((n: any) => (
                    <div key={n.id} style={{ borderLeft: '2px solid var(--primary)', paddingLeft: 10 }}>
                      <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 2 }}>
                        {sgDateTime(n.created_at)} · {n.author ?? '—'}
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
