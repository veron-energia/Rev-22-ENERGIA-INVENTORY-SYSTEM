import React, { useEffect, useState, useCallback } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Warehouse, WarehouseInventory, Product,
  canManageWarehouseStock, isOwnerOrManager, isManagerOrAbove,
} from '../types';
import { SearchSelect } from '../components/SearchSelect';
import { Modal, NoAccess } from '../components/ui';
import { PackagePlus, RefreshCw, Warehouse as WarehouseIcon, AlertTriangle, SlidersHorizontal, MinusCircle, HandHelping } from 'lucide-react';
import RecordUseModal from '../components/stock-loans/RecordUseModal';
import LendModal from '../components/stock-loans/LendModal';
import TakeBackModal from '../components/stock-loans/TakeBackModal';
import OnLoanPanel from '../components/stock-loans/OnLoanPanel';
import { useStockLoans } from '../components/stock-loans/useStockLoans';
import { StockLoan, mayHaveSaved, newRequestId, saveFailure } from '../lib/stock-loans/stockLoans';
import { StockInLine, checkStockInForm, stockStatus as statusOf, stockStatusText } from '../lib/stock/stockPages';

interface Row {
  product: Product;
  inv: WarehouseInventory | null;
}

// The access check is a component of its own, so the page's hooks always run
// in the same order (it used to return before them).
const WarehouseInventoryPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isManagerOrAbove(profile?.role) && profile?.role !== 'inventory_manager') {
    return <NoAccess message="Warehouse inventory is available to Owners, Managers, and Inventory Managers." />;
  }
  return <WarehouseInventoryView />;
};

