import React, { useEffect, useRef, useState } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isManagerOrAbove } from '../types';
import { NoAccess } from '../components/ui';
import { ChevronLeft, ChevronRight, RefreshCw, ScrollText, Search, X } from 'lucide-react';

// The Audit Log is read a page at a time on the server (428: audit_log_page),
// so every entry can be reached, not only the newest 500. Filters and search
// run there too. Times are Singapore time.

const PAGE_SIZE = 50;
// The export reads the same search 1,000 entries at a time.
const EXPORT_PAGE = 1000;
// Excel holds up to 32,767 characters in a cell.
const CELL_LIMIT = 32000;

const ACTION_CLS: Record<string, string> = {
  stock_in: 'badge-success', invoice_paid: 'badge-success', restored: 'badge-success',
  transfer_approved: 'badge-success', adjustment_approved: 'badge-success',
  invoice_refunded: 'badge-danger', invoice_cancelled: 'badge-danger',
  transfer_rejected: 'badge-danger', invoice_deleted: 'badge-danger',
  transfer_partially_approved: 'badge-primary',
  staff_commission_earned: 'badge-success', staff_commission_paid: 'badge-success',
  staff_commission_reversed: 'badge-danger',
  transfer_requested_by_staff: 'badge-primary', commission_paid: 'badge-success', invoice_printed: 'badge-muted',
};

/** One entry as audit_log_page returns it. */
export interface AuditEntry {
  id: string;
  created_at: string;
  action: string;
  table_name: string;
  /** The stored module, or one taken from the table when the entry has none. */
  module: string | null;
  /** False when the module was taken from the table. */
  module_recorded: boolean;
  changed_by: string | null;
  /** 'System' when nobody was signed in. */
  actor_name: string;
  actor_role: string | null;
  reason: string | null;
  record_id: string | null;
  /** The invoice number, when the entry is about an invoice. */
  record_label: string | null;
  old_data: unknown;
  new_data: unknown;
}

interface Choice { value: string; count: number }
interface ActorChoice { id: string; name: string; count: number }
interface Choices { modules: Choice[]; tables: Choice[]; actors: ActorChoice[] }
interface PageResult { as_of: string; total: number; rows: AuditEntry[]; choices?: Choices | null }

interface Filters { from: string; to: string; module: string; table: string; actor: string; text: string }
const NO_FILTERS: Filters = { from: '', to: '', module: '', table: '', actor: '', text: '' };

// One search: its filters, the page on screen, and the time it was made. The
// pages of one search all pass that time, so entries made after the search
// started are left out. An entry from a write still in progress when the
// search started can still appear later (it is dated when its write began),
// so the export skips an entry it already has. A new search (or Refresh)
// starts with none.
interface Query { filters: Filters; offset: number; asOf: string | null; withChoices: boolean }

const searchArgs = (f: Filters) => ({
  p_from: f.from || null,
  p_to: f.to || null,
  p_module: f.module || null,
  p_table: f.table || null,
  p_actor: f.actor || null,
  p_text: f.text.trim() || null,
});

const SGT_DAY = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Singapore', day: '2-digit', month: 'short', year: 'numeric' });
const SGT_TIME = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Singapore', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
const SGT_STAMP = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
});

