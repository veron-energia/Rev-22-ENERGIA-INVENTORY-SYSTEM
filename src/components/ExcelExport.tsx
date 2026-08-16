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
  /** Let the person choose which columns to include. The dialog then always
   *  opens, even without a date range. Off by default, so existing exports are
   *  unchanged. */
  selectableColumns?: boolean;
}

function toDate(v: string | Date | null | undefined): Date | null {
  if (!v) return null;
  const d = v instanceof Date ? v : new Date(v);
  return isNaN(d.getTime()) ? null : d;
}

export function ExcelExportButton<T>({
  rows, columns, filename, sheetName = 'Sheet1',
  dateOf, dateLabel = 'Date', label = 'Export Excel', disabled = false, fetchAll,
  selectableColumns = false,
}: ExcelExportProps<T>) {
  const [open, setOpen] = useState(false);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');

  const hasTimeline = !!dateOf;
  const [picked, setPicked] = useState<string[]>(() => columns.map(c => c.header));
  // The chosen columns in the order they were TICKED, so the sheet can be
  // arranged to suit whatever it is being pasted into. `picked` already records
  // that order; an unknown header is skipped rather than producing a gap.
  const activeColumns = selectableColumns
    ? picked
        .map(h => columns.find(c => c.header === h))
        .filter((c): c is ExcelColumn<T> => !!c)
    : columns;

  // Which column the rows are sorted by, and which way.
  const [sortBy, setSortBy] = useState<string>('');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');

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
    const cols = activeColumns.length > 0 ? activeColumns : columns;

    // Sort by the chosen column. Values are compared as numbers or dates where
    // they clearly are one, so "10" does not land before "9" and a date is not
    // ordered by the text of "12/08/2026". Blanks always sink to the bottom,
    // whichever direction is chosen, so a missing value never buries real data
    // at the top of the sheet.
    const sortCol = cols.find(c => c.header === sortBy);
    const sorted = sortCol ? [...data].sort((a, b) => {
      const av = sortCol.value(a);
      const bv = sortCol.value(b);
      const aBlank = av == null || av === '';
      const bBlank = bv == null || bv === '';
      if (aBlank && bBlank) return 0;
      if (aBlank) return 1;
      if (bBlank) return -1;

      let cmp: number;
      const an = typeof av === 'number' ? av : Number(String(av).replace(/[,\s]/g, ''));
      const bn = typeof bv === 'number' ? bv : Number(String(bv).replace(/[,\s]/g, ''));
      if (Number.isFinite(an) && Number.isFinite(bn)) {
        cmp = an - bn;
      } else {
        const ad = toDate(av as any)?.getTime();
        const bd = toDate(bv as any)?.getTime();
        cmp = (ad != null && bd != null)
          ? ad - bd
          // localeCompare with numeric:true keeps "Item 2" before "Item 10".
          : String(av).localeCompare(String(bv), undefined, { numeric: true, sensitivity: 'base' });
      }
      return sortDir === 'asc' ? cmp : -cmp;
    }) : data;

    const body = sorted.map(r => {
      const o: Record<string, any> = {};
      for (const c of cols) {
        const v = c.value(r);
        o[c.header] = v === undefined || v === null ? '' : v;
      }
      return o;
    });
    const ws = XLSX.utils.json_to_sheet(body, {
      header: cols.map(c => c.header),
    });
    // Roughly size each column to its content so the sheet is readable.
    ws['!cols'] = cols.map(c => {
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
    if (hasTimeline || selectableColumns) {
      setFrom(''); setTo('');
      if (selectableColumns) {
        setPicked(columns.map(c => c.header));
        setSortBy(''); setSortDir('asc');
      }
      setOpen(true); return;
    }
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
            <button className="btn btn-primary"
              disabled={busy || (selectableColumns && picked.length === 0)}
              onClick={async () => {
                setBusy(true);
                try { write(applyRange(await collect())); setOpen(false); } finally { setBusy(false); }
              }}>
              {busy ? 'Preparing…' : fetchAll ? 'Export' : `Export ${inRange.length} row(s)`}
            </button>
          </>}>
          <div className="form-grid">
            {selectableColumns && (
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between',
                              alignItems: 'baseline', marginBottom: 6 }}>
                  <label style={{ marginBottom: 0 }}>Columns to include</label>
                  <span style={{ display: 'flex', gap: 6 }}>
                    <button className="btn btn-secondary btn-sm" style={{ padding: '1px 8px', fontSize: 11 }}
                      onClick={() => setPicked(columns.map(c => c.header))}>All</button>
                    <button className="btn btn-secondary btn-sm" style={{ padding: '1px 8px', fontSize: 11 }}
                      onClick={() => setPicked([])}>None</button>
                  </span>
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))',
                              gap: 4, border: '1px solid var(--border)',
                              borderRadius: 'var(--radius-sm)', padding: 8 }}>
                  {columns.map(c => (
                    <label key={c.header} style={{ display: 'flex', gap: 6, alignItems: 'center',
                                                   fontSize: 12.5, cursor: 'pointer' }}>
                      <input type="checkbox" style={{ width: 'auto' }}
                        checked={picked.includes(c.header)}
                        onChange={e => setPicked(p2 => {
                          if (e.target.checked) return [...p2, c.header];
                          // Unticking the sort column clears the sort, so the
                          // sheet is never ordered by a column it does not contain.
                          if (sortBy === c.header) setSortBy('');
                          return p2.filter(h => h !== c.header);
                        })} />
                      {/* The position shows where this column will land. */}
                      {picked.includes(c.header) && (
                        <span style={{ fontSize: 10.5, fontWeight: 700, color: 'var(--primary)',
                                       minWidth: 14, textAlign: 'right' }}>
                          {picked.indexOf(c.header) + 1}.
                        </span>
                      )}
                      {c.header}
                    </label>
                  ))}
                </div>
                <div style={{ fontSize: 11.5, color: picked.length === 0 ? 'var(--danger)' : 'var(--text-muted)',
                              marginTop: 4 }}>
                  {picked.length === 0
                    ? 'Choose at least one column.'
                    : `${picked.length} of ${columns.length} column${columns.length === 1 ? '' : 's'} — exported in the order you tick them. Untick and tick again to move one to the end.`}
                </div>
              </div>
            )}
            {selectableColumns && picked.length > 0 && (
              <div>
                <label>Sort the rows by</label>
                <div style={{ display: 'flex', gap: 8 }}>
                  <select value={sortBy} onChange={e => setSortBy(e.target.value)} style={{ flex: 1 }}>
                    <option value="">— Keep the order shown on screen —</option>
                    {activeColumns.map(c => (
                      <option key={c.header} value={c.header}>{c.header}</option>
                    ))}
                  </select>
                  <select value={sortDir} onChange={e => setSortDir(e.target.value as 'asc' | 'desc')}
                    disabled={!sortBy} style={{ flex: '0 0 130px' }}>
                    <option value="asc">A → Z / 1 → 9</option>
                    <option value="desc">Z → A / 9 → 1</option>
                  </select>
                </div>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 3 }}>
                  Only the columns you have chosen can be sorted on. Numbers and dates sort by
                  value, not as text, and blanks go to the bottom.
                </div>
              </div>
            )}

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
