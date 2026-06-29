import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Product, ProductType, isManagerOrAbove } from '../types';
import { Modal, RoleGate } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Package, RefreshCw } from 'lucide-react';

interface FormState {
  name: string; sku: string; product_type: ProductType;
  category: string; brand: string; uom: string; barcode: string;
  description: string; supplier_name: string; default_cost_price: number;
  is_active: boolean;
}

const blank = (p?: Product): FormState => ({
  name: p?.name ?? '', sku: p?.sku ?? '', product_type: p?.product_type ?? 'own',
  category: p?.category ?? '', brand: p?.brand ?? '', uom: p?.uom ?? 'pcs',
  barcode: p?.barcode ?? '', description: p?.description ?? '',
  supplier_name: p?.supplier_name ?? '', default_cost_price: p?.default_cost_price ?? 0,
  is_active: p?.is_active ?? true,
});

const ProductsPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isManagerOrAbove(profile?.role);
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState<'all' | ProductType>('all');
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<FormState>(blank());
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.from('products').select('*')
      .is('deleted_at', null).order('created_at', { ascending: false });
    setProducts((data as Product[]) ?? []);
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (p: Product) => { setForm(blank(p)); setEditId(p.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    if (!form.name.trim()) { setErr('Product name is required.'); return; }
    if (!form.sku.trim()) { setErr('SKU / product code is required.'); return; }
    setSaving(true); setErr(null);

    const payload = {
      name: form.name.trim(), sku: form.sku.trim(), product_type: form.product_type,
      category: form.category.trim() || null, brand: form.brand.trim() || null,
      uom: form.uom.trim() || 'pcs', barcode: form.barcode.trim() || null,
      description: form.description.trim() || null, supplier_name: form.supplier_name.trim() || null,
      default_cost_price: form.default_cost_price || 0, is_active: form.is_active,
    };

    const res = editId
      ? await supabase.from('products').update({ ...payload, updated_at: new Date().toISOString() }).eq('id', editId)
      : await supabase.from('products').insert(payload);

    if (res.error) {
      setErr(res.error.message.includes('duplicate') ? 'That SKU already exists. Use a unique product code.' : res.error.message);
      setSaving(false);
      return;
    }
    setSaving(false);
    setModalOpen(false);
    load();
  };

  const handleDelete = async (p: Product) => {
    if (!confirm(`Delete "${p.name}"? It will be hidden but kept in the database and can be restored later.`)) return;
    await supabase.from('products').update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', p.id);
    load();
  };

  const filtered = products.filter(p => {
    const q = search.toLowerCase();
    const matchSearch = !q || p.name.toLowerCase().includes(q) || p.sku.toLowerCase().includes(q) || (p.category ?? '').toLowerCase().includes(q);
    const matchType = typeFilter === 'all' || p.product_type === typeFilter;
    return matchSearch && matchType;
  });

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Products</h2>
          <p>Product master data only — stock is tracked separately in warehouse &amp; store inventory.</p>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <RoleGate allow={isManagerOrAbove}>
            <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Product</button>
          </RoleGate>
        </div>
      </div>

      <div className="alert alert-info">
        <span>ℹ️</span>
        <div>Opening stock, current balance, and low-stock thresholds are no longer set here — they live in inventory (added in Phase 2).</div>
      </div>

      {/* Filters */}
      <div style={{ display: 'flex', gap: 10, marginBottom: 14, flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 220, maxWidth: 360 }}>
          <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name, SKU, category…" style={{ paddingLeft: 34 }} />
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          {(['all', 'own', 'third_party'] as const).map(t => (
            <button key={t} className={`btn btn-sm ${typeFilter === t ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTypeFilter(t)}>
              {t === 'all' ? 'All' : t === 'own' ? 'Own' : '3rd Party'}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="card">
        <div className="table-wrap">
          {loading ? (
            <div className="empty-state"><RefreshCw size={26} className="spin" style={{ opacity: 0.4 }} /><p style={{ marginTop: 10 }}>Loading products…</p></div>
          ) : filtered.length === 0 ? (
            <div className="empty-state">
              <Package size={36} style={{ opacity: 0.3, marginBottom: 10 }} />
              <p style={{ fontWeight: 600 }}>No products found</p>
              <p style={{ fontSize: 13 }}>{canManage ? 'Add your first product to get started.' : 'No products have been added yet.'}</p>
            </div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Product</th><th>SKU</th><th>Type</th><th>Category</th>
                  <th>UoM</th><th>Cost</th><th>Status</th>
                  {canManage && <th></th>}
                </tr>
              </thead>
              <tbody>
                {filtered.map(p => (
                  <tr key={p.id}>
                    <td><strong>{p.name}</strong>{p.brand && <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{p.brand}</div>}</td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{p.sku}</td>
                    <td><span className={`badge ${p.product_type === 'own' ? 'badge-primary' : 'badge-accent'}`}>{p.product_type === 'own' ? 'Own' : '3rd Party'}</span></td>
                    <td>{p.category || '—'}</td>
                    <td>{p.uom}</td>
                    <td>{p.default_cost_price ? `S$${p.default_cost_price.toFixed(2)}` : '—'}</td>
                    <td>{p.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    {canManage && (
                      <td>
                        <div style={{ display: 'flex', gap: 4 }}>
                          <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(p)}><Pencil size={13} /></button>
                          <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(p)}><Trash2 size={13} /></button>
                        </div>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Add / Edit modal */}
      {modalOpen && (
        <Modal
          title={editId ? 'Edit Product' : 'Add Product'}
          maxWidth={540}
          onClose={() => setModalOpen(false)}
          footer={
            <>
              <button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button>
              <button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : editId ? 'Save Changes' : 'Add Product'}</button>
            </>
          }
        >
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Product Name *</label><input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="e.g. Energia Corset 3.0" autoFocus /></div>
              <div className="form-group"><label>SKU / Code *</label><input value={form.sku} onChange={e => setForm(f => ({ ...f, sku: e.target.value }))} placeholder="e.g. EN-CORSET-3" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group">
                <label>Product Type</label>
                <select value={form.product_type} onChange={e => setForm(f => ({ ...f, product_type: e.target.value as ProductType }))}>
                  <option value="own">Own Product</option>
                  <option value="third_party">3rd Party Product</option>
                </select>
              </div>
              <div className="form-group"><label>Category</label><input value={form.category} onChange={e => setForm(f => ({ ...f, category: e.target.value }))} placeholder="e.g. Wellness" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Brand</label><input value={form.brand} onChange={e => setForm(f => ({ ...f, brand: e.target.value }))} placeholder="e.g. Energia" /></div>
              <div className="form-group"><label>Unit of Measure</label><input value={form.uom} onChange={e => setForm(f => ({ ...f, uom: e.target.value }))} placeholder="pcs" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Barcode</label><input value={form.barcode} onChange={e => setForm(f => ({ ...f, barcode: e.target.value }))} placeholder="Optional" /></div>
              <div className="form-group"><label>Default Cost Price (S$)</label><input type="number" min={0} step={0.01} value={form.default_cost_price || ''} onChange={e => setForm(f => ({ ...f, default_cost_price: +e.target.value }))} placeholder="0.00" /></div>
            </div>
            <div className="form-group"><label>Supplier</label><input value={form.supplier_name} onChange={e => setForm(f => ({ ...f, supplier_name: e.target.value }))} placeholder="Optional" /></div>
            <div className="form-group"><label>Description</label><textarea rows={2} value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} placeholder="Optional" /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} />
              <span style={{ fontSize: 13 }}>Active (available for inventory &amp; sales)</span>
            </label>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default ProductsPage;
