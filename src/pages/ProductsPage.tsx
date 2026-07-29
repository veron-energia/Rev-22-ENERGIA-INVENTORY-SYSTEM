import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Product, ProductType, Brand, Category, Supplier, isManagerOrAbove, isOwnerOrManager } from '../types';
import { Modal, RoleGate } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Package, RefreshCw, Star, Tag, Boxes, Truck, SlidersHorizontal } from 'lucide-react';
import DropdownManager from '../components/DropdownManager';

interface FormState {
  name: string; sku: string; product_type: ProductType;
  category: string; brand: string; uom: string; barcode: string;
  description: string; supplier_name: string; default_cost_price: number;
  is_active: boolean;
  brand_id: string; categoryIds: string[]; supplierIds: string[];
}

const blank = (p?: Product): FormState => ({
  name: p?.name ?? '', sku: p?.sku ?? '', product_type: p?.product_type ?? 'own',
  category: p?.category ?? '', brand: p?.brand ?? '', uom: p?.uom ?? 'pcs',
  barcode: p?.barcode ?? '', description: p?.description ?? '',
  supplier_name: p?.supplier_name ?? '', default_cost_price: p?.default_cost_price ?? 0,
  is_active: p?.is_active ?? true,
  brand_id: p?.brand_id ?? '', categoryIds: [], supplierIds: [],
});

