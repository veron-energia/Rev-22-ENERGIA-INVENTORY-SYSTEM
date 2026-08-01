import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Warehouse, Store, Product, TransferType, TransferLine, LocationType,
  TransferRequest, TransferRequestLine, ApprovalStatus, APPROVAL_STATUS_LABELS,
  isOwnerOrManager, Profile,
} from '../types';
import { SearchSelect } from '../components/SearchSelect';
import { Modal } from '../components/ui';
import { Plus, RefreshCw, ArrowLeftRight, Check, X, Trash2, ChevronDown, ChevronUp, Pencil, History, Truck, PackageCheck, AlertTriangle } from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';

// Phase 11 discrepancy resolution options
const RESOLUTION_OPTIONS: { value: string; label: string }[] = [
  { value: 'accept_loss', label: 'Accept missing as loss' },
  { value: 'accept_surplus', label: 'Accept extra as surplus' },
  { value: 'return_excess', label: 'Return excess to source' },
  { value: 'correct_source', label: 'Correct source stock' },
  { value: 'correct_destination', label: 'Correct destination stock' },
  { value: 'inventory_adjustment', label: 'Create linked inventory adjustment' },
  { value: 'other', label: 'Other (reason required)' },
];

// A transfer dispatched more than 7 calendar days ago and still in transit.
const isOverdue = (r: TransferRequest) =>
  r.status === 'in_transit' && !!r.dispatched_at &&
  (Date.now() - new Date(r.dispatched_at).getTime()) > 7 * 24 * 60 * 60 * 1000;

const TRANSFER_TYPES: { value: TransferType; label: string; src: LocationType; dest: LocationType }[] = [
  { value: 'warehouse_to_store', label: 'Warehouse → Store', src: 'warehouse', dest: 'store' },
  { value: 'warehouse_to_warehouse', label: 'Warehouse → Warehouse', src: 'warehouse', dest: 'warehouse' },
  { value: 'store_to_store', label: 'Store → Store', src: 'store', dest: 'store' },
];

const StatusBadge: React.FC<{ s: ApprovalStatus }> = ({ s }) => {
  const cls =
    s === 'approved' || s === 'received' || s === 'completed' ? 'badge-success'
    : s === 'partially_approved' ? 'badge-primary'
    : s === 'in_transit' ? 'badge-primary'
    : s === 'received_with_discrepancy' ? 'badge-danger'
    : s === 'rejected' ? 'badge-danger'
    : s === 'cancelled' ? 'badge-muted'
    : 'badge-accent';
  return <span className={`badge ${cls}`}>{APPROVAL_STATUS_LABELS[s]}</span>;
};

