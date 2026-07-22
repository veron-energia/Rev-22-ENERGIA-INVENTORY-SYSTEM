import React, { useEffect, useState, useCallback, useMemo, useRef } from 'react';
import * as XLSX from 'xlsx';
import Papa from 'papaparse';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, Product, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import { RefreshCw, Upload, FileSpreadsheet, Trash2, CheckCircle2, Eye, Wrench } from 'lucide-react';

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
  settlement_amount: ['total settlement amount', 'settlement amount'],
  fee_amount: ['total fees', 'total fee', 'fees'],
  revenue_amount: ['total revenue', 'revenue'],
  currency: ['currency'],
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
  const [corrDelta, setCorrDelta] = useState(0);
  const [corrReason, setCorrReason] = useState('');
  const orderInput = useRef<HTMLInputElement>(null);
  const settleInput = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [st, mine, pr, vc, pm, rep] = await Promise.all([
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.rpc('my_assigned_store_id'),
      supabase.from('products').select('id,name,sku,is_active').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('vouchers').select('id,name,is_active').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('promotions').select('id,name,is_active').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.rpc('report_tiktok_imports', { p_store_id: null, p_from: null, p_to: null }),
    ]);
    setStores((st.data as Store[]) ?? []);
    setProducts((pr.data as Product[]) ?? []);
    setVouchers((vc.data as any[]) ?? []);
    setPromotions((pm.data as any[]) ?? []);
    setBatches((rep.data as any[]) ?? []);
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
      // raw:false -> formatted text for every cell, so big IDs keep all digits.
      const grid = XLSX.utils.sheet_to_json<string[]>(wb.Sheets[name], { header: 1, raw: false, defval: '' }) as unknown as string[][];
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

  const confirmBatch = async () => {
    if (!activeBatch) return;
    const ids = rows.filter(r => selected[r.id]).map(r => r.id);
    if (ids.length === 0) { setErr('Select at least one row to confirm.'); return; }
    setBusy('confirm'); setErr(null);
    const { data, error } = await supabase.rpc('confirm_tiktok_batch', { p_batch_id: activeBatch.id, p_row_ids: ids });
    setBusy(null);
    if (error) { setErr(error.message); return; }
    const res = data as any;
    alert(`Confirmed: ${res.applied} rows applied (${res.units_deducted} units deducted, ${res.units_returned} returned), ${res.skipped} skipped.`);
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
        <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} /> Refresh</button>
      </div>

      {err && <div className="alert alert-danger" style={{ marginBottom: 14 }}>{err}</div>}

      {loading ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div> : (
        <>
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

          {/* Batches */}
          <div className="card" style={{ padding: 16, marginBottom: 14 }}>
            <h3 style={{ fontSize: 14.5, marginBottom: 8 }}>Import Batches</h3>
            {batches.length === 0 ? <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No imports yet.</div> : (
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
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      {b.file_kind === 'order' && <button className="btn btn-secondary btn-sm" onClick={() => loadBatchRows(b.batch_id)}><Eye size={12} /> Open</button>}
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
                  <button className="btn btn-primary btn-sm" disabled={busy !== null || selCount === 0} onClick={confirmBatch}>
                    <CheckCircle2 size={13} /> {busy === 'confirm' ? 'Confirming…' : 'Confirm Selected Rows'}
                  </button>
                </>}
              </div>
              <table>
                <thead><tr>
                  {staged && <th></th>}
                  <th>#</th><th>Order ID</th><th>Seller SKU</th><th>Product</th><th style={{ textAlign: 'right' }}>Qty</th><th>TikTok Status</th><th>Mapping</th><th>Staging Status</th><th style={{ textAlign: 'right' }}>Δ Stock</th><th></th>
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
                    <td style={{ textAlign: 'right', fontWeight: 600, color: r.stock_delta > 0 ? 'var(--danger)' : r.stock_delta < 0 ? 'var(--success)' : 'inherit' }}>
                      {r.stock_delta > 0 ? `−${r.stock_delta}` : r.stock_delta < 0 ? `+${-r.stock_delta}` : '0'}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      {staged && !r.confirmed && (
                        <button className="btn btn-danger btn-sm btn-icon" title="Remove staged row"
                          onClick={async () => { const { error } = await supabase.rpc('delete_tiktok_row', { p_row_id: r.id }); if (error) setErr(error.message); else loadBatchRows(activeBatch.id); }}>
                          <Trash2 size={12} /></button>
                      )}
                      {canManage && r.confirmed && r.matched_kind && (
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
        </>
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
              <select value={mapTarget} onChange={e => setMapTarget(e.target.value)}>
                <option value="">— Select —</option>
                {(mapKind === 'product' ? products : mapKind === 'voucher' ? vouchers : promotions).map((x: any) =>
                  <option key={x.id} value={x.id}>{x.name}{x.sku ? ` (${x.sku})` : ''}</option>)}
              </select></div>
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
              Positive deducts additional stock; negative returns stock. Applies through the row's mapping ({correctRow.matched_kind}: {targetName(correctRow) ?? '?'}) and is recorded with your reason.
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
