import React, { useMemo, useState } from 'react';
import * as XLSX from 'xlsx';
import { Download } from 'lucide-react';
import { Modal } from './ui';

/**
 * Shared Excel export.
 *
 * Every page exports exactly what is on screen — the same rows, in the same
 * column order, after whatever search and filters are active. Pages whose rows
 * carry a date also offer a date range, so a period can be pulled without
 * changing the page's own filters.
 */

export interface ExcelColumn<T> {
  /** Column heading, matching the on-screen label. */
  header: string;
  /** Cell value for a row. Return a number for numeric cells. */
  value: (row: T) => string | number | null | undefined;
}

export interface ExcelExportProps<T> {
  /** Rows already filtered exactly as displayed. */
  rows: T[];
  columns: ExcelColumn<T>[];
  /** Without .xlsx */
  filename: string;
  /** Sheet name; Excel allows 31 characters. */
  sheetName?: string;
  /**
   * Supply this when the rows carry a date, to offer a range. Return the row's
   * date as a Date, an ISO string, or null when it has none.
   */
  dateOf?: (row: T) => string | Date | null | undefined;
  /** Label shown beside the date range, e.g. "Invoice date". */
  dateLabel?: string;
  label?: string;
  disabled?: boolean;
  /**
   * For server-paginated pages: return every matching row, so the export is not
   * limited to the page on screen.
   */
  fetchAll?: () => Promise<T[]>;
}

function toDate(v: string | Date | null | undefined): Date | null {
  if (!v) return null;
  const d = v instanceof Date ? v : new Date(v);
  return isNaN(d.getTime()) ? null : d;
}

export function ExcelExportButton<T>({
  rows, columns, filename, sheetName = 'Sheet1',
  dateOf, dateLabel = 'Date', label = 'Export Excel', disabled = false, fetchAll,
}: ExcelExportProps<T>) {
  const [open, setOpen] = useState(false);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');

  const hasTimeline = !!dateOf;

  // What the current range would export, so the count can be shown before
  // committing to the download.
  const inRange = useMemo(() => {
    if (!dateOf || (!from && !to)) return rows;
    const f = from ? new Date(from + 'T00:00:00') : null;
    const t = to ? new Date(to + 'T23:59:59') : null;
    return rows.filter(r => {
      const d = toDate(dateOf(r));
      if (!d) return false;
      if (f && d < f) return false;
      if (t && d > t) return false;
      return true;
    });
  }, [rows, dateOf, from, to]);

  const write = (data: T[]) => {
    const body = data.map(r => {
      const o: Record<string, any> = {};
      for (const c of columns) {
        const v = c.value(r);
        o[c.header] = v === undefined || v === null ? '' : v;
      }
      return o;
    });
    const ws = XLSX.utils.json_to_sheet(body, {
      header: columns.map(c => c.header),
    });
    // Roughly size each column to its content so the sheet is readable.
    ws['!cols'] = columns.map(c => {
      const longest = body.reduce((m, r) => Math.max(m, String(r[c.header] ?? '').length), c.header.length);
      return { wch: Math.min(Math.max(longest + 2, 10), 46) };
    });
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, sheetName.slice(0, 31));
    const stamp = new Date().toISOString().slice(0, 10);
    XLSX.writeFile(wb, `${filename}-${stamp}.xlsx`);
  };

  const [busy, setBusy] = useState(false);

  const collect = async (): Promise<T[]> => (fetchAll ? await fetchAll() : rows);

  const applyRange = (data: T[]) => {
    if (!dateOf || (!from && !to)) return data;
    const f = from ? new Date(from + 'T00:00:00') : null;
    const t = to ? new Date(to + 'T23:59:59') : null;
    return data.filter(r => {
      const d = toDate(dateOf(r));
      if (!d) return false;
      if (f && d < f) return false;
      if (t && d > t) return false;
      return true;
    });
  };

  const onClick = async () => {
    if (hasTimeline) { setFrom(''); setTo(''); setOpen(true); return; }
    setBusy(true);
    try { write(await collect()); } finally { setBusy(false); }
  };

  return (
    <>
      <button className="btn btn-secondary" onClick={onClick} disabled={disabled || busy || (rows.length === 0 && !fetchAll)}
        title={rows.length === 0 ? 'Nothing to export' : `Export ${rows.length} row(s) to Excel`}>
        <Download size={15} /> {busy ? 'Preparing…' : label}
      </button>

      {open && (
        <Modal title={label} maxWidth={430} onClose={() => setOpen(false)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setOpen(false)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy}
              onClick={async () => {
                setBusy(true);
                try { write(applyRange(await collect())); setOpen(false); } finally { setBusy(false); }
              }}>
              {busy ? 'Preparing…' : fetchAll ? 'Export' : `Export ${inRange.length} row(s)`}
            </button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              Exports what is on screen now, with the filters and search you have applied.
              Leave the dates blank to export everything currently shown.
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>{dateLabel} from</label>
                <input type="date" value={from} max={to || undefined} onChange={e => setFrom(e.target.value)} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>{dateLabel} to</label>
                <input type="date" value={to} min={from || undefined} onChange={e => setTo(e.target.value)} />
              </div>
            </div>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {([['Today', 0], ['Last 7 days', 6], ['Last 30 days', 29], ['This year', -1]] as [string, number][])
                .map(([lbl, days]) => (
                  <button key={lbl} className="btn btn-secondary btn-sm" onClick={() => {
                    const now = new Date();
                    const end = now.toISOString().slice(0, 10);
                    if (days === -1) {
                      setFrom(`${now.getFullYear()}-01-01`); setTo(end);
                    } else {
                      const s = new Date(now); s.setDate(s.getDate() - days);
                      setFrom(s.toISOString().slice(0, 10)); setTo(end);
                    }
                  }}>{lbl}</button>
                ))}
              <button className="btn btn-secondary btn-sm" onClick={() => { setFrom(''); setTo(''); }}>All dates</button>
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              {fetchAll
                ? 'Every matching record is exported, not just the page on screen.'
                : `${inRange.length} of ${rows.length} row(s) match this range.`}
              {inRange.length === 0 && rows.length > 0 && ' Widen the dates to export something.'}
            </div>
          </div>
        </Modal>
      )}
    </>
  );
}

export default ExcelExportButton;
