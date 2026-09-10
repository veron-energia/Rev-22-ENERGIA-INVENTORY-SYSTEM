export type StockFilters = { from: string; to: string; search: string; products: string[]; locations: string[]; people: string[]; types: string[] };
export function stockMonth() {
  const today = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Singapore' }).format(new Date());
  return { from: today.slice(0, 8) + '01', to: today };
}
// Keep untrusted text as text even when a downstream consumer converts Excel to CSV.
export function stockCell(value: unknown): string | number {
  if (typeof value === 'number') return value;
  const text = String(value ?? '');
  return /^[\s]*[=+\-@]|^[\t\r\n]/.test(text) ? "'" + text : text;
}
export async function collectStockReport(db: any, tab: 'history' | 'table', filters: StockFilters) {
  const rows: any[] = [], seen = new Set<string>(); let asOf: string | null = null, total: number | null = null;
  for (;;) {
    const { data, error }: { data: any; error: any } = await db.rpc(tab === 'history' ? 'stock_history_page' : 'stock_history_table', {
      p_filters: filters, p_limit: 1000, p_offset: rows.length, p_as_of: asOf,
    });
    if (error) throw new Error(error.message);
    if (!data?.has_access) throw new Error('Your store assignments changed. Reload Stock History before exporting.');
    if (total !== null && data.total !== total) throw new Error('The matching records changed during export. Refresh and try again.');
    total = data.total; asOf = data.as_of;
    for (const row of data.rows) {
      const key = tab === 'history' ? row.id : `${row.product_id}:${row.location_key}`;
      if (seen.has(key)) throw new Error('The report changed during export. Refresh and try again.');
      seen.add(key); rows.push(row);
    }
    if (rows.length === total) return rows;
    if (!data.rows.length || rows.length > Number(total)) throw new Error('The full report could not be loaded. No partial export was created.');
  }
}
