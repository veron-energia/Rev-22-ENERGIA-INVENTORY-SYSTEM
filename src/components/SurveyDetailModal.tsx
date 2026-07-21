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
  const readOnly = !isOwnerOrManager(profile?.role);
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

  const save = async () => {
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc('review_health_survey', {
      p_survey_id: surveyId,
      p_acidity: acidity || null,
      p_health_goals: goals || null,
      p_condition: cond || null,
      p_recommendation: rec || null,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setSaved(true); setTimeout(() => setSaved(false), 2000);
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
  const syms: any[] = data?.symptoms ?? [];

  const Field: React.FC<{ k: string; v: React.ReactNode }> = ({ k, v }) => (
    <div><div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{k}</div><div style={{ fontSize: 13, fontWeight: 600 }}>{v || '—'}</div></div>
  );

  return (
    <Modal title={s ? `${s.survey_no} — ${s.full_name}` : 'Survey'} maxWidth={760} onClose={onClose}
      footer={<>
        <button className="btn btn-secondary" onClick={onClose}>Close</button>
        {data?.has_pdf && <button className="btn btn-secondary" onClick={downloadPdf}><Download size={14} /> Signed PDF</button>}
        {!readOnly && <button className="btn btn-secondary" onClick={submitNote} disabled={noteBusy}>{noteBusy ? 'Submitting…' : noteSaved ? <><Check size={14} /> Added</> : 'Submit as Note'}</button>}
        {!readOnly && <button className="btn btn-primary" onClick={save} disabled={busy}>{busy ? 'Saving…' : saved ? <><Check size={14} /> Saved</> : 'Save Review'}</button>}
      </>}>
      {loading ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div> : !s ? <div className="empty-state">Not found</div> : (
        <div className="form-grid">
          {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}

          {/* Customer-declared (read-only record) */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 10 }}>
            <Field k="HP No." v={s.phone} />
            <Field k="Email" v={s.email} />
            <Field k="Date of Birth" v={d(s.date_of_birth)} />
            <Field k="Age" v={s.age} />
            <Field k="Sex" v={s.sex ? (s.sex === 'female' ? 'Female' : 'Male') : '—'} />
            <Field k="Occupation" v={s.occupation} />
            <Field k="Event" v={s.event_name} />
            <Field k="Submitted" v={new Date(s.submitted_at).toLocaleString()} />
          </div>

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
            <label>Symptoms declared ({syms.length})</label>
            {syms.length === 0 ? <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>None indicated.</div> : (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 4 }}>
                {syms.map((x, i) => (
                  <span key={i} className="badge badge-muted" style={{ fontSize: 11 }}>
                    {x.label}{x.duration_text ? ` · ${x.duration_text}` : ''}
                  </span>
                ))}
              </div>
            )}
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

          <div style={{ borderTop: '1px solid var(--border)', paddingTop: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <FileText size={14} style={{ color: 'var(--primary)' }} />
              <strong style={{ fontSize: 13 }}>Consultant section</strong>
              {readOnly && <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, fontSize: 10.5, color: 'var(--text-muted)', border: '1px solid var(--border)', borderRadius: 999, padding: '1px 7px' }}><Lock size={9} /> View only — Owner/Manager can edit</span>}
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
          </div>
        </div>
      )}
    </Modal>
  );
};

export default SurveyDetailModal;
