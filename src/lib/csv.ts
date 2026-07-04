// Shared CSV export (5G-1). Exports the rows currently displayed (i.e. after
// any filters), with a BOM so Excel opens it with correct encoding.
export function exportCsv(filename: string, rows: Record<string, any>[]) {
  if (!rows.length) { alert('Nothing to export.'); return; }
  const headers = Object.keys(rows[0]);
  const esc = (v: any) => {
    const s = v === null || v === undefined ? '' : String(v);
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const csv = [headers.join(','), ...rows.map(r => headers.map(h => esc(r[h])).join(','))].join('\n');
  const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  a.click();
  URL.revokeObjectURL(a.href);
}
