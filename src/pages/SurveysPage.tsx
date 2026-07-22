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
  const [links, setLinks] = useState<SurveyLink[]>([]);
  const [surveys, setSurveys] = useState<HealthSurvey[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [revFilter, setRevFilter] = useState<'all' | 'pending' | 'reviewed'>('all');

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
  const shown = surveys.filter(s => (revFilter === 'all' || (revFilter === 'reviewed' ? !!s.reviewed_at : !s.reviewed_at)))
    .filter(s => !q || s.full_name.toLowerCase().includes(q)
    || s.phone.toLowerCase().includes(q) || (s.email ?? '').toLowerCase().includes(q)
    || s.survey_no.toLowerCase().includes(q));

  return (
    <div>
      <div className="page-header">
        <div><h2>Health Surveys</h2><p><strong>New Customer Form</strong> submissions from the public QR code. Each submission creates a new customer.</p></div>
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
            {([['all', 'All'], ['pending', 'Pending review'], ['reviewed', 'Reviewed']] as const).map(([v, lbl]) => (
              <button key={v} className={`btn btn-sm ${revFilter === v ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setRevFilter(v)}>
                {lbl} ({v === 'all' ? surveys.length : v === 'pending' ? surveys.filter(x => !x.reviewed_at).length : surveys.filter(x => !!x.reviewed_at).length})
              </button>
            ))}
          </div>
          <div style={{ position: 'relative', marginBottom: 12, maxWidth: 380 }}>
            <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name, phone, email or survey no.…" style={{ paddingLeft: 30 }} />
          </div>
          <div className="card"><div className="table-wrap">
            {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
              : shown.length === 0 ? <div className="empty-state"><ClipboardList size={32} style={{ opacity: 0.3 }} />
                  <p style={{ fontWeight: 600, marginTop: 8 }}>{surveys.length === 0 ? 'No forms submitted yet' : 'No submissions match'}</p>
                  {surveys.length === 0 && <p style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>Create a QR link and let a customer scan it.</p>}</div>
              : <table>
                  <thead><tr><th>Survey</th><th>Name</th><th>Contact</th><th>Source</th><th>Store / Event</th><th>Submitted</th><th>Review</th><th></th></tr></thead>
                  <tbody>{shown.map(s => (
                    <tr key={s.id}>
                      <td><strong>{s.survey_no}</strong>
                        {s.pdf_url && <div style={{ fontSize: 10.5, color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 3 }}><FileText size={10} /> signed PDF</div>}</td>
                      <td>{s.full_name}<div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{s.sex ?? ''}{s.age ? ` · ${s.age}y` : ''}</div></td>
                      <td style={{ fontSize: 12.5 }}>{s.phone}{s.email && <div style={{ color: 'var(--text-muted)', fontSize: 11 }}>{s.email}</div>}</td>
                      <td style={{ fontSize: 12.5 }}>{(s as any).source_label ?? <span style={{ color: 'var(--text-muted)' }}>—</span>}
                        {(s as any).source_details && <div style={{ color: 'var(--text-muted)', fontSize: 11 }}>{(s as any).source_details}</div>}</td>
                      <td style={{ fontSize: 12.5 }}>{sName(s.store_id)}{s.event_name && <div style={{ color: 'var(--text-muted)', fontSize: 11 }}>{s.event_name}</div>}</td>
                      <td style={{ fontSize: 12.5 }}>{new Date(s.submitted_at).toLocaleString()}</td>
                      <td>
                        {s.reviewed_at
                          ? <span className="badge badge-success">Reviewed</span>
                          : <span className="badge badge-warning">Pending</span>}
                        {s.acidity_result && <div style={{ fontSize: 10.5, color: 'var(--text-muted)', marginTop: 2, textTransform: 'capitalize' }}>Acidity: {s.acidity_result}</div>}
                      </td>
                      <td><button className="btn btn-secondary btn-sm" onClick={() => setDetailId(s.id)}><Eye size={12} /> Open</button></td>
                    </tr>
                  ))}</tbody>
                </table>}
          </div></div>
        </>
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