const ProductsPage: React.FC = () => {
  const { profile } = useAuth();
  const canManage = isManagerOrAbove(profile?.role);
  const canConfig = isOwnerOrManager(profile?.role);   // dropdowns + important flag: Owner/Manager only
  const [brands, setBrands] = useState<Brand[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [prodCats, setProdCats] = useState<{ product_id: string; category_id: string }[]>([]);
  const [prodSups, setProdSups] = useState<{ product_id: string; supplier_id: string }[]>([]);
  const [importantFilter, setImportantFilter] = useState<'all' | 'only' | 'first'>('all');
  const [tab, setTab] = useState<'products' | 'catalog'>('products');
  const [catalogTab, setCatalogTab] = useState<'brands' | 'categories' | 'suppliers'>('brands');
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
    const [prod, br, cat, sup, pc, ps] = await Promise.all([
      supabase.from('products').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('brands').select('*').is('deleted_at', null).order('name'),
      supabase.from('categories').select('*').is('deleted_at', null).order('name'),
      supabase.from('suppliers').select('*').is('deleted_at', null).order('name'),
      supabase.from('product_categories').select('product_id,category_id'),
      supabase.from('product_suppliers').select('product_id,supplier_id'),
    ]);
    setProducts((prod.data as Product[]) ?? []);
    setBrands((br.data as Brand[]) ?? []);
    setCategories((cat.data as Category[]) ?? []);
    setSuppliers((sup.data as Supplier[]) ?? []);
    setProdCats((pc.data as any[]) ?? []);
    setProdSups((ps.data as any[]) ?? []);
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  const toggleImportant = async (p: Product) => {
    const { error } = await supabase.rpc('set_product_important', { p_product_id: p.id, p_important: !p.is_important });
    if (error) alert(error.message); else load();
  };

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (p: Product) => {
    const cats = prodCats.filter(x => x.product_id === p.id).map(x => x.category_id);
    const sups = prodSups.filter(x => x.product_id === p.id).map(x => x.supplier_id);
    setForm({ ...blank(p), categoryIds: cats, supplierIds: sups });
    setEditId(p.id); setErr(null); setModalOpen(true);
  };

  const handleSave = async () => {
    if (!form.name.trim()) { setErr('Product name is required.'); return; }
    if (!form.sku.trim()) { setErr('SKU / product code is required.'); return; }
    setSaving(true); setErr(null);

    const payload = {
      name: form.name.trim(), sku: form.sku.trim(), product_type: form.product_type,
      category: form.category.trim() || null, brand: form.brand.trim() || null,
      brand_id: form.brand_id || null,
      uom: form.uom.trim() || 'pcs', barcode: form.barcode.trim() || null,
      description: form.description.trim() || null, supplier_name: form.supplier_name.trim() || null,
      default_cost_price: form.default_cost_price || 0, is_active: form.is_active,
    };

    let productId = editId;
    let res;
    if (editId) {
      res = await supabase.from('products').update({ ...payload, updated_at: new Date().toISOString() }).eq('id', editId);
    } else {
      const ins = await supabase.from('products').insert(payload).select('id').single();
      res = ins;
      productId = (ins.data as any)?.id ?? null;
    }

    if (res.error) {
      setErr(res.error.message.includes('duplicate') ? 'That SKU already exists. Use a unique product code.' : res.error.message);
      setSaving(false);
      return;
    }

    // Sync category + supplier links (replace-all).
    if (productId) {
      await supabase.from('product_categories').delete().eq('product_id', productId);
      await supabase.from('product_suppliers').delete().eq('product_id', productId);
      if (form.categoryIds.length) await supabase.from('product_categories').insert(form.categoryIds.map(cid => ({ product_id: productId, category_id: cid })));
      if (form.supplierIds.length) await supabase.from('product_suppliers').insert(form.supplierIds.map(sid => ({ product_id: productId, supplier_id: sid })));
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

  const catNames = (productId: string) => {
    const ids = prodCats.filter(x => x.product_id === productId).map(x => x.category_id);
    const names = categories.filter(c => ids.includes(c.id)).map(c => c.name);
    return names;
  };
  const supNames = (productId: string) => {
    const ids = prodSups.filter(x => x.product_id === productId).map(x => x.supplier_id);
    return suppliers.filter(s => ids.includes(s.id)).map(s => s.name);
  };
  const brandName = (p: Product) => brands.find(b => b.id === p.brand_id)?.name || p.brand || '';

  // Click a column to sort by it; click again to reverse.
  const [sortBy, setSortBy] = useState<'name' | 'sku' | 'cost' | null>(null);
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const toggleSort = (col: 'name' | 'sku' | 'cost') => {
    if (sortBy !== col) { setSortBy(col); setSortDir('asc'); }
    else if (sortDir === 'asc') setSortDir('desc');
    else { setSortBy(null); setSortDir('asc'); }
  };
  const sortArrow = (col: 'name' | 'sku' | 'cost') =>
    sortBy !== col ? '' : sortDir === 'asc' ? ' ▲' : ' ▼';

  const filtered = products.filter(p => {
    const q = search.trim().toLowerCase();
    const matchSearch = !q || p.name.toLowerCase().includes(q) || p.sku.toLowerCase().includes(q);
    const matchType = typeFilter === 'all' || p.product_type === typeFilter;
    const matchImportant = importantFilter !== 'only' || p.is_important;
    return matchSearch && matchType && matchImportant;
  }).sort((a, b) => {
    if (importantFilter === 'first') {
      const imp = (b.is_important ? 1 : 0) - (a.is_important ? 1 : 0);
      if (imp !== 0) return imp;
    }
    if (!sortBy) return 0;
    const dir = sortDir === 'asc' ? 1 : -1;
    if (sortBy === 'cost') {
      return ((Number(a.default_cost_price ?? 0)) - (Number(b.default_cost_price ?? 0))) * dir;
    }
    const av = (sortBy === 'name' ? a.name : a.sku) ?? '';
    const bv = (sortBy === 'name' ? b.name : b.sku) ?? '';
    return av.localeCompare(bv, undefined, { numeric: true, sensitivity: 'base' }) * dir;
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
          {tab === 'products' && (
            <RoleGate allow={isManagerOrAbove}>
              <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Product</button>
            </RoleGate>
          )}
        </div>
      </div>

      {/* Top-level tabs: Products vs catalog setup (Owner/Manager only) */}
      <div style={{ display: 'flex', gap: 6, marginBottom: 16, borderBottom: '1px solid var(--border)' }}>
        <button className={`tab-btn ${tab === 'products' ? 'active' : ''}`} onClick={() => setTab('products')}
          style={{ padding: '8px 16px', background: 'none', border: 'none', borderBottom: tab === 'products' ? '2px solid var(--primary)' : '2px solid transparent', color: tab === 'products' ? 'var(--primary)' : 'var(--text-secondary)', fontWeight: tab === 'products' ? 700 : 500, cursor: 'pointer' }}>
          <Package size={15} style={{ verticalAlign: 'middle', marginRight: 6 }} />Products
        </button>
        {canConfig && (
          <button className={`tab-btn ${tab === 'catalog' ? 'active' : ''}`} onClick={() => setTab('catalog')}
            style={{ padding: '8px 16px', background: 'none', border: 'none', borderBottom: tab === 'catalog' ? '2px solid var(--primary)' : '2px solid transparent', color: tab === 'catalog' ? 'var(--primary)' : 'var(--text-secondary)', fontWeight: tab === 'catalog' ? 700 : 500, cursor: 'pointer' }}>
            <Tag size={15} style={{ verticalAlign: 'middle', marginRight: 6 }} />Brands, Categories &amp; Suppliers
          </button>
        )}
      </div>

      {tab === 'catalog' && canConfig && (
        <div>
          <div style={{ display: 'flex', gap: 6, marginBottom: 16 }}>
            {([['brands', 'Brands', Tag], ['categories', 'Categories', Boxes], ['suppliers', 'Suppliers', Truck]] as const).map(([v, lbl, Icon]) => (
              <button key={v} className={`btn btn-sm ${catalogTab === v ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setCatalogTab(v)}>
                <Icon size={13} /> {lbl}
              </button>
            ))}
          </div>
          <div className="card" style={{ padding: 20 }}>
            <DropdownManager key={catalogTab} kind={catalogTab} embedded onChanged={load} />
          </div>
        </div>
      )}

      {tab === 'products' && (
      <>
      <div className="alert alert-info">
        <span>ℹ️</span>
        <div>Opening stock, current balance, and low-stock thresholds are no longer set here — they live in inventory (added in Phase 2).</div>
      </div>

      {/* Filters */}
      <div style={{ display: 'flex', gap: 10, marginBottom: 14, flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 220, maxWidth: 360 }}>
          <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name or SKU…" style={{ paddingLeft: 34 }} />
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          {(['all', 'own', 'third_party'] as const).map(t => (
            <button key={t} className={`btn btn-sm ${typeFilter === t ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTypeFilter(t)}>
              {t === 'all' ? 'All' : t === 'own' ? 'Own' : '3rd Party'}
            </button>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          {([['all', 'All'], ['only', '★ Important only'], ['first', 'Important first']] as const).map(([v, lbl]) => (
            <button key={v} className={`btn btn-sm ${importantFilter === v ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setImportantFilter(v)}>{lbl}</button>
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
                  <th onClick={() => toggleSort('name')} style={{ cursor: 'pointer', userSelect: 'none' }} title="Sort by product name">Product{sortArrow('name')}</th>
                  <th onClick={() => toggleSort('sku')} style={{ cursor: 'pointer', userSelect: 'none' }} title="Sort by SKU">SKU{sortArrow('sku')}</th>
                  <th>Type</th><th>Category</th>
                  <th>UoM</th>
                  <th onClick={() => toggleSort('cost')} style={{ cursor: 'pointer', userSelect: 'none' }} title="Sort by cost">Cost{sortArrow('cost')}</th>
                  <th>Status</th>
                  {canManage && <th></th>}
                </tr>
              </thead>
              <tbody>
                {filtered.map(p => (
                  <tr key={p.id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                        {p.is_important && <span title="Important product" style={{ display: "inline-flex" }}><Star size={14} fill="var(--success)" color="var(--success)" /></span>}
                        <strong>{p.name}</strong>
                      </div>
                      {brandName(p) && <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{brandName(p)}</div>}
                    </td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{p.sku}</td>
                    <td><span className={`badge ${p.product_type === 'own' ? 'badge-primary' : p.product_type === 'no_commission' ? 'badge-muted' : 'badge-accent'}`}>{p.product_type === 'own' ? 'Own' : p.product_type === 'no_commission' ? 'No commission' : '3rd Party'}</span></td>
                    <td>
                      {(() => {
                        const names = catNames(p.id);
                        return names.length
                          ? <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>{names.map(n => <span key={n} className="badge badge-muted" style={{ fontSize: 11 }}>{n}</span>)}</div>
                          : (p.category || '—');
                      })()}
                    </td>
                    <td>{p.uom}</td>
                    <td>{p.default_cost_price ? `S$${p.default_cost_price.toFixed(2)}` : '—'}</td>
                    <td>{p.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    {canManage && (
                      <td>
                        <div style={{ display: 'flex', gap: 4 }}>
                          {canConfig && <button className={`btn btn-sm btn-icon ${p.is_important ? 'btn-primary' : 'btn-secondary'}`} title={p.is_important ? 'Unmark important' : 'Mark important'} onClick={() => toggleImportant(p)}><Star size={13} fill={p.is_important ? '#fff' : 'none'} /></button>}
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
      </>
      )}

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
                  <option value="no_commission">No commission — delivery, services, pass-through</option>
                </select>
              </div>
              <div className="form-group"><label>Categories <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>(multiple)</span></label>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                  {categories.filter(cat => cat.is_active || form.categoryIds.includes(cat.id)).map(cat => {
                    const on = form.categoryIds.includes(cat.id);
                    return <button key={cat.id} type="button" className={`btn btn-sm ${on ? 'btn-primary' : 'btn-secondary'}`}
                      onClick={() => setForm(f => ({ ...f, categoryIds: on ? f.categoryIds.filter(x => x !== cat.id) : [...f.categoryIds, cat.id] }))}>
                      {on ? '✓ ' : ''}{cat.name}</button>;
                  })}
                  {categories.length === 0 && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>No categories yet — add some via "Categories".</span>}
                </div>
              </div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Brand</label>
                <select value={form.brand_id} onChange={e => setForm(f => ({ ...f, brand_id: e.target.value }))}>
                  <option value="">— None —</option>
                  {brands.filter(b => b.is_active || b.id === form.brand_id).map(b => <option key={b.id} value={b.id}>{b.name}{!b.is_active ? ' (inactive)' : ''}</option>)}
                </select>
              </div>
              <div className="form-group"><label>Unit of Measure</label><input value={form.uom} onChange={e => setForm(f => ({ ...f, uom: e.target.value }))} placeholder="pcs" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Barcode</label><input value={form.barcode} onChange={e => setForm(f => ({ ...f, barcode: e.target.value }))} placeholder="Optional" /></div>
              <div className="form-group"><label>Default Cost Price (S$)</label><input type="number" min={0} step={0.01} value={form.default_cost_price || ''} onChange={e => setForm(f => ({ ...f, default_cost_price: +e.target.value }))} placeholder="0.00" /></div>
            </div>
            <div className="form-group"><label>Suppliers <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>(multiple)</span></label>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                {suppliers.filter(s => s.is_active || form.supplierIds.includes(s.id)).map(s => {
                  const on = form.supplierIds.includes(s.id);
                  return <button key={s.id} type="button" className={`btn btn-sm ${on ? 'btn-primary' : 'btn-secondary'}`}
                    onClick={() => setForm(f => ({ ...f, supplierIds: on ? f.supplierIds.filter(x => x !== s.id) : [...f.supplierIds, s.id] }))}>
                    {on ? '✓ ' : ''}{s.name}</button>;
                })}
                {suppliers.length === 0 && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>No suppliers yet — add some via "Suppliers".</span>}
              </div>
            </div>
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
