import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Store, Product, StoreProductPrice, isOwnerOrManager } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { RefreshCw, Tag, Store as StoreIcon, Pencil } from 'lucide-react';

const PriceListPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isOwnerOrManager(profile?.role)) return <NoAccess message="Only Owners and Managers can manage store price lists." />;

  const [stores, setStores] = useState<Store[]>([]);
  const [selectedStore, setSelectedStore] = useState('');
  const [products, setProducts] = useState<Product[]>([]);
  const [prices, setPrices] = useState<StoreProductPrice[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

  const [editProduct, setEditProduct] = useState<Product | null>(null);
  const [priceVal, setPriceVal] = useState(0);
  const [saving, setSaving] = useState(false);

  const loadBase = useCallback(async () => {
    const [s, p] = await Promise.all([
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
    ]);
    setStores((s.data as Store[]) ?? []);
    setProducts((p.data as Product[]) ?? []);
    if (s.data && s.data.length > 0 && !selectedStore) setSelectedStore((s.data as Store[])[0].id);
  }, [selectedStore]);

  const loadPrices = useCallback(async (storeId: string) => {
    if (!storeId) return;
    setLoading(true);
    const { data } = await supabase.from('store_product_prices').select('*').eq('store_id', storeId).is('deleted_at', null);
    setPrices((data as StoreProductPrice[]) ?? []);
    setLoading(false);
  }, []);

  useEffect(() => { loadBase(); }, [loadBase]);
  useEffect(() => { if (selectedStore) loadPrices(selectedStore); }, [selectedStore, loadPrices]);

  const priceFor = (productId: string) => prices.find(p => p.product_id === productId);

  const openEdit = (p: Product) => { setEditProduct(p); setPriceVal(priceFor(p.id)?.selling_price ?? 0); };

  const handleSave = async () => {
    if (!editProduct) return;
    if (priceVal < 0) { alert('Price cannot be negative.'); return; }
    setSaving(true);
    const existing = priceFor(editProduct.id);
    const res = existing
      ? await supabase.from('store_product_prices').update({ selling_price: priceVal, is_active: true }).eq('id', existing.id)
      : await supabase.from('store_product_prices').insert({ store_id: selectedStore, product_id: editProduct.id, selling_price: priceVal });
    setSaving(false);
    if (res.error) { alert(res.error.message); return; }
    setEditProduct(null);
    loadPrices(selectedStore);
  };

  const filtered = products.filter(p => { const q = search.toLowerCase(); return !q || p.name.toLowerCase().includes(q) || p.sku.toLowerCase().includes(q); });
  const pricedCount = prices.length;

  return (
    <div>
      <div className="page-header">
        <div><h2>Store Price List</h2><p>Set each product's selling price per store. A price is required before stock can be transferred in or sold.</p></div>
        <button className="btn btn-secondary" onClick={() => loadPrices(selectedStore)}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
      </div>

      <div style={{ display: 'flex', gap: 8, marginBottom: 16, flexWrap: 'wrap' }}>
        {stores.map(s => (
          <button key={s.id} onClick={() => setSelectedStore(s.id)} className={`btn btn-sm ${selectedStore === s.id ? 'btn-primary' : 'btn-secondary'}`}>
            <StoreIcon size={14} /> {s.name}
          </button>
        ))}
      </div>

      {selectedStore && (
        <>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12, flexWrap: 'wrap', gap: 10 }}>
            <div style={{ maxWidth: 360, flex: 1 }}>
              <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search product or SKU…" />
            </div>
            <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{pricedCount} of {products.length} products priced</span>
          </div>

          <div className="card">
            <div className="table-wrap">
              {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
              : filtered.length === 0 ? <div className="empty-state"><Tag size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No products</p></div>
              : (
                <table>
                  <thead><tr><th>Product</th><th>SKU</th><th>Type</th><th style={{ textAlign: 'right' }}>Selling Price</th><th></th></tr></thead>
                  <tbody>
                    {filtered.map(p => {
                      const price = priceFor(p.id);
                      return (
                        <tr key={p.id} style={{ opacity: price ? 1 : 0.7 }}>
                          <td><strong>{p.name}</strong></td>
                          <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{p.sku}</td>
                          <td><span className={`badge ${p.product_type === 'own' ? 'badge-primary' : 'badge-accent'}`}>{p.product_type === 'own' ? 'Own' : '3rd Party'}</span></td>
                          <td style={{ textAlign: 'right', fontWeight: 700, fontSize: 14 }}>
                            {price ? `S$${price.selling_price.toFixed(2)}` : <span className="badge badge-danger">No price</span>}
                          </td>
                          <td style={{ textAlign: 'right' }}>
                            <button className="btn btn-secondary btn-sm" onClick={() => openEdit(p)}><Pencil size={13} /> {price ? 'Edit' : 'Set Price'}</button>
                          </td>
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

      {editProduct && (
        <Modal title={`Price — ${editProduct.name}`} maxWidth={380} onClose={() => setEditProduct(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setEditProduct(null)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save Price'}</button></>}>
          <div className="form-group">
            <label>Selling Price (S$) at {stores.find(s => s.id === selectedStore)?.name}</label>
            <input type="number" min={0} step={0.01} value={priceVal || ''} onChange={e => setPriceVal(+e.target.value)} autoFocus placeholder="0.00" />
          </div>
        </Modal>
      )}
    </div>
  );
};

export default PriceListPage;
