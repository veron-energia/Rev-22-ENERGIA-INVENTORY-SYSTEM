import React, { useEffect, useState, useCallback } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, StoreInventory, Product, isOwnerOrManager, canManageWarehouseStock } from '../types';
import { Modal } from '../components/ui';
import { RefreshCw, Store as StoreIcon, AlertTriangle, SlidersHorizontal, MinusCircle, HandHelping } from 'lucide-react';
import RecordUseModal from '../components/stock-loans/RecordUseModal';
import LendModal from '../components/stock-loans/LendModal';
import TakeBackModal from '../components/stock-loans/TakeBackModal';
import OnLoanPanel from '../components/stock-loans/OnLoanPanel';
import { useStockLoans } from '../components/stock-loans/useStockLoans';
import { StockLoan } from '../lib/stock-loans/stockLoans';

interface Row { product: Product; inv: StoreInventory | null; }

const StoreInventoryPage: React.FC = () => {
  const { profile } = useAuth();
  const canSetThreshold = isOwnerOrManager(profile?.role);

  const [stores, setStores] = useState<Store[]>([]);
  const [selectedStore, setSelectedStore] = useState<string>('');
  const [products, setProducts] = useState<Product[]>([]);
  // Recording a use is a real consumption (demo, sample, tester), not a
  // counting correction — so staff can do it themselves, unlike an adjustment.
  // Every line is recorded in one call (401), so a refused line records none.
  const [useOpen, setUseOpen] = useState(false);
  // Lending: stock that is coming back. It leaves the shelf now and shows on
  // the On loan tab until it is taken back (401).
  const [lendOpen, setLendOpen] = useState(false);
  const [takeBack, setTakeBack] = useState<StockLoan | null>(null);
  const [tab, setTab] = useState<'stock' | 'loans'>('stock');
  const [showClosed, setShowClosed] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);
  const canWarehouse = canManageWarehouseStock(profile?.role);
  const [inventory, setInventory] = useState<StoreInventory[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [stockFilter, setStockFilter] = useState<'all' | 'important' | 'in' | 'out' | 'low'>('all');
  const [loadErr, setLoadErr] = useState<string | null>(null);
  // Importance is a product-level flag any staff member may set; kept in its
  // own map so a toggle updates instantly without reloading the whole list.
  const [imp, setImp] = useState<Record<string, boolean>>({});
  const [impBusy, setImpBusy] = useState<string | null>(null);
  const toggleImportant = async (productId: string) => {
    const next = !imp[productId];
    setImpBusy(productId);
    const { error } = await supabase.rpc('set_product_important',
      { p_product_id: productId, p_important: next });
    setImpBusy(null);
    if (error) { setLoadErr(error.message); return; }
    setImp(m => ({ ...m, [productId]: next }));
  };
  const [thresholdRow, setThresholdRow] = useState<Row | null>(null);
  const [thresholdVal, setThresholdVal] = useState(0);

  const loadBase = useCallback(async () => {
    const [{ data: st }, { data: prod }] = await Promise.all([
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
    ]);
    setStores((st as Store[]) ?? []);
    const prodRows = (prod as Product[]) ?? [];
    setProducts(prodRows);
    setImp(Object.fromEntries(prodRows.map((p2: any) => [p2.id, !!p2.is_important])));
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
  useEffect(() => { setFlash(null); }, [selectedStore]);
  const loans = useStockLoans('store', selectedStore, showClosed);
  // Lend, Take back and Record use need access to this store (Owner and
  // Admin: every store; others: the stores they are assigned to), which the
  // database answers as can_act with the On loan list. Managers can read
  // every store's list, so a store they are not assigned to shows it without
  // the buttons. Unknown (not answered yet, or the read failed): Lend and
  // Record use stay, and the database checks them as before.
  const actHere = loans.canAct !== false;
  const noActTitle = actHere ? undefined : 'You are not assigned to this store';
  const available = Object.fromEntries(inventory.map(i => [i.product_id, i.current_qty]));
  const done = (message: string) => {
    setUseOpen(false); setLendOpen(false); setTakeBack(null); setFlash(message);
    loadInventory(selectedStore); loans.reload();
  };

  const rows: Row[] = products.map(p => ({
    product: p, inv: inventory.find(i => i.product_id === p.id) ?? null,
  })).filter(r => {
    const qty = r.inv?.current_qty ?? 0;
    const thr = r.inv?.low_stock_threshold ?? 0;
    if (stockFilter === 'important' && !imp[r.product.id]) return false;
    if (stockFilter === 'in' && qty <= 0) return false;
    if (stockFilter === 'out' && qty > 0) return false;
    if (stockFilter === 'low' && !(qty > 0 && thr > 0 && qty <= thr)) return false;
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
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={rows} filename="store-stock"
            sheetName="Store Stock"
            columns={[
              { header: 'Product', value: (r: any) => r.product.name },
              { header: 'SKU', value: (r: any) => r.product.sku },
              { header: 'Store', value: () => stores.find(s2 => s2.id === selectedStore)?.name ?? '' },
              { header: 'Stock', value: (r: any) => Number(r.inv?.current_qty ?? 0) },
              { header: 'Out on loan', value: (r: any) => Number(loans.outBy[r.product.id] ?? 0) },
              { header: 'Threshold', value: (r: any) => r.inv?.low_stock_threshold ?? '' },
              { header: 'Status', value: (r: any) => stockStatus(r).label },
            ]} />
          <button className="btn btn-secondary" onClick={() => { loadInventory(selectedStore); loans.reload(); }}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-secondary" disabled={!selectedStore || !actHere} title={noActTitle} onClick={() => { setFlash(null); setLendOpen(true); }}>
            <HandHelping size={16} /> Lend
          </button>
          <button className="btn btn-primary" disabled={!selectedStore || !actHere} title={noActTitle} onClick={() => { setFlash(null); setUseOpen(true); }}>
            <MinusCircle size={16} /> Record Use
          </button>
        </div>
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
          {flash && <div className="alert alert-info" role="status"><span>✓</span><div>{flash}</div></div>}
          <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }} role="tablist" aria-label="Store stock views">
            <button role="tab" aria-selected={tab === 'stock'} className={`btn btn-sm ${tab === 'stock' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('stock')}>Stock</button>
            <button role="tab" aria-selected={tab === 'loans'} className={`btn btn-sm ${tab === 'loans' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('loans')}>
              On loan ({loans.open.length}){loans.overdue > 0 && <span className="badge badge-danger" style={{ marginLeft: 4 }}>{loans.overdue} overdue</span>}
            </button>
          </div>
          {tab === 'loans' ? (
            <OnLoanPanel open={loans.open} closed={loans.closed} today={loans.today} loading={loans.loading} error={loans.error}
              showClosed={showClosed} onShowClosed={setShowClosed} onReload={loans.reload}
              canAct={loans.canAct === true} onTakeBack={l => { setFlash(null); setTakeBack(l); }} />
          ) : (<>
          <div style={{ marginBottom: 14, maxWidth: 360 }}>
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search product or SKU…" />
            <div style={{ display: 'flex', gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
              {([['all', 'All'], ['important', 'Important'], ['in', 'With stock'], ['out', 'No stock'], ['low', 'Low stock']] as const).map(([v, l]) => (
                <button key={v} className={`btn btn-sm ${stockFilter === v ? 'btn-primary' : 'btn-secondary'}`}
                  onClick={() => setStockFilter(v)}>{l}</button>
              ))}
            </div>
          </div>
          <div className="card">
            <div className="table-wrap">
              {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
              : rows.length === 0 ? <div className="empty-state"><StoreIcon size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No products</p></div>
              : (
                <table>
                  <thead><tr><th>Product</th><th>SKU</th><th style={{ textAlign: 'right' }}>Stock</th><th style={{ textAlign: 'right' }} title="Lent out from this store and not yet taken back; not in Stock">Out on loan</th><th>Threshold</th><th>Status</th>{canSetThreshold && <th></th>}</tr></thead>
                  <tbody>
                    {rows.map(r => {
                      const st = stockStatus(r);
                      return (
                        <tr key={r.product.id}
                          style={imp[r.product.id] ? {
                            // The whole row turns green, so a fast mover is
                            // visible while scanning rather than needing a column read.
                            background: 'var(--success-light)',
                            boxShadow: 'inset 3px 0 0 var(--success)',
                          } : undefined}>
                          <td>
                            <button
                              onClick={() => toggleImportant(r.product.id)}
                              disabled={impBusy === r.product.id}
                              title={imp[r.product.id] ? 'Marked important — click to unmark' : 'Mark as important'}
                              style={{
                                background: 'none', border: 'none', cursor: 'pointer',
                                padding: 0, marginRight: 8, fontSize: 15, lineHeight: 1,
                                color: imp[r.product.id] ? 'var(--success)' : 'var(--border)',
                                opacity: impBusy === r.product.id ? 0.4 : 1,
                              }}>
                              {imp[r.product.id] ? '★' : '☆'}
                            </button>
                            <strong>{r.product.name}</strong>
                          </td>
                          <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{r.product.sku}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700, fontSize: 15 }}>{r.inv?.current_qty ?? 0}</td>
                          <td style={{ textAlign: 'right' }}>{loans.outBy[r.product.id]
                            ? <button className="btn btn-secondary btn-sm" onClick={() => setTab('loans')} title="Show the On loan list">{loans.outBy[r.product.id]}</button>
                            : <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
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
          </>)}
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

      {useOpen && (
        <RecordUseModal locationType="store" locationId={selectedStore}
          locationName={stores.find(s2 => s2.id === selectedStore)?.name ?? 'Store'}
          products={products} onClose={() => setUseOpen(false)} onDone={done} />
      )}
      {lendOpen && (
        <LendModal locationType="store" locationId={selectedStore}
          locationName={stores.find(s2 => s2.id === selectedStore)?.name ?? 'Store'}
          products={products} available={available} onClose={() => setLendOpen(false)} onDone={done} />
      )}
      {takeBack && (
        <TakeBackModal loan={takeBack} canWarehouse={canWarehouse} onClose={() => setTakeBack(null)} onDone={done} />
      )}
    </div>
  );
};

export default StoreInventoryPage;
