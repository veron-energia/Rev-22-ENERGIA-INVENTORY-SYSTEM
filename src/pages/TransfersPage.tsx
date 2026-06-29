import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Warehouse, Store, Product, TransferType, TransferLine, LocationType,
  TransferRequest, TransferRequestLine, ApprovalStatus, APPROVAL_STATUS_LABELS,
  isOwnerOrManager, Profile,
} from '../types';
import { Modal } from '../components/ui';
import { Plus, RefreshCw, ArrowLeftRight, Check, X, Trash2, ChevronDown, ChevronUp } from 'lucide-react';

const TRANSFER_TYPES: { value: TransferType; label: string; src: LocationType; dest: LocationType }[] = [
  { value: 'warehouse_to_store', label: 'Warehouse → Store', src: 'warehouse', dest: 'store' },
  { value: 'warehouse_to_warehouse', label: 'Warehouse → Warehouse', src: 'warehouse', dest: 'warehouse' },
  { value: 'store_to_store', label: 'Store → Store', src: 'store', dest: 'store' },
];

const StatusBadge: React.FC<{ s: ApprovalStatus }> = ({ s }) => {
  const cls = s === 'approved' ? 'badge-success' : s === 'partially_approved' ? 'badge-primary'
    : s === 'rejected' ? 'badge-danger' : s === 'cancelled' ? 'badge-muted' : 'badge-accent';
  return <span className={`badge ${cls}`}>{APPROVAL_STATUS_LABELS[s]}</span>;
};

