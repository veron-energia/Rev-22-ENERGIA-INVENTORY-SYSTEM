import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Product, Store, Warehouse, LocationType, AdjustmentRequest, Profile,
  APPROVAL_STATUS_LABELS, canManageWarehouseStock,
} from '../types';
import { SearchSelect } from '../components/SearchSelect';
import { Modal } from '../components/ui';
import { Plus, RefreshCw, SlidersHorizontal, X } from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';

const AdjustmentsPage: React.FC = () => {
  const { profile } = useAuth();
  const canWarehouse = canManageWarehouseStock(profile?.role);

  const [requests, setRequests] = useState<AdjustmentRequest[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

  const [open, setOpen] = useState(false);
  const [locType, setLocType] = useState<LocationType>('store');
  const [locId, setLocId] = useState('');
  const [reason, setReason] = useState('');
  const [reference, setReference] = useState('');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [req, prod, st, wh, prof] = await Promise.all([
      supabase.from('approval_requests').select('*').eq('request_type', 'adjustment').order('created_at', { ascending: false }),
      supabase.from('products').select('id,name,sku').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('id,name').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('warehouses').select('id,name').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('profiles').select('id,full_name'),
    ]);
    setRequests((req.data as AdjustmentRequest[]) ?? []);
    setProducts((prod.data as Product[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    setProfiles((prof.data as Profile[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const pName = (id?: string) => products.find(p => p.id === id)?.name ?? '—';
  const uName = (id: string | null) => id ? (profiles.find(p => p.id === id)?.full_name ?? '—') : '—';
  const pSku = (id?: string) => products.find(p => p.id === id)?.sku ?? '';
  const locName = (p: AdjustmentRequest['payload']) => {
    if (!p) return '—';
    if (p.location_type === 'store') return `🏪 ${stores.find(s => s.id === p.location_id)?.name ?? '—'}`;
    return `🏭 ${warehouses.find(w => w.id === p.location_id)?.name ?? '—'}`;
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
        locName(p), uName(req.requested_by), uName((req as any).approved_by),
        req.reason, req.status, (req as any).reference,
        String(p?.current_qty ?? ''), String(p?.new_qty ?? ''), String(p?.difference ?? ''),
        when?.toLocaleDateString('en-GB'), when?.toLocaleDateString('en-CA'),
      ].filter(Boolean).join(' ').toLowerCase().includes(q);
    });
  }, [requests, search, products, stores, warehouses, profiles]);

  // Several products can be corrected in one go; each line carries its own
  // corrected total.
  const [adjLines, setAdjLines] = useState<{ product_id: string; new_qty: number }[]>([{ product_id: '', new_qty: 0 }]);

  const locOptions = locType === 'store' ? stores : warehouses;

  const submit = async () => {
    if (!locId) { setErr('Select a location.'); return; }
    const valid = adjLines.filter(l => l.product_id);
    if (valid.length === 0) { setErr('Select at least one product.'); return; }
    const ids = valid.map(l => l.product_id);
    if (new Set(ids).size !== ids.length) { setErr('The same product is listed more than once.'); return; }
    if (valid.some(l => l.new_qty < 0)) { setErr('A corrected total cannot be negative.'); return; }
    if (!reason.trim()) { setErr('A reason is required.'); return; }

    setSaving(true); setErr(null);
    const done: string[] = [];
    for (const line of valid) {
      const { error } = await supabase.rpc('request_inventory_adjustment', {
        p_location_type: locType, p_location_id: locId, p_product_id: line.product_id,
        p_new_qty: line.new_qty, p_reason: reason.trim(), p_reference: reference.trim() || null,
      });
      if (error) {
        setSaving(false);
        const name = products.find(p => p.id === line.product_id)?.name ?? 'A product';
        setErr(done.length > 0
          ? `${name}: ${error.message} — ${done.length} request(s) were already submitted.`
          : `${name}: ${error.message}`);
        load();
        return;
      }
      done.push(line.product_id);
    }
    setSaving(false);
    setOpen(false); setLocId('');
    setAdjLines([{ product_id: '', new_qty: 0 }]);
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
            dateOf={(r: any) => r.created_at} dateLabel="Requested"
            columns={[
              { header: 'Date', value: (r: any) => new Date(r.created_at).toLocaleDateString('en-GB') },
              { header: 'Location', value: (r: any) => r.location_name ?? '' },
              { header: 'Product', value: (r: any) => r.product_name ?? '' },
              { header: 'Change', value: (r: any) => Number(r.delta ?? 0) },
              { header: 'Reason', value: (r: any) => r.reason ?? '' },
              { header: 'Status', value: (r: any) => r.status ?? '' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={() => { setErr(null); (() => { setErr(null); setAdjLines([{ product_id: '', new_qty: 0 }]); setOpen(true); })(); }}><Plus size={16} /> New Adjustment</button>
        </div>
      </div>

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
                      <td>{statusBadge(req.status)}</td>
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
        <Modal title="New Inventory Adjustment" maxWidth={460} onClose={() => setOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={submit} disabled={saving}>{saving ? 'Submitting…' : 'Submit Request'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group">
                <label>Location Type</label>
                <select value={locType} onChange={e => { setLocType(e.target.value as LocationType); setLocId(''); }}>
                  <option value="store">Store</option>
                  {canWarehouse && <option value="warehouse">Warehouse</option>}
                </select>
              </div>
              <div className="form-group">
                <label>{locType === 'store' ? 'Store' : 'Warehouse'}</label>
                <select value={locId} onChange={e => setLocId(e.target.value)}>
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
                      options={products.map(p => ({ value: p.id, label: `${p.name} (${p.sku})`, search: `${p.name} ${p.sku}` }))}
                      value={l.product_id}
                      exclude={adjLines.filter((_, j) => j !== i).map(x => x.product_id).filter(Boolean)}
                      onChange={v => setAdjLines(ls => ls.map((x, j) => j === i ? { ...x, product_id: v } : x))}
                      placeholder="Search product name or SKU…" />
                  </div>
                  <input type="number" min={0} value={l.new_qty || ''} placeholder="New total" style={{ width: 110 }}
                    onChange={e => setAdjLines(ls => ls.map((x, j) => j === i ? { ...x, new_qty: +e.target.value } : x))} />
                  <button className="btn btn-secondary btn-sm btn-icon" disabled={adjLines.length === 1}
                    onClick={() => setAdjLines(ls => ls.filter((_, j) => j !== i))} title="Remove">×</button>
                </div>
              ))}
              <button className="btn btn-secondary btn-sm" style={{ marginTop: 2 }}
                onClick={() => setAdjLines(ls => [...ls, { product_id: '', new_qty: 0 }])}>+ Add another product</button>
            </div>
            <div className="form-group"><label>Reference</label><input value={reference} onChange={e => setReference(e.target.value)} placeholder="Optional" /></div>
            <div className="form-group"><label>Reason *</label><textarea rows={2} value={reason} onChange={e => setReason(e.target.value)} placeholder="e.g. Stock count correction after audit" /></div>
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Enter the <strong>corrected total</strong> for each product, not the difference. The system works out the change and applies it after approval. The reason and reference apply to every line, and each product becomes its own approval request.</div></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default AdjustmentsPage;
