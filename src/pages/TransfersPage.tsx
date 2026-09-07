import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Warehouse, Store, Product, TransferType, TransferLine, TransferLineKind, LocationType,
  TransferRequest, TransferRequestLine, ApprovalStatus, APPROVAL_STATUS_LABELS,
  isOwnerOrManager, Profile, TransferSourcingRow, TransferSourceOption, TransferRevision,
} from '../types';
import { SearchSelect } from '../components/SearchSelect';
import { Modal } from '../components/ui';
import {
  Plus, RefreshCw, ArrowLeftRight, Check, X, Trash2, ChevronDown, ChevronUp,
  Pencil, History, PackageCheck, AlertTriangle, Truck,
} from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';

const RESOLUTION_OPTIONS: { value: string; label: string }[] = [
  { value: 'accept_loss', label: 'Accept missing as loss' },
  { value: 'accept_surplus', label: 'Accept extra as surplus' },
  { value: 'return_excess', label: 'Return excess to source' },
  { value: 'correct_source', label: 'Correct source stock' },
  { value: 'correct_destination', label: 'Correct destination stock' },
  { value: 'inventory_adjustment', label: 'Create linked inventory adjustment' },
  { value: 'other', label: 'Other / acknowledge (reason required)' },
];

const TRANSFER_TYPES: { value: TransferType; label: string; src: LocationType; dest: LocationType }[] = [
  { value: 'warehouse_to_store', label: 'Warehouse → Store', src: 'warehouse', dest: 'store' },
  { value: 'warehouse_to_warehouse', label: 'Warehouse → Warehouse', src: 'warehouse', dest: 'warehouse' },
  { value: 'store_to_store', label: 'Store → Store', src: 'store', dest: 'store' },
];

const isOverdue = (r: TransferRequest) =>
  r.status === 'in_transit' && !!r.dispatched_at &&
  (Date.now() - new Date(r.dispatched_at).getTime()) > 7 * 24 * 60 * 60 * 1000;

const StatusBadge: React.FC<{ s: ApprovalStatus }> = ({ s }) => {
  const cls =
    s === 'approved' || s === 'received' || s === 'completed' ? 'badge-success'
      : s === 'partially_approved' || s === 'in_transit' ? 'badge-primary'
        : s === 'received_with_discrepancy' || s === 'rejected' ? 'badge-danger'
          : s === 'cancelled' ? 'badge-muted' : 'badge-accent';
  return <span className={`badge ${cls}`}>{APPROVAL_STATUS_LABELS[s]}</span>;
};

type StaffStore = { store_id: string; store_name: string; is_default: boolean };
type ResolutionValue = { resolution: string; reason: string };

interface ReviewLineDraft {
  key: string;
  line_id: string | null;
  line_kind: TransferLineKind;
  product_id: string | null;
  manual_item_name: string;
  manual_uom: string;
  requested_quantity: number;
  approved_quantity: number;
  added_by_approver: boolean;
}

const newProductLine = (): TransferLine => ({ line_kind: 'product', product_id: '', quantity: 0 });
const newManualLine = (): TransferLine => ({
  line_kind: 'manual', product_id: null, manual_item_name: '', manual_uom: '', quantity: 0,
});
const clientKey = () => `new-${Date.now()}-${Math.random().toString(36).slice(2)}`;

