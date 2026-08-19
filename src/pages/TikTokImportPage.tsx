import React, { useEffect, useState, useCallback, useMemo, useRef } from 'react';
import * as XLSX from 'xlsx';
import Papa from 'papaparse';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, Product, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import { RefreshCw, Upload, FileSpreadsheet, Trash2, CheckCircle2, Eye, Wrench } from 'lucide-react';
import { SearchSelect } from '../components/SearchSelect';

// ─────────────────────────────────────────────────────────────────────────────
// Phase 15 — TikTok Sales Import.
//
// Everything is parsed in the browser as TEXT: xlsx cells are read via their
// formatted string (`raw: false`) and CSV parsing never enables dynamic
// typing, so 19-digit TikTok Order IDs are NEVER converted to JavaScript
// numbers. Sheets are detected by their headers, not by filename, sheet name
// or position. Staging happens server-side; nothing touches stock until a
// batch is confirmed there.
// ─────────────────────────────────────────────────────────────────────────────

// Header synonyms per canonical field. Matching is case/space-insensitive on
// the HEADER only — Seller SKU VALUES stay case-sensitive end-to-end.
const ORDER_HEADERS: Record<string, string[]> = {
  order_id: ['order id', 'order number', 'order no'],
  order_status: ['order status', 'order substatus', 'status'],
  seller_sku: ['seller sku', 'sellersku'],
  product_name: ['product name'],
  quantity: ['quantity', 'qty'],
  rts_time: ['rts time'],
  created_time: ['created time', 'create time', 'order created time'],
  paid_time: ['paid time', 'payment time'],
  shipped_time: ['shipped time', 'ship time'],
  delivered_time: ['delivered time', 'delivery time'],
  cancelled_time: ['cancelled time', 'canceled time', 'cancel time'],
  return_quantity: ['sku quantity of return', 'return quantity'],
  refund_amount: ['order refund amount', 'refund amount', 'sku refund amount'],
  sku_subtotal_before: ['sku subtotal before discount', 'subtotal before discount'],
  sku_subtotal_after: ['sku subtotal after discount', 'subtotal after discount', 'sku subtotal'],
  tracking_id: ['tracking id', 'tracking number'],
  package_id: ['package id'],
  warehouse: ['warehouse name', 'warehouse'],
  shipping_provider: ['shipping provider name', 'shipping provider'],
  payment_method: ['payment method'],
  category: ['category'],
};
const SETTLEMENT_HEADERS: Record<string, string[]> = {
  order_id: ['order/adjustment id', 'order id', 'order/adjustment  id'],
  adjustment_id: ['adjustment id'],
  transaction_type: ['type', 'transaction type'],
  related_order_id: ['related order id', 'associated order id', 'related order  id'],
  settlement_amount: ['total settlement amount', 'settlement amount'],
  fee_amount: ['total fees', 'total fee', 'fees'],
  revenue_amount: ['total revenue', 'revenue'],
  adjustment_amount: ['adjustment amount', 'total adjustment amount'],
  refund_amount: ['refund amount', 'total refund amount', 'refund subtotal'],
  currency: ['currency'],
  order_created_time: ['order created time', 'order create time'],
  settled_time: ['order settled time', 'statement date/time', 'settled time'],
};
const ORDER_REQUIRED = ['order_id', 'seller_sku', 'quantity'];
const SETTLEMENT_REQUIRED = ['order_id', 'settlement_amount'];

const norm = (h: string) => String(h ?? '').toLowerCase().replace(/\s+/g, ' ').trim();

// Map a header row to canonical field -> column index. Null if the sheet
// does not carry the required headers.
const matchHeaders = (headerRow: string[], defs: Record<string, string[]>, required: string[]) => {
  const map: Record<string, number> = {};
  headerRow.forEach((h, i) => {
    const n = norm(h);
    for (const [field, alts] of Object.entries(defs)) {
      if (map[field] === undefined && alts.includes(n)) map[field] = i;
    }
  });
  return required.every(f => map[f] !== undefined) ? map : null;
};

interface ParsedSheet { sheetName: string; headerRowIdx: number; map: Record<string, number>; rows: string[][]; }

// Detect the right sheet BY HEADERS: scan the first 10 rows of every sheet.
const detectSheet = (grids: { name: string; grid: string[][] }[], defs: Record<string, string[]>, required: string[]): ParsedSheet | null => {
  for (const { name, grid } of grids) {
    for (let r = 0; r < Math.min(10, grid.length); r++) {
      const map = matchHeaders(grid[r] ?? [], defs, required);
      if (map) return { sheetName: name, headerRowIdx: r, map, rows: grid.slice(r + 1) };
    }
  }
  return null;
};

// A description row (TikTok puts one right under the headers) has no
// plausible order id: empty, or contains whitespace / long prose.
const isDescriptionRow = (orderId: string) => {
  const v = String(orderId ?? '').trim();
  return v === '' ? false : (/\s/.test(v) || v.length > 40);
};

const STATUS_BADGE: Record<string, string> = {
  'New — Will Deduct': 'badge-success',
  'Updated — Additional Deduction': 'badge-primary',
  'Updated — Stock Return': 'badge-primary',
  'No Stock Change': 'badge-muted',
  'Already Imported': 'badge-muted',
  'Unmatched SKU': 'badge-warning',
  'Invalid Status': 'badge-danger',
  'Negative Stock Warning': 'badge-warning',
  'Duplicate Row': 'badge-muted',
  'Invalid Row': 'badge-danger',
};
const CONFIRMABLE = new Set(['New — Will Deduct', 'Updated — Additional Deduction', 'Updated — Stock Return', 'Negative Stock Warning', 'No Stock Change', 'Already Imported']);

const TikTokImportPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isOwnerOrManager(profile?.role);
  const isStaff = profile?.role === 'staff';

  const [stores, setStores] = useState<Store[]>([]);
  const [storeId, setStoreId] = useState('');
  const [assignedStore, setAssignedStore] = useState<string | null>(null);
  const [products, setProducts] = useState<Product[]>([]);
  const [vouchers, setVouchers] = useState<any[]>([]);
  const [promotions, setPromotions] = useState<any[]>([]);
  const [batches, setBatches] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const [activeBatch, setActiveBatch] = useState<any>(null);
  const [rows, setRows] = useState<any[]>([]);
  const [selected, setSelected] = useState<Record<string, boolean>>({});
  const [mapSku, setMapSku] = useState<{ sku: string } | null>(null);
  const [mapKind, setMapKind] = useState<'product' | 'voucher' | 'promotion'>('product');
  const [mapTarget, setMapTarget] = useState('');
  const [correctRow, setCorrectRow] = useState<any>(null);
  // Phase 16 — lifecycle state.
  const [statusMaps, setStatusMaps] = useState<any[]>([]);
  const [statusOpen, setStatusOpen] = useState(false);
  const [newStatus, setNewStatus] = useState(''); const [newAction, setNewAction] = useState<'deduct' | 'return' | 'none'>('deduct'); const [newShipped, setNewShipped] = useState(false);
  const [physReturns, setPhysReturns] = useState<any[]>([]);
  const [resolvePr, setResolvePr] = useState<any>(null);
  const [prRestock, setPrRestock] = useState(true); const [prReason, setPrReason] = useState('damaged'); const [prNote, setPrNote] = useState('');
  const [negPrompt, setNegPrompt] = useState<string | null>(null);
  // Phase 18 — page tabs.
  type PageTab = 'staged' | 'orders' | 'items' | 'settlements' | 'unmatched' | 'recon' | 'history' | 'returns' | 'corrections';
  const [pageTab, setPageTab] = useState<PageTab>('staged');
  const [tabRows, setTabRows] = useState<any[]>([]);
  const [tabLoading, setTabLoading] = useState(false);
  // Phase 17 — settlement staging view.
  const [settleBatch, setSettleBatch] = useState<any>(null);
  const [settleRows, setSettleRows] = useState<any[]>([]);
  const [settleSel, setSettleSel] = useState<Record<string, boolean>>({});
  const [negAck, setNegAck] = useState(false); const [negReason, setNegReason] = useState('');
  const [corrDelta, setCorrDelta] = useState(0);
  const [corrReason, setCorrReason] = useState('');
  const orderInput = useRef<HTMLInputElement>(null);
  const settleInput = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [st, mine, pr, vc, pm, rep, sm, phr] = await Promise.all([
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.rpc('my_assigned_store_id'),
      supabase.from('products').select('id,name,sku,is_active').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('vouchers').select('id,name,is_active').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('promotions').select('id,name,is_active').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.rpc('report_tiktok_imports', { p_store_id: null, p_from: null, p_to: null }),
      supabase.from('tiktok_status_mappings').select('*').order('sort_order'),
      supabase.from('tiktok_physical_returns').select('*').eq('status', 'awaiting').order('created_at'),
    ]);
    setStores((st.data as Store[]) ?? []);
    setProducts((pr.data as Product[]) ?? []);
    setVouchers((vc.data as any[]) ?? []);
    setPromotions((pm.data as any[]) ?? []);
    setBatches((rep.data as any[]) ?? []);
    setStatusMaps((sm.data as any[]) ?? []);
    setPhysReturns((phr.data as any[]) ?? []);
    const assigned = (mine.data as string | null) ?? null;
    setAssignedStore(assigned);
    setStoreId(prev => prev || assigned || '');
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  // Staff: store auto-selected + locked to the assigned store.
  const effectiveStore = isStaff ? (assignedStore ?? '') : storeId;

  const loadBatchRows = async (batchId: string) => {
    const [{ data: b }, { data: r }] = await Promise.all([
      supabase.from('tiktok_import_batches').select('*').eq('id', batchId).single(),
      supabase.from('tiktok_order_rows').select('*').eq('batch_id', batchId).order('row_no'),
    ]);
    setActiveBatch(b ?? null);
    const rr = (r as any[]) ?? [];
    setRows(rr);
    const sel: Record<string, boolean> = {};
    rr.forEach(x => { sel[x.id] = !x.excluded && CONFIRMABLE.has(x.staging_status); });
    setSelected(sel);
  };

  // A platform money movement — TikTok ad payment, subscription, payout — has
  // no customer order to match, so it is complete rather than waiting for one.
  // Shown apart from both Matched and Pending so the pending queue means what
  // it says: rows that still need an order to arrive.
  const matchBadge = (status?: string) =>
    status === 'matched'
      ? <span className="badge badge-success">Matched</span>
      : status === 'no_match_needed'
      ? <span className="badge badge-muted" title="A TikTok platform payment, not a customer order — nothing to match">No match needed</span>
      : <span className="badge badge-warning">Pending Order</span>;

  const SETTLE_CONFIRMABLE = new Set(['New — Matched', 'New — Pending Order', 'New — No Match Needed', 'Updated — Requires Confirmation']);

  const loadSettleRows = async (batchId: string) => {
    const [{ data: b }, { data: r }] = await Promise.all([
      supabase.from('tiktok_import_batches').select('*').eq('id', batchId).single(),
      supabase.from('tiktok_settlement_rows').select('*').eq('batch_id', batchId).order('row_no'),
    ]);
    setSettleBatch(b ?? null);
    const rr = (r as any[]) ?? [];
    setSettleRows(rr);
    const sel: Record<string, boolean> = {};
    // Only matched rows are pre-selected; pending/unmatched need a deliberate tick.
    // Finance rows are ticked too: they are complete, so leaving them
    // unselected would strand them in the preview permanently.
    rr.forEach(x => { sel[x.id] = !x.excluded && SETTLE_CONFIRMABLE.has(x.staging_status)
      && (x.match_status === 'matched' || x.match_status === 'no_match_needed'); });
    setSettleSel(sel);
  };

  const confirmSettleBatch = async () => {
    if (!settleBatch) return;
    const ids = settleRows.filter(r => settleSel[r.id]).map(r => r.id);
    if (ids.length === 0) { setErr('Select at least one settlement row to confirm.'); return; }
    setBusy('sconfirm'); setErr(null);
    const { data, error } = await supabase.rpc('confirm_tiktok_settlement_batch', { p_batch_id: settleBatch.id, p_row_ids: ids });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    const res = data as any;
    alert(`Settlement confirmed: ${res.applied} rows (${res.versioned_updates} versioned updates, ${res.pending} pending order match, ${res.unreconciled} reconciliation warnings), ${res.skipped} skipped.`);
    await load(); await loadSettleRows(settleBatch.id);
  };

  // Per-tab data (fetched on demand).
  useEffect(() => {
    const fetchTab = async () => {
      if (pageTab === 'staged' || pageTab === 'history') { setTabRows([]); return; }
      // Clear FIRST. tabRows is shared by every tab, so without this the new tab
      // renders the previous tab's rows for a moment — and those have different
      // fields. Switching to Reconciliation showed rows with no `kind`, and
      // `r.kind.replace(...)` threw "Cannot read properties of undefined".
      setTabRows([]);
      setTabLoading(true);
      let rows: any[] = [];
      if (pageTab === 'orders') {
        const { data } = await supabase.from('tiktok_order_state').select('*').order('updated_at', { ascending: false }).limit(300);
        rows = (data as any[]) ?? [];
      } else if (pageTab === 'items') {
        const { data } = await supabase.from('tiktok_order_rows').select('*').eq('confirmed', true).order('confirmed_at', { ascending: false }).limit(300);
        rows = (data as any[]) ?? [];
      } else if (pageTab === 'settlements') {
        const { data } = await supabase.rpc('report_tiktok_settlement', { p_store_id: effectiveStore || null, p_from: null, p_to: null });
        rows = (data as any[]) ?? [];
      } else if (pageTab === 'unmatched') {
        const { data } = await supabase.rpc('report_tiktok_unmatched_skus', { p_store_id: effectiveStore || null });
        rows = (data as any[]) ?? [];
      } else if (pageTab === 'recon') {
        const { data } = await supabase.rpc('report_tiktok_recon_exceptions', { p_store_id: effectiveStore || null });
        rows = (data as any[]) ?? [];
      } else if (pageTab === 'returns') {
        const { data } = await supabase.from('tiktok_physical_returns').select('*').order('created_at', { ascending: false }).limit(300);
        rows = (data as any[]) ?? [];
      } else if (pageTab === 'corrections') {
        const { data } = await supabase.from('tiktok_corrections').select('*').order('created_at', { ascending: false }).limit(300);
        rows = (data as any[]) ?? [];
      }
      const filtered = effectiveStore && ['orders', 'items', 'returns', 'corrections'].includes(pageTab)
        ? rows.filter(r => r.store_id === effectiveStore) : rows;
      if (cancelled) return;   // a slower earlier tab must not overwrite this one
      setTabRows(filtered);
      setTabLoading(false);
    };
    let cancelled = false;
    fetchTab();
    return () => { cancelled = true; };
  }, [pageTab, effectiveStore]);

  // ── Worksheet range repair ────────────────────────────────────────────────
  //
  // REGRESSION GUARD. TikTok settlement exports — and XLSX files written by WPS
  // Office generally — can carry a STALE OR WRONG worksheet dimension. One real
  // settlement file held rows 1-12 but declared its range as "A1:BG2".
  //
  // sheet_to_json() trusts !ref, so it read the header and ONE data row and
  // silently dropped the other ten. Nothing errored: the import simply appeared
  // to contain a single settlement line.
  //
  // So !ref is recomputed from the cell addresses actually present before any
  // parsing. Keys beginning with "!" (!ref, !merges, !cols, !rows) are metadata
  // and are skipped.
  const repairWorksheetRange = (ws: XLSX.WorkSheet) => {
    const addresses = Object.keys(ws).filter(
      key => !key.startsWith('!') && /^[A-Z]+[1-9][0-9]*$/.test(key)
    );
    if (addresses.length === 0) return;

    let minRow = Infinity;
    let minCol = Infinity;
    let maxRow = -1;
    let maxCol = -1;

    for (const address of addresses) {
      const cell = XLSX.utils.decode_cell(address);
      minRow = Math.min(minRow, cell.r);
      minCol = Math.min(minCol, cell.c);
      maxRow = Math.max(maxRow, cell.r);
      maxCol = Math.max(maxCol, cell.c);
    }

    if (Number.isFinite(minRow) && Number.isFinite(minCol) && maxRow >= 0 && maxCol >= 0) {
      ws['!ref'] = XLSX.utils.encode_range(
        { r: minRow, c: minCol },
        { r: maxRow, c: maxCol }
      );
    }
  };

  // ── File parsing (both areas share it) ────────────────────────────────────
  const readGrids = async (file: File): Promise<{ name: string; grid: string[][] }[]> => {
    if (file.name.toLowerCase().endsWith('.csv')) {
      const text = await file.text();
      // dynamicTyping stays OFF: every cell is a string, IDs stay exact.
      const parsed = Papa.parse<string[]>(text, { skipEmptyLines: 'greedy' });
      return [{ name: 'CSV', grid: (parsed.data as string[][]).map(r => r.map(c => String(c ?? ''))) }];
    }
    const buf = await file.arrayBuffer();
    const wb = XLSX.read(buf, { type: 'array', cellText: true });
    return wb.SheetNames.map(name => {
      const ws = wb.Sheets[name];
      // See repairWorksheetRange: TikTok's own !ref cannot be trusted.
      repairWorksheetRange(ws);
      // raw:false -> formatted text for every cell, so big IDs keep all digits.
      const grid = XLSX.utils.sheet_to_json<string[]>(ws, { header: 1, raw: false, defval: '' }) as unknown as string[][];
      return { name, grid: grid.map(r => r.map(c => String(c ?? ''))) };
    });
  };

  const handleUpload = async (file: File, kind: 'order' | 'settlement') => {
    setErr(null);
    if (!effectiveStore) { setErr('Please select a store first.'); return; }
    setBusy(kind);
    try {
      const grids = await readGrids(file);
      const defs = kind === 'order' ? ORDER_HEADERS : SETTLEMENT_HEADERS;
      const required = kind === 'order' ? ORDER_REQUIRED : SETTLEMENT_REQUIRED;
      const sheet = detectSheet(grids, defs, required);
      if (!sheet) {
        setErr(`No sheet in "${file.name}" carries the required TikTok ${kind} headers (${required.join(', ')}). Sheets are detected by headers, so please export the standard TikTok ${kind} file.`);
        setBusy(null); return;
      }
      const get = (row: string[], field: string) => sheet.map[field] !== undefined ? String(row[sheet.map[field]] ?? '').trim() : '';
      const payload = sheet.rows
        .filter(r => r.some(c => String(c ?? '').trim() !== ''))
        .filter(r => !isDescriptionRow(get(r, 'order_id')))     // skip TikTok's description row
        .map(r => {
          const o: Record<string, string> = {};
          for (const field of Object.keys(defs)) { const v = get(r, field); if (v !== '') o[field] = v; }
          return o;
        });
      if (payload.length === 0) { setErr('The detected sheet has no data rows.'); setBusy(null); return; }

      const { data, error } = await supabase.rpc(kind === 'order' ? 'stage_tiktok_orders' : 'stage_tiktok_settlement', {
        p_store_id: effectiveStore, p_file_name: file.name, p_sheet_name: sheet.sheetName, p_rows: payload,
      });
      if (error) throw new Error(error.message);
      await load();
      if (kind === 'order' && data) await loadBatchRows(data as string);
      if (kind === 'settlement' && data) await loadSettleRows(data as string);
    } catch (e: any) {
      setErr(e.message ?? 'Import failed');
    }
    setBusy(null);
  };

  // ── Actions ───────────────────────────────────────────────────────────────
  const saveMapping = async () => {
    if (!mapSku || !mapTarget || !effectiveStore) return;
    setBusy('map'); setErr(null);
    const { error } = await supabase.rpc('upsert_tiktok_sku_alias', {
      p_store_id: effectiveStore, p_seller_sku: mapSku.sku, p_target_kind: mapKind, p_target_id: mapTarget,
    });
    if (!error && activeBatch) await supabase.rpc('refresh_tiktok_staging', { p_batch_id: activeBatch.id });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    setMapSku(null); setMapTarget('');
    if (activeBatch) await loadBatchRows(activeBatch.id);
  };

  const confirmBatch = async (allowNegative = false, negativeReason: string | null = null) => {
    if (!activeBatch) return;
    const ids = rows.filter(r => selected[r.id]).map(r => r.id);
    if (ids.length === 0) { setErr('Select at least one row to confirm.'); return; }
    setBusy('confirm'); setErr(null);
    const { data, error } = await supabase.rpc('confirm_tiktok_batch', {
      p_batch_id: activeBatch.id, p_row_ids: ids,
      p_allow_negative: allowNegative, p_negative_reason: negativeReason,
    });
    setBusy(null);
    if (error) {
      // Negative stock demands an explicit, reasoned confirmation.
      if (error.message.includes('NEGATIVE_STOCK_CONFIRMATION_REQUIRED')) {
        setNegPrompt(error.message.split('NEGATIVE_STOCK_CONFIRMATION_REQUIRED:')[1]?.trim() ?? error.message);
        setNegAck(false); setNegReason('');
        return;
      }
      setErr(error.message); return;
    }
    const res = data as any;
    alert(`Confirmed: ${res.applied} rows applied (${res.units_deducted} deducted, ${res.units_returned} returned, ${res.awaiting_physical_return ?? 0} awaiting physical return), ${res.skipped} skipped.`);
    await load(); await loadBatchRows(activeBatch.id);
  };

  const targetName = (r: any) =>
    r.matched_kind === 'product' ? products.find(p => p.id === r.matched_id)?.name
    : r.matched_kind === 'voucher' ? vouchers.find(v => v.id === r.matched_id)?.name
    : r.matched_kind === 'promotion' ? promotions.find(p => p.id === r.matched_id)?.name
    : null;

  const staged = activeBatch?.status === 'staged';
  const selCount = useMemo(() => rows.filter(r => selected[r.id]).length, [rows, selected]);

  return (
    <div>
      <div className="page-header">
        <div><h1>TikTok Sales Import</h1>
          <p style={{ color: 'var(--text-muted)', fontSize: 13 }}>Upload TikTok order and settlement files — sheets are detected by headers, IDs stay exact, and stock only moves when you confirm.</p></div>
        <div style={{ display: 'flex', gap: 8 }}>
          {canManage && <button className="btn btn-secondary" onClick={() => setStatusOpen(true)}>Status Mappings</button>}
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} /> Refresh</button>
        </div>
      </div>

      {err && <div className="alert alert-danger" style={{ marginBottom: 14 }}>{err}</div>}

      {loading ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div> : (
        <>
          {/* Phase 18 tab bar */}
          <div style={{ display: 'flex', gap: 4, marginBottom: 14, borderBottom: '1px solid var(--border)', flexWrap: 'wrap' }}>
            {([['staged', 'Staged Imports'], ['orders', 'Orders'], ['items', 'Order Items'], ['settlements', 'Settlements'],
               ['unmatched', 'Unmatched SKUs'], ['recon', 'Reconciliation'], ['history', 'Import History'],
               ['returns', 'Physical Returns'], ['corrections', 'Corrections']] as const).map(([v, l]) => (
              <button key={v} onClick={() => setPageTab(v)} style={{ padding: '7px 12px', background: 'none', border: 'none', fontSize: 12.5, borderBottom: pageTab === v ? '2px solid var(--primary)' : '2px solid transparent', color: pageTab === v ? 'var(--primary)' : 'var(--text-secondary)', fontWeight: pageTab === v ? 700 : 500, cursor: 'pointer', whiteSpace: 'nowrap' }}>{l}</button>
            ))}
          </div>

          {pageTab === 'staged' && <>
          {/* Store + the two upload areas */}
          <div className="card" style={{ padding: 16, marginBottom: 14 }}>
            <div style={{ display: 'flex', gap: 12, alignItems: 'flex-end', flexWrap: 'wrap' }}>
              <div style={{ minWidth: 220 }}>
                <label>Store {isStaff && <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>(your assigned store)</span>}</label>
                <select value={effectiveStore} disabled={isStaff} onChange={e => setStoreId(e.target.value)}>
                  {!isStaff && <option value="">— Select store —</option>}
                  {stores.filter(s => !isStaff || s.id === assignedStore).map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </div>
              <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                <div style={{ border: '1px dashed var(--border)', borderRadius: 'var(--radius-sm)', padding: '12px 16px' }}>
                  <div style={{ fontWeight: 700, fontSize: 13, marginBottom: 6 }}><FileSpreadsheet size={14} style={{ verticalAlign: -2 }} /> TikTok Order File</div>
                  <input ref={orderInput} type="file" accept=".xlsx,.csv" style={{ display: 'none' }}
                    onChange={e => { const f = e.target.files?.[0]; if (f) handleUpload(f, 'order'); e.target.value = ''; }} />
                  <button className="btn btn-primary btn-sm" disabled={busy !== null || !effectiveStore} onClick={() => orderInput.current?.click()}>
                    <Upload size={13} /> {busy === 'order' ? 'Parsing…' : 'Upload .xlsx / .csv'}
                  </button>
                </div>
                <div style={{ border: '1px dashed var(--border)', borderRadius: 'var(--radius-sm)', padding: '12px 16px' }}>
                  <div style={{ fontWeight: 700, fontSize: 13, marginBottom: 6 }}><FileSpreadsheet size={14} style={{ verticalAlign: -2 }} /> TikTok Settlement File</div>
                  <input ref={settleInput} type="file" accept=".xlsx,.csv" style={{ display: 'none' }}
                    onChange={e => { const f = e.target.files?.[0]; if (f) handleUpload(f, 'settlement'); e.target.value = ''; }} />
                  <button className="btn btn-secondary btn-sm" disabled={busy !== null || !effectiveStore} onClick={() => settleInput.current?.click()}>
                    <Upload size={13} /> {busy === 'settlement' ? 'Parsing…' : 'Upload .xlsx / .csv'}
                  </button>
                </div>
              </div>
            </div>
          </div>

          {/* Physical returns awaiting confirmation */}
          {physReturns.length > 0 && (
            <div className="card" style={{ padding: 16, marginBottom: 14 }}>
              <h3 style={{ fontSize: 14.5, marginBottom: 4 }}>Awaiting Physical Return</h3>
              <p style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
                Cancelled after shipment — stock is NOT returned automatically. Confirm each parcel when it arrives (or record why it never will).
              </p>
              <table>
                <thead><tr><th>Order ID</th><th>Seller SKU</th><th style={{ textAlign: 'right' }}>Expected Qty</th><th>Since</th><th></th></tr></thead>
                <tbody>{physReturns.map(pr => (
                  <tr key={pr.id}>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{pr.order_id}</td>
                    <td style={{ fontSize: 12 }}>{pr.seller_sku}</td>
                    <td style={{ textAlign: 'right' }}>{pr.expected_qty}</td>
                    <td style={{ fontSize: 12 }}>{new Date(pr.created_at).toLocaleDateString()}</td>
                    <td><button className="btn btn-secondary btn-sm" onClick={() => { setResolvePr(pr); setPrRestock(true); setPrReason('damaged'); setPrNote(''); }}>Resolve</button></td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}

          {/* Batches (staged view shows staged only; Import History shows all) */}
          <div className="card" style={{ padding: 16, marginBottom: 14 }}>
            <h3 style={{ fontSize: 14.5, marginBottom: 8 }}>Staged Import Batches</h3>
            {batches.filter(b => b.status === 'staged').length === 0 ? <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No imports yet.</div> : (
              <table>
                <thead><tr><th>File</th><th>Kind</th><th>Store</th><th>Uploaded</th><th style={{ textAlign: 'right' }}>Rows</th><th style={{ textAlign: 'right' }}>Deducted</th><th style={{ textAlign: 'right' }}>Returned</th><th>Status</th><th></th></tr></thead>
                <tbody>{batches.filter(b => b.status === 'staged').map(b => (
                  <tr key={b.batch_id}>
                    <td style={{ fontSize: 12.5 }}><strong>{b.file_name}</strong>{b.uploaded_by_name && <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>{b.uploaded_by_name}</div>}</td>
                    <td style={{ fontSize: 12 }}>{b.file_kind}</td>
                    <td style={{ fontSize: 12 }}>{b.store_name}</td>
                    <td style={{ fontSize: 12 }}>{new Date(b.uploaded_at).toLocaleString()}</td>
                    <td style={{ textAlign: 'right' }}>{b.row_count}</td>
                    <td style={{ textAlign: 'right' }}>{b.units_deducted}</td>
                    <td style={{ textAlign: 'right' }}>{b.units_returned}</td>
                    <td>{b.status === 'confirmed' ? <span className="badge badge-success">Confirmed</span> : <span className="badge badge-warning">Staged</span>}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      {b.file_kind !== 'correction' && <button className="btn btn-secondary btn-sm" onClick={() => b.file_kind === 'settlement' ? loadSettleRows(b.batch_id) : loadBatchRows(b.batch_id)}><Eye size={12} /> Open</button>}
                      {canManage && b.status === 'staged' && (
                        <button className="btn btn-danger btn-sm btn-icon" title="Delete unconfirmed batch"
                          onClick={async () => { if (!confirm('Delete this staged batch? No stock has moved.')) return; const { error } = await supabase.rpc('delete_tiktok_batch', { p_batch_id: b.batch_id }); if (error) setErr(error.message); else { if (activeBatch?.id === b.batch_id) { setActiveBatch(null); setRows([]); } load(); } }}>
                          <Trash2 size={12} /></button>
                      )}
                    </div></td>
                  </tr>
                ))}</tbody>
              </table>
            )}
          </div>

          {/* Staging preview */}
          {activeBatch && (
            <div className="card" style={{ padding: 16 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8, flexWrap: 'wrap' }}>
                <h3 style={{ fontSize: 14.5, flex: 1 }}>{activeBatch.file_name} — {staged ? 'Preview (no stock moved yet)' : 'Confirmed (locked)'}</h3>
                {staged && <>
                  <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{selCount} selected</span>
                  <button className="btn btn-primary btn-sm" disabled={busy !== null || selCount === 0} onClick={() => confirmBatch()}>
                    <CheckCircle2 size={13} /> {busy === 'confirm' ? 'Confirming…' : 'Confirm Selected Rows'}
                  </button>
                </>}
              </div>
              <table>
                <thead><tr>
                  {staged && <th></th>}
                  <th>#</th><th>Order ID</th><th>Seller SKU</th><th>Product</th><th style={{ textAlign: 'right' }}>Qty</th><th>TikTok Status</th><th>Mapping</th><th>Staging Status</th><th>Prev → New</th><th style={{ textAlign: 'right' }}>Δ Stock</th><th style={{ textAlign: 'right' }}>Δ $</th><th></th>
                </tr></thead>
                <tbody>{rows.map(r => (
                  <tr key={r.id} style={{ opacity: r.excluded && !r.confirmed ? 0.45 : 1 }}>
                    {staged && <td><input type="checkbox" checked={!!selected[r.id]} disabled={r.excluded || !CONFIRMABLE.has(r.staging_status)}
                      onChange={e => setSelected(s => ({ ...s, [r.id]: e.target.checked }))} style={{ width: 'auto' }} /></td>}
                    <td style={{ fontSize: 12 }}>{r.row_no}</td>
                    {/* Order IDs render as text — they were never numbers anywhere. */}
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.order_id ?? '—'}</td>
                    <td style={{ fontSize: 12 }}>{r.seller_sku ?? '—'}</td>
                    <td style={{ fontSize: 12 }}>{r.product_name ?? '—'}</td>
                    <td style={{ textAlign: 'right' }}>{r.quantity ?? '—'}</td>
                    <td style={{ fontSize: 12 }}>{r.order_status ?? '—'}</td>
                    <td style={{ fontSize: 12 }}>
                      {r.matched_kind ? <>{r.matched_kind}: {targetName(r) ?? '?'}</> : <span style={{ color: 'var(--text-muted)' }}>—</span>}
                      {staged && r.seller_sku && (
                        <button className="btn btn-secondary btn-sm" style={{ marginLeft: 6, padding: '1px 7px', fontSize: 10.5 }}
                          onClick={() => { setMapSku({ sku: r.seller_sku }); setMapKind('product'); setMapTarget(''); }}>Map</button>
                      )}
                    </td>
                    <td><span className={`badge ${STATUS_BADGE[r.staging_status] ?? 'badge-muted'}`}>{r.staging_status}</span>
                      {r.confirmed && <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>applied</div>}</td>
                    <td style={{ fontSize: 11.5 }}>
                      {r.previous_row_id
                        ? <>v{r.version_no}: {r.prev_quantity}×{r.prev_order_status ?? '?'} → {r.quantity}×{r.order_status ?? '?'}</>
                        : <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                    <td style={{ textAlign: 'right', fontWeight: 600, color: r.stock_delta > 0 ? 'var(--danger)' : r.stock_delta < 0 ? 'var(--success)' : 'inherit' }}>
                      {r.stock_delta > 0 ? `−${r.stock_delta}` : r.stock_delta < 0 ? `+${-r.stock_delta}` : '0'}</td>
                    <td style={{ textAlign: 'right', fontSize: 12 }}>{r.financial_delta != null ? Number(r.financial_delta).toFixed(2) : '—'}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      {staged && !r.confirmed && (
                        <button className="btn btn-danger btn-sm btn-icon" title="Remove staged row"
                          onClick={async () => { const { error } = await supabase.rpc('delete_tiktok_row', { p_row_id: r.id }); if (error) setErr(error.message); else loadBatchRows(activeBatch.id); }}>
                          <Trash2 size={12} /></button>
                      )}
                      {canManage && r.confirmed && r.matched_kind && r.staging_status !== 'Already Imported' && (
                        <button className="btn btn-secondary btn-sm btn-icon" title="Correction (Owner/Manager)"
                          onClick={() => { setCorrectRow(r); setCorrDelta(-1); setCorrReason(''); }}>
                          <Wrench size={12} /></button>
                      )}
                    </div></td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}

          {/* Settlement staging preview */}
          {settleBatch && (
            <div className="card" style={{ padding: 16, marginTop: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 4, flexWrap: 'wrap' }}>
                <h3 style={{ fontSize: 14.5, flex: 1 }}>{settleBatch.file_name} — {settleBatch.status === 'staged' ? 'Settlement Preview' : 'Settlement Confirmed (locked)'}</h3>
                {settleBatch.status === 'staged' && (
                  <button className="btn btn-primary btn-sm" disabled={busy !== null} onClick={confirmSettleBatch}>
                    <CheckCircle2 size={13} /> {busy === 'sconfirm' ? 'Confirming…' : 'Confirm Selected Rows'}
                  </button>
                )}
              </div>
              <p style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
                Settlement imports never change inventory. Total Settlement Amount is the main figure; updates show the differences and require your confirmation to become a new version.
              </p>
              <table>
                <thead><tr>
                  {settleBatch.status === 'staged' && <th></th>}
                  <th>Order/Adj ID</th><th>Type</th><th>Related</th><th>Order Created</th>
                  <th style={{ textAlign: 'right' }}>Settlement</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th>
                  <th>Match</th><th>Status</th><th>Reconciled</th>
                </tr></thead>
                <tbody>{settleRows.map(r => (
                  <tr key={r.id} style={{ opacity: r.excluded && !r.confirmed ? 0.45 : 1 }}>
                    {settleBatch.status === 'staged' && <td><input type="checkbox" checked={!!settleSel[r.id]}
                      disabled={r.excluded || !SETTLE_CONFIRMABLE.has(r.staging_status)}
                      onChange={e => setSettleSel(x => ({ ...x, [r.id]: e.target.checked }))} style={{ width: 'auto' }} /></td>}
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.order_id ?? '—'}
                      {r.version_no > 1 && <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>v{r.version_no}</div>}</td>
                    <td style={{ fontSize: 12 }}>{r.transaction_type ?? '—'}<div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>{r.txn_class}</div></td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 11.5 }}>{r.related_order_id ?? '—'}</td>
                    <td style={{ fontSize: 12 }}>{r.order_created_time ? new Date(r.order_created_time).toLocaleDateString() : '—'}</td>
                    <td style={{ textAlign: 'right', fontWeight: 700 }}>{r.settlement_amount != null ? Number(r.settlement_amount).toFixed(2) : '—'}</td>
                    <td style={{ textAlign: 'right', fontSize: 12 }}>{r.revenue_amount != null ? Number(r.revenue_amount).toFixed(2) : '—'}</td>
                    <td style={{ textAlign: 'right', fontSize: 12 }}>{r.fee_amount != null ? Number(r.fee_amount).toFixed(2) : '—'}</td>
                    <td>{matchBadge(r.match_status)}</td>
                    <td>
                      <span className={`badge ${r.staging_status?.startsWith('Updated') ? 'badge-warning' : r.staging_status === 'Invalid Row' ? 'badge-danger' : 'badge-muted'}`}>{r.staging_status}</span>
                      {r.value_diff && Object.keys(r.value_diff).length > 0 && (
                        <div style={{ fontSize: 10.5, color: 'var(--text-muted)', maxWidth: 220 }}>
                          {Object.entries(r.value_diff as Record<string, any>).map(([f, d]) => (
                            <div key={f}>{f}: {String(d.old ?? '—')} → {String(d.new ?? '—')}</div>
                          ))}
                        </div>
                      )}
                    </td>
                    <td>{r.reconciled === false
                      ? <span className="badge badge-danger" title="Total Settlement ≠ Revenue + Fees (±$0.01)">⚠ Off</span>
                      : r.reconciled === true ? <span className="badge badge-success">OK</span>
                      : <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>—</span>}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}
          </>}

          {/* Import History: every batch including corrections */}
          {pageTab === 'history' && (
            <div className="card" style={{ padding: 16 }}>
              <h3 style={{ fontSize: 14.5, marginBottom: 8 }}>Import History</h3>
              <table>
                <thead><tr><th>File</th><th>Kind</th><th>Store</th><th>Uploaded</th><th style={{ textAlign: 'right' }}>Rows</th><th style={{ textAlign: 'right' }}>Deducted</th><th style={{ textAlign: 'right' }}>Returned</th><th>Status</th><th></th></tr></thead>
                <tbody>{batches.map(b => (
                  <tr key={b.batch_id}>
                    <td style={{ fontSize: 12.5 }}><strong>{b.file_name}</strong>{b.uploaded_by_name && <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>{b.uploaded_by_name}</div>}</td>
                    <td style={{ fontSize: 12 }}>{b.file_kind}</td>
                    <td style={{ fontSize: 12 }}>{b.store_name}</td>
                    <td style={{ fontSize: 12 }}>{new Date(b.uploaded_at).toLocaleString()}</td>
                    <td style={{ textAlign: 'right' }}>{b.row_count}</td>
                    <td style={{ textAlign: 'right' }}>{b.units_deducted}</td>
                    <td style={{ textAlign: 'right' }}>{b.units_returned}</td>
                    <td>{b.status === 'confirmed' ? <span className="badge badge-success">Confirmed</span> : <span className="badge badge-warning">Staged</span>}</td>
                    <td>{b.file_kind !== 'correction' && <button className="btn btn-secondary btn-sm" onClick={() => { setPageTab('staged'); b.file_kind === 'settlement' ? loadSettleRows(b.batch_id) : loadBatchRows(b.batch_id); }}><Eye size={12} /> Open</button>}</td>
                  </tr>
                ))}</tbody>
              </table>
            </div>
          )}

          {/* Orders */}
          {pageTab === 'orders' && (
            <div className="card" style={{ padding: 16 }}>
              <h3 style={{ fontSize: 14.5, marginBottom: 8 }}>Imported Orders</h3>
              {tabLoading ? <div className="empty-state"><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div> : (
                <table>
                  <thead><tr><th>Order ID</th><th>Seller SKU</th><th>Last Status</th><th style={{ textAlign: 'right' }}>Net Deducted</th><th>Shipped</th><th>Updated</th></tr></thead>
                  <tbody>{tabRows.map((r, i) => (
                    <tr key={i}>
                      <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.order_id}</td>
                      <td style={{ fontSize: 12 }}>{r.seller_sku}</td>
                      <td style={{ fontSize: 12 }}>{r.last_status ?? '—'}</td>
                      <td style={{ textAlign: 'right', fontWeight: 600 }}>{r.deducted_qty}</td>
                      <td>{r.was_shipped ? <span className="badge badge-muted">Shipped</span> : <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>—</span>}</td>
                      <td style={{ fontSize: 12 }}>{new Date(r.updated_at).toLocaleString()}</td>
                    </tr>
                  ))}</tbody>
                </table>
              )}
            </div>
          )}

          {/* Order Items */}
          {pageTab === 'items' && (
            <div className="card" style={{ padding: 16 }}>
              <h3 style={{ fontSize: 14.5, marginBottom: 8 }}>Confirmed Order Items (latest 300)</h3>
              {tabLoading ? <div className="empty-state"><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div> : (
                <table>
                  <thead><tr><th>Order ID</th><th>SKU</th><th>Product</th><th style={{ textAlign: 'right' }}>Qty</th><th>Status</th><th style={{ textAlign: 'right' }}>Δ Stock</th><th>Version</th><th>Confirmed</th></tr></thead>
                  <tbody>{tabRows.map(r => (
                    <tr key={r.id}>
                      <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.order_id}</td>
                      <td style={{ fontSize: 12 }}>{r.seller_sku}</td>
                      <td style={{ fontSize: 12 }}>{r.product_name ?? '—'}</td>
                      <td style={{ textAlign: 'right' }}>{r.quantity}</td>
                      <td style={{ fontSize: 12 }}>{r.order_status}</td>
                      <td style={{ textAlign: 'right', fontWeight: 600 }}>{r.stock_delta}</td>
                      <td style={{ fontSize: 11.5 }}>v{r.version_no}{r.previous_row_id ? ' (linked)' : ''}</td>
                      <td style={{ fontSize: 12 }}>{r.confirmed_at ? new Date(r.confirmed_at).toLocaleString() : '—'}</td>
                    </tr>
                  ))}</tbody>
                </table>
              )}
            </div>
          )}

          {/* Settlements */}
          {pageTab === 'settlements' && (
            <div className="card" style={{ padding: 16 }}>
              <h3 style={{ fontSize: 14.5, marginBottom: 8 }}>Settlement Transactions (current versions)</h3>
              {tabLoading ? <div className="empty-state"><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div> : (
                <table>
                  <thead><tr><th>Date</th><th>Order/Adj ID</th><th>Type</th><th>Match</th><th style={{ textAlign: 'right' }}>Settlement</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th><th>Reconciled</th></tr></thead>
                  <tbody>{tabRows.map(r => (
                    <tr key={r.row_id}>
                      <td style={{ fontSize: 12 }}>{r.financial_date ? new Date(r.financial_date).toLocaleDateString() : '—'}</td>
                      <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.order_adjustment_id}{r.version_no > 1 ? ` (v${r.version_no})` : ''}</td>
                      <td style={{ fontSize: 12, textTransform: 'capitalize' }}>{r.txn_class}</td>
                      <td>{matchBadge(r.match_status)}</td>
                      <td style={{ textAlign: 'right', fontWeight: 700 }}>{Number(r.settlement_amount ?? 0).toFixed(2)}</td>
                      <td style={{ textAlign: 'right' }}>{Number(r.revenue_amount ?? 0).toFixed(2)}</td>
                      <td style={{ textAlign: 'right' }}>{Number(r.fee_amount ?? 0).toFixed(2)}</td>
                      <td>{r.reconciled === false ? <span className="badge badge-danger">⚠ Off</span> : r.reconciled === true ? <span className="badge badge-success">OK</span> : '—'}</td>
                    </tr>
                  ))}</tbody>
                </table>
              )}
            </div>
          )}

          {/* Unmatched SKUs */}
          {pageTab === 'unmatched' && (
            <div className="card" style={{ padding: 16 }}>
              <h3 style={{ fontSize: 14.5, marginBottom: 8 }}>Unmatched Seller SKUs</h3>
              {tabLoading ? <div className="empty-state"><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div> : (
                <table>
                  <thead><tr><th>Store</th><th>Seller SKU</th><th style={{ textAlign: 'right' }}>Occurrences</th><th>Last Seen</th><th>Status</th><th></th></tr></thead>
                  <tbody>{tabRows.map((r, i) => (
                    <tr key={i}>
                      <td style={{ fontSize: 12 }}>{r.store_name}</td>
                      <td style={{ fontSize: 12, fontWeight: 600 }}>{r.seller_sku}</td>
                      <td style={{ textAlign: 'right' }}>{r.occurrences}</td>
                      <td style={{ fontSize: 12 }}>{new Date(r.last_seen).toLocaleDateString()}</td>
                      <td>{r.still_unmapped ? <span className="badge badge-warning">Unmapped</span> : <span className="badge badge-success">Now Mapped</span>}</td>
                      <td>{r.still_unmapped && <button className="btn btn-secondary btn-sm" onClick={() => { setMapSku({ sku: r.seller_sku }); setMapKind('product'); setMapTarget(''); }}>Map</button>}</td>
                    </tr>
                  ))}</tbody>
                </table>
              )}
            </div>
          )}

          {/* Reconciliation exceptions */}
          {pageTab === 'recon' && (
            <div className="card" style={{ padding: 16 }}>
              <h3 style={{ fontSize: 14.5, marginBottom: 4 }}>Reconciliation</h3>
              <p style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>Orders without settlement, settlements without order, and Settlement ≠ Revenue + Fees differences (±$0.01).</p>
              {tabLoading ? <div className="empty-state"><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div> : (
                <table>
                  <thead><tr><th>Kind</th><th>Store</th><th>Order ID</th><th>Detail</th><th style={{ textAlign: 'right' }}>Amount</th></tr></thead>
                  <tbody>{tabRows.length === 0 ? <tr><td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 24 }}>Fully reconciled — no exceptions</td></tr>
                    : tabRows.map((r, i) => (
                    <tr key={i}>
                      <td><span className={`badge ${r.kind === 'reconciliation_difference' ? 'badge-danger' : 'badge-warning'}`}>{String(r.kind ?? '—').replace(/_/g, ' ')}</span></td>
                      <td style={{ fontSize: 12 }}>{r.store_name}</td>
                      <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.order_id}</td>
                      <td style={{ fontSize: 12 }}>{r.detail}</td>
                      <td style={{ textAlign: 'right', color: 'var(--danger)' }}>{r.amount != null ? Number(r.amount).toFixed(2) : '—'}</td>
                    </tr>
                  ))}</tbody>
                </table>
              )}
            </div>
          )}

          {/* Physical Returns (all statuses) */}
          {pageTab === 'returns' && (
            <div className="card" style={{ padding: 16 }}>
              <h3 style={{ fontSize: 14.5, marginBottom: 8 }}>Physical Returns</h3>
              {tabLoading ? <div className="empty-state"><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div> : (
                <table>
                  <thead><tr><th>Order ID</th><th>Seller SKU</th><th style={{ textAlign: 'right' }}>Expected</th><th>Status</th><th>Reason</th><th>Created</th><th></th></tr></thead>
                  <tbody>{tabRows.map(pr => (
                    <tr key={pr.id}>
                      <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{pr.order_id}</td>
                      <td style={{ fontSize: 12 }}>{pr.seller_sku}</td>
                      <td style={{ textAlign: 'right' }}>{pr.expected_qty}</td>
                      <td>{pr.status === 'awaiting' ? <span className="badge badge-warning">Awaiting</span>
                        : pr.status === 'restocked' ? <span className="badge badge-success">Restocked</span>
                        : <span className="badge badge-muted">No Restock</span>}</td>
                      <td style={{ fontSize: 12 }}>{pr.resolution_reason ?? '—'}{pr.resolution_note && <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>{pr.resolution_note}</div>}</td>
                      <td style={{ fontSize: 12 }}>{new Date(pr.created_at).toLocaleDateString()}</td>
                      <td>{pr.status === 'awaiting' && <button className="btn btn-secondary btn-sm" onClick={() => { setResolvePr(pr); setPrRestock(true); setPrReason('damaged'); setPrNote(''); }}>Resolve</button>}</td>
                    </tr>
                  ))}</tbody>
                </table>
              )}
            </div>
          )}

          {/* Corrections */}
          {pageTab === 'corrections' && (
            <div className="card" style={{ padding: 16 }}>
              <h3 style={{ fontSize: 14.5, marginBottom: 8 }}>Correction History</h3>
              {tabLoading ? <div className="empty-state"><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div> : (
                <table>
                  <thead><tr><th>When</th><th>Kind</th><th style={{ textAlign: 'right' }}>Qty Δ</th><th>Reason</th></tr></thead>
                  <tbody>{tabRows.map(c => (
                    <tr key={c.id}>
                      <td style={{ fontSize: 12 }}>{new Date(c.created_at).toLocaleString()}</td>
                      <td style={{ fontSize: 12 }}>{c.matched_kind ?? '—'}</td>
                      <td style={{ textAlign: 'right', fontWeight: 600, color: c.qty_delta > 0 ? 'var(--danger)' : 'var(--success)' }}>{c.qty_delta > 0 ? `+${c.qty_delta}` : c.qty_delta}</td>
                      <td style={{ fontSize: 12 }}>{c.reason ?? '—'}</td>
                    </tr>
                  ))}</tbody>
                </table>
              )}
            </div>
          )}
        </>
      )}

      {/* Negative-stock explicit confirmation */}
      {negPrompt && (
        <Modal title="Negative Stock — Explicit Confirmation Required" maxWidth={460} onClose={() => setNegPrompt(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setNegPrompt(null)}>Cancel</button>
            <button className="btn btn-danger" disabled={busy !== null || !negAck || !negReason.trim()}
              onClick={() => { const reason = negReason.trim(); setNegPrompt(null); confirmBatch(true, reason); }}>
              Confirm Into Negative Stock
            </button>
          </>}>
          <div className="form-grid">
            <div className="alert alert-danger" style={{ fontSize: 12.5 }}>
              <strong>Warning:</strong> confirming will drive stock below zero for {negPrompt}
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              Only confirmed TikTok sales may go negative — invoices, transfers and adjustments stay blocked. This confirmation is audit-logged and shows on the dashboard until stock is replenished.
            </div>
            <div><label>Reason <span style={{ color: 'var(--danger)' }}>*</span></label>
              <input value={negReason} onChange={e => setNegReason(e.target.value)} placeholder="e.g. LIVE oversold, replenishment on the way" /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 12.5 }}>
              <input type="checkbox" checked={negAck} onChange={e => setNegAck(e.target.checked)} style={{ width: 'auto' }} />
              I understand these TikTok sales exceed recorded stock and confirm the deduction anyway.
            </label>
          </div>
        </Modal>
      )}

      {/* Physical return resolution */}
      {resolvePr && (
        <Modal title={`Physical Return — order ${resolvePr.order_id}`} maxWidth={440} onClose={() => setResolvePr(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setResolvePr(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy !== null || (!prRestock && prReason === 'other' && !prNote.trim())}
              onClick={async () => {
                setBusy('pr'); setErr(null);
                const { error } = await supabase.rpc('resolve_tiktok_physical_return', {
                  p_return_id: resolvePr.id, p_restock: prRestock,
                  p_reason: prRestock ? null : prReason, p_note: prNote.trim() || null,
                });
                setBusy(null);
                if (error) { setErr(error.message); return; }
                setResolvePr(null); load(); if (activeBatch) loadBatchRows(activeBatch.id);
              }}>{busy === 'pr' ? 'Saving…' : 'Resolve'}</button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5 }}>Expected quantity: <strong>{resolvePr.expected_qty}</strong> × {resolvePr.seller_sku}</div>
            <div>
              <label style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 13, marginBottom: 4 }}>
                <input type="radio" checked={prRestock} onChange={() => setPrRestock(true)} style={{ width: 'auto' }} /> Stock Return — parcel received, put stock back
              </label>
              <label style={{ display: 'flex', alignItems: 'center', gap: 7, fontSize: 13 }}>
                <input type="radio" checked={!prRestock} onChange={() => setPrRestock(false)} style={{ width: 'auto' }} /> No Stock Return — reason required
              </label>
            </div>
            {!prRestock && (
              <div><label>Reason <span style={{ color: 'var(--danger)' }}>*</span></label>
                <select value={prReason} onChange={e => setPrReason(e.target.value)}>
                  <option value="damaged">Damaged</option>
                  <option value="lost">Lost</option>
                  <option value="not_received">Not received</option>
                  <option value="other">Other</option>
                </select></div>
            )}
            <div><label>Note{!prRestock && prReason === 'other' && <span style={{ color: 'var(--danger)' }}> *</span>}</label>
              <input value={prNote} onChange={e => setPrNote(e.target.value)} /></div>
          </div>
        </Modal>
      )}

      {/* Status mappings (Owner/Manager) */}
      {statusOpen && (
        <Modal title="TikTok Status Mappings" maxWidth={540} onClose={() => setStatusOpen(false)}
          footer={<button className="btn btn-secondary" onClick={() => setStatusOpen(false)}>Close</button>}>
          <div className="form-grid">
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              Each TikTok order status maps to Deduct Stock, Return Stock or No Stock Action. "Marks shipped" controls the cancellation lifecycle: after a shipped status, cancellations wait for the physical return instead of restocking automatically. Unknown statuses are treated as Invalid Status.
            </div>
            <div>
              {statusMaps.map(m => (
                <div key={m.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 4px', borderBottom: '1px solid var(--border)' }}>
                  <span style={{ flex: 1, fontSize: 13, fontWeight: 600, opacity: m.is_active ? 1 : 0.5 }}>{m.status_label}</span>
                  <select value={m.action} style={{ maxWidth: 150 }} onChange={async e => {
                    const { error } = await supabase.rpc('upsert_tiktok_status_mapping', { p_status_label: m.status_label, p_action: e.target.value, p_marks_shipped: m.marks_shipped, p_is_active: m.is_active });
                    if (error) setErr(error.message); else load();
                  }}>
                    <option value="deduct">Deduct Stock</option>
                    <option value="return">Return Stock</option>
                    <option value="none">No Stock Action</option>
                  </select>
                  <label style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 11.5 }}>
                    <input type="checkbox" checked={m.marks_shipped} style={{ width: 'auto' }} onChange={async e => {
                      const { error } = await supabase.rpc('upsert_tiktok_status_mapping', { p_status_label: m.status_label, p_action: m.action, p_marks_shipped: e.target.checked, p_is_active: m.is_active });
                      if (error) setErr(error.message); else load();
                    }} /> shipped
                  </label>
                  <button className={`btn btn-sm ${m.is_active ? 'btn-danger' : 'btn-primary'}`} onClick={async () => {
                    const { error } = await supabase.rpc('set_tiktok_status_mapping_active', { p_id: m.id, p_active: !m.is_active });
                    if (error) setErr(error.message); else load();
                  }}>{m.is_active ? 'Deactivate' : 'Activate'}</button>
                </div>
              ))}
            </div>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <input placeholder="New TikTok status" value={newStatus} onChange={e => setNewStatus(e.target.value)} style={{ flex: 1 }} />
              <select value={newAction} onChange={e => setNewAction(e.target.value as any)} style={{ maxWidth: 140 }}>
                <option value="deduct">Deduct</option>
                <option value="return">Return</option>
                <option value="none">No Action</option>
              </select>
              <label style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 11.5 }}>
                <input type="checkbox" checked={newShipped} onChange={e => setNewShipped(e.target.checked)} style={{ width: 'auto' }} /> shipped
              </label>
              <button className="btn btn-primary btn-sm" disabled={!newStatus.trim()} onClick={async () => {
                const { error } = await supabase.rpc('upsert_tiktok_status_mapping', { p_status_label: newStatus.trim(), p_action: newAction, p_marks_shipped: newShipped, p_is_active: true });
                if (error) setErr(error.message); else { setNewStatus(''); setNewShipped(false); load(); }
              }}>Add</button>
            </div>
          </div>
        </Modal>
      )}

      {/* SKU mapping */}
      {mapSku && (
        <Modal title={`Map Seller SKU — ${mapSku.sku}`} maxWidth={420} onClose={() => setMapSku(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setMapSku(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy !== null || !mapTarget} onClick={saveMapping}>{busy === 'map' ? 'Saving…' : 'Save Mapping'}</button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              Matching is exact and case-sensitive. The mapping is remembered for this store — future files with this SKU match automatically. Inactive records cannot be mapped.
            </div>
            <div><label>Map to</label>
              <select value={mapKind} onChange={e => { setMapKind(e.target.value as any); setMapTarget(''); }}>
                <option value="product">Product</option>
                <option value="voucher">Voucher</option>
                <option value="promotion">Promotion</option>
              </select></div>
            <div><label>{mapKind === 'product' ? 'Product' : mapKind === 'voucher' ? 'Voucher' : 'Promotion'}</label>
              <SearchSelect
                value={mapTarget} onChange={setMapTarget}
                placeholder={`Search ${mapKind} name or ${mapKind === 'product' ? 'SKU' : 'code'}…`}
                options={(mapKind === 'product' ? products : mapKind === 'voucher' ? vouchers : promotions)
                  .map((x: any) => ({
                    value: x.id,
                    label: x.name,
                    sublabel: x.sku ?? x.code ?? undefined,
                    search: `${x.name} ${x.sku ?? ''} ${x.code ?? ''}`,
                  }))} /></div>
          </div>
        </Modal>
      )}

      {/* Correction (Owner/Manager, confirmed rows) */}
      {correctRow && (
        <Modal title={`Correction — order ${correctRow.order_id}`} maxWidth={420} onClose={() => setCorrectRow(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setCorrectRow(null)}>Cancel</button>
            <button className="btn btn-primary" disabled={busy !== null || corrDelta === 0 || !corrReason.trim()} onClick={async () => {
              setBusy('corr'); setErr(null);
              const { error } = await supabase.rpc('correct_tiktok_row', { p_row_id: correctRow.id, p_qty_delta: corrDelta, p_reason: corrReason.trim() });
              setBusy(null);
              if (error) { setErr(error.message); return; }
              setCorrectRow(null); await load(); if (activeBatch) await loadBatchRows(activeBatch.id);
            }}>{busy === 'corr' ? 'Applying…' : 'Apply Correction'}</button>
          </>}>
          <div className="form-grid">
            <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
              Creates an Owner/Manager correction batch with a reversing (negative) or additional (positive) stock movement. Applies through the row's mapping ({correctRow.matched_kind}: {targetName(correctRow) ?? '?'}) and is recorded with your reason.
            </div>
            <div><label>Quantity delta</label>
              <input type="number" value={corrDelta} onChange={e => setCorrDelta(parseInt(e.target.value || '0', 10))} /></div>
            <div><label>Reason <span style={{ color: 'var(--danger)' }}>*</span></label>
              <input value={corrReason} onChange={e => setCorrReason(e.target.value)} /></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default TikTokImportPage;
