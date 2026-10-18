import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Product, Store, Warehouse, LocationType, AdjustmentRequest, Profile,
  APPROVAL_STATUS_LABELS, canManageWarehouseStock,
} from '../types';
import { SearchSelect } from '../components/SearchSelect';
import { Modal } from '../components/ui';
import { Plus, RefreshCw, SlidersHorizontal } from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';
import {
  AdjustmentLine, adjustmentPlace, adjustmentSentMessage, checkAdjustmentForm, countableStoreIds, linesSettingToZero,
  zeroConfirmText,
} from '../lib/stock/stockPages';
import { mayHaveSaved, newRequestId, saveFailure } from '../lib/stock-loans/stockLoans';

const emptyLine = (): AdjustmentLine => ({ product_id: '', new_qty: '' });

const AdjustmentsPage: React.FC = () => {
  const { profile, assignments } = useAuth();
  const canWarehouse = canManageWarehouseStock(profile?.role);

  const [requests, setRequests] = useState<AdjustmentRequest[]>([]);
  // Every product, store and warehouse, deleted ones too, so old requests
  // keep their names. The form offers only the live ones.
  const [products, setProducts] = useState<Product[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  // The open stores my_assigned_stores() lists (every one for an Owner, Admin
  // or Manager). The form offers only those this person may count.
  const [myStoreIds, setMyStoreIds] = useState<string[] | null>(null);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [flash, setFlash] = useState<string | null>(null);

  const [open, setOpen] = useState(false);
  const [locType, setLocType] = useState<LocationType>('store');
  const [locId, setLocId] = useState('');
  const [reason, setReason] = useState('');
  const [reference, setReference] = useState('');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // One id per opened form: a retry after a lost answer sends nothing twice.
  // After a failure that may have saved, the form is locked as it was sent.
  const [formId, setFormId] = useState('');
  const [locked, setLocked] = useState(false);
  // Several products can be corrected in one go; each line carries its own
  // counted total, typed as text so an empty box is never taken as 0.
  const [adjLines, setAdjLines] = useState<AdjustmentLine[]>([emptyLine()]);
  // The stock at the chosen place now, by product (null: not read).
  const [live, setLive] = useState<Record<string, number> | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [req, prod, st, wh, prof, mine] = await Promise.all([
      supabase.from('approval_requests').select('*').eq('request_type', 'adjustment').order('created_at', { ascending: false }),
      supabase.from('products').select('id,name,sku,is_active,deleted_at').order('name'),
      supabase.from('stores').select('id,name,is_active,deleted_at').order('name'),
      supabase.from('warehouses').select('id,name,is_active,deleted_at').order('name'),
      supabase.from('profiles').select('id,full_name'),
      supabase.rpc('my_assigned_stores'),
    ]);
    setLoadErr(req.error ? `The requests could not be loaded (${req.error.message}). Refresh to try again.` : null);
    setRequests((req.data as AdjustmentRequest[]) ?? []);
    setProducts((prod.data as Product[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    setProfiles((prof.data as Profile[]) ?? []);
    setMyStoreIds(mine.error ? null : ((mine.data as { store_id: string }[]) ?? []).map(s => s.store_id));
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  // The stock at the chosen place, so each line shows what the system holds
  // and a count of 0 over real stock is confirmed first.
  useEffect(() => {
    if (!open || !locId) { setLive(null); return; }
    let gone = false;
    (async () => {
      const res = locType === 'store'
        ? await supabase.from('store_inventory').select('product_id,current_qty').eq('store_id', locId)
        : await supabase.from('warehouse_inventory').select('product_id,current_qty').eq('warehouse_id', locId);
      if (gone) return;
      setLive(res.error ? null : Object.fromEntries(
        ((res.data as { product_id: string; current_qty: number }[]) ?? []).map(r => [r.product_id, r.current_qty])));
    })();
    return () => { gone = true; };
  }, [open, locType, locId]);

  const pName = (id?: string) => products.find(p => p.id === id)?.name ?? '—';
  const uName = (id: string | null) => id ? (profiles.find(p => p.id === id)?.full_name ?? '—') : '—';
  const pSku = (id?: string) => products.find(p => p.id === id)?.sku ?? '';
  const storeName = (id?: string) => stores.find(s => s.id === id)?.name;
  const warehouseName = (id?: string) => warehouses.find(w => w.id === id)?.name;
  const place = (p: AdjustmentRequest['payload']) => adjustmentPlace(p, storeName, warehouseName);
  const locName = (p: AdjustmentRequest['payload']) => {
    if (!p) return '—';
    return `${p.location_type === 'store' ? '🏪' : '🏭'} ${place(p) || '—'}`;
  };

  // Searches everything in a row, plus the SKU, which is not a visible column
  // but is how stock is usually identified on a count sheet.
  const filtered = useMemo<AdjustmentRequest[]>(() => {
    const q = search.trim().toLowerCase();
    if (!q) return requests;
    return requests.filter(req => {
      const p = req.payload;
      const when = req.created_at ? new Date(req.created_at) : null;
      return [
        pName(p?.product_id), pSku(p?.product_id),
        locName(p), uName(req.requested_by), uName(req.approved_by),
        req.reason, req.status, p?.reference, req.response_note,
        String(p?.current_qty ?? ''), String(p?.new_qty ?? ''), String(p?.difference ?? ''),
        when?.toLocaleDateString('en-GB'), when?.toLocaleDateString('en-CA'),
      ].filter(Boolean).join(' ').toLowerCase().includes(q);
    });
  }, [requests, search, products, stores, warehouses, profiles]);

  const liveProducts = products.filter(p => p.is_active && !p.deleted_at);
  // An Owner or Admin counts any store; anyone else, a Manager too, only the
  // stores they work at, as the server requires.
  const countable = countableStoreIds(profile?.role, myStoreIds, (assignments ?? []).map(a => a.store_id));
  const locOptions = locType === 'store'
    ? stores.filter(s => s.is_active && !s.deleted_at && (countable == null || countable.includes(s.id)))
    : warehouses.filter(w => w.is_active && !w.deleted_at);
  const placeName = (locType === 'store' ? storeName(locId) : warehouseName(locId)) ?? 'this place';

  const openForm = () => {
    setErr(null); setFlash(null); setLocId(''); setReason(''); setReference('');
    setAdjLines([emptyLine()]); setFormId(newRequestId()); setLocked(false); setOpen(true);
  };

  const submit = async () => {
    const c = checkAdjustmentForm(locId, adjLines, reason, reference);
    if (!c.ok) { setErr(c.error); return; }
    const zero = locked ? [] : linesSettingToZero(c.value.p_lines, live);
    if (zero.length > 0 && !window.confirm(zeroConfirmText(zero.map(id => pName(id)), placeName))) return;

    setSaving(true); setErr(null);
    // One call for every line: all are sent or none is. A line whose count
    // matches the system is left out and named.
    const { data, error } = await supabase.rpc('request_inventory_adjustments', {
      p_location_type: locType, p_location_id: locId, p_lines: c.value.p_lines,
      p_reason: c.value.p_reason, p_reference: c.value.p_reference, p_request_id: formId,
    });
    setSaving(false);
    if (error) {
      setLocked(mayHaveSaved(error));
      // "This form was already sent, and has been changed since" says itself
      // what was kept.
      setErr(/already sent/i.test(error.message ?? '') ? error.message
        : saveFailure(error, 'The form is locked as it was sent: press Submit Request again to finish, and nothing will be sent twice.'));
      load();
      return;
    }
    const res = (data ?? {}) as { requests?: unknown[]; unchanged?: { product_id: string; current_qty: number }[] };
    setFlash(adjustmentSentMessage(res.requests?.length ?? 0, res.unchanged ?? [], id => pName(id)));
    setOpen(false); setLocId('');
    setAdjLines([emptyLine()]);
    setReason(''); setReference('');
    load();
  };

  const statusBadge = (s: AdjustmentRequest['status']) => {
    const cls = s === 'approved' ? 'badge-success' : s === 'rejected' ? 'badge-danger' : s === 'pending' ? 'badge-accent' : 'badge-muted';
    return <span className={`badge ${cls}`}>{APPROVAL_STATUS_LABELS[s]}</span>;
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Inventory Adjustments</h2><p>Request a stock correction. Owner or Manager approval applies the change.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={filtered} filename="adjustments" sheetName="Adjustments"
            dateOf={(r: AdjustmentRequest) => r.created_at} dateLabel="Requested"
            columns={[
              { header: 'Date', value: (r: AdjustmentRequest) => new Date(r.created_at).toLocaleDateString('en-GB') },
              { header: 'Location', value: (r: AdjustmentRequest) => place(r.payload) },
              { header: 'Product', value: (r: AdjustmentRequest) => r.payload?.product_id ? pName(r.payload.product_id) : '' },
              { header: 'SKU', value: (r: AdjustmentRequest) => pSku(r.payload?.product_id) },
              { header: 'Current', value: (r: AdjustmentRequest) => r.payload?.current_qty ?? '' },
              { header: 'New total', value: (r: AdjustmentRequest) => r.payload?.new_qty ?? '' },
              { header: 'Change', value: (r: AdjustmentRequest) => Number(r.payload?.difference ?? 0) },
              { header: 'Reason', value: (r: AdjustmentRequest) => r.reason ?? '' },
              { header: 'Reference', value: (r: AdjustmentRequest) => r.payload?.reference ?? '' },
              { header: 'Status', value: (r: AdjustmentRequest) => APPROVAL_STATUS_LABELS[r.status] ?? r.status },
              { header: 'Approver\'s note', value: (r: AdjustmentRequest) => r.response_note ?? '' },
              { header: 'Requested by', value: (r: AdjustmentRequest) => uName(r.requested_by) },
              { header: 'Resolved by', value: (r: AdjustmentRequest) => r.approved_by ? uName(r.approved_by) : '' },
              { header: 'Resolved at', value: (r: AdjustmentRequest) => r.approved_at ? new Date(r.approved_at).toLocaleString('en-GB') : '' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openForm}><Plus size={16} /> New Adjustment</button>
        </div>
      </div>

      {flash && <div className="alert alert-info" role="status"><span>✓</span><div>{flash}</div></div>}

      <div style={{ marginBottom: 12, maxWidth: 460 }}>
        <input value={search} onChange={e => setSearch(e.target.value)}
          placeholder="Search product, SKU, warehouse, store, person or reason…" />
        {search && (
          <div style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 6 }}>
            {filtered.length} match{filtered.length === 1 ? '' : 'es'} of {requests.length}
            <button className="btn btn-secondary btn-sm" style={{ marginLeft: 8 }}
              onClick={() => setSearch('')}>Clear</button>
          </div>
        )}
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : loadErr ? <div className="alert alert-danger" role="alert">{loadErr}</div>
          : filtered.length === 0 ? <div className="empty-state"><SlidersHorizontal size={32} style={{ opacity: 0.3 }} />
              <p style={{ fontWeight: 600, marginTop: 8 }}>
                {search ? 'Nothing matches that search' : 'No adjustment requests yet'}
              </p>
              {search && <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }}
                onClick={() => setSearch('')}>Clear search</button>}
            </div>
          : (
            <table>
              <thead><tr><th>Date</th><th>Location</th><th>Product</th><th>Change</th><th>Reason</th><th>Status</th><th>By</th></tr></thead>
              <tbody>
                {filtered.map(req => {
                  const p = req.payload;
                  return (
                    <tr key={req.id}>
                      <td style={{ fontSize: 12.5, whiteSpace: 'nowrap' }}>{new Date(req.created_at).toLocaleDateString()}</td>
                      <td style={{ fontSize: 12.5 }}>{locName(p)}</td>
                      <td><strong>{pName(p?.product_id)}</strong></td>
                      <td style={{ fontSize: 13 }}>{p?.current_qty} → <strong>{p?.new_qty}</strong> <span style={{ color: (p?.difference ?? 0) >= 0 ? 'var(--success)' : 'var(--danger)' }}>({(p?.difference ?? 0) >= 0 ? '+' : ''}{p?.difference})</span></td>
                      <td style={{ fontSize: 12.5, color: 'var(--text-secondary)', maxWidth: 180 }}>{req.reason || '—'}</td>
                      <td>
                        {statusBadge(req.status)}
                        {/* The approver's reason: every rejection has one (the Owner, 9 Oct 2026). */}
                        {req.response_note && (
                          <div style={{ fontSize: 11.5, color: 'var(--text-secondary)', marginTop: 3, maxWidth: 200 }}>
                            {req.status === 'rejected' ? 'Reason' : 'Note'}: {req.response_note}
                          </div>)}
                      </td>
                      <td style={{ fontSize: 12.5 }}>{uName(req.requested_by)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {open && (
        <Modal title="New Inventory Adjustment" maxWidth={480} confirmClose onClose={() => setOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={submit} disabled={saving}>{saving ? 'Submitting…' : locked ? 'Submit Request again' : 'Submit Request'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group">
                <label>Location Type</label>
                <select value={locType} disabled={locked} onChange={e => { setLocType(e.target.value as LocationType); setLocId(''); }}>
                  <option value="store">Store</option>
                  {canWarehouse && <option value="warehouse">Warehouse</option>}
                </select>
              </div>
              <div className="form-group">
                <label>{locType === 'store' ? 'Store' : 'Warehouse'}</label>
                <select value={locId} disabled={locked} onChange={e => setLocId(e.target.value)}>
                  <option value="">— Select —</option>
                  {locOptions.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
                </select>
              </div>
            </div>
            <div className="form-group">
              <label>Products</label>
              {adjLines.map((l, i) => (
                <div key={i} style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 6 }}>
                  <div style={{ flex: 1 }}>
                    <SearchSelect
                      options={liveProducts.map(p => ({ value: p.id, label: `${p.name} (${p.sku})`, search: `${p.name} ${p.sku}` }))}
                      value={l.product_id} disabled={locked}
                      exclude={adjLines.filter((_, j) => j !== i).map(x => x.product_id).filter(Boolean)}
                      onChange={v => setAdjLines(ls => ls.map((x, j) => j === i ? { ...x, product_id: v } : x))}
                      placeholder="Search product name or SKU…" />
                    {live && l.product_id && (
                      <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>
                        System now: {live[l.product_id] ?? 0}
                      </div>
                    )}
                  </div>
                  <input type="text" inputMode="numeric" value={l.new_qty} placeholder="New total" style={{ width: 110 }}
                    aria-label="Counted total" disabled={locked}
                    onChange={e => setAdjLines(ls => ls.map((x, j) => j === i ? { ...x, new_qty: e.target.value } : x))} />
                  <button className="btn btn-secondary btn-sm btn-icon" disabled={locked || adjLines.length === 1}
                    onClick={() => setAdjLines(ls => ls.filter((_, j) => j !== i))} title="Remove">×</button>
                </div>
              ))}
              <button className="btn btn-secondary btn-sm" style={{ marginTop: 2 }} disabled={locked}
                onClick={() => setAdjLines(ls => [...ls, emptyLine()])}>+ Add another product</button>
            </div>
            <div className="form-group"><label>Reference</label><input value={reference} disabled={locked} onChange={e => setReference(e.target.value)} placeholder="Optional" /></div>
            <div className="form-group"><label>Reason *</label><textarea rows={2} value={reason} disabled={locked} onChange={e => setReason(e.target.value)} placeholder="e.g. Stock count correction after audit" /></div>
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>
              Enter the <strong>counted total</strong> for each product, as a whole number, not the difference.
              Each product becomes its own approval request. A product whose count matches the system is left out.
              If a sale or delivery changes the stock before approval, the approver will ask for a new count.
            </div></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default AdjustmentsPage;
