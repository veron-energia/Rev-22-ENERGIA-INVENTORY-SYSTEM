import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Warehouse, WarehouseInventory, Product,
  canManageWarehouseStock, isOwnerOrManager, isManagerOrAbove,
} from '../types';
import { Modal, NoAccess, RoleGate } from '../components/ui';
import { Plus, PackagePlus, RefreshCw, Warehouse as WarehouseIcon, AlertTriangle, SlidersHorizontal } from 'lucide-react';

interface Row {
  product: Product;
  inv: WarehouseInventory | null;
}

const WarehouseInventoryPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isManagerOrAbove(profile?.role) && profile?.role !== 'inventory_manager') {
    return <NoAccess message="Warehouse inventory is available to Owners, Managers, and Inventory Managers." />;
  }
  const canStockIn = canManageWarehouseStock(profile?.role);
  const canSetThreshold = isOwnerOrManager(profile?.role);

  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [selectedWh, setSelectedWh] = useState<string>('');
  const [products, setProducts] = useState<Product[]>([]);
  const [inventory, setInventory] = useState<WarehouseInventory[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [loadErr, setLoadErr] = useState<string | null>(null);

  // Stock-in modal
  const [stockInOpen, setStockInOpen] = useState(false);
  const [siForm, setSiForm] = useState({ product_id: '', quantity: 0, reason: '', note: '', reference: '' });
  const [siSaving, setSiSaving] = useState(false);
  const [siErr, setSiErr] = useState<string | null>(null);

  // Threshold modal
  const [thresholdRow, setThresholdRow] = useState<Row | null>(null);
  const [thresholdVal, setThresholdVal] = useState(0);

  const loadBase = useCallback(async () => {
    const [{ data: wh }, { data: prod }] = await Promise.all([
      supabase.from('warehouses').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
    ]);
    setWarehouses((wh as Warehouse[]) ?? []);
    setProducts((prod as Product[]) ?? []);
    if (wh && wh.length > 0 && !selectedWh) setSelectedWh(wh[0].id);
  }, [selectedWh]);

  const loadInventory = useCallback(async (whId: string) => {
    if (!whId) return;
    setLoading(true);
    const { data, error } = await supabase.from('warehouse_inventory').select('*').eq('warehouse_id', whId);
    if (error) { console.error('warehouse_inventory read failed:', error); setLoadErr(error.message); }
    else setLoadErr(null);
    setInventory((data as WarehouseInventory[]) ?? []);
    setLoading(false);
  }, []);

  useEffect(() => { loadBase(); }, [loadBase]);
  useEffect(() => { if (selectedWh) loadInventory(selectedWh); }, [selectedWh, loadInventory]);

  const rows: Row[] = products.map(p => ({
    product: p,
    inv: inventory.find(i => i.product_id === p.id) ?? null,
  })).filter(r => {
    const q = search.toLowerCase();
    return !q || r.product.name.toLowerCase().includes(q) || r.product.sku.toLowerCase().includes(q);
  });

  const handleStockIn = async () => {
    if (!siForm.product_id) { setSiErr('Select a product.'); return; }
    if (siForm.quantity <= 0) { setSiErr('Quantity must be greater than zero.'); return; }
    if (!siForm.reason.trim()) { setSiErr('A reason is required.'); return; }
    setSiSaving(true); setSiErr(null);
    const { error } = await supabase.rpc('warehouse_stock_in', {
      p_warehouse_id: selectedWh,
      p_product_id: siForm.product_id,
      p_quantity: siForm.quantity,
      p_reason: siForm.reason.trim(),
      p_note: siForm.note.trim() || null,
      p_reference: siForm.reference.trim() || null,
    });
    setSiSaving(false);
    if (error) { setSiErr(error.message); return; }
    setStockInOpen(false);
    setSiForm({ product_id: '', quantity: 0, reason: '', note: '', reference: '' });
    loadInventory(selectedWh);
  };

  const openThreshold = (r: Row) => { setThresholdRow(r); setThresholdVal(r.inv?.low_stock_threshold ?? 0); };
  const handleThreshold = async () => {
    if (!thresholdRow) return;
    const { error } = await supabase.rpc('set_low_stock_threshold', {
      p_location_type: 'warehouse', p_location_id: selectedWh,
      p_product_id: thresholdRow.product.id, p_threshold: thresholdVal,
    });
    if (error) { alert(error.message); return; }
    setThresholdRow(null);
    loadInventory(selectedWh);
  };

  const stockStatus = (r: Row) => {
    const qty = r.inv?.current_qty ?? 0;
    const thr = r.inv?.low_stock_threshold ?? 0;
    if (qty === 0) return { label: 'Out of Stock', cls: 'badge-danger' };
    if (thr > 0 && qty <= thr) return { label: 'Low Stock', cls: 'badge-accent' };
    return { label: 'Normal', cls: 'badge-success' };
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Warehouse Inventory</h2><p>Stock balances per warehouse. Add stock manually and set low-stock thresholds.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={() => loadInventory(selectedWh)}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          {canStockIn && <button className="btn btn-primary" onClick={() => { setSiForm({ product_id: '', quantity: 0, reason: '', note: '', reference: '' }); setSiErr(null); setStockInOpen(true); }} disabled={!selectedWh}><PackagePlus size={16} /> Stock In</button>}
        </div>
      </div>

      {/* Warehouse selector */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
        {warehouses.map(w => (
          <button key={w.id} onClick={() => setSelectedWh(w.id)}
            className={`btn btn-sm ${selectedWh === w.id ? 'btn-primary' : 'btn-secondary'}`}>
            <WarehouseIcon size={14} /> {w.name}
          </button>
        ))}
        {warehouses.length === 0 && <p style={{ color: 'var(--text-muted)', fontSize: 13 }}>No active warehouses. Add one under Warehouses first.</p>}
      </div>

      {selectedWh && (
        <>
          {loadErr && <div className="alert alert-danger"><span>⚠</span><div>Couldn't read warehouse stock: {loadErr}. If this mentions a policy, run <code>07_phase2_fix_rls.sql</code>.</div></div>}
          <div style={{ marginBottom: 14, maxWidth: 360 }}>
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search product or SKU…" />
          </div>

          <div className="card">
            <div className="table-wrap">
              {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
              : rows.length === 0 ? <div className="empty-state"><WarehouseIcon size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No products</p></div>
              : (
                <table>
                  <thead><tr><th>Product</th><th>SKU</th><th style={{ textAlign: 'right' }}>Stock</th><th>Threshold</th><th>Status</th>{canSetThreshold && <th></th>}</tr></thead>
                  <tbody>
                    {rows.map(r => {
                      const st = stockStatus(r);
                      return (
                        <tr key={r.product.id}>
                          <td><strong>{r.product.name}</strong></td>
                          <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{r.product.sku}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700, fontSize: 15 }}>{r.inv?.current_qty ?? 0}</td>
                          <td>{r.inv?.low_stock_threshold ? r.inv.low_stock_threshold : <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                          <td><span className={`badge ${st.cls}`}>{st.label === 'Low Stock' && <AlertTriangle size={11} />}{st.label}</span></td>
                          {canSetThreshold && <td><button className="btn btn-secondary btn-sm" onClick={() => openThreshold(r)}><SlidersHorizontal size={13} /> Threshold</button></td>}
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </div>
          </div>
        </>
      )}

      {/* Stock-in modal */}
      {stockInOpen && (
        <Modal title="Manual Warehouse Stock-In" maxWidth={460} onClose={() => setStockInOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setStockInOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleStockIn} disabled={siSaving}>{siSaving ? 'Saving…' : 'Add Stock'}</button></>}>
          <div className="form-grid">
            {siErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{siErr}</div></div>}
            <div className="form-group">
              <label>Product *</label>
              <select value={siForm.product_id} onChange={e => setSiForm(f => ({ ...f, product_id: e.target.value }))}>
                <option value="">— Select product —</option>
                {products.map(p => <option key={p.id} value={p.id}>{p.name} ({p.sku})</option>)}
              </select>
            </div>
            <div className="form-group"><label>Quantity *</label><input type="number" min={1} value={siForm.quantity || ''} onChange={e => setSiForm(f => ({ ...f, quantity: +e.target.value }))} placeholder="0" /></div>
            <div className="form-group"><label>Reason *</label><input value={siForm.reason} onChange={e => setSiForm(f => ({ ...f, reason: e.target.value }))} placeholder="e.g. New delivery from supplier" /></div>
            <div className="form-grid-2">
              <div className="form-group"><label>Reference No.</label><input value={siForm.reference} onChange={e => setSiForm(f => ({ ...f, reference: e.target.value }))} placeholder="Optional" /></div>
              <div className="form-group"><label>Note</label><input value={siForm.note} onChange={e => setSiForm(f => ({ ...f, note: e.target.value }))} placeholder="Optional" /></div>
            </div>
          </div>
        </Modal>
      )}

      {/* Threshold modal */}
      {thresholdRow && (
        <Modal title={`Low Stock Threshold — ${thresholdRow.product.name}`} maxWidth={380} onClose={() => setThresholdRow(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setThresholdRow(null)}>Cancel</button><button className="btn btn-primary" onClick={handleThreshold}>Save</button></>}>
          <div className="form-group">
            <label>Alert when stock is at or below</label>
            <input type="number" min={0} value={thresholdVal} onChange={e => setThresholdVal(+e.target.value)} autoFocus />
            <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 5 }}>Set to 0 to disable the low-stock alert for this product in this warehouse.</span>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default WarehouseInventoryPage;
