import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Voucher, VoucherKind, VoucherStoreStock, Store, VOUCHER_KIND_LABELS, isOwnerOrManager } from '../types';
import StorePriceEditor from '../components/StorePriceEditor';
import { Modal, NoAccess } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Ticket, RefreshCw, Boxes } from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;

const blank = (v?: Voucher) => ({
  name: v?.name ?? '', code: v?.code ?? '', voucher_kind: (v?.voucher_kind ?? 'normal') as VoucherKind,
  discount_amount: v?.discount_amount ?? 0, discount_percent: v?.discount_percent ?? 0,
  max_discount_cap: v?.max_discount_cap ?? 0, qty_type: v?.qty_type ?? 'unlimited',
  selling_price: v?.selling_price ?? 0, valid_from: v?.valid_from ?? '', valid_until: v?.valid_until ?? '',
  is_active: v?.is_active ?? true, description: v?.description ?? '', terms: v?.terms ?? '',
});

const VouchersPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isOwnerOrManager(profile?.role)) return <NoAccess message="Only Owners and Managers can manage vouchers." />;

  const [rows, setRows] = useState<Voucher[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [mnmFor, setMnmFor] = useState<{ id: string; name: string } | null>(null);
  const [stock, setStock] = useState<VoucherStoreStock[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blank());
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const [stockFor, setStockFor] = useState<Voucher | null>(null);
  const [stockStore, setStockStore] = useState('');
  const [stockQty, setStockQty] = useState(0);
  const [stockBusy, setStockBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const [v, s, vs] = await Promise.all([
      supabase.from('vouchers').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('voucher_store_stock').select('*'),
    ]);
    setRows((v.data as Voucher[]) ?? []);
    setStores((s.data as Store[]) ?? []);
    setStock((vs.data as VoucherStoreStock[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setModalOpen(true); };
  const openEdit = (v: Voucher) => { setForm(blank(v)); setEditId(v.id); setErr(null); setModalOpen(true); };

  const handleSave = async () => {
    if (!form.name.trim()) { setErr('Name is required.'); return; }
    if (!form.code.trim()) { setErr('Code is required.'); return; }
    if (form.voucher_kind === 'fixed_discount' && form.discount_amount <= 0) { setErr('Fixed discount amount must be greater than zero.'); return; }
    if (form.voucher_kind === 'percentage_discount' && (form.discount_percent <= 0 || form.discount_percent > 100)) { setErr('Discount percent must be between 0 and 100.'); return; }
    setSaving(true); setErr(null);
    const payload: any = {
      name: form.name.trim(), code: form.code.trim(), voucher_kind: form.voucher_kind,
      discount_amount: form.voucher_kind === 'fixed_discount' ? form.discount_amount : null,
      discount_percent: form.voucher_kind === 'percentage_discount' ? form.discount_percent : null,
      max_discount_cap: form.voucher_kind === 'percentage_discount' && form.max_discount_cap > 0 ? form.max_discount_cap : null,
      qty_type: form.qty_type, selling_price: form.selling_price,
      valid_from: form.valid_from || null, valid_until: form.valid_until || null,
      is_active: form.is_active, description: form.description.trim() || null, terms: form.terms.trim() || null,
    };
    const res = editId
      ? await supabase.from('vouchers').update(payload).eq('id', editId)
      : await supabase.from('vouchers').insert(payload);
    if (res.error) { setErr(res.error.message); setSaving(false); return; }
    setSaving(false); setModalOpen(false); load();
  };

  const handleDelete = async (v: Voucher) => {
    if (!confirm(`Delete voucher "${v.name}"?`)) return;
    await supabase.from('vouchers').update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', v.id);
    load();
  };

  const openStock = (v: Voucher) => { setStockFor(v); setStockStore(stores[0]?.id ?? ''); setStockQty(0); };
  const addStock = async () => {
    if (!stockFor || !stockStore || stockQty <= 0) return;
    setStockBusy(true);
    const { error } = await supabase.rpc('voucher_stock_in', { p_voucher_id: stockFor.id, p_store_id: stockStore, p_quantity: stockQty, p_note: null });
    setStockBusy(false);
    if (error) { alert(error.message); return; }
    setStockFor(null); load();
  };

  const stockFancy = (vId: string) => stock.filter(s => s.voucher_id === vId);
  const validityText = (v: Voucher) => {
    const f = v.valid_from ? new Date(v.valid_from).toLocaleDateString() : null;
    const u = v.valid_until ? new Date(v.valid_until).toLocaleDateString() : null;
    if (!f && !u) return 'No expiry';
    if (f && u) return `${f} → ${u}`;
    if (u) return `Until ${u}`;
    return `From ${f}`;
  };
  const filtered = rows.filter(v => { const q = search.toLowerCase(); return !q || v.name.toLowerCase().includes(q) || v.code.toLowerCase().includes(q); });

  const kindBadge = (k: VoucherKind) => {
    const cls = k === 'normal' ? 'badge-primary' : k === 'fixed_discount' ? 'badge-accent' : 'badge-success';
    return <span className={`badge ${cls}`}>{VOUCHER_KIND_LABELS[k]}</span>;
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Vouchers</h2><p>Sellable vouchers and discount vouchers. Limited vouchers track stock per store.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Voucher</button>
        </div>
      </div>

      <div style={{ marginBottom: 14, position: 'relative', maxWidth: 360 }}>
        <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name or code…" style={{ paddingLeft: 34 }} />
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><Ticket size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No vouchers yet</p></div>
          : (
            <table>
              <thead><tr><th>Name</th><th>Code</th><th>Type</th><th>Value</th><th>Qty</th><th>Validity</th><th style={{ textAlign: 'right' }}>Price</th><th></th></tr></thead>
              <tbody>
                {filtered.map(v => (
                  <tr key={v.id}>
                    <td><strong>{v.name}</strong></td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{v.code}</td>
                    <td>{kindBadge(v.voucher_kind)}</td>
                    <td style={{ fontSize: 13 }}>
                      {v.voucher_kind === 'fixed_discount' ? money(v.discount_amount ?? 0)
                        : v.voucher_kind === 'percentage_discount' ? `${v.discount_percent}%${v.max_discount_cap ? ` (cap ${money(v.max_discount_cap)})` : ''}`
                        : '—'}
                    </td>
                    <td style={{ fontSize: 12.5 }}>
                      {v.qty_type === 'unlimited' ? <span className="badge badge-muted">Unlimited</span>
                        : <span>{stockFancy(v.id).reduce((s, x) => s + x.current_qty, 0)} in stock</span>}
                    </td>
                    <td style={{ fontSize: 11.5, color: v.valid_until && new Date(v.valid_until) < new Date() ? 'var(--danger)' : 'var(--text-muted)' }}>{validityText(v)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(v.selling_price)}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      {v.qty_type === 'limited' && <button className="btn btn-secondary btn-sm" onClick={() => openStock(v)}><Boxes size={13} /> Stock</button>}
                      <button className="btn btn-secondary btn-sm" title="Member / Non-Member store prices" onClick={() => setMnmFor({ id: v.id, name: v.name })}>M/NM</button>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(v)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(v)}><Trash2 size={13} /></button>
                    </div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {modalOpen && (
        <Modal title={editId ? 'Edit Voucher' : 'Add Voucher'} maxWidth={520} onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Name *</label><input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus /></div>
              <div className="form-group"><label>Code *</label><input value={form.code} onChange={e => setForm(f => ({ ...f, code: e.target.value }))} placeholder="e.g. SAVE72" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group">
                <label>Voucher Type</label>
                <select value={form.voucher_kind} onChange={e => setForm(f => ({ ...f, voucher_kind: e.target.value as VoucherKind }))}>
                  <option value="normal">Normal (sellable)</option>
                  <option value="fixed_discount">Fixed Amount Discount</option>
                  <option value="percentage_discount">Percentage Discount</option>
                </select>
              </div>
              <div className="form-group"><label>Selling Price (S$)</label><input type="number" min={0} step={0.01} value={form.selling_price || ''} onChange={e => setForm(f => ({ ...f, selling_price: +e.target.value }))} placeholder="0.00" /></div>
            </div>

            {form.voucher_kind === 'fixed_discount' && (
              <div className="form-group"><label>Discount Amount (S$)</label><input type="number" min={0} step={0.01} value={form.discount_amount || ''} onChange={e => setForm(f => ({ ...f, discount_amount: +e.target.value }))} placeholder="e.g. 72" /></div>
            )}
            {form.voucher_kind === 'percentage_discount' && (
              <div className="form-grid-2">
                <div className="form-group"><label>Discount %</label><input type="number" min={0} max={100} step={0.5} value={form.discount_percent || ''} onChange={e => setForm(f => ({ ...f, discount_percent: +e.target.value }))} placeholder="e.g. 10" /></div>
                <div className="form-group"><label>Max Cap (S$, optional)</label><input type="number" min={0} step={0.01} value={form.max_discount_cap || ''} onChange={e => setForm(f => ({ ...f, max_discount_cap: +e.target.value }))} placeholder="Leave 0 for no cap" /></div>
              </div>
            )}

            <div className="form-grid-2">
              <div className="form-group">
                <label>Quantity Type</label>
                <select value={form.qty_type} onChange={e => setForm(f => ({ ...f, qty_type: e.target.value as any }))}>
                  <option value="unlimited">Unlimited (no stock)</option>
                  <option value="limited">Limited (per-store stock)</option>
                </select>
              </div>
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', marginTop: 26 }}>
                <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
              </label>
            </div>
            <div>
              <div className="form-grid-2">
                <div className="form-group"><label>Valid From (optional)</label><input type="date" value={form.valid_from} onChange={e => setForm(f => ({ ...f, valid_from: e.target.value }))} /></div>
                <div className="form-group"><label>Valid Until (optional)</label><input type="date" value={form.valid_until} onChange={e => setForm(f => ({ ...f, valid_until: e.target.value }))} /></div>
              </div>
              <span style={{ fontSize: 11.5, color: 'var(--text-muted)', display: 'block', marginTop: -4 }}>
                Leave both blank for a voucher that never expires. Set only "Valid Until" for an expiry with no fixed start, or only "Valid From" to delay when it becomes usable.
              </span>
            </div>
            <div className="form-group"><label>Description</label><textarea rows={2} value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} placeholder="Optional" /></div>
            {form.qty_type === 'limited' && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>After saving, use the <strong>Stock</strong> button to add voucher quantity per store.</div></div>}
          </div>
        </Modal>
      )}

      {stockFor && (
        <Modal title={`Voucher Stock — ${stockFor.name}`} maxWidth={420} onClose={() => setStockFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setStockFor(null)}>Close</button><button className="btn btn-primary" onClick={addStock} disabled={stockBusy || !stockStore || stockQty <= 0}>{stockBusy ? 'Adding…' : 'Add Stock'}</button></>}>
          <div className="form-grid">
            <div className="form-grid-2">
              <div className="form-group">
                <label>Store</label>
                <select value={stockStore} onChange={e => setStockStore(e.target.value)}>
                  {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </div>
              <div className="form-group"><label>Add Quantity</label><input type="number" min={1} value={stockQty || ''} onChange={e => setStockQty(+e.target.value)} placeholder="0" /></div>
            </div>
            <div>
              <label>Current stock by store</label>
              <table style={{ marginTop: 4 }}>
                <thead><tr><th>Store</th><th style={{ textAlign: 'right' }}>Qty</th></tr></thead>
                <tbody>
                  {stockFancy(stockFor.id).length === 0 ? <tr><td colSpan={2} style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 14 }}>No stock yet</td></tr>
                    : stockFancy(stockFor.id).map(s => (
                      <tr key={s.id}><td>{stores.find(st => st.id === s.store_id)?.name ?? '—'}</td><td style={{ textAlign: 'right', fontWeight: 600 }}>{s.current_qty}</td></tr>
                    ))}
                </tbody>
              </table>
            </div>
          </div>
        </Modal>
      )}
      {mnmFor && (
        <StorePriceEditor kind="voucher" targetId={mnmFor.id} targetName={mnmFor.name}
          stores={stores} onClose={() => setMnmFor(null)} />
      )}
    </div>
  );
};

export default VouchersPage;
