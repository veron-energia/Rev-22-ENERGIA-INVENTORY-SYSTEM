import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Product, Store, Warehouse, LocationType, AdjustmentRequest, Profile,
  APPROVAL_STATUS_LABELS, canManageWarehouseStock,
} from '../types';
import { Modal } from '../components/ui';
import { Plus, RefreshCw, SlidersHorizontal, X } from 'lucide-react';

const AdjustmentsPage: React.FC = () => {
  const { profile } = useAuth();
  const canWarehouse = canManageWarehouseStock(profile?.role);

  const [requests, setRequests] = useState<AdjustmentRequest[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);

  const [open, setOpen] = useState(false);
  const [locType, setLocType] = useState<LocationType>('store');
  const [locId, setLocId] = useState('');
  const [productId, setProductId] = useState('');
  const [newQty, setNewQty] = useState(0);
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
  const locName = (p: AdjustmentRequest['payload']) => {
    if (!p) return '—';
    if (p.location_type === 'store') return `🏪 ${stores.find(s => s.id === p.location_id)?.name ?? '—'}`;
    return `🏭 ${warehouses.find(w => w.id === p.location_id)?.name ?? '—'}`;
  };

  const locOptions = locType === 'store' ? stores : warehouses;

  const submit = async () => {
    if (!locId) { setErr('Select a location.'); return; }
    if (!productId) { setErr('Select a product.'); return; }
    if (!reason.trim()) { setErr('A reason is required.'); return; }
    setSaving(true); setErr(null);
    const { error } = await supabase.rpc('request_inventory_adjustment', {
      p_location_type: locType, p_location_id: locId, p_product_id: productId,
      p_new_qty: newQty, p_reason: reason.trim(), p_reference: reference.trim() || null,
    });
    setSaving(false);
    if (error) { setErr(error.message); return; }
    setOpen(false); setLocId(''); setProductId(''); setNewQty(0); setReason(''); setReference('');
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
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={() => { setErr(null); setOpen(true); }}><Plus size={16} /> New Adjustment</button>
        </div>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : requests.length === 0 ? <div className="empty-state"><SlidersHorizontal size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No adjustment requests yet</p></div>
          : (
            <table>
              <thead><tr><th>Date</th><th>Location</th><th>Product</th><th>Change</th><th>Reason</th><th>Status</th><th>By</th></tr></thead>
              <tbody>
                {requests.map(req => {
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
              <label>Product</label>
              <select value={productId} onChange={e => setProductId(e.target.value)}>
                <option value="">— Select product —</option>
                {products.map(p => <option key={p.id} value={p.id}>{p.name} ({p.sku})</option>)}
              </select>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>New Quantity (corrected total)</label><input type="number" min={0} value={newQty || ''} onChange={e => setNewQty(+e.target.value)} placeholder="0" /></div>
              <div className="form-group"><label>Reference</label><input value={reference} onChange={e => setReference(e.target.value)} placeholder="Optional" /></div>
            </div>
            <div className="form-group"><label>Reason *</label><textarea rows={2} value={reason} onChange={e => setReason(e.target.value)} placeholder="e.g. Stock count correction after audit" /></div>
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Enter the <strong>corrected total</strong>, not the difference. The system calculates the change and applies it after approval.</div></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default AdjustmentsPage;
