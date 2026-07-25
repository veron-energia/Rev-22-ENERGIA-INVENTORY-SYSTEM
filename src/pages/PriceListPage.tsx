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
  const [price, setPrice] = useState<string>('');
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

  const openEdit = (p: Product) => {
    const pr = priceFor(p.id);
    setEditProduct(p);
    setPrice(pr?.selling_price != null ? String(pr.selling_price)
             : (pr?.member_price != null ? String(pr.member_price) : ''));
  };

  const handleSave = async () => {
    if (!editProduct) return;
    const v = price === '' ? null : Number(price);
    if (v == null) { alert('A selling price is required.'); return; }
    if (v < 0) { alert('Price cannot be negative.'); return; }
    setSaving(true);
    // Phase 19: one selling price; every product is Available for Sale.
    const { error } = await supabase.rpc('set_product_prices', {
      p_store_id: selectedStore, p_product_id: editProduct.id,
      p_member: v, p_non_member: v, p_eligibility: 'both',
    });
    setSaving(false);
    if (error) { alert(error.message); return; }
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
                          <td style={{ textAlign: 'right', fontSize: 12.5 }}>
                            {(() => {
                              if (!price) return <span className="badge badge-danger">No price</span>;
                              const val = price.selling_price ?? price.member_price;
                              return <div>
                                <strong>{val != null ? `S$${Number(val).toFixed(2)}` : '—'}</strong>
                                <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Available for sale</div>
                                {val == null && <span className="badge badge-danger" style={{ fontSize: 10 }}>Incomplete</span>}
                              </div>;
                            })()}
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
          <div className="form-grid">
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Selling Price at {stores.find(s => s.id === selectedStore)?.name} (S$) *</label>
              <input type="number" min={0} step={0.01} value={price} onChange={e => setPrice(e.target.value)} placeholder="0.00" autoFocus />
            </div>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Every product is available for sale. A product needs its price before stock can be transferred into a store.</div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default PriceListPage;
