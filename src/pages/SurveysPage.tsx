import React, { useEffect, useState, useCallback, useRef } from 'react';
import QRCode from 'qrcode';
import { supabase } from '../lib/supabase';
import { esc } from '../lib/printDoc';
import { useAuth } from '../context/AuthContext';
import { Store, SurveyLink, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import SurveyDetailModal from '../components/SurveyDetailModal';
import type { SurveyCustomer, SurveyStoreOption } from '../components/SurveyDetailModal';
import SourceOptionsModal from '../components/SourceOptionsModal';
import SurveyHoldsPanel, { HeldForm } from '../components/SurveyHoldsPanel';
import { linkExpiryFromDay, linkStatus, sgDate, sgDateTime } from '../lib/survey/links.mjs';
import { RefreshCw, Plus, QrCode, Copy, ClipboardList, Search, Link2, Check, Eye } from 'lucide-react';

const randomToken = () => {
  const a = new Uint8Array(16);
  crypto.getRandomValues(a);
  return Array.from(a, b => b.toString(16).padStart(2, '0')).join('');
};

type SourceOption = { id: string; label: string; requires_details: boolean };
/** The source an event link starts with: "Event Name", as before 419. */
const defaultEventSource = (opts: SourceOption[]) =>
  opts.find(o => /^event/i.test(o.label)) ?? opts.find(o => /event|roadshow/i.test(o.label)) ?? null;

const SurveysPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  // Health declarations, the consultant's survey and the remarks are not an
  // Inventory Manager's (the server refuses them all, 406 and 419), so they
  // are not offered Start survey, Open or Remarks.
  const canOpenSurvey = profile?.role !== 'inventory_manager';
  const [tab, setTab] = useState<'submissions' | 'to_match' | 'links'>('submissions');
  // 433: QR forms the server held for staff instead of making a second
  // customer. null until the server answers (and before 433 is applied, or
  // for an Inventory Manager, who sees no health surveys): no To match tab.
  const [holds, setHolds] = useState<HeldForm[] | null>(null);
  const [holdsErr, setHoldsErr] = useState<string | null>(null);
  const loadHolds = useCallback(async () => {
    if (!canOpenSurvey) { setHolds(null); return; }
    const { data, error } = await supabase.rpc('health_survey_holds_list');
    // A server without 433 has no such function (PGRST202): no tab. Any other
    // failure keeps the list already shown, and says so.
    if (error) {
      if (error.code === 'PGRST202' || /Could not find the function/i.test(error.message)) setHolds(null);
      else setHoldsErr(error.message);
      return;
    }
    setHoldsErr(null);
    setHolds((data as HeldForm[]) ?? []);
  }, [canOpenSurvey]);
  useEffect(() => { void loadHolds(); }, [loadHolds]);
  useEffect(() => { if (!holds && tab === 'to_match') setTab('submissions'); }, [holds, tab]);
  // Every customer, with their single survey and remark count, so a consultant
  // can record findings for people who never used the public QR form.
  const [custRows, setCustRows] = useState<any[]>([]);
  const [custSearch, setCustSearch] = useState('');
  const [custDebounced, setCustDebounced] = useState('');
  const [custFilter, setCustFilter] = useState<'all' | 'with_survey' | 'no_survey' | 'with_remarks'>('all');
  const [custPage, setCustPage] = useState(0);
  const [custTotal, setCustTotal] = useState(0);
  const [custLoading, setCustLoading] = useState(false);
  const [custErr, setCustErr] = useState<string | null>(null);
  const CUST_PAGE = 50;
  // Only the newest request may fill the list: a slow older answer is dropped.
  const custSeq = useRef(0);

  const loadCustomers = useCallback(async () => {
    // 419: the list shows the consultant's findings, so the server refuses it
    // to Inventory Managers; it is not asked for.
    if (!canOpenSurvey) { setCustRows([]); setCustTotal(0); return; }
    const seq = ++custSeq.current;
    setCustLoading(true);
    const { data, error } = await supabase.rpc('customer_survey_overview', {
      p_query: custDebounced.trim() || null, p_filter: custFilter,
      p_limit: CUST_PAGE, p_offset: custPage * CUST_PAGE,
    });
    if (seq !== custSeq.current) return;
    setCustLoading(false);
    // CUSTOMERS-6: a failed load says so, instead of "No customers match".
    if (error) { setCustErr(error.message); return; }
    setCustErr(null);
    const list = (data as any[]) ?? [];
    setCustRows(list);
    setCustTotal(list.length > 0 ? Number(list[0].total_count) : 0);
  }, [custDebounced, custFilter, custPage, canOpenSurvey]);

  useEffect(() => { if (tab === 'submissions') void loadCustomers(); }, [tab, loadCustomers]);
  useEffect(() => {
    const t = setTimeout(() => { setCustDebounced(custSearch); setCustPage(0); }, 300);
    return () => clearTimeout(t);
  }, [custSearch]);
  useEffect(() => { setCustPage(0); }, [custFilter]);

  // CUSTOMERS-5: every customer opens the same consultant window. With no
  // survey yet, nothing is made until the first real save in that window, so
  // a customer only looked at can still fill in the QR form.
  const [detailId, setDetailId] = useState<string | null>(null);
  const [startFor, setStartFor] = useState<SurveyCustomer | null>(null);
  const openCustomerSurvey = (row: any) => {
    if (row.survey_id) { setStartFor(null); setDetailId(row.survey_id); return; }
    setDetailId(null);
    setStartFor({ customer_id: row.customer_id, full_name: row.full_name, phone: row.phone, email: row.email });
  };

  // Remarks log.
  const [remarksFor, setRemarksFor] = useState<any | null>(null);
  const [remarkList, setRemarkList] = useState<any[]>([]);
  const [remarkErr, setRemarkErr] = useState<string | null>(null);
  const [newRemark, setNewRemark] = useState('');
  const [remarkType, setRemarkType] = useState('consultation');
  const [rBusy, setRBusy] = useState(false);
  const openRemarks = async (row: any) => {
    setRemarksFor(row); setNewRemark(''); setRemarkType('consultation'); setRemarkErr(null);
    const { data, error } = await supabase.from('customer_remarks').select('*')
      .eq('customer_id', row.customer_id).order('created_at', { ascending: false });
    if (error) setRemarkErr(`The remarks could not be loaded: ${error.message}`);
    setRemarkList((data as any[]) ?? []);
  };
  const addRemark = async () => {
    if (!remarksFor || !newRemark.trim()) return;
    setRBusy(true); setRemarkErr(null);
    const { error } = await supabase.rpc('add_customer_remark', {
      p_customer_id: remarksFor.customer_id, p_remark: newRemark.trim(),
      p_remark_type: remarkType, p_survey_id: remarksFor.survey_id ?? null,
    });
    setRBusy(false);
    // Shown inside the Remarks window, where it was asked for.
    if (error) { setRemarkErr(error.message); return; }
    setNewRemark(''); await openRemarks(remarksFor); void loadCustomers();
  };
  const [links, setLinks] = useState<SurveyLink[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [myStores, setMyStores] = useState<SurveyStoreOption[]>([]);
  const [sourceOptions, setSourceOptions] = useState<SourceOption[]>([]);
  const [linksErr, setLinksErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // CUSTOMERS-6: the QR links, stores and sources; no longer every survey
  // with its signature (it was never shown).
  const load = useCallback(async () => {
    setLoading(true);
    const [l, st, mine, src] = await Promise.all([
      supabase.from('survey_links').select('*').order('created_at', { ascending: false }),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.rpc('my_assigned_stores'),
      supabase.rpc('active_customer_source_options'),
    ]);
    setLinksErr(l.error ? l.error.message : null);
    setLinks((l.data as SurveyLink[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setMyStores(((mine.data as any[]) ?? []).map(x => ({ store_id: x.store_id, store_name: x.store_name })));
    setSourceOptions((src.data as SourceOption[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);
  // Refresh, and every save in a survey window, reload the lists shown.
  const refreshAll = () => { void load(); void loadHolds(); void loadCustomers(); };

  const sName = (id: string) => stores.find(s => s.id === id)?.name ?? '—';
  const srcName = (id?: string | null) => (id ? sourceOptions.find(o => o.id === id)?.label ?? null : null);
  const urlFor = (t: string) => `${window.location.origin}/survey/${t}`;

  // ---- Create link ----
  const [addOpen, setAddOpen] = useState(false);
  const emptyLink = { store_id: '', event_name: '', expires_at: '', source_option_id: '' };
  const [nf, setNf] = useState<any>(emptyLink);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const create = async () => {
    if (!nf.store_id) { setErr('Select a store.'); return; }
    const event = nf.event_name.trim();
    // CUSTOMERS-12: an event's link says how its customers heard about us.
    if (event && !nf.source_option_id) { setErr('Choose how these customers heard about us.'); return; }
    setBusy(true); setErr(null);
    const { error } = await supabase.from('survey_links').insert({
      token: randomToken(), store_id: nf.store_id,
      event_name: event || null,
      source_option_id: event ? nf.source_option_id : null,
      // CUSTOMERS-7: the link works to the end of the chosen day in Singapore.
      expires_at: linkExpiryFromDay(nf.expires_at),
      created_by: profile?.id ?? null,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setAddOpen(false); setNf(emptyLink); load();
  };
  const openNewLink = () => {
    setErr(null);
    setNf({ ...emptyLink, source_option_id: defaultEventSource(sourceOptions)?.id ?? '' });
    setAddOpen(true);
  };

  const toggleActive = async (l: SurveyLink) => {
    const { error } = await supabase.from('survey_links').update({ is_active: !l.is_active }).eq('id', l.id);
    if (error) alert(error.message); else load();
  };

  // ---- QR ----
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
      <div class="m">${esc(sName(qrFor.store_id))}${qrFor.event_name ? ` · ${esc(qrFor.event_name)}` : ''}</div>
      <img src="${esc(qrImg)}" />
      <div class="m">Scan to complete the form</div>
    </body></html>`);
    w.document.close(); w.focus(); setTimeout(() => w.print(), 300);
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Health Surveys</h2><p>Every customer, with their health survey and consultation remarks. Public QR submissions appear here too.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={refreshAll}><RefreshCw size={15} className={loading || custLoading ? 'spin' : ''} /> Refresh</button>
          {canManage && <button className="btn btn-secondary" onClick={() => setSourcesOpen(true)}>Customer Sources</button>}
          {canManage && tab === 'links' && <button className="btn btn-primary" onClick={openNewLink}><Plus size={16} /> New QR Link</button>}
        </div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 16, borderBottom: '1px solid var(--border)' }}>
        {([['submissions', 'Submissions'],
           ...(holds ? [['to_match', `To match (${holds.length})`] as const] : []),
           ['links', 'QR Links']] as const).map(([v, l]) => (
          <button key={v} data-tab={v} onClick={() => setTab(v)} style={{ padding: '8px 16px', background: 'none', border: 'none', borderBottom: tab === v ? '2px solid var(--primary)' : '2px solid transparent', color: tab === v ? 'var(--primary)' : 'var(--text-secondary)', fontWeight: tab === v ? 700 : 500, cursor: 'pointer' }}>{l}</button>
        ))}
      </div>

      {tab === 'submissions' && !canOpenSurvey && (
        <div className="card"><div className="empty-state" data-no-health-data>
          <ClipboardList size={32} style={{ opacity: 0.3 }} />
          <p style={{ fontWeight: 600, marginTop: 8 }}>Health surveys are for Owners, Managers and Staff.</p>
        </div></div>
      )}
      {tab === 'submissions' && canOpenSurvey && (
        <>
          {holds && holds.length > 0 && (
            <div className="alert alert-warning" style={{ marginBottom: 12, alignItems: 'center' }}>
              <span>⚠</span>
              <div style={{ flex: 1 }}>
                {holds.length === 1 ? '1 QR form is' : `${holds.length} QR forms are`} waiting to be matched to a customer.
              </div>
              <button className="btn btn-secondary btn-sm" onClick={() => setTab('to_match')}>Open To match</button>
            </div>
          )}
          {custErr && (
            <div className="alert alert-danger" role="alert" data-cust-error style={{ marginBottom: 12, alignItems: 'center' }}>
              <span>⚠</span>
              <div style={{ flex: 1 }}>Could not load customers ({custErr}).</div>
              <button className="btn btn-secondary btn-sm" onClick={() => void loadCustomers()}>Retry</button>
            </div>
          )}
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
                    <p style={{ fontWeight: 600, marginTop: 8 }}>{custErr ? 'Could not load customers' : 'No customers match'}</p></div>
                : <table>
                    <thead><tr>
                      <th>Customer</th><th>Contact</th><th>Survey</th><th>Condition</th>
                      <th>Recommendation</th><th style={{ textAlign: 'right' }}>Remarks</th><th></th>
                    </tr></thead>
                    <tbody>{custRows.map(r => (
                      <tr key={r.customer_id}>
                        <td style={{ fontWeight: 600 }}>{r.full_name}<div style={{ fontSize: 10.5, fontWeight: 400, color: 'var(--text-muted)', overflowWrap: 'anywhere' }}>Customer ID: {r.customer_id}</div></td>
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
                                  {r.last_remark_at ? sgDate(r.last_remark_at) : ''}
                                </div></>
                            : '—'}
                        </td>
                        <td><div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                          {canOpenSurvey && <button className="btn btn-secondary btn-sm" data-remarks={r.customer_id} onClick={() => openRemarks(r)}>Remarks</button>}
                          {canOpenSurvey && <button className="btn btn-primary btn-sm" data-open-survey={r.customer_id}
                            onClick={() => openCustomerSurvey(r)}>
                            <Eye size={12} /> {r.survey_id ? 'Open' : 'Start survey'}
                          </button>}
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
            {remarkErr && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{remarkErr}</div></div>}
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
                          {String(r.remark_type).replace('_', ' ')} · {sgDateTime(r.created_at)}
                        </div>
                      </div>
                    ))}
                  </div>}
            </div>
          </div>
        </Modal>
      )}

      {tab === 'to_match' && holds && (
        <>
          {holdsErr && (
            <div className="alert alert-warning" role="alert" style={{ marginBottom: 12 }}>
              <span>⚠</span>
              <div>The waiting forms could not be reloaded just now ({holdsErr}). The list below may be out of date;
                press Refresh to try again.</div>
            </div>
          )}
          <SurveyHoldsPanel forms={holds} canClose={canManage}
            onChanged={() => { void loadHolds(); void loadCustomers(); }} />
        </>
      )}

      {tab === 'links' && (
        <div className="card"><div className="table-wrap">
          {linksErr && <div className="alert alert-danger" role="alert" style={{ margin: 12 }}><span>⚠</span><div>The QR links could not be loaded ({linksErr}).</div></div>}
          {links.length === 0 ? <div className="empty-state"><QrCode size={32} style={{ opacity: 0.3 }} />
              <p style={{ fontWeight: 600, marginTop: 8 }}>No QR links yet</p>
              <p style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>Create one per store or event.</p></div>
            : <table>
                <thead><tr><th>Store</th><th>Event</th><th>Link</th><th>Last day</th><th>Status</th><th></th></tr></thead>
                <tbody>{links.map(l => {
                  const status = linkStatus(l);
                  return (
                  <tr key={l.id} data-link={l.id}>
                    <td><strong>{sName(l.store_id)}</strong></td>
                    <td style={{ fontSize: 12.5 }}>{l.event_name || '—'}
                      {l.event_name && srcName(l.source_option_id) && (
                        <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Heard about us: {srcName(l.source_option_id)}</div>
                      )}</td>
                    <td style={{ fontSize: 11.5, color: 'var(--text-muted)', maxWidth: 260, overflow: 'hidden', textOverflow: 'ellipsis' }}>{urlFor(l.token)}</td>
                    <td style={{ fontSize: 12.5 }}>{l.expires_at ? sgDate(l.expires_at) : '—'}</td>
                    <td>{status === 'active' ? <span className="badge badge-success">Active</span>
                      : status === 'expired' ? <span className="badge badge-danger">Expired</span>
                      : <span className="badge badge-muted">Inactive</span>}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => setQrFor(l)}><QrCode size={12} /> QR</button>
                        <button className="btn btn-secondary btn-sm" onClick={() => copy(l.token)}><Copy size={12} /> Copy</button>
                        {canManage && <button className="btn btn-secondary btn-sm" onClick={() => toggleActive(l)}>{l.is_active ? 'Deactivate' : 'Activate'}</button>}
                      </div>
                    </td>
                  </tr>
                  );
                })}</tbody>
              </table>}
        </div></div>
      )}
      {(detailId || startFor) && (
        <SurveyDetailModal key={detailId ?? startFor?.customer_id}
          surveyId={detailId} customer={detailId ? null : startFor} stores={myStores}
          onClose={() => { setDetailId(null); setStartFor(null); }}
          onSaved={() => { void loadCustomers(); }} />
      )}
      {sourcesOpen && <SourceOptionsModal onClose={() => { setSourcesOpen(false); void load(); }} />}

      {addOpen && (
        <Modal title="New Customer Form — QR Link" maxWidth={440} onClose={() => setAddOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setAddOpen(false)}>Cancel</button><button className="btn btn-primary" data-create-link onClick={create} disabled={busy}>{busy ? 'Creating…' : 'Create'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-group"><label htmlFor="link-store">Store *</label>
              <select id="link-store" value={nf.store_id} onChange={e => setNf({ ...nf, store_id: e.target.value })}>
                <option value="">— Select —</option>{stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select></div>
            <div className="form-group"><label htmlFor="link-event">Event (optional)</label><input id="link-event" value={nf.event_name} onChange={e => setNf({ ...nf, event_name: e.target.value })} placeholder="e.g. Roadshow @ Adelphi" /></div>
            {nf.event_name.trim() && (
              <div className="form-group"><label htmlFor="link-source">How these customers heard about us *</label>
                <select id="link-source" value={nf.source_option_id} onChange={e => setNf({ ...nf, source_option_id: e.target.value })}>
                  <option value="">— Choose —</option>
                  {sourceOptions.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}
                </select>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 2 }}>
                  The form does not ask them; every form from this link records this, with the event's name.
                </div></div>
            )}
            <div className="form-group"><label htmlFor="link-expiry">Last day the link works (optional)</label>
              <input id="link-expiry" type="date" value={nf.expires_at} onChange={e => setNf({ ...nf, expires_at: e.target.value })} />
              <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 2 }}>It works until midnight that day, Singapore time.</div></div>
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
              <button className="btn btn-secondary btn-sm" aria-label="Copy link" onClick={() => copy(qrFor.token)}>{copied ? <Check size={12} /> : <Link2 size={12} />}</button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default SurveysPage;