const WarehouseInventoryView: React.FC = () => {
  const { profile } = useAuth();
  // Stock In, Record use, Lend and Take back all need the warehouse stock
  // permission the database checks (Owner, Manager, Inventory Manager); an
  // Admin sees the page and the On loan list but changes nothing.
  const canStockIn = canManageWarehouseStock(profile?.role);
  const canUseStock = canManageWarehouseStock(profile?.role);
  const canSetThreshold = isOwnerOrManager(profile?.role);

  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [selectedWh, setSelectedWh] = useState<string>('');
  const [products, setProducts] = useState<Product[]>([]);
  const [inventory, setInventory] = useState<WarehouseInventory[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [stockFilter, setStockFilter] = useState<'all' | 'in' | 'out' | 'low'>('all');
  const [loadErr, setLoadErr] = useState<string | null>(null);

  // Stock-in modal
  const [stockInOpen, setStockInOpen] = useState(false);
  const [siForm, setSiForm] = useState({ reason: '', note: '', reference: '' });
  // Quantities are typed as text, so an empty box is never taken as a number.
  const [siLines, setSiLines] = useState<StockInLine[]>([{ product_id: '', quantity: '' }]);
  const [siSaving, setSiSaving] = useState(false);
  const [siErr, setSiErr] = useState<string | null>(null);
  // One id per opened Stock In form: a retry after a lost answer adds nothing
  // twice (420). After a failure that may have saved, the form is locked as
  // it was sent.
  const [siFormId, setSiFormId] = useState('');
  const [siLocked, setSiLocked] = useState(false);

  // Threshold modal
  const [thresholdRow, setThresholdRow] = useState<Row | null>(null);
  const [thresholdVal, setThresholdVal] = useState(0);

  // Record use and lending (401)
  const [useOpen, setUseOpen] = useState(false);
  const [lendOpen, setLendOpen] = useState(false);
  const [takeBack, setTakeBack] = useState<StockLoan | null>(null);
  const [tab, setTab] = useState<'stock' | 'loans'>('stock');
  const [showClosed, setShowClosed] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);

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
  useEffect(() => { setFlash(null); }, [selectedWh]);
  const loans = useStockLoans('warehouse', selectedWh, showClosed);
  // The database's own answer (can_act) agrees with canUseStock; Take back is
  // offered only once it has said so, Lend and Record use unless it said no.
  const actHere = canUseStock && loans.canAct !== false;
  const available = Object.fromEntries(inventory.map(i => [i.product_id, i.current_qty]));
  const whName = warehouses.find(w => w.id === selectedWh)?.name ?? 'Warehouse';
  const done = (message: string) => {
    setUseOpen(false); setLendOpen(false); setTakeBack(null); setFlash(message);
    loadInventory(selectedWh); loans.reload();
  };

  const rows: Row[] = products.map(p => ({
    product: p,
    inv: inventory.find(i => i.product_id === p.id) ?? null,
  })).filter(r => {
    const qty = r.inv?.current_qty ?? 0;
    const thr = r.inv?.low_stock_threshold ?? 0;
    if (stockFilter === 'in' && qty <= 0) return false;
    if (stockFilter === 'out' && qty > 0) return false;
    if (stockFilter === 'low' && !(qty > 0 && thr > 0 && qty <= thr)) return false;
    const q = search.toLowerCase();
    return !q || r.product.name.toLowerCase().includes(q) || r.product.sku.toLowerCase().includes(q);
  });

  const openStockIn = () => {
    setSiForm({ reason: '', note: '', reference: '' }); setSiErr(null); setFlash(null);
    setSiLines([{ product_id: '', quantity: '' }]); setSiFormId(newRequestId()); setSiLocked(false); setStockInOpen(true);
  };

  const handleStockIn = async () => {
    const c = checkStockInForm(siLines, siForm);
    if (!c.ok) { setSiErr(c.error); return; }
    setSiSaving(true); setSiErr(null);
    // One call for every line: all are added or none is, so a failed save
    // leaves nothing half done and the same form can simply be sent again.
    const { data, error } = await supabase.rpc('warehouse_stock_ins', {
      p_warehouse_id: selectedWh, p_lines: c.value.p_lines, p_reason: c.value.p_reason,
      p_note: c.value.p_note, p_reference: c.value.p_reference, p_request_id: siFormId,
    });
    setSiSaving(false);
    if (error) {
      setSiLocked(mayHaveSaved(error));
      setSiErr(saveFailure(error, 'The form is locked as it was sent: press Add Stock again to finish, and nothing will be added twice.'));
      loadInventory(selectedWh);
      return;
    }
    const n = ((data as { lines?: unknown[] } | null)?.lines ?? []).length;
    setStockInOpen(false);
    setSiForm({ reason: '', note: '', reference: '' });
    setSiLines([{ product_id: '', quantity: '' }]);
    setFlash(`Stock added for ${n} product${n === 1 ? '' : 's'} at ${whName}.`);
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

  // 0 or less is out of stock; below 0 also shows as Negative (shared with
  // Store Stock; a warehouse cannot go below 0 today).
  const stockStatus = (r: Row) => statusOf(r.inv?.current_qty, r.inv?.low_stock_threshold);

  return (
    <div>
      <div className="page-header">
        <div><h2>Warehouse Inventory</h2><p>Stock balances per warehouse. Add stock manually and set low-stock thresholds.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={rows} filename="warehouse-stock"
            sheetName="Warehouse Stock"
            columns={[
              { header: 'Product', value: (r: any) => r.product.name },
              { header: 'SKU', value: (r: any) => r.product.sku },
              { header: 'Warehouse', value: () => warehouses.find(w => w.id === selectedWh)?.name ?? '' },
              { header: 'Stock', value: (r: any) => Number(r.inv?.current_qty ?? 0) },
              { header: 'Out on loan', value: (r: any) => Number(loans.outBy[r.product.id] ?? 0) },
              { header: 'Threshold', value: (r: any) => r.inv?.low_stock_threshold ?? '' },
              { header: 'Status', value: (r: any) => stockStatusText(r.inv?.current_qty, r.inv?.low_stock_threshold) },
            ]} />
          <button className="btn btn-secondary" onClick={() => { loadInventory(selectedWh); loans.reload(); }}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          {canUseStock && <button className="btn btn-secondary" disabled={!selectedWh || !actHere} onClick={() => { setFlash(null); setLendOpen(true); }}><HandHelping size={16} /> Lend</button>}
          {canUseStock && <button className="btn btn-secondary" disabled={!selectedWh || !actHere} onClick={() => { setFlash(null); setUseOpen(true); }}><MinusCircle size={16} /> Record Use</button>}
          {canStockIn && <button className="btn btn-primary" onClick={openStockIn} disabled={!selectedWh}><PackagePlus size={16} /> Stock In</button>}
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
          {loadErr && <div className="alert alert-danger"><span>⚠</span><div>Couldn't read stock: {loadErr}. Refresh to try again.</div></div>}
          {flash && <div className="alert alert-info" role="status"><span>✓</span><div>{flash}</div></div>}
          <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }} role="tablist" aria-label="Warehouse stock views">
            <button role="tab" aria-selected={tab === 'stock'} className={`btn btn-sm ${tab === 'stock' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('stock')}>Stock</button>
            <button role="tab" aria-selected={tab === 'loans'} className={`btn btn-sm ${tab === 'loans' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('loans')}>
              On loan ({loans.open.length}){loans.overdue > 0 && <span className="badge badge-danger" style={{ marginLeft: 4 }}>{loans.overdue} overdue</span>}
            </button>
          </div>
          {tab === 'loans' ? (
            <OnLoanPanel open={loans.open} closed={loans.closed} today={loans.today} loading={loans.loading} error={loans.error}
              showClosed={showClosed} onShowClosed={setShowClosed} onReload={loans.reload}
              canAct={canUseStock && loans.canAct === true} onTakeBack={l => { setFlash(null); setTakeBack(l); }} />
          ) : (<>
          <div style={{ marginBottom: 14, maxWidth: 360 }}>
            <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search product or SKU…" />
            <div style={{ display: 'flex', gap: 6, marginTop: 8, flexWrap: 'wrap' }}>
              {([['all', 'All'], ['in', 'With stock'], ['out', 'No stock'], ['low', 'Low stock']] as const).map(([v, l]) => (
                <button key={v} className={`btn btn-sm ${stockFilter === v ? 'btn-primary' : 'btn-secondary'}`}
                  onClick={() => setStockFilter(v)}>{l}</button>
              ))}
            </div>
          </div>

          <div className="card">
            <div className="table-wrap">
              {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
              : rows.length === 0 ? <div className="empty-state"><WarehouseIcon size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No products</p></div>
              : (
                <table>
                  <thead><tr><th>Product</th><th>SKU</th><th style={{ textAlign: 'right' }}>Stock</th><th style={{ textAlign: 'right' }} title="Lent out from this warehouse and not yet taken back; not in Stock">Out on loan</th><th>Threshold</th><th>Status</th>{canSetThreshold && <th></th>}</tr></thead>
                  <tbody>
                    {rows.map(r => {
                      const st = stockStatus(r);
                      return (
                        <tr key={r.product.id}>
                          <td><strong>{r.product.name}</strong></td>
                          <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{r.product.sku}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700, fontSize: 15 }}>{r.inv?.current_qty ?? 0}</td>
                          <td style={{ textAlign: 'right' }}>{loans.outBy[r.product.id]
                            ? <button className="btn btn-secondary btn-sm" onClick={() => setTab('loans')} title="Show the On loan list">{loans.outBy[r.product.id]}</button>
                            : <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                          <td>{r.inv?.low_stock_threshold ? r.inv.low_stock_threshold : <span style={{ color: 'var(--text-muted)' }}>—</span>}</td>
                          <td><span className={`badge ${st.cls}`}>{st.label === 'Low Stock' && <AlertTriangle size={11} />}{st.label}</span>
                            {st.negative && <span className="badge badge-danger" style={{ marginLeft: 4 }}>Negative ({r.inv?.current_qty})</span>}</td>
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

      {/* Stock-in modal */}
      {stockInOpen && (
        <Modal title="Manual Warehouse Stock-In" maxWidth={460} onClose={() => setStockInOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setStockInOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleStockIn} disabled={siSaving}>{siSaving ? 'Saving…' : siLocked ? 'Add Stock again' : 'Add Stock'}</button></>}>
          <div className="form-grid">
            {siErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{siErr}</div></div>}
            <div className="form-group">
              <label>Products *</label>
              {siLines.map((l, i) => (
                <div key={i} style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 6 }}>
                  <div style={{ flex: 1 }}>
                    <SearchSelect
                      options={products.map(p => ({ value: p.id, label: `${p.name} (${p.sku})`, search: `${p.name} ${p.sku}` }))}
                      value={l.product_id} disabled={siLocked}
                      exclude={siLines.filter((_, j) => j !== i).map(x => x.product_id).filter(Boolean)}
                      onChange={v => setSiLines(ls => ls.map((x, j) => j === i ? { ...x, product_id: v } : x))}
                      placeholder="Search product name or SKU…" />
                  </div>
                  <input type="text" inputMode="numeric" value={l.quantity} placeholder="Qty" style={{ width: 90 }} aria-label="Quantity" disabled={siLocked}
                    onChange={e => setSiLines(ls => ls.map((x, j) => j === i ? { ...x, quantity: e.target.value } : x))} />
                  <button className="btn btn-secondary btn-sm btn-icon" disabled={siLocked || siLines.length === 1}
                    onClick={() => setSiLines(ls => ls.filter((_, j) => j !== i))} title="Remove">×</button>
                </div>
              ))}
              <button className="btn btn-secondary btn-sm" style={{ marginTop: 2 }} disabled={siLocked}
                onClick={() => setSiLines(ls => [...ls, { product_id: '', quantity: '' }])}>+ Add another product</button>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 5 }}>
                The reason, reference and note below apply to every line. Every line is added together, or none is.
              </div>
            </div>
            <div className="form-group"><label>Reason *</label><input value={siForm.reason} disabled={siLocked} onChange={e => setSiForm(f => ({ ...f, reason: e.target.value }))} placeholder="e.g. New delivery from supplier" /></div>
            <div className="form-grid-2">
              <div className="form-group"><label>Reference No.</label><input value={siForm.reference} disabled={siLocked} onChange={e => setSiForm(f => ({ ...f, reference: e.target.value }))} placeholder="Optional" /></div>
              <div className="form-group"><label>Note</label><input value={siForm.note} disabled={siLocked} onChange={e => setSiForm(f => ({ ...f, note: e.target.value }))} placeholder="Optional" /></div>
            </div>
          </div>
        </Modal>
      )}

      {useOpen && (
        <RecordUseModal locationType="warehouse" locationId={selectedWh} locationName={whName}
          products={products} onClose={() => setUseOpen(false)} onDone={done} />
      )}
      {lendOpen && (
        <LendModal locationType="warehouse" locationId={selectedWh} locationName={whName}
          products={products} available={available} onClose={() => setLendOpen(false)} onDone={done} />
      )}
      {takeBack && (
        <TakeBackModal loan={takeBack} canWarehouse={canUseStock} onClose={() => setTakeBack(null)} onDone={done} />
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
