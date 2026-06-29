import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  AdjustmentRequest, Product, Store, Warehouse, Profile, isOwnerOrManager,
} from '../types';
import { Modal, NoAccess } from '../components/ui';
import { RefreshCw, Check, X, ClipboardCheck, RotateCcw, XCircle, SlidersHorizontal } from 'lucide-react';

const TYPE_META: Record<string, { label: string; icon: React.ReactNode; cls: string }> = {
  invoice_refund: { label: 'Refund', icon: <RotateCcw size={13} />, cls: 'badge-danger' },
  invoice_cancel: { label: 'Cancellation', icon: <XCircle size={13} />, cls: 'badge-accent' },
  adjustment: { label: 'Adjustment', icon: <SlidersHorizontal size={13} />, cls: 'badge-primary' },
};

const ApprovalsPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isOwnerOrManager(profile?.role)) return <NoAccess message="Only Owners and Managers can review approvals." />;

  const [requests, setRequests] = useState<AdjustmentRequest[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [rejectFor, setRejectFor] = useState<AdjustmentRequest | null>(null);
  const [rejectNote, setRejectNote] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    const [req, prod, st, wh, prof] = await Promise.all([
      supabase.from('approval_requests').select('*')
        .in('request_type', ['invoice_refund', 'invoice_cancel', 'adjustment'])
        .eq('status', 'pending').order('created_at', { ascending: false }),
      supabase.from('products').select('id,name,sku'),
      supabase.from('stores').select('id,name'),
      supabase.from('warehouses').select('id,name'),
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
    if (p.location_type === 'warehouse') return `🏭 ${warehouses.find(w => w.id === p.location_id)?.name ?? '—'}`;
    return p.invoice_no ?? '—';
  };

  const approve = async (req: AdjustmentRequest) => {
    setBusy(req.id);
    const fn = req.request_type === 'adjustment' ? 'resolve_inventory_adjustment' : 'resolve_invoice_action';
    const { error } = await supabase.rpc(fn, { p_request_id: req.id, p_approve: true, p_note: null });
    setBusy(null);
    if (error) { alert(error.message); return; }
    load();
  };

  const doReject = async () => {
    if (!rejectFor) return;
    setBusy(rejectFor.id);
    const fn = rejectFor.request_type === 'adjustment' ? 'resolve_inventory_adjustment' : 'resolve_invoice_action';
    const { error } = await supabase.rpc(fn, { p_request_id: rejectFor.id, p_approve: false, p_note: rejectNote.trim() || null });
    setBusy(null);
    if (error) { alert(error.message); return; }
    setRejectFor(null); setRejectNote(''); load();
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Approvals</h2><p>Pending refund, cancellation, and inventory-adjustment requests awaiting your decision.</p></div>
        <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : requests.length === 0 ? <div className="empty-state"><ClipboardCheck size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>Nothing pending</p><p style={{ fontSize: 13 }}>Transfer approvals live on the Transfers page.</p></div>
          : (
            <table>
              <thead><tr><th>Type</th><th>Detail</th><th>Location / Invoice</th><th>Reason</th><th>Requested by</th><th></th></tr></thead>
              <tbody>
                {requests.map(req => {
                  const meta = TYPE_META[req.request_type];
                  const p = req.payload;
                  return (
                    <tr key={req.id}>
                      <td><span className={`badge ${meta.cls}`}>{meta.icon} {meta.label}</span></td>
                      <td style={{ fontSize: 13 }}>
                        {req.request_type === 'adjustment'
                          ? <><strong>{pName(p?.product_id)}</strong><div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{p?.current_qty} → {p?.new_qty} ({(p?.difference ?? 0) >= 0 ? '+' : ''}{p?.difference})</div></>
                          : <>Invoice {p?.invoice_no}<div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{p?.return_stock ? 'Return stock' : 'No stock return'}</div></>}
                      </td>
                      <td style={{ fontSize: 12.5 }}>{locName(p)}</td>
                      <td style={{ fontSize: 12.5, color: 'var(--text-secondary)', maxWidth: 200 }}>{req.reason || '—'}</td>
                      <td style={{ fontSize: 12.5 }}>{uName(req.requested_by)}</td>
                      <td>
                        <div style={{ display: 'flex', gap: 4 }}>
                          <button className="btn btn-primary btn-sm" onClick={() => approve(req)} disabled={busy === req.id}><Check size={13} /> Approve</button>
                          <button className="btn btn-danger btn-sm" onClick={() => { setRejectFor(req); setRejectNote(''); }} disabled={busy === req.id}><X size={13} /> Reject</button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {rejectFor && (
        <Modal title="Reject Request" maxWidth={400} onClose={() => setRejectFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setRejectFor(null)}>Back</button><button className="btn btn-danger" onClick={doReject} disabled={busy === rejectFor.id}>Reject</button></>}>
          <div className="form-group">
            <label>Reason / note (optional)</label>
            <textarea rows={2} value={rejectNote} onChange={e => setRejectNote(e.target.value)} placeholder="Why is this being rejected?" autoFocus />
          </div>
        </Modal>
      )}
    </div>
  );
};

export default ApprovalsPage;
