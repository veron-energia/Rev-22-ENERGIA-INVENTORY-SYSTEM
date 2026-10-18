import React, { useMemo, useState } from 'react';
import * as XLSX from 'xlsx';
import { Download } from 'lucide-react';
import { Modal } from './ui';
import { calendarDate, calendarDateInRange } from '../lib/calendarDates';
import { sortExportRows } from '../lib/excelSort.mjs';

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
  /**
   * What the rows are sorted by when this column is chosen, when that is not
   * the cell itself: the raw date behind a date written as text, say. Without
   * it the cell's value is sorted, a day-first date (12/08/2026) as a date.
   */
  sortValue?: (row: T) => string | number | Date | null | undefined;
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
  /** Zone for timestamp ranges and date shortcuts; date-only values never shift. */
  dateTimeZone?: string;
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

export function ExcelExportButton<T>({
  rows, columns, filename, sheetName = 'Sheet1',
  dateOf, dateLabel = 'Date', dateTimeZone, label = 'Export Excel', disabled = false, fetchAll,
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
    return rows.filter(r => calendarDateInRange(dateOf(r), from, to, dateTimeZone));
  }, [rows, dateOf, from, to, dateTimeZone]);

  const write = (data: T[]) => {
    const cols = activeColumns.length > 0 ? activeColumns : columns;

    // Sort by the chosen column (lib/excelSort): numbers and dates by value,
    // so "10" does not land before "9" and "12/08/2026" is 12 August (427:
    // it was read as 8 December); the column's sortValue when it has one.
    // Blanks always sink to the bottom, whichever direction is chosen.
    const sortCol = cols.find(c => c.header === sortBy);
    const sorted = sortCol ? sortExportRows(data, sortCol.sortValue ?? sortCol.value, sortDir) : data;

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
    // Today in Singapore (427): before 8 am the UTC date is still yesterday.
    const stamp = calendarDate(new Date(), 'Asia/Singapore');
    XLSX.writeFile(wb, `${filename}-${stamp}.xlsx`);
  };

  const [busy, setBusy] = useState(false);
  const [exportError, setExportError] = useState('');

  const collect = async (): Promise<T[]> => (fetchAll ? await fetchAll() : rows);

  const applyRange = (data: T[]) => {
    if (!dateOf || (!from && !to)) return data;
    return data.filter(r => calendarDateInRange(dateOf(r), from, to, dateTimeZone));
  };

  const onClick = async () => {
    setExportError('');
    if (hasTimeline || selectableColumns) {
      setFrom(''); setTo('');
      if (selectableColumns) {
        setPicked(columns.map(c => c.header));
        setSortBy(''); setSortDir('asc');
      }
      setOpen(true); return;
    }
    setBusy(true);
    try { write(await collect()); }
    catch (error) { setExportError(error instanceof Error ? error.message : 'The export could not be completed. Please try again.'); }
    finally { setBusy(false); }
  };

  return (
    <>
      <button className="btn btn-secondary" onClick={onClick} disabled={disabled || busy || (rows.length === 0 && !fetchAll)}
        title={rows.length === 0 ? 'Nothing to export' : `Export ${rows.length} row(s) to Excel`}>
        <Download size={15} /> {busy ? 'Preparing…' : label}
      </button>
      {!open && exportError && <div className="alert alert-danger" role="alert">Export failed: {exportError}</div>}

      {open && (
        <Modal title={label} maxWidth={430} onClose={() => setOpen(false)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setOpen(false)}>Cancel</button>
            <button className="btn btn-primary"
              disabled={busy || (selectableColumns && picked.length === 0)}
              onClick={async () => {
                setBusy(true); setExportError('');
                try { write(applyRange(await collect())); setOpen(false); }
                catch (error) { setExportError(error instanceof Error ? error.message : 'The export could not be completed. Please try again.'); }
                finally { setBusy(false); }
              }}>
              {busy ? 'Preparing…' : fetchAll ? 'Export' : `Export ${inRange.length} row(s)`}
            </button>
          </>}>
          <div className="form-grid">
            {exportError && <div className="alert alert-danger" role="alert">Export failed: {exportError}</div>}
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
                    const end = calendarDate(now, dateTimeZone);
                    if (days === -1) {
                      setFrom(`${end.slice(0, 4)}-01-01`); setTo(end);
                    } else {
                      const s = new Date(end + 'T12:00:00Z'); s.setUTCDate(s.getUTCDate() - days);
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