/** "2026-10-09 15:53:20", Singapore time: the export's When. */
export function sgtStamp(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '';
  const p = Object.fromEntries(SGT_STAMP.formatToParts(d).map(x => [x.type, x.value]));
  return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}:${p.second}`;
}

const json = (v: unknown) => (v === null || v === undefined ? '' : JSON.stringify(v));

/** What changed, in full: the before and after details. */
export function auditDetailsText(e: Pick<AuditEntry, 'old_data' | 'new_data'>): string {
  const parts: string[] = [];
  if (e.old_data !== null && e.old_data !== undefined) parts.push(`Before: ${json(e.old_data)}`);
  if (e.new_data !== null && e.new_data !== undefined) parts.push(`After: ${json(e.new_data)}`);
  const text = parts.join('\n');
  return text.length > CELL_LIMIT ? `${text.slice(0, CELL_LIMIT)}… (cut at ${CELL_LIMIT.toLocaleString('en-GB')} characters)` : text;
}

const actionText = (a: string) => a.replace(/_/g, ' ');
const roleText = (r: string | null) => (r ? r.replace(/_/g, ' ') : '');
const moduleText = (e: AuditEntry) => (e.module ? (e.module_recorded ? e.module : `${e.module} (from table)`) : '');
const recordText = (e: AuditEntry) => e.record_label || e.record_id || '';

const AuditLogPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isManagerOrAbove(profile?.role);

  const [query, setQuery] = useState<Query>({ filters: NO_FILTERS, offset: 0, asOf: null, withChoices: true });
  const [textInput, setTextInput] = useState('');
  const [rows, setRows] = useState<AuditEntry[]>([]);
  const [total, setTotal] = useState(0);
  const [choices, setChoices] = useState<Choices | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // The as-of time of the search on screen, for its next pages and the export.
  const asOfRef = useRef<string | null>(null);
  const queryRef = useRef(query);
  queryRef.current = query;
  const choicesLoaded = useRef(false);
  const request = useRef(0);

  // A new search: the first page, with a new as-of time.
  const search = (change: (f: Filters) => Filters, withChoices = false) => {
    asOfRef.current = null;
    setQuery(q => ({ filters: change(q.filters), offset: 0, asOf: null, withChoices }));
  };
  const setFilter = (key: keyof Filters, value: string) => search(f => ({ ...f, [key]: value }));
  const goTo = (offset: number) => setQuery(q => ({ ...q, offset, asOf: asOfRef.current, withChoices: false }));
  const refresh = () => search(f => f, true);

  // Typing waits for a pause before it searches.
  useEffect(() => {
    const t = setTimeout(() => {
      if (queryRef.current.filters.text !== textInput) search(f => ({ ...f, text: textInput }));
    }, 350);
    return () => clearTimeout(t);
  }, [textInput]);

  useEffect(() => {
    if (!hasAccess) return;
    // Only the latest request may land, so a slow answer never replaces a newer one.
    const id = ++request.current;
    setLoading(true);
    setError(null);
    void (async () => {
      try {
        // The filters' choices come with the first page, and again on Refresh
        // (or until they have loaded once).
        const withChoices = query.withChoices || !choicesLoaded.current;
        const { data, error: rpcError } = await supabase.rpc('audit_log_page', {
          ...searchArgs(query.filters),
          p_limit: PAGE_SIZE, p_offset: query.offset, p_as_of: query.asOf, p_with_choices: withChoices,
        });
        if (rpcError) throw new Error(rpcError.message);
        if (id !== request.current) return;
        const page = (data ?? {}) as PageResult;
        if (!query.asOf) asOfRef.current = page.as_of ?? null;
        setRows(Array.isArray(page.rows) ? page.rows : []);
        setTotal(Number(page.total ?? 0));
        if (withChoices && page.choices) { setChoices(page.choices); choicesLoaded.current = true; }
      } catch (e) {
        if (id !== request.current) return;
        setRows([]); setTotal(0);
        setError(e instanceof Error ? e.message : String(e));
      } finally {
        if (id === request.current) setLoading(false);
      }
    })();
  }, [query, hasAccess]);

  // Every entry of the search on screen, at the same as-of time, for the export.
  // Each entry once: one that arrives late moves the rest down a place, so the
  // next page can start with an entry already read.
  const fetchAll = async (): Promise<AuditEntry[]> => {
    const out: AuditEntry[] = [];
    const seen = new Set<string>();
    let asOf = asOfRef.current;
    for (let offset = 0; ; offset += EXPORT_PAGE) {
      const { data, error: rpcError } = await supabase.rpc('audit_log_page', {
        ...searchArgs(query.filters), p_limit: EXPORT_PAGE, p_offset: offset, p_as_of: asOf, p_with_choices: false,
      });
      if (rpcError) throw new Error(rpcError.message);
      const page = (data ?? {}) as PageResult;
      asOf = asOf ?? page.as_of ?? null;
      const got = Array.isArray(page.rows) ? page.rows : [];
      for (const e of got) if (!seen.has(e.id)) { seen.add(e.id); out.push(e); }
      if (got.length < EXPORT_PAGE || out.length >= Number(page.total ?? 0)) return out;
    }
  };

  if (!hasAccess) return <NoAccess message="Only Owners, Admins, and Managers can view the audit log." />;

  const f = query.filters;
  const filtered = Boolean(f.from || f.to || f.module || f.table || f.actor || f.text.trim());
  const first = total === 0 ? 0 : query.offset + 1;
  const last = Math.min(query.offset + rows.length, total);
  const keepChoice = (list: Choice[], value: string) =>
    value && !list.some(c => c.value === value) ? [...list, { value, count: 0 }] : list;

  return (
    <div>
      <div className="page-header">
        <div><h2>Audit Log</h2><p>Every important action, newest first. Read-only. Times are Singapore time.</p></div>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <ExcelExportButton<AuditEntry>
            rows={rows} fetchAll={fetchAll} filename="audit-log" sheetName="Audit Log"
            disabled={loading || !!error || total === 0}
            columns={[
              { header: 'When (SGT)', value: e => sgtStamp(e.created_at) },
              { header: 'Action', value: e => actionText(e.action) },
              { header: 'Table', value: e => e.table_name ?? '' },
              { header: 'Module', value: e => moduleText(e) },
              { header: 'By', value: e => e.actor_name ?? '' },
              { header: 'Role', value: e => roleText(e.actor_role) },
              { header: 'Reason', value: e => e.reason ?? '' },
              { header: 'Record', value: e => recordText(e) },
              { header: 'Details', value: e => auditDetailsText(e) },
            ]} />
          <button className="btn btn-secondary" onClick={refresh}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 10, marginBottom: 14, flexWrap: 'wrap', alignItems: 'flex-end' }}>
        <div style={{ position: 'relative', flex: '1 1 240px', maxWidth: 360 }}>
          <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
          <input value={textInput} onChange={e => setTextInput(e.target.value)} aria-label="Search the audit log"
            placeholder="Search action, reason, person, record, invoice no., details…" style={{ paddingLeft: 34 }} />
        </div>
        <label style={{ display: 'flex', flexDirection: 'column', fontSize: 11.5, gap: 2, margin: 0 }}>From
          <input type="date" aria-label="From" value={f.from} onChange={e => setFilter('from', e.target.value)} style={{ width: 150 }} />
        </label>
        <label style={{ display: 'flex', flexDirection: 'column', fontSize: 11.5, gap: 2, margin: 0 }}>To
          <input type="date" aria-label="To" value={f.to} onChange={e => setFilter('to', e.target.value)} style={{ width: 150 }} />
        </label>
        <select aria-label="Module" value={f.module} onChange={e => setFilter('module', e.target.value)} style={{ maxWidth: 190 }}>
          <option value="">All modules</option>
          {keepChoice(choices?.modules ?? [], f.module).map(m => <option key={m.value} value={m.value}>{m.value}{m.count ? ` (${m.count})` : ''}</option>)}
        </select>
        <select aria-label="Table" value={f.table} onChange={e => setFilter('table', e.target.value)} style={{ maxWidth: 210 }}>
          <option value="">All tables</option>
          {keepChoice(choices?.tables ?? [], f.table).map(t => <option key={t.value} value={t.value}>{t.value}{t.count ? ` (${t.count})` : ''}</option>)}
        </select>
        <select aria-label="Person" value={f.actor} onChange={e => setFilter('actor', e.target.value)} style={{ maxWidth: 210 }}>
          <option value="">Everyone</option>
          {(choices?.actors ?? []).map(a => <option key={a.id} value={a.id}>{a.name} ({a.count})</option>)}
          {f.actor && !(choices?.actors ?? []).some(a => a.id === f.actor) && <option value={f.actor}>Chosen person</option>}
        </select>
        {filtered && (
          <button className="btn btn-secondary btn-sm" onClick={() => { setTextInput(''); search(() => NO_FILTERS); }}>
            <X size={13} /> Clear filters
          </button>
        )}
      </div>

      {error && (
        <div className="alert alert-danger" role="alert" style={{ marginBottom: 14 }}>
          The audit log could not be loaded: {error}
        </div>
      )}

      <div className="card">
        <div className="table-wrap">
          {loading && rows.length === 0 ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : error ? <div className="empty-state"><ScrollText size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>Nothing to show until the log loads.</p></div>
          : rows.length === 0 ? <div className="empty-state"><ScrollText size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>{filtered ? 'No audit entries match these filters' : 'No audit entries'}</p></div>
          : (
            <table>
              <thead><tr><th>When (SGT)</th><th>Action</th><th>Table</th><th>Module</th><th>By</th><th>Role</th><th>Reason</th><th>Record</th><th>Details</th></tr></thead>
              <tbody style={{ opacity: loading ? 0.55 : 1 }}>
                {rows.map(l => {
                  const when = new Date(l.created_at);
                  const details = l.new_data != null ? json(l.new_data) : l.old_data != null ? json(l.old_data) : '';
                  return (
                    <tr key={l.id}>
                      <td style={{ whiteSpace: 'nowrap', fontSize: 12 }}>{SGT_DAY.format(when)}<div style={{ color: 'var(--text-muted)' }}>{SGT_TIME.format(when)}</div></td>
                      <td><span className={`badge ${ACTION_CLS[l.action] ?? 'badge-muted'}`}>{actionText(l.action)}</span></td>
                      <td style={{ fontSize: 12.5 }}>{l.table_name}</td>
                      <td style={{ fontSize: 12 }}>{l.module ?? '—'}
                        {l.module && !l.module_recorded && <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }} title="Not recorded with the entry; taken from its table">from table</div>}</td>
                      <td style={{ fontSize: 12.5 }}>{l.actor_name}</td>
                      <td style={{ fontSize: 12 }}>{roleText(l.actor_role) || '—'}</td>
                      <td style={{ fontSize: 12, color: 'var(--text-muted)', maxWidth: 180 }}>{l.reason || '—'}</td>
                      <td style={{ fontSize: 11.5, fontFamily: 'var(--font-display)', maxWidth: 140, overflowWrap: 'anywhere' }}
                        title={l.record_id ?? undefined}>{l.record_label || (l.record_id ? `${l.record_id.slice(0, 8)}…` : '—')}</td>
                      <td style={{ fontSize: 11.5, color: 'var(--text-muted)', maxWidth: 240, fontFamily: 'var(--font-display)', overflowWrap: 'anywhere' }}
                        title={details.length > 70 ? details.slice(0, 2000) : undefined}>
                        {details ? (details.length > 70 ? `${details.slice(0, 70)}…` : details) : '—'}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
        {!error && total > 0 && (
          <div data-testid="audit-pager" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, padding: '10px 14px', flexWrap: 'wrap', borderTop: '1px solid var(--border)' }}>
            <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              {first.toLocaleString('en-GB')}–{last.toLocaleString('en-GB')} of {total.toLocaleString('en-GB')} {total === 1 ? 'entry' : 'entries'}
            </span>
            <div style={{ display: 'flex', gap: 6 }}>
              <button className="btn btn-secondary btn-sm" disabled={loading || query.offset === 0}
                onClick={() => goTo(Math.max(0, query.offset - PAGE_SIZE))}><ChevronLeft size={13} /> Newer</button>
              <button className="btn btn-secondary btn-sm" disabled={loading || query.offset + PAGE_SIZE >= total}
                onClick={() => goTo(query.offset + PAGE_SIZE)}>Older <ChevronRight size={13} /></button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default AuditLogPage;
