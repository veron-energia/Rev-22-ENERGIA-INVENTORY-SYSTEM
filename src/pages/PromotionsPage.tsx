import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Promotion, PromotionItem, PromotionItemType, Product, Voucher, Store,
  PROMO_TYPE_LABELS, PromotionType, isOwnerOrManager,
  PromotionChoiceGroup, PromotionChoiceOption,
} from '../types';
import StorePriceEditor from '../components/StorePriceEditor';
import { SearchSelect } from '../components/SearchSelect';
import { Modal, NoAccess } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Package2, RefreshCw, X, Layers } from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;

const blankPromo = (p?: Promotion) => ({
  name: p?.name ?? '', code: p?.code ?? '', promo_type: (p?.promo_type ?? 'bundle') as PromotionType,
  fixed_price: p?.fixed_price ?? 0, start_date: p?.start_date ?? '', end_date: p?.end_date ?? '',
  is_active: p?.is_active ?? true, description: p?.description ?? '', terms: p?.terms ?? '',
});

type ChoiceKind = 'product' | 'voucher' | 'therapy' | 'credit_package';

const PromotionsPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isOwnerOrManager(profile?.role);
  const [rows, setRows] = useState<Promotion[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [mnmFor, setMnmFor] = useState<{ id: string; name: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');

  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blankPromo());
  const [saving, setSaving] = useState(false);
  const [applyPriceEverywhere, setApplyPriceEverywhere] = useState(true);
  const [dgBase, setDgBase] = useState<'cheapest' | 'highest'>('cheapest');
  const [ngBase, setNgBase] = useState<'cheapest' | 'highest'>('cheapest');
  const [therapyPkgs, setTherapyPkgs] = useState<any[]>([]);
  const [creditPkgs, setCreditPkgs] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);

  // Builder (items) — for an existing promotion
  const [itemsFor, setItemsFor] = useState<Promotion | null>(null);
  const [items, setItems] = useState<PromotionItem[]>([]);
  const [previewStore, setPreviewStore] = useState('');
  const [origTotal, setOrigTotal] = useState<number | null>(null);
  const [itemErr, setItemErr] = useState<string | null>(null);
  const [itemBusy, setItemBusy] = useState(false);
  // new-item form
  const [niType, setNiType] = useState<PromotionItemType>('product');
  const [niProduct, setNiProduct] = useState('');
  const [niVoucher, setNiVoucher] = useState('');
  const [niChild, setNiChild] = useState('');
  const [niTreatment, setNiTreatment] = useState('');
  const [niTherapy, setNiTherapy] = useState('');
  const [niCredit, setNiCredit] = useState('');
  const [niQty, setNiQty] = useState(1);

  // Draft items chosen inside the Add Promotion modal (saved after the promotion is created).
  interface DraftItem { item_type: PromotionItemType; product_id: string; voucher_id: string; child_promotion_id: string; treatment_name: string; quantity: number; }
  const [dItems, setDItems] = useState<DraftItem[]>([]);
  const [dErr, setDErr] = useState<string | null>(null);
  // Draft choice groups chosen inside the Add Promotion modal.
  interface DraftGroup { label: string; item_kind: ChoiceKind; choose_qty: number; option_ids: string[]; base_mode: 'cheapest' | 'highest'; }
  const [dGroups, setDGroups] = useState<DraftGroup[]>([]);
  const [dgLabel, setDgLabel] = useState('');
  const [dgKind, setDgKind] = useState<ChoiceKind>('product');
  const [dgQty, setDgQty] = useState(1);
  const [dgOptSel, setDgOptSel] = useState<Record<number, string>>({});
  // Promotions that already contain a nested promotion (not nestable, per the 2-level rule).
  const [promosWithChildren, setPromosWithChildren] = useState<Set<string>>(new Set());
  // Choice groups of the promotion open in the builder
  const [groups, setGroups] = useState<PromotionChoiceGroup[]>([]);
  const [options, setOptions] = useState<PromotionChoiceOption[]>([]);
  const [ngLabel, setNgLabel] = useState('');
  const [ngKind, setNgKind] = useState<ChoiceKind>('product');
  const [ngQty, setNgQty] = useState(1);
  const [noFor, setNoFor] = useState<string>('');    // group id an option is being added to
  const [noItem, setNoItem] = useState('');          // product/voucher id
  const [grpErr, setGrpErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [p, pr, vc, st, pi] = await Promise.all([
      supabase.from('promotions').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('vouchers').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('promotion_items').select('promotion_id').eq('item_type', 'promotion'),
    ]);
    setRows((p.data as Promotion[]) ?? []);
    setProducts((pr.data as Product[]) ?? []);
    setVouchers((vc.data as Voucher[]) ?? []);
    const { data: tp } = await supabase.from('unlimited_therapy_packages').select('id,name,sku').is('deleted_at', null).eq('is_active', true).order('name');
    setTherapyPkgs((tp as any[]) ?? []);
    const { data: cp } = await supabase.from('credit_packages').select('id,name,sku').is('deleted_at', null).eq('is_active', true).order('name');
    setCreditPkgs((cp as any[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setPromosWithChildren(new Set(((pi.data as any[]) ?? []).map(x => x.promotion_id)));
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setForm(blankPromo()); setEditId(null); setErr(null); setDItems([]); setDErr(null); setDGroups([]); setDgLabel(''); setDgKind('product'); setDgQty(1); setDgOptSel({}); resetNewItem(); setModalOpen(true); };
  const openEdit = (p: Promotion) => { setForm(blankPromo(p)); setEditId(p.id); setErr(null); setModalOpen(true); };

  const addDraftItem = () => {
    setDErr(null);
    if (niType === 'product' && !niProduct) { setDErr('Select a product.'); return; }
    if (niType === 'voucher' && !niVoucher) { setDErr('Select a voucher.'); return; }
    if (niType === 'promotion' && !niChild) { setDErr('Select a promotion.'); return; }
    if (niType === 'treatment' && !niTreatment.trim()) { setDErr('Enter a treatment name.'); return; }
    if (niType === 'therapy' && !niTherapy) { setDErr('Select a therapy package.'); return; }
    if (niType === 'credit_package' && !niCredit) { setDErr('Select a credit package.'); return; }
    if (!niQty || niQty <= 0) { setDErr('Quantity must be greater than zero.'); return; }
    setDItems(ds => [...ds, {
      item_type: niType, product_id: niProduct, voucher_id: niVoucher,
      child_promotion_id: niChild, treatment_name: niTreatment.trim(), quantity: niQty,
      therapy_package_id: niTherapy, credit_package_id: niCredit,
    }]);
    resetNewItem();
  };

  const draftLabel = (d: { item_type: PromotionItemType; product_id: string; voucher_id: string; child_promotion_id: string; treatment_name: string; therapy_package_id?: string; credit_package_id?: string }) => {
    switch (d.item_type) {
      case 'product': return `📦 ${pName(d.product_id)}`;
      case 'voucher': return `🎟 ${vName(d.voucher_id)}`;
      case 'promotion': return `🧩 ${promoName(d.child_promotion_id)} (nested)`;
      case 'treatment': return `💆 ${d.treatment_name}`;
      case 'therapy': return `✨ ${therapyPkgs.find((t: any) => t.id === (d as any).therapy_package_id)?.name ?? 'Therapy'}`;
      case 'credit_package': return `💳 ${creditPkgs.find((c: any) => c.id === (d as any).credit_package_id)?.name ?? 'Credit package'}`;
    }
  };

  const addDraftGroup = () => {
    setDErr(null);
    if (!dgLabel.trim()) { setDErr('Enter a choice-group label.'); return; }
    if (!dgQty || dgQty <= 0) { setDErr('Choose quantity must be greater than zero.'); return; }
    setDGroups(gs => [...gs, { label: dgLabel.trim(), item_kind: dgKind, choose_qty: dgQty, option_ids: [], base_mode: dgBase }]);
    setDgLabel(''); setDgKind('product'); setDgQty(1);
  };

  const addDraftOption = (gi: number) => {
    const optId = dgOptSel[gi];
    if (!optId) return;
    setDGroups(gs => gs.map((g, j) => j === gi && !g.option_ids.includes(optId)
      ? { ...g, option_ids: [...g.option_ids, optId] } : g));
    setDgOptSel(s => ({ ...s, [gi]: '' }));
  };

  const handleSave = async () => {
    if (!form.name.trim()) { setErr('Name is required.'); return; }
    if (!form.code.trim()) { setErr('Code is required.'); return; }
    if (form.fixed_price < 0) { setErr('Fixed price cannot be negative.'); return; }
    if (form.start_date && form.end_date && form.end_date < form.start_date) { setErr('End date cannot be before start date.'); return; }
    setSaving(true); setErr(null);
    const payload: any = {
      name: form.name.trim(), code: form.code.trim(), promo_type: form.promo_type,
      fixed_price: form.fixed_price, start_date: form.start_date || null, end_date: form.end_date || null,
      is_active: form.is_active, description: form.description.trim() || null, terms: form.terms.trim() || null,
    };
    const res = editId
      ? await supabase.from('promotions').update(payload).eq('id', editId).select().single()
      : await supabase.from('promotions').insert(payload).select().single();
    if (res.error) { setErr(res.error.message); setSaving(false); return; }
    // One price, applied to every store.
    const savedId = (res.data as any)?.id ?? editId;
    if (applyPriceEverywhere && savedId && form.fixed_price > 0) {
      const { error: pErr } = await supabase.rpc('set_promotion_price_all_stores', {
        p_promotion_id: savedId, p_price: form.fixed_price, p_available: true,
      });
      if (pErr) { setErr(`Saved, but the store prices could not be set: ${pErr.message}`); setSaving(false); load(); return; }
    }
    setSaving(false); setModalOpen(false);
    if (!editId && res.data) {
      // Save the draft items chosen in the modal, then open the builder (shows totals).
      const promo = res.data as Promotion;
      let firstErr: string | null = null;
      for (const d of dItems) {
        const { error } = await supabase.rpc('add_promotion_item', {
          p_promotion_id: promo.id, p_item_type: d.item_type,
          p_product_id: d.item_type === 'product' ? d.product_id : null,
          p_voucher_id: d.item_type === 'voucher' ? d.voucher_id : null,
          p_child_promotion_id: d.item_type === 'promotion' ? d.child_promotion_id : null,
          p_treatment_name: d.item_type === 'treatment' ? d.treatment_name : null,
          p_therapy_package_id: d.item_type === 'therapy' ? (d as any).therapy_package_id : null,
          p_credit_package_id: d.item_type === 'credit_package' ? (d as any).credit_package_id : null,
          p_quantity: d.quantity, p_notes: null,
        });
        if (error && !firstErr) firstErr = error.message;
      }
      // Save draft choice groups + their options.
      for (const g of dGroups) {
        const gr = await supabase.from('promotion_choice_groups')
          .insert({ promotion_id: promo.id, label: g.label, item_kind: g.item_kind, choose_qty: g.choose_qty, base_mode: g.base_mode })
          .select().single();
        if (gr.error) { if (!firstErr) firstErr = gr.error.message; continue; }
        for (const optId of g.option_ids) {
          const { error } = await supabase.from('promotion_choice_options').insert({
            group_id: (gr.data as any).id,
            product_id: g.item_kind === 'product' ? optId : null,
            voucher_id: g.item_kind === 'voucher' ? optId : null,
            therapy_package_id: g.item_kind === 'therapy' ? optId : null,
            credit_package_id: g.item_kind === 'credit_package' ? optId : null,
          });
          if (error && !firstErr) firstErr = error.message;
        }
      }
      await load();
      await openItems(promo);
      if (firstErr) setItemErr(`One item could not be added: ${firstErr}`);
    } else {
      await load();
    }
  };

  const handleDelete = async (p: Promotion) => {
    if (!confirm(`Delete promotion "${p.name}"?`)) return;
    await supabase.from('promotions').update({ deleted_at: new Date().toISOString(), is_active: false }).eq('id', p.id);
    load();
  };

  const openItems = async (p: Promotion) => {
    setItemsFor(p); setItemErr(null); setPreviewStore(stores[0]?.id ?? '');
    resetNewItem();
    const { data } = await supabase.from('promotion_items').select('*').eq('promotion_id', p.id).order('created_at');
    setItems((data as PromotionItem[]) ?? []);
    await loadGroups(p.id);
  };

  const loadGroups = async (promoId: string) => {
    const g = await supabase.from('promotion_choice_groups').select('*').eq('promotion_id', promoId).order('created_at');
    const gs = (g.data as PromotionChoiceGroup[]) ?? [];
    setGroups(gs);
    if (gs.length > 0) {
      const o = await supabase.from('promotion_choice_options').select('*').in('group_id', gs.map(x => x.id));
      setOptions((o.data as PromotionChoiceOption[]) ?? []);
    } else setOptions([]);
    setGrpErr(null); setNgLabel(''); setNgKind('product'); setNgQty(1); setNoFor(''); setNoItem('');
  };

  const addGroup = async () => {
    if (!itemsFor) return;
    setGrpErr(null);
    if (!ngLabel.trim()) { setGrpErr('Enter a group label (e.g. "Choose your product").'); return; }
    if (!ngQty || ngQty <= 0) { setGrpErr('Choose quantity must be greater than zero.'); return; }
    const { error } = await supabase.from('promotion_choice_groups').insert({
      promotion_id: itemsFor.id, label: ngLabel.trim(), item_kind: ngKind, choose_qty: ngQty, base_mode: ngBase,
    });
    if (error) { setGrpErr(error.message); return; }
    await loadGroups(itemsFor.id);
  };

  const addOption = async (g: PromotionChoiceGroup) => {
    if (!noItem) return;
    setGrpErr(null);
    const { error } = await supabase.from('promotion_choice_options').insert({
      group_id: g.id,
      product_id: g.item_kind === 'product' ? noItem : null,
      voucher_id: g.item_kind === 'voucher' ? noItem : null,
      therapy_package_id: g.item_kind === 'therapy' ? noItem : null,
      credit_package_id: g.item_kind === 'credit_package' ? noItem : null,
    });
    if (error) { setGrpErr(error.message); return; }
    setNoItem('');
    if (itemsFor) await loadGroups(itemsFor.id);
  };

  const removeGroup = async (id: string) => {
    await supabase.from('promotion_choice_groups').delete().eq('id', id);
    if (itemsFor) await loadGroups(itemsFor.id);
  };
  const removeOption = async (id: string) => {
    await supabase.from('promotion_choice_options').delete().eq('id', id);
    if (itemsFor) await loadGroups(itemsFor.id);
  };
  const resetNewItem = () => {
    setNiType('product'); setNiProduct(''); setNiVoucher(''); setNiChild('');
    setNiTreatment(''); setNiTherapy(''); setNiCredit(''); setNiQty(1);
  };

  // Recompute original total when items or store change.
  useEffect(() => {
    (async () => {
      if (!itemsFor || !previewStore) { setOrigTotal(null); return; }
      const { data } = await supabase.rpc('promotion_original_total', { p_promotion_id: itemsFor.id, p_store_id: previewStore });
      setOrigTotal(typeof data === 'number' ? data : Number(data ?? 0));
    })();
  }, [itemsFor, previewStore, items]);

  const addItem = async () => {
    if (!itemsFor) return;
    setItemBusy(true); setItemErr(null);
    const { error } = await supabase.rpc('add_promotion_item', {
      p_promotion_id: itemsFor.id, p_item_type: niType,
      p_product_id: niType === 'product' ? niProduct || null : null,
      p_voucher_id: niType === 'voucher' ? niVoucher || null : null,
      p_child_promotion_id: niType === 'promotion' ? niChild || null : null,
      p_treatment_name: niType === 'treatment' ? niTreatment.trim() || null : null,
      p_therapy_package_id: niType === 'therapy' ? niTherapy || null : null,
      p_credit_package_id: niType === 'credit_package' ? niCredit || null : null,
      p_quantity: niQty, p_notes: null,
    });
    setItemBusy(false);
    if (error) { setItemErr(error.message); return; }
    resetNewItem();
    const { data } = await supabase.from('promotion_items').select('*').eq('promotion_id', itemsFor.id).order('created_at');
    setItems((data as PromotionItem[]) ?? []);
  };

  const removeItem = async (id: string) => {
    await supabase.from('promotion_items').delete().eq('id', id);
    if (itemsFor) {
      const { data } = await supabase.from('promotion_items').select('*').eq('promotion_id', itemsFor.id).order('created_at');
      setItems((data as PromotionItem[]) ?? []);
    }
  };

  const pName = (id: string | null) => products.find(p => p.id === id)?.name ?? '—';
  const vName = (id: string | null) => vouchers.find(v => v.id === id)?.name ?? '—';
  const promoName = (id: string | null) => rows.find(r => r.id === id)?.name ?? '—';
  const itemLabel = (it: PromotionItem) => {
    switch (it.item_type) {
      case 'product': return `📦 ${pName(it.product_id)}`;
      case 'voucher': return `🎟 ${vName(it.voucher_id)}`;
      case 'promotion': return `🧩 ${promoName(it.child_promotion_id)} (nested)`;
      case 'treatment': return `💆 ${it.treatment_name}`;
      case 'therapy': return `✨ ${therapyPkgs.find((t: any) => t.id === (it as any).therapy_package_id)?.name ?? 'Therapy'}`;
      case 'credit_package': return `💳 ${creditPkgs.find((c: any) => c.id === (it as any).credit_package_id)?.name ?? 'Credit package'}`;
    }
  };
  // Only leaf promotions (no nested promotions) may be nested inside another.
  const nestableChildren = useMemo(() =>
    rows.filter(r => itemsFor && r.id !== itemsFor.id), [rows, itemsFor]);

  const savings = origTotal != null && itemsFor ? origTotal - itemsFor.fixed_price : null;
  const filtered = rows.filter(p => { const q = search.toLowerCase(); return !q || p.name.toLowerCase().includes(q) || p.code.toLowerCase().includes(q); });

  if (!hasAccess) return <NoAccess message="Only Owners and Managers can manage promotions." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Promotions & Bundles</h2><p>Build bundles from products, vouchers, treatments, and other promotions (nested up to 2 levels).</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Promotion</button>
        </div>
      </div>

      <div style={{ marginBottom: 14, position: 'relative', maxWidth: 360 }}>
        <Search size={15} style={{ position: 'absolute', left: 11, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search name or code…" style={{ paddingLeft: 34 }} />
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><Package2 size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No promotions yet</p></div>
          : (
            <table>
              <thead><tr><th>Name</th><th>Code</th><th>Type</th><th style={{ textAlign: 'right' }}>Fixed Price</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {filtered.map(p => (
                  <tr key={p.id}>
                    <td><strong>{p.name}</strong></td>
                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5 }}>{p.code}</td>
                    <td><span className="badge badge-primary">{PROMO_TYPE_LABELS[p.promo_type]}</span></td>
                    <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(p.fixed_price)}</td>
                    <td>{p.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => openItems(p)}><Layers size={13} /> Items</button>
                      <button className="btn btn-secondary btn-sm" title="Per-store selling prices" onClick={() => setMnmFor({ id: p.id, name: p.name })}>Prices</button>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(p)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(p)}><Trash2 size={13} /></button>
                    </div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Create/edit promotion */}
      {modalOpen && (
        <Modal title={editId ? 'Edit Promotion' : 'Add Promotion'} wide onClose={() => setModalOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : (editId ? 'Save' : 'Save & Add Items')}</button></>}>
          <div className="form-grid">
            {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
            <div className="form-grid-2">
              <div className="form-group"><label>Name *</label><input value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} autoFocus /></div>
              <div className="form-group"><label>Code *</label><input value={form.code} onChange={e => setForm(f => ({ ...f, code: e.target.value }))} placeholder="e.g. BUNDLE1" /></div>
            </div>
            <div className="form-grid-2">
              <div className="form-group">
                <label>Type</label>
                <select value={form.promo_type} onChange={e => setForm(f => ({ ...f, promo_type: e.target.value as PromotionType }))}>
                  <option value="bundle">Bundle</option>
                  <option value="treatment">Treatment Package</option>
                  <option value="other">Other</option>
                </select>
              </div>
              <div className="form-group">
                <label>Fixed Price (S$)</label>
                <input type="number" min={0} step={0.01} value={form.fixed_price || ''} onChange={e => setForm(f => ({ ...f, fixed_price: +e.target.value }))} placeholder="e.g. 188" />
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, marginTop: 6, fontWeight: 400 }}>
                  <input type="checkbox" style={{ width: 'auto' }} checked={applyPriceEverywhere}
                    onChange={e => setApplyPriceEverywhere(e.target.checked)} />
                  Use this price at every store
                </label>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                  Leave ticked and you never need to open Prices — untick it only to set different prices per store.
                </div>
              </div>
            </div>
            <div className="form-grid-2">
              <div className="form-group"><label>Start Date (optional)</label><input type="date" value={form.start_date} onChange={e => setForm(f => ({ ...f, start_date: e.target.value }))} /></div>
              <div className="form-group"><label>End Date (optional)</label><input type="date" value={form.end_date} onChange={e => setForm(f => ({ ...f, end_date: e.target.value }))} /></div>
            </div>
            <div className="form-group"><label>Description</label><textarea rows={2} value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} placeholder="Optional" /></div>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input type="checkbox" checked={form.is_active} onChange={e => setForm(f => ({ ...f, is_active: e.target.checked }))} style={{ width: 'auto' }} /><span style={{ fontSize: 13 }}>Active</span>
            </label>
            {!editId && (
              <div style={{ borderTop: '1px solid var(--border)', paddingTop: 12 }}>
                <label>Included items ({dItems.length})</label>
                {dItems.length > 0 && (
                  <table style={{ marginTop: 4 }}>
                    <thead><tr><th>Item</th><th style={{ textAlign: 'right' }}>Qty</th><th></th></tr></thead>
                    <tbody>
                      {dItems.map((d, i) => (
                        <tr key={i}>
                          <td style={{ fontSize: 13 }}>{draftLabel(d)}</td>
                          <td style={{ textAlign: 'right' }}>{d.quantity}</td>
                          <td style={{ textAlign: 'right' }}><button className="btn btn-danger btn-sm btn-icon" onClick={() => setDItems(ds => ds.filter((_, j) => j !== i))}><X size={13} /></button></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
                {dErr && <div className="alert alert-danger" style={{ marginTop: 6 }}><span>⚠</span><div>{dErr}</div></div>}
                <div style={{ display: 'flex', gap: 8, marginTop: 6, alignItems: 'center', flexWrap: 'wrap' }}>
                  <select value={niType} onChange={e => setNiType(e.target.value as PromotionItemType)} style={{ width: 120 }}>
                    <option value="product">Product</option>
                    <option value="voucher">Voucher</option>
                    <option value="promotion">Promotion</option>
                    <option value="therapy">Therapy</option>
                    <option value="credit_package">Credit package</option>
                    <option value="treatment">Treatment</option>
                  </select>
                  {niType === 'product' && (
                    <SearchSelect style={{ flex: 1, minWidth: 180 }} placeholder="Search product name or SKU…"
                      value={niProduct} onChange={setNiProduct}
                      options={products.map((p: any) => ({ value: p.id, label: p.name, sublabel: p.sku, search: `${p.name} ${p.sku ?? ''}` }))} />
                  )}
                  {niType === 'voucher' && (
                    <SearchSelect style={{ flex: 1, minWidth: 180 }} placeholder="Search voucher name or code…"
                      value={niVoucher} onChange={setNiVoucher}
                      options={vouchers.map((v: any) => ({ value: v.id, label: v.name, sublabel: v.code, search: `${v.name} ${v.code ?? ''}` }))} />
                  )}
                  {niType === 'therapy' && (
                    <SearchSelect style={{ flex: 1, minWidth: 180 }} placeholder="Search therapy package or SKU…"
                      value={niTherapy} onChange={setNiTherapy}
                      options={therapyPkgs.map((x: any) => ({ value: x.id, label: x.name, sublabel: x.sku, search: `${x.name} ${x.sku ?? ''}` }))} />
                  )}
                  {niType === 'credit_package' && (
                    <SearchSelect style={{ flex: 1, minWidth: 180 }} placeholder="Search credit package or SKU…"
                      value={niCredit} onChange={setNiCredit}
                      options={creditPkgs.map((x: any) => ({ value: x.id, label: x.name, sublabel: x.sku, search: `${x.name} ${x.sku ?? ''}` }))} />
                  )}
                  {niType === 'promotion' && (
                    <select value={niChild} onChange={e => setNiChild(e.target.value)} style={{ flex: 1, minWidth: 150 }}>
                      <option value="">— Promotion —</option>
                      {rows.filter(r => !promosWithChildren.has(r.id)).map(r => <option key={r.id} value={r.id}>{r.name}</option>)}
                    </select>
                  )}
                  {niType === 'treatment' && (
                    <input value={niTreatment} onChange={e => setNiTreatment(e.target.value)} placeholder="Treatment name" style={{ flex: 1, minWidth: 150 }} />
                  )}
                  <input type="number" min={1} value={niQty || ''} onChange={e => setNiQty(+e.target.value)} placeholder="Qty" style={{ width: 64 }} />
                  <button className="btn btn-secondary btn-sm" onClick={addDraftItem}><Plus size={13} /> Add</button>
                </div>
                <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6, display: 'block' }}>
                  Items are saved with the promotion. The original total and savings preview opens after saving.
                  {niType === 'promotion' ? ' Only promotions without a nested promotion of their own can be nested (max 2 levels).' : ''}
                </span>
              </div>
            )}

            {!editId && (
              <div style={{ borderTop: '1px solid var(--border)', paddingTop: 12 }}>
                <label>Choice groups ({dGroups.length}) <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— "choose N from…" picked by the cashier at invoice time</span></label>
                {dGroups.map((g, gi) => (
                  <div key={gi} style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10, marginTop: 8 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <strong style={{ flex: 1, fontSize: 13 }}>{g.label}</strong>
                      <span className="badge badge-primary">choose {g.choose_qty} {g.item_kind}{g.choose_qty > 1 ? 's' : ''}</span>
                      {g.item_kind === 'product' && (
                        <select value={g.base_mode} style={{ width: 150, fontSize: 11.5, padding: '2px 6px' }}
                          title="Which option sets the base price. Picks above the base pay the difference."
                          onChange={e => setDGroups(gs => gs.map((x, j) => j === gi ? { ...x, base_mode: e.target.value as any } : x))}>
                          <option value="cheapest">base = cheapest</option>
                          <option value="highest">base = highest</option>
                        </select>
                      )}
                      <button className="btn btn-danger btn-sm btn-icon" onClick={() => setDGroups(gs => gs.filter((_, j) => j !== gi))}><X size={13} /></button>
                    </div>
                    <div style={{ marginTop: 6, display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                      {g.option_ids.map(id => (
                        <span key={id} className="badge badge-muted" style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                          {g.item_kind === 'product' ? pName(id)
                            : g.item_kind === 'voucher' ? vName(id)
                            : g.item_kind === 'therapy' ? (therapyPkgs.find(t => t.id === id)?.name ?? id)
                            : (creditPkgs.find(c => c.id === id)?.name ?? id)}
                          <X size={11} style={{ cursor: 'pointer' }} onClick={() => setDGroups(gs => gs.map((x, j) => j === gi ? { ...x, option_ids: x.option_ids.filter(o => o !== id) } : x))} />
                        </span>
                      ))}
                      {g.option_ids.length === 0 && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>No options yet</span>}
                    </div>
                    <div style={{ display: 'flex', gap: 6, marginTop: 8 }}>
                      <SearchSelect style={{ flex: 1 }} placeholder={`Search ${g.item_kind} by name or SKU…`}
                        value={dgOptSel[gi] ?? ''}
                        onChange={v => setDgOptSel(s2 => ({ ...s2, [gi]: v }))}
                        exclude={g.option_ids}
                        options={(g.item_kind === 'product'
                            ? products.map((p: any) => ({ id: p.id, name: p.name, sku: p.sku }))
                            : g.item_kind === 'voucher'
                            ? vouchers.map((v: any) => ({ id: v.id, name: v.name, sku: v.code }))
                            : g.item_kind === 'therapy'
                            ? therapyPkgs.map((t: any) => ({ id: t.id, name: t.name, sku: t.sku }))
                            : creditPkgs.map((c: any) => ({ id: c.id, name: c.name, sku: c.sku })))
                          .map(x => ({ value: x.id, label: x.name, sublabel: x.sku ?? undefined, search: `${x.name} ${x.sku ?? ''}` }))} />
                      <button className="btn btn-secondary btn-sm" onClick={() => addDraftOption(gi)} disabled={!dgOptSel[gi]}><Plus size={13} /> Option</button>
                    </div>
                  </div>
                ))}
                <div style={{ display: 'flex', gap: 8, marginTop: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                  <input value={dgLabel} onChange={e => setDgLabel(e.target.value)} placeholder='Group label, e.g. "Choose your product"' style={{ flex: 1, minWidth: 170 }} />
                  <select value={dgKind} onChange={e => setDgKind(e.target.value as ChoiceKind)} style={{ width: 130 }}>
                    <option value="product">Products</option>
                    <option value="voucher">Vouchers</option>
                    <option value="therapy">Therapy</option>
                    <option value="credit_package">Credit packages</option>
                  </select>
                  {dgKind === 'product' && (
                    <select value={dgBase} onChange={e => setDgBase(e.target.value as any)} style={{ width: 140 }} title="Which option sets the base price">
                      <option value="cheapest">base = cheapest</option>
                      <option value="highest">base = highest</option>
                    </select>
                  )}
                  <input type="number" min={1} value={dgQty || ''} onChange={e => setDgQty(+e.target.value)} placeholder="N" style={{ width: 64 }} title="How many the customer chooses" />
                  <button className="btn btn-secondary btn-sm" onClick={addDraftGroup}><Plus size={13} /> Group</button>
                </div>
                <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6, display: 'block' }}>Groups are saved with the promotion. Promotions with choice groups cannot be nested.</span>
              </div>
            )}
          </div>
        </Modal>
      )}

      {/* Item builder */}
      {itemsFor && (
        <Modal title={`Items — ${itemsFor.name}`} wide onClose={() => setItemsFor(null)}
          footer={<button className="btn btn-secondary" onClick={() => setItemsFor(null)}>Done</button>}>
          <div className="form-grid">
            {/* Pricing preview */}
            <div style={{ display: 'flex', gap: 10, alignItems: 'flex-end', flexWrap: 'wrap' }}>
              <div className="form-group" style={{ flex: 1, minWidth: 180, marginBottom: 0 }}>
                <label>Preview original total at store</label>
                <select value={previewStore} onChange={e => setPreviewStore(e.target.value)}>
                  {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              </div>
              <div style={{ display: 'flex', gap: 10 }}>
                <div style={{ padding: 10, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', textAlign: 'center', minWidth: 96 }}>
                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Original</div>
                  <div style={{ fontSize: 15, fontWeight: 700 }}>{origTotal == null ? '—' : money(origTotal)}</div>
                </div>
                <div style={{ padding: 10, background: 'var(--primary-light)', borderRadius: 'var(--radius-sm)', textAlign: 'center', minWidth: 96 }}>
                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Bundle price</div>
                  <div style={{ fontSize: 15, fontWeight: 700 }}>{money(itemsFor.fixed_price)}</div>
                </div>
                <div style={{ padding: 10, background: 'var(--success-light)', borderRadius: 'var(--radius-sm)', textAlign: 'center', minWidth: 96 }}>
                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Savings</div>
                  <div style={{ fontSize: 15, fontWeight: 700, color: savings != null && savings < 0 ? 'var(--danger)' : 'inherit' }}>{savings == null ? '—' : money(savings)}</div>
                </div>
              </div>
            </div>

            {/* Existing items */}
            <div>
              <label>Included items ({items.length})</label>
              {items.length === 0 ? <div style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 4 }}>No items yet — add some below.</div> : (
                <table style={{ marginTop: 4 }}>
                  <thead><tr><th>Item</th><th style={{ textAlign: 'right' }}>Qty</th><th></th></tr></thead>
                  <tbody>
                    {items.map(it => (
                      <tr key={it.id}>
                        <td style={{ fontSize: 13 }}>{itemLabel(it)}</td>
                        <td style={{ textAlign: 'right' }}>{it.quantity}</td>
                        <td style={{ textAlign: 'right' }}><button className="btn btn-danger btn-sm btn-icon" onClick={() => removeItem(it.id)}><X size={13} /></button></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>

            {/* Choice groups */}
            <div style={{ borderTop: '1px solid var(--border)', paddingTop: 12 }}>
              <label>Choice groups ({groups.length}) <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— "choose N from…" picked by the cashier at invoice time</span></label>
              {grpErr && <div className="alert alert-danger" style={{ marginTop: 6 }}><span>⚠</span><div>{grpErr}</div></div>}
              {groups.map(g => (
                <div key={g.id} style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10, marginTop: 8 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <strong style={{ flex: 1, fontSize: 13 }}>{g.label}</strong>
                    <span className="badge badge-primary">choose {g.choose_qty} {g.item_kind}{g.choose_qty > 1 ? 's' : ''}</span>
                    {g.item_kind === 'product' && <span className="badge badge-muted" title="At sale, any product can be chosen; the cheapest option here sets the base price and pricier picks pay the difference.">base = cheapest option</span>}
                    <button className="btn btn-danger btn-sm btn-icon" onClick={() => removeGroup(g.id)}><X size={13} /></button>
                  </div>
                  <div style={{ marginTop: 6, display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                    {options.filter(o => o.group_id === g.id).map(o => (
                      <span key={o.id} className="badge badge-muted" style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                        {g.item_kind === 'product' ? pName(o.product_id) : vName(o.voucher_id)}
                        <X size={11} style={{ cursor: 'pointer' }} onClick={() => removeOption(o.id)} />
                      </span>
                    ))}
                    {options.filter(o => o.group_id === g.id).length === 0 && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>No options yet</span>}
                  </div>
                  <div style={{ display: 'flex', gap: 6, marginTop: 8 }}>
                    <select value={noFor === g.id ? noItem : ''} onChange={e => { setNoFor(g.id); setNoItem(e.target.value); }} style={{ flex: 1 }}>
                      <option value="">— Add {g.item_kind} option —</option>
                      {(g.item_kind === 'product' ? products.map(p => ({ id: p.id, name: p.name })) : vouchers.map(v => ({ id: v.id, name: v.name })))
                        .map(x => <option key={x.id} value={x.id}>{x.name}</option>)}
                    </select>
                    <button className="btn btn-secondary btn-sm" onClick={() => addOption(g)} disabled={noFor !== g.id || !noItem}><Plus size={13} /> Option</button>
                  </div>
                </div>
              ))}
              <div style={{ display: 'flex', gap: 8, marginTop: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                <input value={ngLabel} onChange={e => setNgLabel(e.target.value)} placeholder='Group label, e.g. "Choose your product"' style={{ flex: 1, minWidth: 170 }} />
                <select value={ngKind} onChange={e => setNgKind(e.target.value as 'product' | 'voucher')} style={{ width: 110 }}>
                  <option value="product">Products</option>
                  <option value="voucher">Vouchers</option>
                </select>
                <input type="number" min={1} value={ngQty || ''} onChange={e => setNgQty(+e.target.value)} placeholder="N" style={{ width: 64 }} title="How many the customer chooses" />
                <button className="btn btn-secondary btn-sm" onClick={addGroup}><Plus size={13} /> Group</button>
              </div>
              <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6, display: 'block' }}>Promotions with choice groups cannot be nested inside another promotion.</span>
            </div>

            {/* Add item */}
            <div style={{ borderTop: '1px solid var(--border)', paddingTop: 12 }}>
              <label>Add a fixed item <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— always included</span></label>
              {itemErr && <div className="alert alert-danger" style={{ marginTop: 6 }}><span>⚠</span><div>{itemErr}</div></div>}
              <div style={{ display: 'flex', gap: 8, marginTop: 6, alignItems: 'center', flexWrap: 'wrap' }}>
                <select value={niType} onChange={e => { setNiType(e.target.value as PromotionItemType); }} style={{ width: 130 }}>
                  <option value="product">Product</option>
                  <option value="voucher">Voucher</option>
                  <option value="promotion">Promotion</option>
                  <option value="therapy">Therapy</option>
                  <option value="credit_package">Credit package</option>
                  <option value="treatment">Treatment</option>
                </select>
                {niType === 'product' && (
                  <SearchSelect style={{ flex: 1, minWidth: 180 }} placeholder="Search product name or SKU…"
                    value={niProduct} onChange={setNiProduct}
                    options={products.map((p: any) => ({ value: p.id, label: p.name, sublabel: p.sku, search: `${p.name} ${p.sku ?? ''}` }))} />
                )}
                {niType === 'voucher' && (
                  <SearchSelect style={{ flex: 1, minWidth: 180 }} placeholder="Search voucher name or code…"
                    value={niVoucher} onChange={setNiVoucher}
                    options={vouchers.map((v: any) => ({ value: v.id, label: v.name, sublabel: v.code, search: `${v.name} ${v.code ?? ''}` }))} />
                )}
                {niType === 'therapy' && (
                  <SearchSelect style={{ flex: 1, minWidth: 180 }} placeholder="Search therapy package or SKU…"
                    value={niTherapy} onChange={setNiTherapy}
                    options={therapyPkgs.map((x: any) => ({ value: x.id, label: x.name, sublabel: x.sku, search: `${x.name} ${x.sku ?? ''}` }))} />
                )}
                {niType === 'credit_package' && (
                  <SearchSelect style={{ flex: 1, minWidth: 180 }} placeholder="Search credit package or SKU…"
                    value={niCredit} onChange={setNiCredit}
                    options={creditPkgs.map((x: any) => ({ value: x.id, label: x.name, sublabel: x.sku, search: `${x.name} ${x.sku ?? ''}` }))} />
                )}
                {niType === 'promotion' && (
                  <select value={niChild} onChange={e => setNiChild(e.target.value)} style={{ flex: 1, minWidth: 160 }}>
                    <option value="">— Promotion —</option>
                    {nestableChildren.map(r => <option key={r.id} value={r.id}>{r.name}</option>)}
                  </select>
                )}
                {niType === 'treatment' && (
                  <input value={niTreatment} onChange={e => setNiTreatment(e.target.value)} placeholder="Treatment name" style={{ flex: 1, minWidth: 160 }} />
                )}
                <input type="number" min={1} value={niQty || ''} onChange={e => setNiQty(+e.target.value)} placeholder="Qty" style={{ width: 70 }} />
                <button className="btn btn-primary btn-sm" onClick={addItem} disabled={itemBusy}><Plus size={13} /> Add</button>
              </div>
              {niType === 'promotion' && <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6, display: 'block' }}>Only promotions with no nested promotion of their own can be added (max 2 levels).</span>}
            </div>
          </div>
        </Modal>
      )}
      {mnmFor && (
        <StorePriceEditor kind="promotion" targetId={mnmFor.id} targetName={mnmFor.name}
          stores={stores} onClose={() => setMnmFor(null)} />
      )}
    </div>
  );
};

export default PromotionsPage;