const TransfersPage: React.FC = () => {
  const { profile } = useAuth();
  const canApprove = isOwnerOrManager(profile?.role);
  const isStaff = profile?.role === 'staff';
  const [assignedStoreId, setAssignedStoreId] = useState<string | null>(null);
  const [approveSourceWh, setApproveSourceWh] = useState('');
  const [storePrices, setStorePrices] = useState<{ store_id: string; product_id: string }[]>([]);

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
  // Phase 10: pending-transfer editing
  const [editReq, setEditReq] = useState<TransferRequest | null>(null);
  const [editLines, setEditLines] = useState<TransferLine[]>([]);
  const [editNote, setEditNote] = useState('');
  const [editReason, setEditReason] = useState('');
  const [editSourceType, setEditSourceType] = useState<'warehouse' | 'store'>('warehouse');
  const [editSourceId, setEditSourceId] = useState('');
  const [editDestType, setEditDestType] = useState<'warehouse' | 'store'>('store');
  const [editDestId, setEditDestId] = useState('');
  const [editBusy, setEditBusy] = useState(false);
  const [editErr, setEditErr] = useState<string | null>(null);
  const [historyReq, setHistoryReq] = useState<TransferRequest | null>(null);
  const [revisions, setRevisions] = useState<any[]>([]);

  // Phase 11: receive (receipt confirmation)
  const [receiveReq, setReceiveReq] = useState<TransferRequest | null>(null);
  const [receiveQty, setReceiveQty] = useState<Record<string, number>>({}); // product_id -> actual
  const [receiveReason, setReceiveReason] = useState<Record<string, string>>({}); // product_id -> per-line reason
  const [receiveNote, setReceiveNote] = useState('');
  const [receiveBusy, setReceiveBusy] = useState(false);
  const [receiveErr, setReceiveErr] = useState<string | null>(null);

  // Phase 11: resolve discrepancy
  const [resolveReq, setResolveReq] = useState<TransferRequest | null>(null);
  const [resolutions, setResolutions] = useState<Record<string, { resolution: string; reason: string }>>({});
  const [resolveNote, setResolveNote] = useState('');
  const [resolveBusy, setResolveBusy] = useState(false);
  const [resolveErr, setResolveErr] = useState<string | null>(null);

  const loadAll = useCallback(async () => {
    setLoading(true);
    const [req, lns, wh, st, prod, prof, myStore, prc] = await Promise.all([
      supabase.from('transfer_requests').select('*').order('created_at', { ascending: false }),
      supabase.from('transfer_request_lines').select('*'),
      supabase.from('warehouses').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('profiles').select('*'),
      supabase.rpc('my_assigned_store_id'),
      supabase.from('store_product_prices').select('store_id,product_id').is('deleted_at', null).eq('is_active', true),
    ]);
    setRequests((req.data as TransferRequest[]) ?? []);
    const grouped: Record<string, TransferRequestLine[]> = {};
    ((lns.data as TransferRequestLine[]) ?? []).forEach(l => { (grouped[l.transfer_request_id] ??= []).push(l); });
    setLinesByReq(grouped);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setProducts((prod.data as Product[]) ?? []);
    setProfiles((prof.data as Profile[]) ?? []);
    setAssignedStoreId((myStore.data as string | null) ?? null);
    setStorePrices((prc.data as { store_id: string; product_id: string }[]) ?? []);
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
    const validLines = lines.filter(l => l.product_id && l.quantity > 0);
    if (validLines.length === 0) { setCreateErr('Add at least one product with quantity.'); return; }

    // Staff: simplified request — product + qty + note only. Destination is
    // their assigned store; source is chosen by Owner/Manager at approval.
    if (isStaff) {
      if (!assignedStoreId) { setCreateErr('You are not assigned to a store, so you cannot request a transfer.'); return; }
      setSaving(true); setCreateErr(null);
      const { error } = await supabase.rpc('create_staff_transfer_request', {
        p_lines: validLines, p_note: note.trim() || null,
      });
      setSaving(false);
      if (error) { setCreateErr(error.message); return; }
      setCreateOpen(false); resetCreate(); loadAll();
      return;
    }

    if (!sourceId || !destId) { setCreateErr('Select source and destination.'); return; }
    setSaving(true); setCreateErr(null);
    const { error } = await supabase.rpc('create_transfer_request', {
      p_transfer_type: tType, p_source_type: cfg.src, p_source_id: sourceId,
      p_dest_type: cfg.dest, p_dest_id: destId, p_lines: validLines, p_note: note.trim() || null,
    });
    setSaving(false);
    if (error) { setCreateErr(error.message); return; }
    setCreateOpen(false); resetCreate(); loadAll();
  };

  const canEditReq = (req: TransferRequest) =>
    req.status === 'pending' && (canApprove || req.requested_by === profile?.id);

  const openEdit = (req: TransferRequest) => {
    setEditReq(req);
    const reqLines = linesByReq[req.id] ?? [];
    setEditLines(reqLines.map(l => ({ product_id: l.product_id, quantity: l.quantity })));
    setEditNote(req.note ?? ''); setEditReason(''); setEditErr(null);
    setEditSourceType(req.source_type as any); setEditSourceId(req.source_id);
    setEditDestType(req.dest_type as any); setEditDestId(req.dest_id);
  };

  const saveEdit = async () => {
    if (!editReq) return;
    if (!editReason.trim()) { setEditErr('An edit reason is required.'); return; }
    setEditBusy(true); setEditErr(null);
    const headerChanged = editSourceType !== editReq.source_type || editSourceId !== editReq.source_id
      || editDestType !== editReq.dest_type || editDestId !== editReq.dest_id;
    const { error } = await supabase.rpc('edit_transfer_request', {
      p_transfer_id: editReq.id,
      p_expected_version: editReq.version ?? null,
      p_reason: editReason.trim(),
      p_source_type: canApprove && headerChanged ? editSourceType : null,
      p_source_id: canApprove && headerChanged ? editSourceId : null,
      p_dest_type: canApprove && headerChanged ? editDestType : null,
      p_dest_id: canApprove && headerChanged ? editDestId : null,
      p_lines: editLines.filter(l => l.product_id && l.quantity > 0),
      p_note: editNote || null,
    });
    setEditBusy(false);
    if (error) { setEditErr(error.message); return; }
    setEditReq(null); loadAll();
  };

  const openHistory = async (req: TransferRequest) => {
    setHistoryReq(req);
    const { data } = await supabase.rpc('transfer_revisions', { p_transfer_id: req.id });
    setRevisions((data as any[]) ?? []);
  };

  const openApprove = (req: TransferRequest) => {
    setApproveReq(req);
    const reqLines = linesByReq[req.id] ?? [];
    setApproveLines(reqLines.map(l => ({ product_id: l.product_id, quantity: l.quantity })));
    setApproveNote(''); setRejectReason(''); setApproveErr(null); setApproveSourceWh('');
  };

  const handleApprove = async () => {
    if (!approveReq) return;
    setApproveBusy(true); setApproveErr(null);
    if (!approveReq.source_id && !approveSourceWh) { setApproveErr('Choose a source warehouse to approve this request.'); setApproveBusy(false); return; }
    const { error } = await supabase.rpc('approve_transfer', {
      p_request_id: approveReq.id, p_approved_lines: approveLines, p_note: approveNote.trim() || null,
      p_source_warehouse_id: approveReq.source_id ? null : (approveSourceWh || null),
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

  // Phase 11 — receipt permission (destination-store staff, or Owner/Manager;
  // warehouse destinations are Owner/Manager only).
  const canReceive = (req: TransferRequest) =>
    req.status === 'in_transit' &&
    (canApprove || (req.dest_type === 'store' && req.dest_id === assignedStoreId));

  const openReceive = (req: TransferRequest) => {
    setReceiveReq(req);
    const lines = (linesByReq[req.id] ?? []).filter(l => (l.in_transit_quantity ?? 0) > 0);
    const q: Record<string, number> = {}; const r: Record<string, string> = {};
    lines.forEach(l => { q[l.product_id] = l.in_transit_quantity ?? 0; r[l.product_id] = ''; });
    setReceiveQty(q); setReceiveReason(r); setReceiveNote(''); setReceiveErr(null);
  };

  const confirmAllReceived = () => {
    if (!receiveReq) return;
    const q: Record<string, number> = {};
    (linesByReq[receiveReq.id] ?? []).forEach(l => { if ((l.in_transit_quantity ?? 0) > 0) q[l.product_id] = l.in_transit_quantity ?? 0; });
    setReceiveQty(q);
  };

  const receiveHasMismatch = () => {
    if (!receiveReq) return false;
    return (linesByReq[receiveReq.id] ?? []).some(l =>
      (l.in_transit_quantity ?? 0) > 0 && (receiveQty[l.product_id] ?? 0) !== (l.approved_quantity ?? l.in_transit_quantity ?? 0));
  };

  const saveReceive = async () => {
    if (!receiveReq) return;
    const lines = (linesByReq[receiveReq.id] ?? []).filter(l => (l.in_transit_quantity ?? 0) > 0);
    if (lines.some(l => (receiveQty[l.product_id] ?? -1) < 0)) { setReceiveErr('Received quantity cannot be negative.'); return; }
    if (receiveHasMismatch() && !receiveNote.trim()) { setReceiveErr('A mismatch reason is required — the received quantity differs from what was approved.'); return; }
    setReceiveBusy(true); setReceiveErr(null);
    const { error } = await supabase.rpc('receive_transfer', {
      p_request_id: receiveReq.id,
      p_lines: lines.map(l => ({ product_id: l.product_id, received_quantity: receiveQty[l.product_id] ?? 0, reason: receiveReason[l.product_id] || null })),
      p_note: receiveNote.trim() || null,
      p_confirm_all: false,
    });
    setReceiveBusy(false);
    if (error) { setReceiveErr(error.message); return; }
    setReceiveReq(null); loadAll();
  };

  const openResolve = (req: TransferRequest) => {
    setResolveReq(req);
    const init: Record<string, { resolution: string; reason: string }> = {};
    (linesByReq[req.id] ?? []).filter(l => (l.discrepancy_quantity ?? 0) !== 0 && !l.discrepancy_resolved_at)
      .forEach(l => { init[l.product_id] = { resolution: (l.discrepancy_quantity ?? 0) > 0 ? 'accept_surplus' : 'accept_loss', reason: '' }; });
    setResolutions(init); setResolveNote(''); setResolveErr(null);
  };

  const saveResolve = async () => {
    if (!resolveReq) return;
    const entries = Object.entries(resolutions);
    if (entries.some(([, v]) => v.resolution === 'other' && !v.reason.trim())) {
      setResolveErr('A reason is required for any "Other" resolution.'); return;
    }
    setResolveBusy(true); setResolveErr(null);
    const { error } = await supabase.rpc('resolve_transfer_discrepancy', {
      p_request_id: resolveReq.id,
      p_resolutions: entries.map(([product_id, v]) => ({ product_id, resolution: v.resolution, reason: v.reason || null })),
      p_note: resolveNote.trim() || null,
    });
    setResolveBusy(false);
    if (error) { setResolveErr(error.message); return; }
    setResolveReq(null); loadAll();
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
        <div><h2>Stock Transfers</h2><p>Request transfers between warehouses and stores. Approval dispatches the stock (In Transit); the destination confirms receipt to add it in.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={requests} filename="transfers" sheetName="Transfers"
            dateOf={(r: any) => r.created_at} dateLabel="Requested"
            columns={[
              { header: 'Date', value: (r: any) => new Date(r.created_at).toLocaleDateString('en-GB') },
              { header: 'Transfer No', value: (r: any) => r.request_no ?? '' },
              { header: 'From', value: (r: any) => r.from_name ?? '' },
              { header: 'To', value: (r: any) => r.to_name ?? '' },
              { header: 'Status', value: (r: any) => r.status ?? '' },
            ]} />
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
                        <td>
                          <StatusBadge s={req.status} />
                          {(req.edit_count ?? 0) > 0 && <span className="badge badge-accent" style={{ marginLeft: 4, fontSize: 10 }} title={`Edited ${req.edit_count}×`}>edited</span>}
                          {isOverdue(req) && <span className="badge badge-danger" style={{ marginLeft: 4, fontSize: 10 }} title="In transit over 7 days"><AlertTriangle size={9} style={{ verticalAlign: -1 }} /> overdue</span>}
                        </td>
                        <td style={{ fontSize: 12.5 }}>{userName(req.requested_by)}</td>
                        <td>
                          <div style={{ display: 'flex', gap: 4 }}>
                            {req.status === 'pending' && canApprove && <button className="btn btn-primary btn-sm" onClick={() => openApprove(req)}><Check size={13} /> Review</button>}
                            {canReceive(req) && <button className="btn btn-primary btn-sm" onClick={() => openReceive(req)}><PackageCheck size={13} /> Receive</button>}
                            {req.status === 'received_with_discrepancy' && canApprove && <button className="btn btn-danger btn-sm" onClick={() => openResolve(req)}><AlertTriangle size={13} /> Resolve</button>}
                            {canEditReq(req) && <button className="btn btn-secondary btn-sm" onClick={() => openEdit(req)}><Pencil size={13} /> Edit</button>}
                            {(req.edit_count ?? 0) > 0 && <button className="btn btn-secondary btn-sm btn-icon" title="Edit history" onClick={() => openHistory(req)}><History size={13} /></button>}
                            {req.status === 'pending' && req.requested_by === profile?.id && <button className="btn btn-secondary btn-sm btn-icon" onClick={() => handleCancel(req)}><Trash2 size={13} /></button>}
                          </div>
                        </td>
                      </tr>
                      {isOpen && (
                        <tr>
                          <td></td>
                          <td colSpan={7} style={{ background: 'var(--surface-2)' }}>
                            {(() => {
                              const dispatched = ['in_transit', 'received', 'received_with_discrepancy', 'completed', 'approved', 'partially_approved'].includes(req.status);
                              const receivedShown = ['received', 'received_with_discrepancy', 'completed'].includes(req.status);
                              const discShown = req.status === 'received_with_discrepancy' || req.status === 'completed';
                              return (
                                <div style={{ padding: '4px 0' }}>
                                  <table style={{ width: 'auto', minWidth: 420 }}>
                                    <thead><tr>
                                      <th>Product</th>
                                      <th style={{ textAlign: 'right' }}>Requested</th>
                                      {dispatched && <th style={{ textAlign: 'right' }}>Approved</th>}
                                      {receivedShown && <th style={{ textAlign: 'right' }}>Received</th>}
                                      {discShown && <th style={{ textAlign: 'right' }}>Diff</th>}
                                    </tr></thead>
                                    <tbody>
                                      {reqLines.map(l => {
                                        const diff = l.discrepancy_quantity ?? 0;
                                        return (
                                          <tr key={l.id}>
                                            <td><strong>{productName(l.product_id)}</strong> <span style={{ color: 'var(--text-muted)', fontSize: 11.5 }}>{productSku(l.product_id)}</span></td>
                                            <td style={{ textAlign: 'right' }}>{l.quantity}</td>
                                            {dispatched && <td style={{ textAlign: 'right', fontWeight: 700, color: (l.approved_quantity ?? 0) < l.quantity ? 'var(--accent)' : 'var(--success)' }}>{l.approved_quantity ?? 0}</td>}
                                            {receivedShown && <td style={{ textAlign: 'right', fontWeight: 700 }}>{l.received_quantity ?? 0}</td>}
                                            {discShown && <td style={{ textAlign: 'right', fontWeight: 700, color: diff === 0 ? 'var(--text-muted)' : 'var(--danger)' }}>{diff > 0 ? `+${diff}` : diff}{l.discrepancy_resolution ? ` · ${l.discrepancy_resolution}` : ''}</td>}
                                          </tr>
                                        );
                                      })}
                                    </tbody>
                                  </table>
                                  {req.note && <p style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 8 }}><strong>Note:</strong> {req.note}</p>}
                                  {req.rejection_reason && <p style={{ fontSize: 12, color: 'var(--danger)', marginTop: 8 }}><strong>Rejected:</strong> {req.rejection_reason}</p>}
                                  {req.approved_at && <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6 }}>{req.status === 'rejected' ? 'Rejected' : req.dispatched_at ? 'Dispatched' : 'Approved'} by {userName(req.approved_by)} on {new Date(req.approved_at).toLocaleString()}</p>}
                                  {req.received_at && <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 2 }}>Received by {userName(req.received_by ?? null)} on {new Date(req.received_at).toLocaleString()}{req.receipt_note ? ` — ${req.receipt_note}` : ''}</p>}
                                </div>
                              );
                            })()}
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
            {isStaff ? (
              <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>
                Requesting stock into your store: <strong>{stores.find(s => s.id === (assignedStoreId ?? ''))?.name ?? 'No store assigned'}</strong>.
                An Owner or Manager will choose which warehouse to send it from when they approve.
              </div></div>
            ) : (
              <>
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
              </>
            )}
            <div>
              <label>Products</label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {lines.map((line, i) => (
                  <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                    <div style={{ flex: 1 }}>
                      <SearchSelect
                        options={(isStaff && assignedStoreId
                          ? products.filter(p => storePrices.some(sp => sp.store_id === assignedStoreId && sp.product_id === p.id))
                          : products
                        ).map(p => ({ value: p.id, label: `${p.name} (${p.sku})`, search: `${p.name} ${p.sku}` }))}
                        value={line.product_id}
                        exclude={lines.filter((_, j) => j !== i).map(x => x.product_id).filter(Boolean)}
                        onChange={v => setLines(ls => ls.map((l, j) => j === i ? { ...l, product_id: v } : l))}
                        placeholder="Search product name or SKU…" />
                    </div>
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
              {approveReq.source_id ? locName(approveReq.source_type, approveReq.source_id) : <em>source not chosen yet</em>} → {locName(approveReq.dest_type, approveReq.dest_id)}
            </p>
            {!approveReq.source_id && (
              <div className="form-group">
                <label>Source Warehouse * <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— this was a Staff request; choose where the stock ships from</span></label>
                <select value={approveSourceWh} onChange={e => setApproveSourceWh(e.target.value)}>
                  <option value="">— Select warehouse —</option>
                  {warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
                </select>
              </div>
            )}
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

      {editReq && (
        <Modal title={`Edit Transfer — ${TRANSFER_TYPES.find(t => t.value === editReq.transfer_type)?.label ?? ''}`} maxWidth={560} onClose={() => setEditReq(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setEditReq(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveEdit} disabled={editBusy}>{editBusy ? 'Saving…' : 'Save Changes'}</button></>}>
          <div className="form-grid">
            {editErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{editErr}</div></div>}
            {!canApprove && (
              <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>You can edit the items and note. Only an Owner or Manager can change the source or destination.</div></div>
            )}
            {canApprove && (
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Source</label>
                  <select value={`${editSourceType}:${editSourceId}`} onChange={e => { const [ty, id] = e.target.value.split(':'); setEditSourceType(ty as any); setEditSourceId(id); }}>
                    {warehouses.map(w => <option key={w.id} value={`warehouse:${w.id}`}>🏭 {w.name}</option>)}
                    {stores.map(s => <option key={s.id} value={`store:${s.id}`}>🏪 {s.name}</option>)}
                  </select>
                </div>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Destination</label>
                  <select value={`${editDestType}:${editDestId}`} onChange={e => { const [ty, id] = e.target.value.split(':'); setEditDestType(ty as any); setEditDestId(id); }}>
                    {warehouses.map(w => <option key={w.id} value={`warehouse:${w.id}`}>🏭 {w.name}</option>)}
                    {stores.map(s => <option key={s.id} value={`store:${s.id}`}>🏪 {s.name}</option>)}
                  </select>
                </div>
              </div>
            )}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Items</label>
              {editLines.map((l, i) => (
                <div key={i} style={{ display: 'flex', gap: 6, marginBottom: 6 }}>
                  <div style={{ flex: 1 }}>
                    <SearchSelect
                      options={products.map(p => ({ value: p.id, label: `${p.name} (${p.sku})`, search: `${p.name} ${p.sku}` }))}
                      value={l.product_id}
                      exclude={editLines.filter((_, j) => j !== i).map(x => x.product_id).filter(Boolean)}
                      onChange={v => setEditLines(ls => ls.map((x, j) => j === i ? { ...x, product_id: v } : x))}
                      placeholder="Search product name or SKU…" />
                  </div>
                  <input type="number" min={1} value={l.quantity || ''} onChange={e => setEditLines(ls => ls.map((x, j) => j === i ? { ...x, quantity: +e.target.value } : x))} style={{ width: 90 }} placeholder="Qty" />
                  <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setEditLines(ls => ls.filter((_, j) => j !== i))}><X size={13} /></button>
                </div>
              ))}
              <button className="btn btn-secondary btn-sm" onClick={() => setEditLines(ls => [...ls, { product_id: '', quantity: 0 }])}><Plus size={13} /> Add item</button>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Note</label><input value={editNote} onChange={e => setEditNote(e.target.value)} placeholder="Optional note" /></div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Edit reason *</label><textarea rows={2} value={editReason} onChange={e => setEditReason(e.target.value)} placeholder="Why is this transfer being edited?" /></div>
          </div>
        </Modal>
      )}

      {historyReq && (
        <Modal title="Edit history" maxWidth={520} onClose={() => setHistoryReq(null)}
          footer={<button className="btn btn-secondary" onClick={() => setHistoryReq(null)}>Close</button>}>
          {revisions.length === 0 ? <div style={{ color: 'var(--text-muted)' }}>No edits recorded.</div> : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {revisions.map((r, i) => (
                <div key={i} style={{ borderLeft: '2px solid var(--primary)', paddingLeft: 10 }}>
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>v{r.version} → v{r.version + 1} · {new Date(r.created_at).toLocaleString('en-GB')} · {r.editor ?? '—'}</div>
                  <div style={{ fontSize: 13 }}>{r.reason}</div>
                  {r.changed_summary && Object.keys(r.changed_summary).length > 0 && (
                    <div style={{ fontSize: 11.5, color: 'var(--text-secondary)', marginTop: 2 }}>
                      Changed: {Object.keys(r.changed_summary).join(', ')}
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </Modal>
      )}

      {receiveReq && (
        <Modal title="Confirm Receipt" maxWidth={560} onClose={() => setReceiveReq(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setReceiveReq(null)}>Cancel</button>
            <button className="btn btn-secondary" onClick={confirmAllReceived} disabled={receiveBusy}><Check size={14} /> Confirm All Received</button>
            <button className="btn btn-primary" onClick={saveReceive} disabled={receiveBusy}>{receiveBusy ? 'Saving…' : 'Confirm Receipt'}</button>
          </>}>
          <div className="form-grid">
            {receiveErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{receiveErr}</div></div>}
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span><Truck size={15} /></span><div>
              Enter the <strong>actual quantity received</strong> for each line. The destination’s stock increases by what you enter — including any extra. Receipt can only be confirmed once.
            </div></div>
            <p style={{ fontSize: 13, color: 'var(--text-secondary)', margin: 0 }}>
              {locName(receiveReq.source_type, receiveReq.source_id)} → <strong>{locName(receiveReq.dest_type, receiveReq.dest_id)}</strong>
            </p>
            <div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 4 }}>
                {(linesByReq[receiveReq.id] ?? []).filter(l => (l.in_transit_quantity ?? 0) > 0).map(l => {
                  const approved = l.approved_quantity ?? l.in_transit_quantity ?? 0;
                  const actual = receiveQty[l.product_id] ?? 0;
                  const mismatch = actual !== approved;
                  return (
                    <div key={l.id} style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                      <div style={{ flex: 1 }}>
                        <strong>{productName(l.product_id)}</strong>{' '}
                        <span style={{ color: 'var(--text-muted)', fontSize: 12 }}>approved {approved}</span>
                      </div>
                      <input type="number" min={0} value={receiveQty[l.product_id] ?? 0} style={{ width: 90 }}
                        onChange={e => setReceiveQty(q => ({ ...q, [l.product_id]: Math.max(0, +e.target.value) }))} />
                      {mismatch && <span className="badge badge-danger" style={{ fontSize: 10 }}>{actual > approved ? `+${actual - approved}` : actual - approved}</span>}
                    </div>
                  );
                })}
              </div>
            </div>
            {receiveHasMismatch() && (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Mismatch reason * <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— the received quantity differs from what was approved</span></label>
                <textarea rows={2} value={receiveNote} onChange={e => setReceiveNote(e.target.value)} placeholder="Explain the difference (short shipment, damaged, extra units…)" />
              </div>
            )}
            {!receiveHasMismatch() && (
              <div className="form-group" style={{ marginBottom: 0 }}><label>Notes (optional)</label><input value={receiveNote} onChange={e => setReceiveNote(e.target.value)} placeholder="Any notes about this receipt" /></div>
            )}
          </div>
        </Modal>
      )}

      {resolveReq && (
        <Modal title="Resolve Discrepancy" maxWidth={580} onClose={() => setResolveReq(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setResolveReq(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={saveResolve} disabled={resolveBusy}>{resolveBusy ? 'Saving…' : 'Resolve & Complete'}</button>
          </>}>
          <div className="form-grid">
            {resolveErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{resolveErr}</div></div>}
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>
              Choose how to resolve each mismatch. Once every line is resolved the transfer is marked <strong>Completed</strong>.
            </div></div>
            {(linesByReq[resolveReq.id] ?? []).filter(l => (l.discrepancy_quantity ?? 0) !== 0 && !l.discrepancy_resolved_at).map(l => {
              const diff = l.discrepancy_quantity ?? 0;
              const r = resolutions[l.product_id] ?? { resolution: 'accept_loss', reason: '' };
              const opts = RESOLUTION_OPTIONS.filter(o =>
                diff > 0 ? o.value !== 'accept_loss' : o.value !== 'accept_surplus' && o.value !== 'return_excess');
              return (
                <div key={l.id} style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
                  <div style={{ fontSize: 13, marginBottom: 6 }}>
                    <strong>{productName(l.product_id)}</strong>{' '}
                    <span className="badge badge-danger" style={{ fontSize: 10 }}>{diff > 0 ? `+${diff} extra` : `${Math.abs(diff)} missing`}</span>
                    <span style={{ color: 'var(--text-muted)', fontSize: 11.5, marginLeft: 6 }}>approved {l.approved_quantity ?? 0} · received {l.received_quantity ?? 0}</span>
                  </div>
                  <div style={{ display: 'flex', gap: 8 }}>
                    <select value={r.resolution} style={{ flex: 1 }}
                      onChange={e => setResolutions(s => ({ ...s, [l.product_id]: { ...r, resolution: e.target.value } }))}>
                      {opts.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
                    </select>
                    <input placeholder="Reason (optional)" value={r.reason} style={{ flex: 1 }}
                      onChange={e => setResolutions(s => ({ ...s, [l.product_id]: { ...r, reason: e.target.value } }))} />
                  </div>
                </div>
              );
            })}
            <div className="form-group" style={{ marginBottom: 0 }}><label>Overall note (optional)</label><input value={resolveNote} onChange={e => setResolveNote(e.target.value)} /></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default TransfersPage;
