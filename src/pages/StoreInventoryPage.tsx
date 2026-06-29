import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, StoreInventory, Product, isOwnerOrManager } from '../types';
import { Modal } from '../components/ui';
import { RefreshCw, Store as StoreIcon, AlertTriangle, SlidersHorizontal } from 'lucide-react';

interface Row { product: Product; inv: StoreInventory | null; }

const StoreInventoryPage: React.FC = () => {
  const { profile } = useAuth();
  const canSetThreshold = isOwnerOrManager(profile?.role);

  const [stores, setStores] = useState<Store[]>([]);
  const [selectedStore, setSelectedStore] = useState<string>('');
  const [products, setProducts] = useState<Product[]>([]);
  const [inventory, setInventory] = useState<StoreInventory[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [thresholdRow, setThresholdRow] = useState<Row | null>(null);
  const [thresholdVal, setThresholdVal] = useState(0);

  const loadBase = useCallback(async () => {
    const [{ data: st }, { data: prod }] = await Promise.all([
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
    ]);
    setStores((st as Store[]) ?? []);
    setProducts((prod as Product[]) ?? []);
    if (st && st.length > 0 && !selectedStore) setSelectedStore(st[0].id);
  }, [selectedStore]);

  const loadInventory = useCallback(async (storeId: string) => {
    if (!storeId) return;
    setLoading(true);
    const { data, error } = await supabase.from('store_inventory').select('*').eq('store_id', storeId);
    if (error) { console.error('store_inventory read failed:', error); setLoadErr(error.message); }
    else setLoadErr(null);
    setInventory((data as StoreInventory[]) ?? []);
    setLoading(false);
  }, []);

  useEffect(() => { loadBase(); }, [loadBase]);
  useEffect(() => { if (selectedStore) loadInventory(selectedStore); }, [selectedStore, loadInventory]);

  const rows: Row[] = products.map(p => ({
    product: p, inv: inventory.find(i => i.product_id === p.id) ?? null,
  })).filter(r => {
    const q = search.toLowerCase();
    return !q || r.product.name.toLowerCase().includes(q) || r.product.sku.toLowerCase().includes(q);
  });

  const openThreshold = (r: Row) => { setThresholdRow(r); setThresholdVal(r.inv?.low_stock_threshold ?? 0); };
  const handleThreshold = async () => {
    if (!thresholdRow) return;
    const { error } = await supabase.rpc('set_low_stock_threshold', {
      p_location_type: 'store', p_location_id: selectedStore,
      p_product_id: thresholdRow.product.id, p_threshold: thresholdVal,
    });
    if (error) { alert(error.message); return; }
    setThresholdRow(null);
    loadInventory(selectedStore);
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
        <div><h2>Store Inventory</h2><p>Stock balances per store. Stores receive stock via approved transfers from a warehouse.</p></div>
        <button className="btn btn-secondary" onClick={() => loadInventory(selectedStore)}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
      </div>

      <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
        {stores.map(s => (
          <button key={s.id} onClick={() => setSelectedStore(s.id)} className={`btn btn-sm ${selectedStore === s.id ? 'btn-primary' : 'btn-secondary'}`}>
            <StoreIcon size={14} /> {s.name}
          </button>
        ))}
        {stores.length === 0 && <p style={{ color: 'var(--text-muted)', fontSize: 13 }}>No stores available to you.</p>}
      </div>

      {selectedStore && (
        <>
          {loadErr && <div className="alert alert-danger"><span>⚠</span><div>Couldn't read store stock: {loadErr}. If this mentions a policy, run <code>07_phase2_fix_rls.sql</code>.</div></div>}
          <div style={{ marginBottom: 14, maxWidth: 360 }}>
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search product or SKU…" />
          </div>
          <div className="card">
            <div className="table-wrap">
              {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
              : rows.length === 0 ? <div className="empty-state"><StoreIcon size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No products</p></div>
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

      {thresholdRow && (
        <Modal title={`Low Stock Threshold — ${thresholdRow.product.name}`} maxWidth={380} onClose={() => setThresholdRow(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setThresholdRow(null)}>Cancel</button><button className="btn btn-primary" onClick={handleThreshold}>Save</button></>}>
          <div className="form-group">
            <label>Alert when stock is at or below</label>
            <input type="number" min={0} value={thresholdVal} onChange={e => setThresholdVal(+e.target.value)} autoFocus />
            <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 5 }}>Set to 0 to disable the alert for this product in this store.</span>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default StoreInventoryPage;