const TransfersPage: React.FC = () => {
  const { profile } = useAuth();
  const canApprove = isOwnerOrManager(profile?.role);

  const [requests, setRequests] = useState<TransferRequest[]>([]);
  const [linesByReq, setLinesByReq] = useState<Record<string, TransferRequestLine[]>>({});
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState<string | null>(null);

  const [createOpen, setCreateOpen] = useState(false);
  const [tType, setTType] = useState<TransferType>('warehouse_to_store');
  const [sourceId, setSourceId] = useState('');
  const [destId, setDestId] = useState('');
  const [lines, setLines] = useState<TransferLine[]>([{ product_id: '', quantity: 0 }]);
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [createErr, setCreateErr] = useState<string | null>(null);

  const [approveReq, setApproveReq] = useState<TransferRequest | null>(null);
  const [approveLines, setApproveLines] = useState<TransferLine[]>([]);
  const [approveNote, setApproveNote] = useState('');
  const [rejectReason, setRejectReason] = useState('');
  const [approveErr, setApproveErr] = useState<string | null>(null);
  const [approveBusy, setApproveBusy] = useState(false);

  const loadAll = useCallback(async () => {
    setLoading(true);
    const [req, lns, wh, st, prod, prof] = await Promise.all([
      supabase.from('transfer_requests').select('*').order('created_at', { ascending: false }),
      supabase.from('transfer_request_lines').select('*'),
      supabase.from('warehouses').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('profiles').select('*'),
    ]);
    setRequests((req.data as TransferRequest[]) ?? []);
    const grouped: Record<string, TransferRequestLine[]> = {};
    ((lns.data as TransferRequestLine[]) ?? []).forEach(l => { (grouped[l.transfer_request_id] ??= []).push(l); });
    setLinesByReq(grouped);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setProducts((prod.data as Product[]) ?? []);
    setProfiles((prof.data as Profile[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { loadAll(); }, [loadAll]);

  const cfg = TRANSFER_TYPES.find(t => t.value === tType)!;
  const sourceOptions = cfg.src === 'warehouse' ? warehouses : stores;
  const destOptions = (cfg.dest === 'warehouse' ? warehouses : stores).filter(o => o.id !== sourceId);

  const productName = (id: string) => products.find(p => p.id === id)?.name ?? 'Unknown';
  const productSku = (id: string) => products.find(p => p.id === id)?.sku ?? '';
  const userName = (id: string | null) => id ? (profiles.find(p => p.id === id)?.full_name ?? '—') : '—';
  const locName = (type: LocationType | undefined, id: string | undefined) => {
    if (!id) return '—';
    const list = type === 'warehouse' ? warehouses : stores;
    return list.find(l => l.id === id)?.name ?? '—';
  };

  const resetCreate = () => {
    setTType('warehouse_to_store'); setSourceId(''); setDestId('');
    setLines([{ product_id: '', quantity: 0 }]); setNote(''); setCreateErr(null);
  };

  const handleCreate = async () => {
    if (!sourceId || !destId) { setCreateErr('Select source and destination.'); return; }
    const validLines = lines.filter(l => l.product_id && l.quantity > 0);
    if (validLines.length === 0) { setCreateErr('Add at least one product with quantity.'); return; }
    setSaving(true); setCreateErr(null);
    const { error } = await supabase.rpc('create_transfer_request', {
      p_transfer_type: tType, p_source_type: cfg.src, p_source_id: sourceId,
      p_dest_type: cfg.dest, p_dest_id: destId, p_lines: validLines, p_note: note.trim() || null,
    });
    setSaving(false);
    if (error) { setCreateErr(error.message); return; }
    setCreateOpen(false); resetCreate(); loadAll();
  };

  const openApprove = (req: TransferRequest) => {
    setApproveReq(req);
    const reqLines = linesByReq[req.id] ?? [];
    setApproveLines(reqLines.map(l => ({ product_id: l.product_id, quantity: l.quantity })));
    setApproveNote(''); setRejectReason(''); setApproveErr(null);
  };

  const handleApprove = async () => {
    if (!approveReq) return;
    setApproveBusy(true); setApproveErr(null);
    const { error } = await supabase.rpc('approve_transfer', {
      p_request_id: approveReq.id, p_approved_lines: approveLines, p_note: approveNote.trim() || null,
    });
    setApproveBusy(false);
    if (error) { setApproveErr(error.message); return; }
    setApproveReq(null); loadAll();
  };

  const handleReject = async () => {
    if (!approveReq) return;
    if (!rejectReason.trim()) { setApproveErr('A rejection reason is required.'); return; }
    setApproveBusy(true); setApproveErr(null);
    const { error } = await supabase.rpc('reject_transfer', {
      p_request_id: approveReq.id, p_rejection_reason: rejectReason.trim(),
    });
    setApproveBusy(false);
    if (error) { setApproveErr(error.message); return; }
    setApproveReq(null); loadAll();
  };

  const handleCancel = async (req: TransferRequest) => {
    if (!confirm('Cancel this pending transfer request?')) return;
    const { error } = await supabase.rpc('cancel_transfer_request', { p_request_id: req.id });
    if (error) { alert(error.message); return; }
    loadAll();
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Stock Transfers</h2><p>Request transfers between warehouses and stores. Owner or Manager approval moves the stock.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={loadAll}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={() => { resetCreate(); setCreateOpen(true); }}><Plus size={16} /> New Transfer</button>
        </div>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : requests.length === 0 ? <div className="empty-state"><ArrowLeftRight size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No transfer requests yet</p></div>
          : (
            <table>
              <thead><tr><th></th><th>Date</th><th>Type</th><th>From → To</th><th>Items</th><th>Status</th><th>Requested by</th><th></th></tr></thead>
              <tbody>
                {requests.map(req => {
                  const reqLines = linesByReq[req.id] ?? [];
                  const isOpen = expanded === req.id;
                  return (
                    <React.Fragment key={req.id}>
                      <tr>
                        <td><button className="btn btn-secondary btn-sm btn-icon" onClick={() => setExpanded(isOpen ? null : req.id)}>{isOpen ? <ChevronUp size={13} /> : <ChevronDown size={13} />}</button></td>
                        <td style={{ whiteSpace: 'nowrap', fontSize: 12.5 }}>{new Date(req.created_at).toLocaleDateString()}</td>
                        <td style={{ fontSize: 12.5 }}>{TRANSFER_TYPES.find(t => t.value === req.transfer_type)?.label ?? req.transfer_type}</td>
                        <td style={{ fontSize: 12.5 }}>{locName(req.source_type, req.source_id)} → {locName(req.dest_type, req.dest_id)}</td>
                        <td>{reqLines.length} item{reqLines.length !== 1 ? 's' : ''}</td>
                        <td><StatusBadge s={req.status} /></td>
                        <td style={{ fontSize: 12.5 }}>{userName(req.requested_by)}</td>
                        <td>
                          <div style={{ display: 'flex', gap: 4 }}>
                            {req.status === 'pending' && canApprove && <button className="btn btn-primary btn-sm" onClick={() => openApprove(req)}><Check size={13} /> Review</button>}
                            {req.status === 'pending' && req.requested_by === profile?.id && <button className="btn btn-secondary btn-sm btn-icon" onClick={() => handleCancel(req)}><Trash2 size={13} /></button>}
                          </div>
                        </td>
                      </tr>
                      {isOpen && (
                        <tr>
                          <td></td>
                          <td colSpan={7} style={{ background: 'var(--surface-2)' }}>
                            <div style={{ padding: '4px 0' }}>
                              <table style={{ width: 'auto', minWidth: 380 }}>
                                <thead><tr><th>Product</th><th style={{ textAlign: 'right' }}>Requested</th>{(req.status === 'approved' || req.status === 'partially_approved') && <th style={{ textAlign: 'right' }}>Approved</th>}</tr></thead>
                                <tbody>
                                  {reqLines.map(l => (
                                    <tr key={l.id}>
                                      <td><strong>{productName(l.product_id)}</strong> <span style={{ color: 'var(--text-muted)', fontSize: 11.5 }}>{productSku(l.product_id)}</span></td>
                                      <td style={{ textAlign: 'right' }}>{l.quantity}</td>
                                      {(req.status === 'approved' || req.status === 'partially_approved') && <td style={{ textAlign: 'right', fontWeight: 700, color: (l.approved_quantity ?? 0) < l.quantity ? 'var(--accent)' : 'var(--success)' }}>{l.approved_quantity ?? 0}</td>}
                                    </tr>
                                  ))}
                                </tbody>
                              </table>
                              {req.note && <p style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 8 }}><strong>Note:</strong> {req.note}</p>}
                              {req.rejection_reason && <p style={{ fontSize: 12, color: 'var(--danger)', marginTop: 8 }}><strong>Rejected:</strong> {req.rejection_reason}</p>}
                              {req.approved_at && <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6 }}>{req.status === 'rejected' ? 'Rejected' : 'Approved'} by {userName(req.approved_by)} on {new Date(req.approved_at).toLocaleString()}</p>}
                            </div>
                          </td>
                        </tr>
                      )}
                    </React.Fragment>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {createOpen && (
        <Modal title="New Stock Transfer" maxWidth={580} onClose={() => setCreateOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setCreateOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleCreate} disabled={saving}>{saving ? 'Submitting…' : 'Submit Request'}</button></>}>
          <div className="form-grid">
            {createErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{createErr}</div></div>}
            <div className="form-group">
              <label>Transfer Type</label>
              <select value={tType} onChange={e => { setTType(e.target.value as TransferType); setSourceId(''); setDestId(''); }}>
                {TRANSFER_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
              </select>
            </div>
            <div className="form-grid-2">
              <div className="form-group">
                <label>From ({cfg.src})</label>
                <select value={sourceId} onChange={e => { setSourceId(e.target.value); if (e.target.value === destId) setDestId(''); }}>
                  <option value="">— Select —</option>
                  {sourceOptions.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label>To ({cfg.dest})</label>
                <select value={destId} onChange={e => setDestId(e.target.value)}>
                  <option value="">— Select —</option>
                  {destOptions.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
                </select>
              </div>
            </div>
            <div>
              <label>Products</label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {lines.map((line, i) => (
                  <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                    <select value={line.product_id} onChange={e => setLines(ls => ls.map((l, j) => j === i ? { ...l, product_id: e.target.value } : l))} style={{ flex: 1 }}>
                      <option value="">— Product —</option>
                      {products.map(p => <option key={p.id} value={p.id}>{p.name} ({p.sku})</option>)}
                    </select>
                    <input type="number" min={1} value={line.quantity || ''} placeholder="Qty" style={{ width: 90 }}
                      onChange={e => setLines(ls => ls.map((l, j) => j === i ? { ...l, quantity: +e.target.value } : l))} />
                    <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setLines(ls => ls.filter((_, j) => j !== i))} disabled={lines.length === 1}><X size={13} /></button>
                  </div>
                ))}
              </div>
              <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => setLines(ls => [...ls, { product_id: '', quantity: 0 }])}><Plus size={13} /> Add Product</button>
            </div>
            <div className="form-group"><label>Note (optional)</label><input value={note} onChange={e => setNote(e.target.value)} placeholder="Reason for transfer" /></div>
            {cfg.dest === 'store' && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>The destination store must have a price set for every product, or the request will be blocked.</div></div>}
          </div>
        </Modal>
      )}

      {approveReq && (
        <Modal title="Review Transfer Request" maxWidth={520} onClose={() => setApproveReq(null)}
          footer={<>
            <button className="btn btn-danger" onClick={handleReject} disabled={approveBusy}><X size={15} /> Reject</button>
            <button className="btn btn-primary" onClick={handleApprove} disabled={approveBusy}><Check size={15} /> Approve</button>
          </>}>
          <div className="form-grid">
            {approveErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{approveErr}</div></div>}
            <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
              {locName(approveReq.source_type, approveReq.source_id)} → {locName(approveReq.dest_type, approveReq.dest_id)}
            </p>
            <div>
              <label>Approved Quantities <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— lower a quantity for partial approval, set 0 to exclude</span></label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 6 }}>
                {(linesByReq[approveReq.id] ?? []).map((l, i) => (
                  <div key={l.id} style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                    <div style={{ flex: 1 }}><strong>{productName(l.product_id)}</strong> <span style={{ color: 'var(--text-muted)', fontSize: 12 }}>requested {l.quantity}</span></div>
                    <input type="number" min={0} max={l.quantity} value={approveLines[i]?.quantity ?? 0} style={{ width: 90 }}
                      onChange={e => setApproveLines(al => al.map((a, j) => j === i ? { ...a, quantity: Math.min(+e.target.value, l.quantity) } : a))} />
                  </div>
                ))}
              </div>
            </div>
            <div className="form-group"><label>Note (optional)</label><input value={approveNote} onChange={e => setApproveNote(e.target.value)} /></div>
            <div className="form-group"><label>Rejection reason (required only if rejecting)</label><input value={rejectReason} onChange={e => setRejectReason(e.target.value)} placeholder="Why is this being rejected?" /></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default TransfersPage;
