import React, { useEffect, useState, useCallback } from 'react';
import QRCode from 'qrcode';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, SurveyLink, HealthSurvey, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import SurveyDetailModal from '../components/SurveyDetailModal';
import SourceOptionsModal from '../components/SourceOptionsModal';
import { RefreshCw, Plus, QrCode, Copy, ClipboardList, Search, Link2, Check, Eye, FileText } from 'lucide-react';

const randomToken = () => {
  const a = new Uint8Array(16);
  crypto.getRandomValues(a);
  return Array.from(a, b => b.toString(16).padStart(2, '0')).join('');
};

const SurveysPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  const [tab, setTab] = useState<'submissions' | 'links'>('submissions');
  // Every customer, with their single survey and remark count, so a consultant
  // can record findings for people who never used the public QR form.
  const [custRows, setCustRows] = useState<any[]>([]);
  const [custSearch, setCustSearch] = useState('');
  const [custDebounced, setCustDebounced] = useState('');
  const [custFilter, setCustFilter] = useState<'all' | 'with_survey' | 'no_survey' | 'with_remarks'>('all');
  const [custPage, setCustPage] = useState(0);
  const [custTotal, setCustTotal] = useState(0);
  const [custLoading, setCustLoading] = useState(false);
  const CUST_PAGE = 50;

  const loadCustomers = useCallback(async () => {
    setCustLoading(true);
    const { data } = await supabase.rpc('customer_survey_overview', {
      p_query: custDebounced.trim() || null, p_filter: custFilter,
      p_limit: CUST_PAGE, p_offset: custPage * CUST_PAGE,
    });
    const list = (data as any[]) ?? [];
    setCustRows(list);
    setCustTotal(list.length > 0 ? Number(list[0].total_count) : 0);
    setCustLoading(false);
  }, [custDebounced, custFilter, custPage]);

  useEffect(() => { if (tab === 'submissions') void loadCustomers(); }, [tab, loadCustomers]);
  useEffect(() => {
    const t = setTimeout(() => { setCustDebounced(custSearch); setCustPage(0); }, 300);
    return () => clearTimeout(t);
  }, [custSearch]);
  useEffect(() => { setCustPage(0); }, [custFilter]);

  // Every customer opens the SAME consultant dialog. If they have no survey yet
  // one is created on the spot, so a customer who never used the public QR form
  // still gets the full Consultant section rather than a cut-down form.
  const [startingFor, setStartingFor] = useState<string | null>(null);
  const openCustomerSurvey = async (row: any) => {
    if (row.survey_id) { setDetailId(row.survey_id); return; }
    setStartingFor(row.customer_id); setErr(null);
    const { data, error } = await supabase.rpc('upsert_consultant_survey', {
      p_customer_id: row.customer_id,
      p_remarks_condition: null, p_remarks_recommendation: null,
      p_acidity_result: null, p_health_goals: null,
      p_has_medical_condition: null, p_drinks_alcohol: null,
      p_smokes: null, p_on_treatment: null, p_treatment_list: null,
      // Only meaningful when there is a single store; otherwise the
      // function picks a sensible default itself.
      p_store_id: stores.length === 1 ? stores[0].id : null,
    });
    setStartingFor(null);
    if (error) { setErr(error.message); return; }
    await loadCustomers();
    setDetailId(data as string);
  };

  // Remarks log.
  const [remarksFor, setRemarksFor] = useState<any | null>(null);
  const [remarkList, setRemarkList] = useState<any[]>([]);
  const [newRemark, setNewRemark] = useState('');
  const [remarkType, setRemarkType] = useState('consultation');
  const [rBusy, setRBusy] = useState(false);
  const openRemarks = async (row: any) => {
    setRemarksFor(row); setNewRemark(''); setRemarkType('consultation');
    const { data } = await supabase.from('customer_remarks').select('*')
      .eq('customer_id', row.customer_id).order('created_at', { ascending: false });
    setRemarkList((data as any[]) ?? []);
  };
  const addRemark = async () => {
    if (!remarksFor || !newRemark.trim()) return;
    setRBusy(true);
    const { error } = await supabase.rpc('add_customer_remark', {
      p_customer_id: remarksFor.customer_id, p_remark: newRemark.trim(),
      p_remark_type: remarkType, p_survey_id: remarksFor.survey_id ?? null,
    });
    setRBusy(false);
    if (error) { setErr(error.message); return; }
    setNewRemark(''); await openRemarks(remarksFor); void loadCustomers();
  };
  const [links, setLinks] = useState<SurveyLink[]>([]);
  const [surveys, setSurveys] = useState<HealthSurvey[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    const [l, s, st] = await Promise.all([
      supabase.from('survey_links').select('*').order('created_at', { ascending: false }),
      supabase.from('health_surveys').select('*').order('submitted_at', { ascending: false }),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
    ]);
    setLinks((l.data as SurveyLink[]) ?? []);
    setSurveys((s.data as HealthSurvey[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const sName = (id: string) => stores.find(s => s.id === id)?.name ?? '—';
  const urlFor = (t: string) => `${window.location.origin}/survey/${t}`;

  // ---- Create link ----
  const [addOpen, setAddOpen] = useState(false);
  const [nf, setNf] = useState<any>({ store_id: '', event_name: '', expires_at: '' });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const create = async () => {
    if (!nf.store_id) { setErr('Select a store.'); return; }
    setBusy(true); setErr(null);
    const { error } = await supabase.from('survey_links').insert({
      token: randomToken(), store_id: nf.store_id,
      event_name: nf.event_name.trim() || null,
      expires_at: nf.expires_at ? new Date(nf.expires_at).toISOString() : null,
      created_by: profile?.id ?? null,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setAddOpen(false); setNf({ store_id: '', event_name: '', expires_at: '' }); load();
  };

  const toggleActive = async (l: SurveyLink) => {
    const { error } = await supabase.from('survey_links').update({ is_active: !l.is_active }).eq('id', l.id);
    if (error) alert(error.message); else load();
  };

  // ---- QR ----
  const [detailId, setDetailId] = useState<string | null>(null);
  const [sourcesOpen, setSourcesOpen] = useState(false);
  const [qrFor, setQrFor] = useState<SurveyLink | null>(null);
  const [qrImg, setQrImg] = useState('');
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!qrFor) { setQrImg(''); return; }
    QRCode.toDataURL(urlFor(qrFor.token), { width: 480, margin: 2 })
      .then(setQrImg).catch(() => setQrImg(''));
  }, [qrFor]);
  const copy = (t: string) => {
    navigator.clipboard?.writeText(urlFor(t));
    setCopied(true); setTimeout(() => setCopied(false), 1500);
  };
  const printQr = () => {
    if (!qrFor || !qrImg) return;
    const w = window.open('', '_blank'); if (!w) return;
    w.document.write(`<html><head><title>New Customer Form — QR</title><style>
      body{font-family:Arial,sans-serif;text-align:center;padding:40px;}
      img{width:320px;height:320px;} h2{margin:16px 0 4px;} .m{color:#666;font-size:13px;}
    </style></head><body>
      <h2>New Customer Form</h2>
      <div class="m">${sName(qrFor.store_id)}${qrFor.event_name ? ` · ${qrFor.event_name}` : ''}</div>
      <img src="${qrImg}" />
      <div class="m">Scan to complete the form</div>
    </body></html>`);
    w.document.close(); w.focus(); setTimeout(() => w.print(), 300);
  };

  const q = search.trim().toLowerCase();

  return (
    <div>
      <div className="page-header">
        <div><h2>Health Surveys</h2><p>Every customer, with their health survey and consultation remarks. Public QR submissions appear here too.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          {canManage && <button className="btn btn-secondary" onClick={() => setSourcesOpen(true)}>Customer Sources</button>}
          {canManage && tab === 'links' && <button className="btn btn-primary" onClick={() => { setAddOpen(true); setErr(null); }}><Plus size={16} /> New QR Link</button>}
        </div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 16, borderBottom: '1px solid var(--border)' }}>
        {([['submissions', 'Submissions'], ['links', 'QR Links']] as const).map(([v, l]) => (
          <button key={v} onClick={() => setTab(v)} style={{ padding: '8px 16px', background: 'none', border: 'none', borderBottom: tab === v ? '2px solid var(--primary)' : '2px solid transparent', color: tab === v ? 'var(--primary)' : 'var(--text-secondary)', fontWeight: tab === v ? 700 : 500, cursor: 'pointer' }}>{l}</button>
        ))}
      </div>

      {tab === 'submissions' && (
        <>
          <div style={{ display: 'flex', gap: 6, marginBottom: 12, flexWrap: 'wrap' }}>
            {([['all', 'All customers'], ['with_survey', 'With survey'], ['no_survey', 'No survey yet'], ['with_remarks', 'With remarks']] as const).map(([v, lbl]) => (
              <button key={v} className={`btn btn-sm ${custFilter === v ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setCustFilter(v)}>{lbl}</button>
            ))}
          </div>
          <div style={{ position: 'relative', marginBottom: 12, maxWidth: 380 }}>
            <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
            <input value={custSearch} onChange={e => setCustSearch(e.target.value)}
              placeholder="Search name, phone, email or survey no.…" style={{ paddingLeft: 30, width: '100%' }} />
          </div>
          <div className="card">
            <div className="table-wrap">
              {custLoading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
                : custRows.length === 0 ? <div className="empty-state"><ClipboardList size={32} style={{ opacity: 0.3 }} />
                    <p style={{ fontWeight: 600, marginTop: 8 }}>No customers match</p></div>
                : <table>
                    <thead><tr>
                      <th>Customer</th><th>Contact</th><th>Survey</th><th>Condition</th>
                      <th>Recommendation</th><th style={{ textAlign: 'right' }}>Remarks</th><th></th>
                    </tr></thead>
                    <tbody>{custRows.map(r => (
                      <tr key={r.customer_id}>
                        <td style={{ fontWeight: 600 }}>{r.full_name}</td>
                        <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                          {[r.phone, r.email].filter(Boolean).join(' · ') || '—'}
                        </td>
                        <td style={{ fontSize: 12 }}>
                          {r.survey_id
                            ? <><span className={`badge ${r.reviewed_at ? 'badge-success' : 'badge-accent'}`}>{r.survey_no}</span>
                                <div style={{ color: 'var(--text-muted)', fontSize: 11, marginTop: 2 }}>
                                  {r.source === 'consultant' ? 'By consultant' : 'Public form'}{r.reviewed_at ? ' · reviewed' : ' · pending'}
                                </div></>
                            : <span className="badge badge-muted">None yet</span>}
                        </td>
                        <td style={{ fontSize: 12, maxWidth: 200 }}>{r.remarks_condition ?? '—'}</td>
                        <td style={{ fontSize: 12, maxWidth: 200 }}>{r.remarks_recommendation ?? '—'}</td>
                        <td style={{ textAlign: 'right', fontSize: 12 }}>
                          {Number(r.remark_count) > 0
                            ? <>{r.remark_count}
                                <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>
                                  {r.last_remark_at ? new Date(r.last_remark_at).toLocaleDateString('en-GB') : ''}
                                </div></>
                            : '—'}
                        </td>
                        <td><div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                          <button className="btn btn-secondary btn-sm" onClick={() => openRemarks(r)}>Remarks</button>
                          <button className="btn btn-primary btn-sm"
                            disabled={startingFor === r.customer_id}
                            onClick={() => openCustomerSurvey(r)}>
                            <Eye size={12} /> {startingFor === r.customer_id ? 'Opening…' : r.survey_id ? 'Open' : 'Start survey'}
                          </button>
                        </div></td>
                      </tr>
                    ))}</tbody>
                  </table>}
            </div>
            {!custLoading && custTotal > 0 && (
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                            padding: '10px 12px', borderTop: '1px solid var(--border)', flexWrap: 'wrap', gap: 8 }}>
                <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
                  Showing {custPage * CUST_PAGE + 1}–{Math.min((custPage + 1) * CUST_PAGE, custTotal)} of {custTotal.toLocaleString()} customer(s)
                </div>
                <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                  <button className="btn btn-secondary btn-sm" disabled={custPage === 0}
                    onClick={() => setCustPage(p => Math.max(0, p - 1))}>Previous</button>
                  <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
                    Page {custPage + 1} of {Math.max(1, Math.ceil(custTotal / CUST_PAGE))}
                  </span>
                  <button className="btn btn-secondary btn-sm" disabled={(custPage + 1) * CUST_PAGE >= custTotal}
                    onClick={() => setCustPage(p => p + 1)}>Next</button>
                </div>
              </div>
            )}
          </div>
        </>
      )}

      {remarksFor && (
        <Modal title={`Remarks — ${remarksFor.full_name}`} maxWidth={560} onClose={() => setRemarksFor(null)}
          footer={<button className="btn btn-secondary" onClick={() => setRemarksFor(null)}>Close</button>}>
          <div className="form-grid">
            {canManage && (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Add a remark</label>
                <textarea rows={2} value={newRemark} onChange={e => setNewRemark(e.target.value)}
                  placeholder="Consultation note, recommendation or follow-up" />
                <div style={{ display: 'flex', gap: 8, marginTop: 6 }}>
                  <select value={remarkType} onChange={e => setRemarkType(e.target.value)} style={{ maxWidth: 180 }}>
                    <option value="consultation">Consultation</option>
                    <option value="recommendation">Recommendation</option>
                    <option value="follow_up">Follow-up</option>
                    <option value="other">Other</option>
                  </select>
                  <button className="btn btn-primary btn-sm" onClick={addRemark} disabled={rBusy || !newRemark.trim()}>
                    {rBusy ? 'Saving…' : 'Add remark'}
                  </button>
                </div>
              </div>
            )}
            <div>
              <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6 }}>History ({remarkList.length})</div>
              {remarkList.length === 0
                ? <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No remarks recorded yet.</div>
                : <div style={{ maxHeight: 280, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
                    {remarkList.map(r => (
                      <div key={r.id} style={{ padding: '8px 10px', borderBottom: '1px solid var(--border)' }}>
                        <div style={{ fontSize: 12.5 }}>{r.remark}</div>
                        <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>
                          {String(r.remark_type).replace('_', ' ')} · {new Date(r.created_at).toLocaleString('en-GB')}
                        </div>
                      </div>
                    ))}
                  </div>}
            </div>
          </div>
        </Modal>
      )}

      {tab === 'links' && (
        <div className="card"><div className="table-wrap">
          {links.length === 0 ? <div className="empty-state"><QrCode size={32} style={{ opacity: 0.3 }} />
              <p style={{ fontWeight: 600, marginTop: 8 }}>No QR links yet</p>
              <p style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>Create one per store or event.</p></div>
            : <table>
                <thead><tr><th>Store</th><th>Event</th><th>Link</th><th>Expires</th><th>Status</th><th></th></tr></thead>
                <tbody>{links.map(l => (
                  <tr key={l.id}>
                    <td><strong>{sName(l.store_id)}</strong></td>
                    <td style={{ fontSize: 12.5 }}>{l.event_name || '—'}</td>
                    <td style={{ fontSize: 11.5, color: 'var(--text-muted)', maxWidth: 260, overflow: 'hidden', textOverflow: 'ellipsis' }}>{urlFor(l.token)}</td>
                    <td style={{ fontSize: 12.5 }}>{l.expires_at ? new Date(l.expires_at).toLocaleDateString() : '—'}</td>
                    <td>{l.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => setQrFor(l)}><QrCode size={12} /> QR</button>
                        <button className="btn btn-secondary btn-sm" onClick={() => copy(l.token)}><Copy size={12} /> Copy</button>
                        {canManage && <button className="btn btn-secondary btn-sm" onClick={() => toggleActive(l)}>{l.is_active ? 'Deactivate' : 'Activate'}</button>}
                      </div>
                    </td>
                  </tr>
                ))}</tbody>
              </table>}
        </div></div>
      )}
      {detailId && <SurveyDetailModal surveyId={detailId} onClose={() => setDetailId(null)} onSaved={load} />}
      {sourcesOpen && <SourceOptionsModal onClose={() => setSourcesOpen(false)} />}

      {addOpen && (
        <Modal title="New Customer Form — QR Link" maxWidth={440} onClose={() => setAddOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setAddOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={create} disabled={busy}>{busy ? 'Creating…' : 'Create'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-group"><label>Store *</label>
              <select value={nf.store_id} onChange={e => setNf({ ...nf, store_id: e.target.value })}>
                <option value="">— Select —</option>{stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select></div>
            <div className="form-group"><label>Event (optional)</label><input value={nf.event_name} onChange={e => setNf({ ...nf, event_name: e.target.value })} placeholder="e.g. Roadshow @ Adelphi" /></div>
            <div className="form-group"><label>Expires (optional)</label><input type="date" value={nf.expires_at} onChange={e => setNf({ ...nf, expires_at: e.target.value })} /></div>
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span>
              <div>Anyone with this link can submit a survey — but it can never read customer or health data. Deactivate it when the event ends.</div></div>
          </div>
        </Modal>
      )}

      {qrFor && (
        <Modal title={`New Customer Form QR — ${sName(qrFor.store_id)}`} maxWidth={380} onClose={() => setQrFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setQrFor(null)}>Close</button><button className="btn btn-primary" onClick={printQr}>Print</button></>}>
          <div style={{ textAlign: 'center' }}>
            {qrImg ? <img src={qrImg} alt="New Customer Form QR" style={{ width: 260, height: 260 }} /> : <RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} />}
            {qrFor.event_name && <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{qrFor.event_name}</div>}
            <div style={{ display: 'flex', gap: 6, marginTop: 12 }}>
              <input readOnly value={urlFor(qrFor.token)} style={{ fontSize: 11.5 }} onFocus={e => e.target.select()} />
              <button className="btn btn-secondary btn-sm" onClick={() => copy(qrFor.token)}>{copied ? <Check size={12} /> : <Link2 size={12} />}</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default SurveysPage;