const TransfersPage: React.FC = () => {
  const { profile } = useAuth();
  const canApprove = isOwnerOrManager(profile?.role);
  const isStaff = profile?.role === 'staff';

  const [assignedStoreId, setAssignedStoreId] = useState<string | null>(null);
  const [myStores, setMyStores] = useState<StaffStore[]>([]);
  const [storePrices, setStorePrices] = useState<{ store_id: string; product_id: string }[]>([]);
  const [requests, setRequests] = useState<TransferRequest[]>([]);
  const [linesByReq, setLinesByReq] = useState<Record<string, TransferRequestLine[]>>({});
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState<string | null>(null);

  // Create
  const [createOpen, setCreateOpen] = useState(false);
  const [tType, setTType] = useState<TransferType>('warehouse_to_store');
  const [sourceId, setSourceId] = useState('');
  const [destId, setDestId] = useState('');
  const [lines, setLines] = useState<TransferLine[]>([newProductLine()]);
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [createErr, setCreateErr] = useState<string | null>(null);

  // Review / approval
  const [approveReq, setApproveReq] = useState<TransferRequest | null>(null);
  const [reviewLines, setReviewLines] = useState<ReviewLineDraft[]>([]);
  const [reviewSources, setReviewSources] = useState<Record<string, TransferSourceOption[]>>({});
  const [alloc, setAlloc] = useState<Record<string, Record<string, number>>>({});
  const [approveNote, setApproveNote] = useState('');
  const [rejectReason, setRejectReason] = useState('');
  const [approveErr, setApproveErr] = useState<string | null>(null);
  const [approveBusy, setApproveBusy] = useState(false);

  // Edit
  const [editReq, setEditReq] = useState<TransferRequest | null>(null);
  const [editLines, setEditLines] = useState<TransferLine[]>([]);
  const [editNote, setEditNote] = useState('');
  const [editReason, setEditReason] = useState('');
  const [editSourceType, setEditSourceType] = useState<LocationType>('warehouse');
  const [editSourceId, setEditSourceId] = useState('');
  const [editDestType, setEditDestType] = useState<LocationType>('store');
  const [editDestId, setEditDestId] = useState('');
  const [editBusy, setEditBusy] = useState(false);
  const [editErr, setEditErr] = useState<string | null>(null);
  const [historyReq, setHistoryReq] = useState<TransferRequest | null>(null);
  const [revisions, setRevisions] = useState<TransferRevision[]>([]);

  // Receive
  const [receiveReq, setReceiveReq] = useState<TransferRequest | null>(null);
  const [receiveQty, setReceiveQty] = useState<Record<string, number>>({});
  const [receiveReason, setReceiveReason] = useState<Record<string, string>>({});
  const [receiveNote, setReceiveNote] = useState('');
  const [receiveBusy, setReceiveBusy] = useState(false);
  const [receiveErr, setReceiveErr] = useState<string | null>(null);

  // Discrepancy resolution
  const [resolveReq, setResolveReq] = useState<TransferRequest | null>(null);
  const [resolutions, setResolutions] = useState<Record<string, ResolutionValue>>({});
  const [resolveNote, setResolveNote] = useState('');
  const [resolveBusy, setResolveBusy] = useState(false);
  const [resolveErr, setResolveErr] = useState<string | null>(null);

  const loadAll = useCallback(async () => {
    setLoading(true);
    const [req, lns, wh, st, prod, prof, myStore, myStoreList, prc] = await Promise.all([
      supabase.from('transfer_requests').select('*').order('created_at', { ascending: false }),
      supabase.from('transfer_request_lines').select('*'),
      supabase.from('warehouses').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('profiles').select('*'),
      supabase.rpc('my_assigned_store_id'),
      supabase.rpc('my_assigned_stores'),
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
    setMyStores((myStoreList.data as StaffStore[]) ?? []);
    setStorePrices((prc.data as { store_id: string; product_id: string }[]) ?? []);
    setLoading(false);
  }, []);

  useEffect(() => { void loadAll(); }, [loadAll]);

  const cfg = TRANSFER_TYPES.find(t => t.value === tType)!;
  const sourceOptions = cfg.src === 'warehouse' ? warehouses : stores;
  const destOptions = (cfg.dest === 'warehouse' ? warehouses : stores).filter(o => o.id !== sourceId);

  const productName = (id: string | null | undefined, manualName?: string | null) => {
    if (id) return products.find(p => p.id === id)?.name ?? 'Product unavailable';
    return manualName?.trim() || 'Manual item';
  };
  const productSku = (id: string | null | undefined) => id ? (products.find(p => p.id === id)?.sku ?? '') : '';
  const userName = (id: string | null | undefined) => id ? (profiles.find(p => p.id === id)?.full_name ?? '—') : '—';
  const locName = (type: LocationType | null | undefined, id: string | null | undefined) => {
    if (!type || !id) return '—';
    const list = type === 'warehouse' ? warehouses : stores;
    return list.find(l => l.id === id)?.name ?? '—';
  };

  const selectedStaffDestId = destId || (myStores.length === 1 ? myStores[0]?.store_id : assignedStoreId) || '';
  const productHasStorePrice = (storeId: string | null | undefined, productId: string) =>
    !storeId || storePrices.some(sp => sp.store_id === storeId && sp.product_id === productId);
  const productOptionsForStore = (storeId?: string | null) => products
    .filter(p => productHasStorePrice(storeId, p.id))
    .map(p => ({ value: p.id, label: `${p.name} (${p.sku})`, search: `${p.name} ${p.sku}` }));

  const validDraftLine = (l: TransferLine) => {
    if (!Number.isFinite(l.quantity) || l.quantity <= 0) return false;
    if (l.line_kind === 'manual') return !!l.manual_item_name?.trim() && !!l.manual_uom?.trim();
    return !!l.product_id;
  };
  const serializeDraftLines = (draft: TransferLine[]) => draft.filter(validDraftLine).map(l => ({
    line_kind: l.line_kind,
    product_id: l.line_kind === 'product' ? l.product_id : null,
    manual_item_name: l.line_kind === 'manual' ? l.manual_item_name?.trim() : null,
    manual_uom: l.line_kind === 'manual' ? l.manual_uom?.trim() : null,
    quantity: Math.floor(Number(l.quantity)),
  }));

  const resetCreate = () => {
    setTType('warehouse_to_store'); setSourceId('');
    setDestId(isStaff && myStores.length === 1 ? (myStores[0]?.store_id ?? assignedStoreId ?? '') : '');
    setLines([newProductLine()]); setNote(''); setCreateErr(null);
  };

  const handleCreate = async () => {
    const validLines = serializeDraftLines(lines);
    if (validLines.length !== lines.length || validLines.length === 0) {
      setCreateErr('Complete every line. Products need a product and quantity; manual items need a name, quantity and unit/UOM.');
      return;
    }
    setSaving(true); setCreateErr(null);
    if (isStaff) {
      if (!selectedStaffDestId) { setSaving(false); setCreateErr('Choose which assigned store this request is for.'); return; }
      const { error } = await supabase.rpc('create_staff_transfer_request', {
        p_lines: validLines, p_note: note.trim() || null, p_store_id: selectedStaffDestId,
      });
      setSaving(false);
      if (error) { setCreateErr(error.message); return; }
      setCreateOpen(false); resetCreate(); void loadAll(); return;
    }

    if (!sourceId || !destId) { setSaving(false); setCreateErr('Select source and destination.'); return; }
    const { error } = await supabase.rpc('create_transfer_request', {
      p_transfer_type: tType, p_source_type: cfg.src, p_source_id: sourceId,
      p_dest_type: cfg.dest, p_dest_id: destId, p_lines: validLines, p_note: note.trim() || null,
    });
    setSaving(false);
    if (error) { setCreateErr(error.message); return; }
    setCreateOpen(false); resetCreate(); void loadAll();
  };

  const canEditReq = (req: TransferRequest) => req.status === 'pending' && (canApprove || req.requested_by === profile?.id);

  const openEdit = (req: TransferRequest) => {
    setEditReq(req);
    setEditLines((linesByReq[req.id] ?? []).map(l => ({
      line_id: l.id,
      line_kind: l.line_kind ?? (l.product_id ? 'product' : 'manual'),
      product_id: l.product_id,
      manual_item_name: l.manual_item_name ?? '',
      manual_uom: l.manual_uom ?? '',
      quantity: l.quantity,
    })));
    setEditNote(req.note ?? ''); setEditReason(''); setEditErr(null);
    setEditSourceType(req.source_type ?? 'warehouse'); setEditSourceId(req.source_id ?? '');
    setEditDestType(req.dest_type); setEditDestId(req.dest_id);
  };

  const saveEdit = async () => {
    if (!editReq) return;
    if (!editReason.trim()) { setEditErr('An edit reason is required.'); return; }
    const payload = serializeDraftLines(editLines);
    if (payload.length !== editLines.length || payload.length === 0) {
      setEditErr('Complete every item before saving.'); return;
    }
    const sourceChanged = !!editSourceId && (editSourceType !== editReq.source_type || editSourceId !== editReq.source_id);
    const destChanged = editDestType !== editReq.dest_type || editDestId !== editReq.dest_id;
    setEditBusy(true); setEditErr(null);
    const { error } = await supabase.rpc('edit_transfer_request', {
      p_transfer_id: editReq.id,
      p_expected_version: editReq.version ?? null,
      p_reason: editReason.trim(),
      p_source_type: canApprove && sourceChanged ? editSourceType : null,
      p_source_id: canApprove && sourceChanged ? editSourceId : null,
      p_dest_type: canApprove && destChanged ? editDestType : null,
      p_dest_id: canApprove && destChanged ? editDestId : null,
      p_lines: payload,
      p_note: editNote || null,
    });
    setEditBusy(false);
    if (error) { setEditErr(error.message); return; }
    setEditReq(null); void loadAll();
  };

  const openHistory = async (req: TransferRequest) => {
    setHistoryReq(req);
    const { data } = await supabase.rpc('transfer_revisions', { p_transfer_id: req.id });
    setRevisions((data as TransferRevision[]) ?? []);
  };

  const seedAllocation = (key: string, quantity: number, sources: TransferSourceOption[]) => {
    let left = Math.max(0, Math.floor(quantity));
    const next: Record<string, number> = {};
    [...sources].sort((a, b) => b.available - a.available).forEach(src => {
      if (left <= 0) return;
      const take = Math.min(left, src.available);
      if (take > 0) {
        next[`${src.source_type}:${src.source_id}`] = take;
        left -= take;
      }
    });
    setAlloc(a => ({ ...a, [key]: next }));
  };

  const loadSourcesForAddedProduct = async (key: string, productId: string, approvedQty: number) => {
    if (!approveReq || !productId) return;
    const { data, error } = await supabase.rpc('transfer_product_sourcing', {
      p_request_id: approveReq.id, p_product_id: productId,
    });
    if (error) { setApproveErr(error.message); return; }
    const rows = (data as TransferSourceOption[]) ?? [];
    setReviewSources(s => ({ ...s, [key]: rows }));
    seedAllocation(key, approvedQty, rows);
  };

  const openApprove = async (req: TransferRequest) => {
    setApproveReq(req); setApproveNote(''); setRejectReason(''); setApproveErr(null); setApproveBusy(false);
    setAlloc({}); setReviewSources({});
    const reqLines = linesByReq[req.id] ?? [];
    const drafts: ReviewLineDraft[] = reqLines.map(l => ({
      key: l.id, line_id: l.id,
      line_kind: l.line_kind ?? (l.product_id ? 'product' : 'manual'),
      product_id: l.product_id,
      manual_item_name: l.manual_item_name ?? '', manual_uom: l.manual_uom ?? '',
      requested_quantity: l.quantity,
      approved_quantity: l.approved_quantity ?? l.quantity,
      added_by_approver: !!l.added_by_approver,
    }));
    setReviewLines(drafts);
    const { data, error } = await supabase.rpc('transfer_request_sourcing', { p_request_id: req.id });
    if (error) { setApproveErr(error.message); return; }
    const rows = (data as TransferSourcingRow[]) ?? [];
    const grouped: Record<string, TransferSourceOption[]> = {};
    rows.forEach(r => {
      (grouped[r.line_id] ??= []).push({
        source_type: r.source_type, source_id: r.source_id, source_name: r.source_name,
        on_hand: r.on_hand, reserved: r.reserved, available: r.available, allocated: r.allocated,
      });
    });
    setReviewSources(grouped);
    drafts.filter(d => d.line_kind === 'product').forEach(d => seedAllocation(d.key, d.approved_quantity, grouped[d.key] ?? []));
  };

  const allocFor = (key: string) => Object.values(alloc[key] ?? {}).reduce((sum, q) => sum + (Number(q) || 0), 0);
  const reviewLineValid = (l: ReviewLineDraft) => {
    if (!Number.isFinite(l.approved_quantity) || l.approved_quantity < 0) return false;
    if (l.line_kind === 'manual') return !!l.manual_item_name.trim() && !!l.manual_uom.trim();
    return !!l.product_id;
  };
  const allocationComplete = reviewLines.every(l => {
    if (l.line_kind === 'manual') return true;
    if (!l.product_id) return false;
    return allocFor(l.key) === l.approved_quantity;
  });

  const updateReviewQty = (key: string, raw: number) => {
    const q = Math.max(0, Math.floor(Number(raw) || 0));
    setReviewLines(ls => ls.map(l => l.key === key ? { ...l, approved_quantity: q } : l));
    const line = reviewLines.find(l => l.key === key);
    if (line?.line_kind === 'product') seedAllocation(key, q, reviewSources[key] ?? []);
  };

  const handleApprove = async () => {
    if (!approveReq) return;
    if (!reviewLines.every(reviewLineValid)) { setApproveErr('Complete every review line before approving.'); return; }
    if (!allocationComplete) {
      const bad = reviewLines.filter(l => l.line_kind === 'product' && allocFor(l.key) !== l.approved_quantity)
        .map(l => productName(l.product_id, l.manual_item_name)).join(', ');
      setApproveErr(`Allocate exactly the approved quantity for: ${bad}.`); return;
    }
    const payload = reviewLines.map(l => ({
      line_id: l.line_id,
      line_kind: l.line_kind,
      product_id: l.line_kind === 'product' ? l.product_id : null,
      manual_item_name: l.line_kind === 'manual' ? l.manual_item_name.trim() : null,
      manual_uom: l.line_kind === 'manual' ? l.manual_uom.trim() : null,
      approved_quantity: l.approved_quantity,
      sources: l.line_kind === 'product'
        ? Object.entries(alloc[l.key] ?? {}).filter(([, q]) => Number(q) > 0).map(([sourceKey, q]) => {
          const [source_type, source_id] = sourceKey.split(':');
          return { source_type, source_id, quantity: Number(q) };
        }) : [],
    }));
    setApproveBusy(true); setApproveErr(null);
    const { error } = await supabase.rpc('review_and_dispatch_transfer', {
      p_request_id: approveReq.id, p_lines: payload, p_note: approveNote.trim() || null,
    });
    setApproveBusy(false);
    if (error) { setApproveErr(error.message); return; }
    setApproveReq(null); void loadAll();
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
    setApproveReq(null); void loadAll();
  };

  const canReceive = (req: TransferRequest) => req.status === 'in_transit' && (
    canApprove || (req.dest_type === 'store' && myStores.some(s => s.store_id === req.dest_id)) ||
    (req.dest_type === 'store' && req.dest_id === assignedStoreId)
  );

  const openReceive = (req: TransferRequest) => {
    setReceiveReq(req);
    const shipped = (linesByReq[req.id] ?? []).filter(l => (l.in_transit_quantity ?? 0) > 0);
    const q: Record<string, number> = {}; const r: Record<string, string> = {};
    shipped.forEach(l => { q[l.id] = l.in_transit_quantity ?? 0; r[l.id] = ''; });
    setReceiveQty(q); setReceiveReason(r); setReceiveNote(''); setReceiveErr(null);
  };

  const confirmAllReceived = () => {
    if (!receiveReq) return;
    const q: Record<string, number> = {};
    (linesByReq[receiveReq.id] ?? []).forEach(l => { if ((l.in_transit_quantity ?? 0) > 0) q[l.id] = l.in_transit_quantity ?? 0; });
    setReceiveQty(q);
  };

  const receiveHasMismatch = () => {
    if (!receiveReq) return false;
    return (linesByReq[receiveReq.id] ?? []).some(l =>
      (l.in_transit_quantity ?? 0) > 0 && (receiveQty[l.id] ?? 0) !== (l.approved_quantity ?? l.in_transit_quantity ?? 0));
  };

  const saveReceive = async () => {
    if (!receiveReq) return;
    const shipped = (linesByReq[receiveReq.id] ?? []).filter(l => (l.in_transit_quantity ?? 0) > 0);
    if (shipped.some(l => (receiveQty[l.id] ?? -1) < 0)) { setReceiveErr('Received quantity cannot be negative.'); return; }
    if (receiveHasMismatch() && !receiveNote.trim()) {
      setReceiveErr('A mismatch reason is required — the received quantity differs from what was approved.'); return;
    }
    setReceiveBusy(true); setReceiveErr(null);
    const { error } = await supabase.rpc('receive_transfer', {
      p_request_id: receiveReq.id,
      p_lines: shipped.map(l => ({ line_id: l.id, received_quantity: receiveQty[l.id] ?? 0, reason: receiveReason[l.id] || null })),
      p_note: receiveNote.trim() || null, p_confirm_all: false,
    });
    setReceiveBusy(false);
    if (error) { setReceiveErr(error.message); return; }
    setReceiveReq(null); void loadAll();
  };

  const openResolve = (req: TransferRequest) => {
    setResolveReq(req);
    const init: Record<string, ResolutionValue> = {};
    (linesByReq[req.id] ?? []).filter(l => (l.discrepancy_quantity ?? 0) !== 0 && !l.discrepancy_resolved_at)
      .forEach(l => { init[l.id] = { resolution: (l.discrepancy_quantity ?? 0) > 0 ? 'accept_surplus' : 'accept_loss', reason: '' }; });
    setResolutions(init); setResolveNote(''); setResolveErr(null);
  };

  const saveResolve = async () => {
    if (!resolveReq) return;
    const entries = Object.entries(resolutions);
    if (entries.some(([, v]) => v.resolution === 'other' && !v.reason.trim())) {
      setResolveErr('A reason is required for any "Other / acknowledge" resolution.'); return;
    }
    setResolveBusy(true); setResolveErr(null);
    const { error } = await supabase.rpc('resolve_transfer_discrepancy', {
      p_request_id: resolveReq.id,
      p_resolutions: entries.map(([line_id, v]) => ({ line_id, resolution: v.resolution, reason: v.reason || null })),
      p_note: resolveNote.trim() || null,
    });
    setResolveBusy(false);
    if (error) { setResolveErr(error.message); return; }
    setResolveReq(null); void loadAll();
  };

  const handleCancel = async (req: TransferRequest) => {
    if (!confirm('Cancel this pending transfer request?')) return;
    const { error } = await supabase.rpc('cancel_transfer_request', { p_request_id: req.id });
    if (error) { alert(error.message); return; }
    void loadAll();
  };

  const reviewProductOptions = useMemo(() => {
    if (!approveReq || approveReq.dest_type !== 'store') return productOptionsForStore(null);
    return productOptionsForStore(approveReq.dest_id);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [approveReq, products, storePrices]);

  return (
    <div>
      <div className="page-header">
        <div><h2>Stock Transfers</h2><p>Request products or manual items. Approval dispatches product stock; the destination adds product stock only when receipt is confirmed.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={requests} filename="transfers" sheetName="Transfers"
            dateOf={(r: TransferRequest) => r.created_at} dateLabel="Requested"
            columns={[
              { header: 'Date', value: (r: TransferRequest) => new Date(r.created_at).toLocaleDateString('en-GB') },
              { header: 'Type', value: (r: TransferRequest) => r.transfer_type ?? '' },
              { header: 'From', value: (r: TransferRequest) => locName(r.source_type, r.source_id) },
              { header: 'To', value: (r: TransferRequest) => locName(r.dest_type, r.dest_id) },
              { header: 'Status', value: (r: TransferRequest) => r.status ?? '' },
            ]} />
          <button className="btn btn-secondary" onClick={() => void loadAll()}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={() => { resetCreate(); setCreateOpen(true); }}><Plus size={16} /> New Transfer</button>
        </div>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
            : requests.length === 0 ? <div className="empty-state"><ArrowLeftRight size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No transfer requests yet</p></div>
              : <table>
                <thead><tr><th></th><th>Date</th><th>Type</th><th>From → To</th><th>Items</th><th>Status</th><th>Requested by</th><th></th></tr></thead>
                <tbody>
                  {requests.map(req => {
                    const reqLines = linesByReq[req.id] ?? [];
                    const isOpen = expanded === req.id;
                    return <React.Fragment key={req.id}>
                      <tr>
                        <td><button className="btn btn-secondary btn-sm btn-icon" onClick={() => setExpanded(isOpen ? null : req.id)}>{isOpen ? <ChevronUp size={13} /> : <ChevronDown size={13} />}</button></td>
                        <td style={{ whiteSpace: 'nowrap', fontSize: 12.5 }}>{new Date(req.created_at).toLocaleDateString()}</td>
                        <td style={{ fontSize: 12.5 }}>{TRANSFER_TYPES.find(t => t.value === req.transfer_type)?.label ?? req.transfer_type}</td>
                        <td style={{ fontSize: 12.5 }}>{req.source_id ? locName(req.source_type, req.source_id) : <em>source deferred</em>} → {locName(req.dest_type, req.dest_id)}</td>
                        <td>{reqLines.length} item{reqLines.length !== 1 ? 's' : ''}</td>
                        <td>
                          <StatusBadge s={req.status} />
                          {(req.edit_count ?? 0) > 0 && <span className="badge badge-accent" style={{ marginLeft: 4, fontSize: 10 }}>edited</span>}
                          {isOverdue(req) && <span className="badge badge-danger" style={{ marginLeft: 4, fontSize: 10 }}><AlertTriangle size={9} style={{ verticalAlign: -1 }} /> overdue</span>}
                        </td>
                        <td style={{ fontSize: 12.5 }}>{userName(req.requested_by)}</td>
                        <td><div style={{ display: 'flex', gap: 4 }}>
                          {req.status === 'pending' && canApprove && <button className="btn btn-primary btn-sm" onClick={() => void openApprove(req)}><Check size={13} /> Review</button>}
                          {canReceive(req) && <button className="btn btn-primary btn-sm" onClick={() => openReceive(req)}><PackageCheck size={13} /> Receive</button>}
                          {req.status === 'received_with_discrepancy' && canApprove && <button className="btn btn-danger btn-sm" onClick={() => openResolve(req)}><AlertTriangle size={13} /> Resolve</button>}
                          {canEditReq(req) && <button className="btn btn-secondary btn-sm" onClick={() => openEdit(req)}><Pencil size={13} /> Edit</button>}
                          {(req.edit_count ?? 0) > 0 && <button className="btn btn-secondary btn-sm btn-icon" title="Edit history" onClick={() => void openHistory(req)}><History size={13} /></button>}
                          {req.status === 'pending' && req.requested_by === profile?.id && <button className="btn btn-secondary btn-sm btn-icon" onClick={() => void handleCancel(req)}><Trash2 size={13} /></button>}
                        </div></td>
                      </tr>
                      {isOpen && <tr><td></td><td colSpan={7} style={{ background: 'var(--surface-2)' }}>
                        <div style={{ padding: '4px 0' }}>
                          <table style={{ width: 'auto', minWidth: 560 }}>
                            <thead><tr><th>Item</th><th style={{ textAlign: 'right' }}>Requested</th><th style={{ textAlign: 'right' }}>Approved</th><th style={{ textAlign: 'right' }}>Received</th><th style={{ textAlign: 'right' }}>Diff</th></tr></thead>
                            <tbody>{reqLines.map(l => {
                              const manual = l.line_kind === 'manual' || !l.product_id;
                              const added = !!l.added_by_approver;
                              const approved = l.approved_quantity;
                              const adjustment = !added && approved != null ? approved - l.quantity : 0;
                              const diff = l.discrepancy_quantity ?? 0;
                              return <tr key={l.id}>
                                <td>
                                  <strong>{productName(l.product_id, l.manual_item_name)}</strong>{' '}
                                  {!manual && <span style={{ color: 'var(--text-muted)', fontSize: 11.5 }}>{productSku(l.product_id)}</span>}
                                  {manual && <span className="badge badge-muted" style={{ marginLeft: 5, fontSize: 10 }}>Manual / Non-inventory</span>}
                                  {added && <span className="badge badge-accent" style={{ marginLeft: 5, fontSize: 10 }}>Added during review</span>}
                                  {manual && l.manual_uom && <span style={{ color: 'var(--text-muted)', fontSize: 11.5, marginLeft: 5 }}>UOM: {l.manual_uom}</span>}
                                </td>
                                <td style={{ textAlign: 'right' }}>{added ? '—' : `${l.quantity}${manual && l.manual_uom ? ` ${l.manual_uom}` : ''}`}</td>
                                <td style={{ textAlign: 'right', fontWeight: 700 }}>
                                  {approved == null ? '—' : <>{approved}{manual && l.manual_uom ? ` ${l.manual_uom}` : ''}{!added && adjustment !== 0 && <span style={{ marginLeft: 5, color: adjustment > 0 ? 'var(--success)' : 'var(--accent)', fontSize: 11 }}>({adjustment > 0 ? '+' : ''}{adjustment})</span>}</>}
                                </td>
                                <td style={{ textAlign: 'right', fontWeight: 700 }}>{l.received_quantity == null ? '—' : `${l.received_quantity}${manual && l.manual_uom ? ` ${l.manual_uom}` : ''}`}</td>
                                <td style={{ textAlign: 'right', color: diff === 0 ? 'var(--text-muted)' : 'var(--danger)' }}>{l.received_quantity == null ? '—' : `${diff > 0 ? '+' : ''}${diff}`}{l.discrepancy_resolution ? ` · ${l.discrepancy_resolution}` : ''}</td>
                              </tr>;
                            })}</tbody>
                          </table>
                          {req.note && <p style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 8 }}><strong>Note:</strong> {req.note}</p>}
                          {req.rejection_reason && <p style={{ fontSize: 12, color: 'var(--danger)', marginTop: 8 }}><strong>Rejected:</strong> {req.rejection_reason}</p>}
                          {req.approved_at && <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6 }}>{req.dispatched_at ? 'Dispatched' : 'Approved'} by {userName(req.approved_by)} on {new Date(req.approved_at).toLocaleString()}</p>}
                          {req.received_at && <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 2 }}>Received by {userName(req.received_by)} on {new Date(req.received_at).toLocaleString()}{req.receipt_note ? ` — ${req.receipt_note}` : ''}</p>}
                        </div>
                      </td></tr>}
                    </React.Fragment>;
                  })}
                </tbody>
              </table>}
        </div>
      </div>

      {createOpen && <Modal title="New Stock Transfer" maxWidth={650} onClose={() => setCreateOpen(false)}
        footer={<><button className="btn btn-secondary" onClick={() => setCreateOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={() => void handleCreate()} disabled={saving}>{saving ? 'Submitting…' : 'Submit Request'}</button></>}>
        <div className="form-grid">
          {createErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{createErr}</div></div>}
          {isStaff ? <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>
            Requesting into {myStores.length > 1 ? <select value={destId} onChange={e => setDestId(e.target.value)} style={{ width: 'auto', display: 'inline-block', margin: '0 4px' }}><option value="">— choose a store —</option>{myStores.map(m => <option key={m.store_id} value={m.store_id}>{m.store_name}</option>)}</select>
              : <strong>{stores.find(s => s.id === selectedStaffDestId)?.name ?? 'No store assigned'}</strong>}.
            An Owner or Manager chooses the product source location(s) during Review.
          </div></div> : <>
            <div className="form-group"><label>Transfer Type</label><select value={tType} onChange={e => { setTType(e.target.value as TransferType); setSourceId(''); setDestId(''); }}>{TRANSFER_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}</select></div>
            <div className="form-grid-2">
              <div className="form-group"><label>From ({cfg.src})</label><select value={sourceId} onChange={e => { setSourceId(e.target.value); if (e.target.value === destId) setDestId(''); }}><option value="">— Select —</option>{sourceOptions.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}</select></div>
              <div className="form-group"><label>To ({cfg.dest})</label><select value={destId} onChange={e => setDestId(e.target.value)}><option value="">— Select —</option>{destOptions.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}</select></div>
            </div>
          </>}

          <div><label>Items</label><div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {lines.map((line, i) => <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              {line.line_kind === 'product' ? <div style={{ flex: 1 }}><SearchSelect
                options={productOptionsForStore(isStaff ? selectedStaffDestId : (cfg.dest === 'store' ? destId : null))}
                value={line.product_id ?? ''}
                exclude={lines.filter((x, j) => j !== i && x.line_kind === 'product').map(x => x.product_id ?? '').filter(Boolean)}
                onChange={v => setLines(ls => ls.map((l, j) => j === i ? { ...l, product_id: v } : l))}
                placeholder="Search product name or SKU…" /></div>
                : <><input style={{ flex: 1 }} value={line.manual_item_name ?? ''} onChange={e => setLines(ls => ls.map((l, j) => j === i ? { ...l, manual_item_name: e.target.value } : l))} placeholder="Manual item name (e.g. A4 Paper)" />
                  <input style={{ width: 105 }} value={line.manual_uom ?? ''} onChange={e => setLines(ls => ls.map((l, j) => j === i ? { ...l, manual_uom: e.target.value } : l))} placeholder="Unit / UOM" /></>}
              <input type="number" min={1} value={line.quantity || ''} placeholder="Qty" style={{ width: 90 }} onChange={e => setLines(ls => ls.map((l, j) => j === i ? { ...l, quantity: +e.target.value } : l))} />
              <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setLines(ls => ls.filter((_, j) => j !== i))} disabled={lines.length === 1}><X size={13} /></button>
            </div>)}
          </div><div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
              <button className="btn btn-secondary btn-sm" onClick={() => setLines(ls => [...ls, newProductLine()])}><Plus size={13} /> Add Product</button>
              <button className="btn btn-secondary btn-sm" onClick={() => setLines(ls => [...ls, newManualLine()])}><Plus size={13} /> Add Manual Item</button>
            </div></div>
          <div className="form-group"><label>Note (optional)</label><input value={note} onChange={e => setNote(e.target.value)} placeholder="Reason for transfer" /></div>
          <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Normal Products require a destination-store price and use inventory. Manual items exist only on this transfer and never create a Product, SKU, price, inventory row or stock movement.</div></div>
        </div>
      </Modal>}

      {approveReq && <Modal title="Review Transfer Request" maxWidth={780} onClose={() => setApproveReq(null)}
        footer={<><button className="btn btn-danger" onClick={() => void handleReject()} disabled={approveBusy}><X size={15} /> Reject</button><button className="btn btn-primary" onClick={() => void handleApprove()} disabled={approveBusy}><Check size={15} /> Approve & Dispatch</button></>}>
        <div className="form-grid">
          {approveErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{approveErr}</div></div>}
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', margin: 0 }}>
            {approveReq.source_id ? locName(approveReq.source_type, approveReq.source_id) : <em>source will be allocated below</em>} → <strong>{locName(approveReq.dest_type, approveReq.dest_id)}</strong>
          </p>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {reviewLines.map(line => {
              const sources = reviewSources[line.key] ?? [];
              const got = allocFor(line.key);
              const adjustment = line.line_id && !line.added_by_approver ? line.approved_quantity - line.requested_quantity : 0;
              return <div key={line.key} style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
                <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 8 }}>
                  <div style={{ flex: 1 }}>
                    {line.line_kind === 'product' ? (line.line_id ? <>
                      <strong>{productName(line.product_id)}</strong> <span style={{ color: 'var(--text-muted)', fontSize: 11.5 }}>{productSku(line.product_id)}</span>
                    </> : <SearchSelect
                      options={reviewProductOptions}
                      value={line.product_id ?? ''}
                      exclude={reviewLines.filter(x => x.key !== line.key && x.line_kind === 'product').map(x => x.product_id ?? '').filter(Boolean)}
                      onChange={v => {
                        setReviewLines(ls => ls.map(x => x.key === line.key ? { ...x, product_id: v } : x));
                        void loadSourcesForAddedProduct(line.key, v, line.approved_quantity);
                      }} placeholder="Search product to add…" />)
                      : <div style={{ display: 'flex', gap: 6 }}>
                        <input style={{ flex: 1 }} value={line.manual_item_name} onChange={e => setReviewLines(ls => ls.map(x => x.key === line.key ? { ...x, manual_item_name: e.target.value } : x))} placeholder="Manual item name" />
                        <input style={{ width: 110 }} value={line.manual_uom} onChange={e => setReviewLines(ls => ls.map(x => x.key === line.key ? { ...x, manual_uom: e.target.value } : x))} placeholder="Unit / UOM" />
                      </div>}
                    <div style={{ marginTop: 3, display: 'flex', gap: 5, alignItems: 'center', flexWrap: 'wrap' }}>
                      {line.line_kind === 'manual' && <span className="badge badge-muted" style={{ fontSize: 10 }}>Manual / Non-inventory</span>}
                      {(!line.line_id || line.added_by_approver) && <span className="badge badge-accent" style={{ fontSize: 10 }}>Added during review</span>}
                      {!!line.line_id && !line.added_by_approver && <span style={{ color: 'var(--text-muted)', fontSize: 11.5 }}>Requested: {line.requested_quantity}{line.line_kind === 'manual' && line.manual_uom ? ` ${line.manual_uom}` : ''}</span>}
                      {adjustment !== 0 && <span style={{ fontSize: 11.5, fontWeight: 600, color: adjustment > 0 ? 'var(--success)' : 'var(--accent)' }}>Adjustment: {adjustment > 0 ? '+' : ''}{adjustment}</span>}
                    </div>
                  </div>
                  <div><label style={{ fontSize: 11.5 }}>Approved</label><input type="number" min={0} value={line.approved_quantity} onChange={e => updateReviewQty(line.key, +e.target.value)} style={{ width: 90 }} /></div>
                  {!line.line_id && <button className="btn btn-secondary btn-sm btn-icon" onClick={() => {
                    setReviewLines(ls => ls.filter(x => x.key !== line.key));
                    setReviewSources(s => { const n = { ...s }; delete n[line.key]; return n; });
                    setAlloc(a => { const n = { ...a }; delete n[line.key]; return n; });
                  }}><Trash2 size={13} /></button>}
                </div>

                {line.line_kind === 'manual' ? <div className="alert alert-info" style={{ marginBottom: 0, padding: '7px 9px' }}><span>ℹ️</span><div>Non-inventory item — no stock allocation required. It will still be marked In Transit and received by line.</div></div>
                  : line.product_id && <>
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, marginBottom: 5 }}><strong>Source allocation</strong><span style={{ color: got === line.approved_quantity ? 'var(--success)' : 'var(--danger)', fontWeight: 600 }}>{got} of {line.approved_quantity} allocated{got === line.approved_quantity ? ' ✓' : ''}</span></div>
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(245px, 1fr))', gap: 7 }}>
                      {sources.map(src => {
                        const sourceKey = `${src.source_type}:${src.source_id}`;
                        const val = alloc[line.key]?.[sourceKey] ?? 0;
                        return <div key={sourceKey} style={{ border: '1px solid var(--border)', borderRadius: 6, padding: 7, opacity: src.available <= 0 ? 0.55 : 1 }}>
                          <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                            <div style={{ flex: 1, minWidth: 0 }}>
                              <div style={{ fontWeight: 600, fontSize: 12.5, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{src.source_type === 'store' ? '🏪' : '🏭'} {src.source_name}</div>
                              <div style={{ fontSize: 10.8, color: 'var(--text-muted)' }}>On Hand: {src.on_hand} · Reserved: {src.reserved} · <strong>Available: {src.available}</strong></div>
                            </div>
                            <input type="number" min={0} max={src.available} disabled={src.available <= 0} value={val || ''} placeholder="0" style={{ width: 72 }} onChange={e => {
                              const q = Math.max(0, Math.min(Math.floor(Number(e.target.value) || 0), src.available));
                              setAlloc(a => ({ ...a, [line.key]: { ...(a[line.key] ?? {}), [sourceKey]: q } }));
                            }} />
                          </div>
                        </div>;
                      })}
                    </div>
                    {sources.length === 0 && <div style={{ color: 'var(--danger)', fontSize: 12 }}>No valid source locations were returned for this product.</div>}
                  </>}
              </div>;
            })}
          </div>

          <div style={{ display: 'flex', gap: 8 }}>
            <button className="btn btn-secondary btn-sm" onClick={() => setReviewLines(ls => [...ls, { key: clientKey(), line_id: null, line_kind: 'product', product_id: '', manual_item_name: '', manual_uom: '', requested_quantity: 0, approved_quantity: 1, added_by_approver: true }])}><Plus size={13} /> Add Product</button>
            <button className="btn btn-secondary btn-sm" onClick={() => setReviewLines(ls => [...ls, { key: clientKey(), line_id: null, line_kind: 'manual', product_id: null, manual_item_name: '', manual_uom: '', requested_quantity: 0, approved_quantity: 1, added_by_approver: true }])}><Plus size={13} /> Add Manual Item</button>
          </div>
          <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Automatic allocation uses the locations with the largest Available quantity first. You can change the split manually. Approved quantity may be lower than, equal to, or greater than the Staff request.</div>
          <div className="form-group"><label>Approval note (optional)</label><input value={approveNote} onChange={e => setApproveNote(e.target.value)} /></div>
          <div className="form-group"><label>Rejection reason (required only if rejecting)</label><input value={rejectReason} onChange={e => setRejectReason(e.target.value)} placeholder="Why is this being rejected?" /></div>
        </div>
      </Modal>}

      {editReq && <Modal title={`Edit Transfer — ${TRANSFER_TYPES.find(t => t.value === editReq.transfer_type)?.label ?? ''}`} maxWidth={660} onClose={() => setEditReq(null)}
        footer={<><button className="btn btn-secondary" onClick={() => setEditReq(null)}>Cancel</button><button className="btn btn-primary" onClick={() => void saveEdit()} disabled={editBusy}>{editBusy ? 'Saving…' : 'Save Changes'}</button></>}>
        <div className="form-grid">
          {editErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{editErr}</div></div>}
          {!canApprove && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>You can edit Products, Manual Items and the note. An unsourced Staff request is not stock-validated until an Owner/Manager allocates a source during Review.</div></div>}
          {canApprove && <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Source</label><select value={editSourceId ? `${editSourceType}:${editSourceId}` : ''} onChange={e => { if (!e.target.value) return; const [ty, id] = e.target.value.split(':'); setEditSourceType(ty as LocationType); setEditSourceId(id); }}>
              {!editReq.source_id && <option value="">— Deferred; choose during Review —</option>}{warehouses.map(w => <option key={w.id} value={`warehouse:${w.id}`}>🏭 {w.name}</option>)}{stores.map(s => <option key={s.id} value={`store:${s.id}`}>🏪 {s.name}</option>)}</select></div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Destination</label><select value={`${editDestType}:${editDestId}`} onChange={e => { const [ty, id] = e.target.value.split(':'); setEditDestType(ty as LocationType); setEditDestId(id); }}>{warehouses.map(w => <option key={w.id} value={`warehouse:${w.id}`}>🏭 {w.name}</option>)}{stores.map(s => <option key={s.id} value={`store:${s.id}`}>🏪 {s.name}</option>)}</select></div>
          </div>}
          <div><label>Items</label><div style={{ display: 'flex', flexDirection: 'column', gap: 7, marginTop: 5 }}>
            {editLines.map((l, i) => <div key={i} style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              {l.line_kind === 'product' ? <div style={{ flex: 1 }}><SearchSelect
                options={productOptionsForStore(editDestType === 'store' ? editDestId : null)} value={l.product_id ?? ''}
                exclude={editLines.filter((x, j) => j !== i && x.line_kind === 'product').map(x => x.product_id ?? '').filter(Boolean)}
                onChange={v => setEditLines(ls => ls.map((x, j) => j === i ? { ...x, product_id: v } : x))} placeholder="Search product name or SKU…" /></div>
                : <><input style={{ flex: 1 }} value={l.manual_item_name ?? ''} onChange={e => setEditLines(ls => ls.map((x, j) => j === i ? { ...x, manual_item_name: e.target.value } : x))} placeholder="Manual item name" /><input style={{ width: 105 }} value={l.manual_uom ?? ''} onChange={e => setEditLines(ls => ls.map((x, j) => j === i ? { ...x, manual_uom: e.target.value } : x))} placeholder="Unit / UOM" /></>}
              <input type="number" min={1} value={l.quantity || ''} onChange={e => setEditLines(ls => ls.map((x, j) => j === i ? { ...x, quantity: +e.target.value } : x))} style={{ width: 90 }} placeholder="Qty" />
              <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setEditLines(ls => ls.filter((_, j) => j !== i))} disabled={editLines.length === 1}><X size={13} /></button>
            </div>)}
          </div><div style={{ display: 'flex', gap: 8, marginTop: 8 }}><button className="btn btn-secondary btn-sm" onClick={() => setEditLines(ls => [...ls, newProductLine()])}><Plus size={13} /> Add Product</button><button className="btn btn-secondary btn-sm" onClick={() => setEditLines(ls => [...ls, newManualLine()])}><Plus size={13} /> Add Manual Item</button></div></div>
          <div className="form-group" style={{ marginBottom: 0 }}><label>Note</label><input value={editNote} onChange={e => setEditNote(e.target.value)} placeholder="Optional note" /></div>
          <div className="form-group" style={{ marginBottom: 0 }}><label>Edit reason *</label><textarea rows={2} value={editReason} onChange={e => setEditReason(e.target.value)} placeholder="Why is this transfer being edited?" /></div>
        </div>
      </Modal>}

      {historyReq && <Modal title="Edit history" maxWidth={520} onClose={() => setHistoryReq(null)} footer={<button className="btn btn-secondary" onClick={() => setHistoryReq(null)}>Close</button>}>
        {revisions.length === 0 ? <div style={{ color: 'var(--text-muted)' }}>No edits recorded.</div> : <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {revisions.map((r, i) => <div key={i} style={{ borderLeft: '2px solid var(--primary)', paddingLeft: 10 }}><div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>v{r.version} → v{r.version + 1} · {new Date(r.created_at).toLocaleString('en-GB')} · {r.editor ?? '—'}</div><div style={{ fontSize: 13 }}>{r.reason}</div>{r.changed_summary && Object.keys(r.changed_summary).length > 0 && <div style={{ fontSize: 11.5, color: 'var(--text-secondary)', marginTop: 2 }}>Changed: {Object.keys(r.changed_summary).join(', ')}</div>}</div>)}
        </div>}
      </Modal>}

      {receiveReq && <Modal title="Confirm Receipt" maxWidth={620} onClose={() => setReceiveReq(null)} footer={<><button className="btn btn-secondary" onClick={confirmAllReceived} disabled={receiveBusy}><Check size={14} /> Confirm All Received</button><button className="btn btn-primary" onClick={() => void saveReceive()} disabled={receiveBusy}>{receiveBusy ? 'Saving…' : 'Confirm Receipt'}</button></>}>
        <div className="form-grid">
          {receiveErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{receiveErr}</div></div>}
          <div className="alert alert-info" style={{ marginBottom: 0 }}><span><Truck size={15} /></span><div>Enter the actual received quantity for every line. Product inventory is added to the destination now. Manual items are recorded as received but never change inventory.</div></div>
          <p style={{ fontSize: 13, color: 'var(--text-secondary)', margin: 0 }}>{receiveReq.source_id ? locName(receiveReq.source_type, receiveReq.source_id) : 'Multiple / non-inventory source'} → <strong>{locName(receiveReq.dest_type, receiveReq.dest_id)}</strong></p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {(linesByReq[receiveReq.id] ?? []).filter(l => (l.in_transit_quantity ?? 0) > 0).map(l => {
              const approved = l.approved_quantity ?? l.in_transit_quantity ?? 0;
              const actual = receiveQty[l.id] ?? 0;
              const mismatch = actual !== approved;
              const manual = l.line_kind === 'manual' || !l.product_id;
              return <div key={l.id} style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                <div style={{ flex: 1 }}><strong>{productName(l.product_id, l.manual_item_name)}</strong>{manual && <span className="badge badge-muted" style={{ marginLeft: 5, fontSize: 10 }}>Manual / Non-inventory</span>} <span style={{ color: 'var(--text-muted)', fontSize: 12 }}>approved {approved}{manual && l.manual_uom ? ` ${l.manual_uom}` : ''}</span></div>
                <input type="number" min={0} value={actual} style={{ width: 90 }} onChange={e => setReceiveQty(q => ({ ...q, [l.id]: Math.max(0, +e.target.value) }))} />
                {mismatch && <span className="badge badge-danger" style={{ fontSize: 10 }}>{actual > approved ? `+${actual - approved}` : actual - approved}</span>}
              </div>;
            })}
          </div>
          {receiveHasMismatch() ? <div className="form-group" style={{ marginBottom: 0 }}><label>Mismatch reason *</label><textarea rows={2} value={receiveNote} onChange={e => setReceiveNote(e.target.value)} placeholder="Explain the difference" /></div>
            : <div className="form-group" style={{ marginBottom: 0 }}><label>Notes (optional)</label><input value={receiveNote} onChange={e => setReceiveNote(e.target.value)} /></div>}
        </div>
      </Modal>}

      {resolveReq && <Modal title="Resolve Discrepancy" maxWidth={640} onClose={() => setResolveReq(null)} footer={<><button className="btn btn-secondary" onClick={() => setResolveReq(null)}>Cancel</button><button className="btn btn-primary" onClick={() => void saveResolve()} disabled={resolveBusy}>{resolveBusy ? 'Saving…' : 'Resolve & Complete'}</button></>}>
        <div className="form-grid">
          {resolveErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{resolveErr}</div></div>}
          <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Manual-item discrepancies are acknowledgement-only. Inventory correction options are available only for real Product lines.</div></div>
          {(linesByReq[resolveReq.id] ?? []).filter(l => (l.discrepancy_quantity ?? 0) !== 0 && !l.discrepancy_resolved_at).map(l => {
            const diff = l.discrepancy_quantity ?? 0;
            const manual = l.line_kind === 'manual' || !l.product_id;
            const r = resolutions[l.id] ?? { resolution: diff > 0 ? 'accept_surplus' : 'accept_loss', reason: '' };
            const opts = manual
              ? RESOLUTION_OPTIONS.filter(o => o.value === 'accept_loss' || o.value === 'accept_surplus' || o.value === 'other')
              : RESOLUTION_OPTIONS.filter(o => diff > 0 ? o.value !== 'accept_loss' : o.value !== 'accept_surplus' && o.value !== 'return_excess');
            return <div key={l.id} style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
              <div style={{ fontSize: 13, marginBottom: 6 }}><strong>{productName(l.product_id, l.manual_item_name)}</strong>{manual && <span className="badge badge-muted" style={{ marginLeft: 5, fontSize: 10 }}>Manual / Non-inventory</span>} <span className="badge badge-danger" style={{ fontSize: 10 }}>{diff > 0 ? `+${diff} extra` : `${Math.abs(diff)} missing`}</span><span style={{ color: 'var(--text-muted)', fontSize: 11.5, marginLeft: 6 }}>approved {l.approved_quantity ?? 0} · received {l.received_quantity ?? 0}</span></div>
              <div style={{ display: 'flex', gap: 8 }}><select value={r.resolution} style={{ flex: 1 }} onChange={e => setResolutions(s => ({ ...s, [l.id]: { ...r, resolution: e.target.value } }))}>{opts.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}</select><input placeholder="Reason (optional)" value={r.reason} style={{ flex: 1 }} onChange={e => setResolutions(s => ({ ...s, [l.id]: { ...r, reason: e.target.value } }))} /></div>
            </div>;
          })}
          <div className="form-group" style={{ marginBottom: 0 }}><label>Overall note (optional)</label><input value={resolveNote} onChange={e => setResolveNote(e.target.value)} /></div>
        </div>
      </Modal>}
    </div>
  );
};

export default TransfersPage;
