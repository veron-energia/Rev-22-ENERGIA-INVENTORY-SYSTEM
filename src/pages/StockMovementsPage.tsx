import React, { useEffect, useMemo, useRef, useState } from 'react';
import { RefreshCw } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { ExcelExportButton } from '../components/ExcelExport';
import { Modal } from '../components/ui';
import { StockHistoryFilter, StockOption } from '../components/stock-history/StockHistoryFilter';
import { TransferNoteHistory } from '../components/stock-history/TransferNoteHistory';
import { collectStockReport, stockCell, stockMonth, StockFilters } from '../components/stock-history/report';
import '../components/stock-history/stock-history.css';
const kinds = ['products', 'locations', 'people', 'types'] as const;
const labels = { products: 'Products', locations: 'Locations', people: 'Recorded by', types: 'Movement type' };
const emptyOptions = () => ({ products: [], locations: [], people: [], types: [] } as Record<typeof kinds[number], StockOption[]>);
const StockMovementsPage: React.FC = () => {
  const [tab, setTab] = useState<'history' | 'table'>('history'), [search, setSearch] = useState(''), [query, setQuery] = useState('');
  const [dates, setDates] = useState(stockMonth), [selected, setSelected] = useState(emptyOptions), [page, setPage] = useState(0), [refresh, setRefresh] = useState(0);
  const [result, setResult] = useState<any>(null), [loading, setLoading] = useState(true), [error, setError] = useState(''), [transfer, setTransfer] = useState('');
  const cutoff = useRef<string | null>(null);
  useEffect(() => { const timer = setTimeout(() => { setQuery(search); setPage(0); }, 250); return () => clearTimeout(timer); }, [search]);
  const filters = useMemo<StockFilters>(() => ({ ...dates, search: query, products: selected.products.map(o => o.value), locations: selected.locations.map(o => o.value), people: selected.people.map(o => o.value), types: selected.types.map(o => o.value) }), [dates, query, selected]);
  useEffect(() => { cutoff.current = null; }, [filters, tab, refresh]);
  useEffect(() => {
    let live = true; setLoading(true); setError(''); setResult(null);
    supabase.rpc(tab === 'history' ? 'stock_history_page' : 'stock_history_table', { p_filters: filters, p_limit: 100, p_offset: page * 100, p_as_of: cutoff.current }).then(({ data, error }) => {
      if (!live) return;
      if (error) setError(error.message || 'Stock History could not be loaded.'); else { cutoff.current = data.as_of; setResult(data); }
      setLoading(false);
    });
    return () => { live = false; };
  }, [filters, tab, page, refresh]);
  const change = (kind: typeof kinds[number], values: StockOption[]) => { setSelected(s => ({ ...s, [kind]: values })); setPage(0); };
  const context = `${dates.from} to ${dates.to} · Asia/Singapore · Search: ${query || 'All'} · ${kinds.map(k => `${labels[k]}: ${selected[k].map(o => o.label).join(' OR ') || 'All permitted'}`).join(' · ')}`;
  const filtered = !!query.trim() || !!selected.people.length || !!selected.types.length;
  const showMovements = (r: any) => { setSelected(s => ({ ...s, products: [{ value: r.product_id, label: `${r.product_name} · ${r.product_sku}` }], locations: [{ value: r.location_key, label: r.location_name }] })); setTab('history'); setPage(0); };
  const value = (n: unknown) => n == null ? 'Unknown' : Number(n).toLocaleString('en-SG');
  const cols = tab === 'history' ? [
    { header: 'Date/time (Asia/Singapore)', value: (r: any) => new Date(r.created_at).toLocaleString('en-GB', { timeZone: 'Asia/Singapore' }) },
    ...[['Type', 'type_label'], ['Product', 'product_name'], ['SKU', 'product_sku'], ['Source', 'from_name'], ['Destination', 'to_name'], ['Quantity (units)', 'quantity'], ['Recorded by', 'by_name'], ['Notes', 'notes'], ['Transfer reference', 'transfer_request_id']].map(([header, key]) => ({ header, value: (r: any) => stockCell(r[key]) })),
  ] : [
    ...[['Product', 'product_name'], ['SKU', 'product_sku'], ['Location', 'location_name']].map(([header, key]) => ({ header, value: (r: any) => stockCell(r[key]) })),
    ...[['Actual opening (units)', 'opening_balance'], [`${filtered ? 'Filtered' : 'All'} inbound (units)`, 'inbound'], [`${filtered ? 'Filtered' : 'All'} outbound (units)`, 'outbound'], ['Actual closing (units)', 'closing_balance'], ['Other movement net (units)', 'other_movement_net'], ['Incoming in transit (units)', 'in_transit_incoming'], ['Outgoing in transit (units)', 'in_transit_outgoing']].map(([header, key]) => ({ header, value: (r: any) => r[key] == null ? 'Unknown / not applicable' : Number(r[key]) })),
    { header: 'Reconciliation warning', value: (r: any) => stockCell(r.warning) },
  ];
  return <div className="stock-history">
    <div className="page-header"><div><h2>Stock Movement History</h2><p>Read-only stock movements and product balances for your permitted locations.</p></div>
      <ExcelExportButton rows={result?.rows || []} columns={[...cols, { header: 'Report filters and dates', value: () => stockCell(context) }, { header: 'Balance basis', value: () => tab === 'table' ? 'Actual observed balances; movement filters affect inbound/outbound only. Transit is separate from sellable stock.' : 'Recorded movements, scoped to permitted locations.' }]} filename={`stock-${tab}`} sheetName={tab === 'history' ? 'Stock History' : 'Stock Table'} disabled={loading || !!error || !result?.has_access || !result.total || query !== search} fetchAll={() => collectStockReport(supabase, tab, filters)} />
      <button className="btn btn-secondary" onClick={() => setRefresh(n => n + 1)} disabled={loading}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
    </div>
    <div className="stock-search"><label>Search stock history<input value={search} onChange={e => setSearch(e.target.value)} placeholder="Product, SKU, location, person, type, note, quantity or date…" /></label><button className="btn btn-secondary" disabled={!search} onClick={() => setSearch('')}>Clear search</button></div>
    <div className="stock-filter-bar">{kinds.map(kind => <StockHistoryFilter key={kind} kind={kind} label={labels[kind]} selected={selected[kind]} onChange={v => change(kind, v)} />)}</div>
    <div className="stock-dates"><label>From (Singapore)<input type="date" value={dates.from} max={dates.to} onChange={e => { setDates(d => ({ ...d, from: e.target.value })); setPage(0); }} /></label><label>Through (Singapore)<input type="date" value={dates.to} min={dates.from} max={stockMonth().to} onChange={e => { setDates(d => ({ ...d, to: e.target.value })); setPage(0); }} /></label><button className="btn btn-secondary" onClick={() => { setSelected(emptyOptions()); setDates(stockMonth()); setPage(0); }}>Clear filters</button></div>
    <p aria-label="Active filter summary" style={{ fontSize: 12, overflowWrap: 'anywhere', marginTop: 10 }}>{context}</p>
    <div className="stock-tabs" role="tablist" aria-label="Stock History views" onKeyDown={e => {
      if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) {
        e.preventDefault(); const next = e.key === 'Home' ? 'history' : e.key === 'End' ? 'table' : tab === 'history' ? 'table' : 'history';
        setTab(next); setPage(0); document.getElementById(`stock-tab-${next}`)?.focus();
      }
    }}>{(['history', 'table'] as const).map(t => <button key={t} id={`stock-tab-${t}`} role="tab" aria-controls="stock-results" tabIndex={tab === t ? 0 : -1} aria-selected={tab === t} className={`btn ${tab === t ? 'btn-primary' : 'btn-secondary'}`} onClick={() => { setTab(t); setPage(0); }}>{t === 'history' ? 'History' : 'Table'}</button>)}</div>
    <section id="stock-results" role="tabpanel" aria-labelledby={`stock-tab-${tab}`}>
    {tab === 'table' && <p>All quantities are product units. In Transit shows incoming / outgoing separately and is excluded from sellable Closing Balance.{filtered && ' Inbound and Outbound are filtered movements; actual balances stay unchanged. Other movements explain the difference.'}</p>}
    {error ? <div className="alert alert-danger" role="alert">{error} <button className="btn btn-secondary" onClick={() => setRefresh(n => n + 1)}>Retry</button></div>
      : loading || query !== search ? <p role="status">Loading Stock History…</p> : !result?.has_access ? <p role="status">You have no current store assignment. Ask your manager to assign a store before viewing Stock History.</p>
      : <><p role="status">{result.total.toLocaleString()} matching {tab === 'history' ? 'movements' : 'product/location rows'} · {dates.from}–{dates.to} SGT</p>
        {!result.rows.length ? <p>No results match these filters.</p> : <div className="card table-wrap" tabIndex={0} role="region" aria-label="Stock results; scroll horizontally for all columns"><table>
          {tab === 'history' ? <><thead><tr>{['Date (SGT)', 'Type', 'Product', 'Movement', 'Qty (units)', 'By', 'Notes'].map(h => <th key={h}>{h}</th>)}</tr></thead><tbody>{result.rows.map((r: any) => <tr key={r.id}>
            <td>{new Date(r.created_at).toLocaleString('en-GB', { timeZone: 'Asia/Singapore' })}</td><td>{r.type_label}</td><td><strong>{r.product_name}</strong><div>{r.product_sku}</div></td><td>{r.from_name || '—'} → {r.to_name || '—'}</td><td>{r.quantity}</td><td>{r.by_name || 'Author unavailable'}</td><td>{r.notes || '—'}{r.transfer_request_id && <div><button className="btn btn-secondary" onClick={() => setTransfer(r.transfer_request_id)}>Transfer details & notes</button></div>}</td>
          </tr>)}</tbody></> : <><thead><tr>{['Location', 'Actual opening', filtered ? 'Filtered inbound' : 'Inbound', filtered ? 'Filtered outbound' : 'Outbound', 'Actual closing', 'In Transit (in / out)', 'Details'].map(h => <th key={h}>{h}</th>)}</tr></thead><tbody>{result.rows.map((r: any, index: number) => <React.Fragment key={`${r.product_id}:${r.location_key}`}>
            {(index === 0 || result.rows[index - 1].product_id !== r.product_id) && <tr className="stock-product-heading"><th colSpan={7}><span>{r.product_name} · {r.product_sku} · units</span></th></tr>}
            <tr><td>{r.location_name}</td><td>{value(r.opening_balance)}</td><td>{value(r.inbound)}</td><td>{value(r.outbound)}</td><td>{value(r.closing_balance)}</td><td>{value(r.in_transit_incoming)} / {value(r.in_transit_outgoing)}</td><td><button className="btn btn-secondary" onClick={() => showMovements(r)}>View movements</button>{filtered && <div>Other movement net: {value(r.other_movement_net)}</div>}{r.warning && <div className="stock-warning">{r.warning}</div>}</td></tr>
          </React.Fragment>)}</tbody></>}
        </table></div>}
        <div className="stock-pagination"><button className="btn btn-secondary" disabled={!page} onClick={() => setPage(p => p - 1)}>Previous</button><span>Page {page + 1} of {Math.max(1, Math.ceil(result.total / 100))}</span><button className="btn btn-secondary" disabled={(page + 1) * 100 >= result.total} onClick={() => setPage(p => p + 1)}>Next</button></div>
      </>}
    </section>
    {transfer && <Modal title="Transfer details and notes" onClose={() => setTransfer('')} maxWidth={720}><TransferNoteHistory requestId={transfer} showLines /></Modal>}
  </div>;
};
export default StockMovementsPage;
