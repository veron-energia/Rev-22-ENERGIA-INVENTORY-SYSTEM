import React, { useEffect, useState, useCallback } from 'react';
import { ExcelExportButton } from '../components/ExcelExport';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Voucher, VoucherKind, VoucherStoreStock, Store, VOUCHER_KIND_LABELS, VOUCHER_CATEGORY_LABELS, BIRTHDAY_RULE_LABELS,
  VoucherDiscountCategory, BirthdayRule, isOwnerOrManager } from '../types';
import StorePriceEditor from '../components/StorePriceEditor';
import { Modal, NoAccess } from '../components/ui';
import { Plus, Pencil, Trash2, Search, Ticket, RefreshCw, Boxes } from 'lucide-react';
import { dayNumbers, dayText, isPastValidUntil, sgToday, voucherDependents, type VoucherDeleteAnswer } from '../lib/catalogue/pageRules.mjs';

const money = (n: number) => `S$${n.toFixed(2)}`;

// reward_eligible is read here only (the Voucher type in types/index.ts does
// not carry it yet).
type VoucherRow = Voucher & { reward_eligible?: boolean | null };

const blank = (v?: VoucherRow) => ({
  name: v?.name ?? '', code: v?.code ?? '', voucher_kind: (v?.voucher_kind ?? 'normal') as VoucherKind,
  discount_amount: v?.discount_amount ?? 0, discount_percent: v?.discount_percent ?? 0,
  max_discount_cap: v?.max_discount_cap ?? 0, qty_type: v?.qty_type ?? 'unlimited',
  selling_price: v?.selling_price ?? 0, valid_from: v?.valid_from ?? '', valid_until: v?.valid_until ?? '',
  is_active: v?.is_active ?? true, description: v?.description ?? '', terms: v?.terms ?? '',
  // 384: where a discount voucher is offered on an invoice line.
  discount_category: (v?.discount_category ?? 'voucher') as VoucherDiscountCategory,
  birthday_rule: (v?.birthday_rule ?? '') as BirthdayRule | '',
  // THERAPY-7: whether staff may hand a free-session voucher out as a reward.
  reward_eligible: v?.reward_eligible !== false,
});

/** "Birthday · in the birth month", for a discount voucher; null for a normal one. */
const categoryText = (v: Voucher): string | null => {
  if (v.voucher_kind === 'normal') return null;
  const c = v.discount_category ?? 'voucher';
  return c === 'birthday' && v.birthday_rule
    ? `${VOUCHER_CATEGORY_LABELS[c]} · ${BIRTHDAY_RULE_LABELS[v.birthday_rule].toLowerCase()}`
    : VOUCHER_CATEGORY_LABELS[c];
};

const VouchersPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isOwnerOrManager(profile?.role);
  const [rows, setRows] = useState<VoucherRow[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [mnmFor, setMnmFor] = useState<{ id: string; name: string } | null>(null);
  const [stock, setStock] = useState<VoucherStoreStock[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState(blank());
  const [saving, setSaving] = useState(false);
  // Ticked for a new voucher only. On an edit it stays unticked unless staff
  // tick it, so saving a name change never touches the store prices.
  const [applyPriceEverywhere, setApplyPriceEverywhere] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [pageErr, setPageErr] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  // Delete, when something still depends on the voucher: what it is, and why.
  const [delFor, setDelFor] = useState<{ voucher: VoucherRow; answer: VoucherDeleteAnswer } | null>(null);
  const [delReason, setDelReason] = useState('');
  const [delBusy, setDelBusy] = useState(false);
  const [delErr, setDelErr] = useState<string | null>(null);

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
    setRows((v.data as VoucherRow[]) ?? []);
    setStores((s.data as Store[]) ?? []);
    setStock((vs.data as VoucherStoreStock[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setForm(blank()); setEditId(null); setErr(null); setApplyPriceEverywhere(true); setModalOpen(true); };
  const openEdit = (v: VoucherRow) => { setForm(blank(v)); setEditId(v.id); setErr(null); setApplyPriceEverywhere(false); setModalOpen(true); };

  const handleSave = async () => {
    if (!form.name.trim()) { setErr('Name is required.'); return; }
    if (!form.code.trim()) { setErr('Code is required.'); return; }
    if (form.voucher_kind === 'fixed_discount' && form.discount_amount <= 0) { setErr('Fixed discount amount must be greater than zero.'); return; }
    if (form.voucher_kind === 'percentage_discount' && (form.discount_percent <= 0 || form.discount_percent > 100)) { setErr('Discount percent must be between 0 and 100.'); return; }
    const isDiscount = form.voucher_kind !== 'normal';
    if (isDiscount && form.discount_category === 'birthday' && !form.birthday_rule) {
      setErr('Choose when the birthday discount applies: on the birthday itself, or in the birth month.'); return;
    }
    setSaving(true); setErr(null);
    const payload: any = {
      name: form.name.trim(), code: form.code.trim(), voucher_kind: form.voucher_kind,
      discount_amount: form.voucher_kind === 'fixed_discount' ? form.discount_amount : null,
      discount_percent: form.voucher_kind === 'percentage_discount' ? form.discount_percent : null,
      max_discount_cap: form.voucher_kind === 'percentage_discount' && form.max_discount_cap > 0 ? form.max_discount_cap : null,
      qty_type: form.qty_type, selling_price: form.selling_price,
      valid_from: form.valid_from || null, valid_until: form.valid_until || null,
      is_active: form.is_active, description: form.description.trim() || null, terms: form.terms.trim() || null,
      // A normal voucher has no category; only a birthday one has a rule.
      discount_category: isDiscount ? form.discount_category : null,
      birthday_rule: isDiscount && form.discount_category === 'birthday' ? form.birthday_rule : null,
      // Only a free-session voucher can be a reward; a discount voucher's flag
      // is left as it is (422's server rule, THERAPY-7, never offers one as a
      // reward; 423's DEPLOY ORDER ships this page only after 422).
      ...(isDiscount ? {} : { reward_eligible: form.reward_eligible }),
    };
    const res = editId
      ? await supabase.from('vouchers').update(payload).eq('id', editId).select().single()
      : await supabase.from('vouchers').insert(payload).select().single();
    if (res.error) { setErr(res.error.message); setSaving(false); return; }
    // Ticked, the price is applied to every store, so it never has to be typed
    // again in the Prices dialog. Each store keeps whether it sells the voucher
    // (p_available null; 423); a store with no price yet sells it.
    if (applyPriceEverywhere && res.data && form.selling_price > 0) {
      const { error: pErr } = await supabase.rpc('set_voucher_price_all_stores', {
        p_voucher_id: (res.data as any).id, p_price: form.selling_price, p_available: null,
      });
      if (pErr) { setErr(`Saved, but the store prices could not be set: ${pErr.message}`); setSaving(false); load(); return; }
    }
    setSaving(false); setModalOpen(false); load();
  };

  // Delete marks the voucher deleted and switches it off (soft_delete_voucher,
  // 423). When customers still hold it, a store has it in stock, or something
  // live offers it, the server says so first and nothing changes until the
  // second step, which needs a reason.
  const handleDelete = async (v: VoucherRow) => {
    if (!window.confirm(`Delete voucher "${v.name}"?`)) return;
    setPageErr(null); setNotice(null);
    const { data, error } = await supabase.rpc('soft_delete_voucher', { p_voucher_id: v.id, p_reason: null, p_confirmed: false });
    if (error) { setPageErr(`"${v.name}" was not deleted: ${error.message}`); return; }
    const answer = (data ?? {}) as VoucherDeleteAnswer;
    if (answer.needs_confirmation) {
      setDelFor({ voucher: v, answer }); setDelReason(''); setDelErr(null);
      return;
    }
    setNotice(`"${v.name}" deleted.`);
    load();
  };

  const confirmDelete = async () => {
    if (!delFor) return;
    if (!delReason.trim()) { setDelErr('Give a short reason. It is kept in the history.'); return; }
    setDelBusy(true); setDelErr(null);
    const { data, error } = await supabase.rpc('soft_delete_voucher', {
      p_voucher_id: delFor.voucher.id, p_reason: delReason.trim(), p_confirmed: true,
    });
    setDelBusy(false);
    if (error) { setDelErr(error.message); return; }
    if (!(data as VoucherDeleteAnswer | null)?.deleted) { setDelErr('The voucher was not deleted. Refresh and try again.'); return; }
    setNotice(`"${delFor.voucher.name}" deleted. Customers keep the vouchers they hold.`);
    setDelFor(null);
    load();
  };

  const openStock = (v: VoucherRow) => { setStockFor(v); setStockStore(stores[0]?.id ?? ''); setStockQty(0); };
  const addStock = async () => {
    if (!stockFor || !stockStore || stockQty <= 0) return;
    setStockBusy(true);
    const { error } = await supabase.rpc('voucher_stock_in', { p_voucher_id: stockFor.id, p_store_id: stockStore, p_quantity: stockQty, p_note: null });
    setStockBusy(false);
    if (error) { alert(error.message); return; }
    setStockFor(null); load();
  };

  const stockFancy = (vId: string) => stock.filter(s => s.voucher_id === vId);
  // Dates are days (YYYY-MM-DD), shown as they are, with no time zone shift.
  const validityText = (v: VoucherRow) => {
    const f = v.valid_from ? dayText(v.valid_from) : null;
    const u = v.valid_until ? dayText(v.valid_until) : null;
    if (!f && !u) return 'No expiry';
    if (f && u) return `${f} → ${u}`;
    if (u) return `Until ${u}`;
    return `From ${f}`;
  };
  const today = sgToday();
  const filtered = rows.filter(v => { const q = search.toLowerCase(); return !q || v.name.toLowerCase().includes(q) || v.code.toLowerCase().includes(q); });

  const kindBadge = (k: VoucherKind) => {
    const cls = k === 'normal' ? 'badge-primary' : k === 'fixed_discount' ? 'badge-accent' : 'badge-success';
    return <span className={`badge ${cls}`}>{VOUCHER_KIND_LABELS[k]}</span>;
  };

  if (!hasAccess) return <NoAccess message="Only Owners and Managers can manage vouchers." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Vouchers</h2><p>Sellable vouchers and discount vouchers. Limited vouchers track stock per store.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={filtered} filename="vouchers" sheetName="Vouchers"
            dateOf={(r: any) => r.created_at} dateLabel="Created"
            columns={[
              { header: 'Name', value: (v: any) => v.name },
              { header: 'Code', value: (v: any) => v.code },
              { header: 'Type', value: (v: any) => v.voucher_kind },
              { header: 'Offered as', value: (v: any) => categoryText(v) ?? '' },
              { header: 'Qty type', value: (v: any) => v.qty_type },
              { header: 'Selling price', value: (v: any) => Number(v.selling_price ?? 0) },
              { header: 'Valid from', value: (v: any) => dayNumbers(v.valid_from) },
              { header: 'Valid until', value: (v: any) => v.valid_until ? dayNumbers(v.valid_until) : 'No expiry' },
              // A discount voucher is never a reward: 422's rule (THERAPY-7), live before this page.
              { header: 'Can be a reward', value: (v: any) => v.voucher_kind === 'normal' ? (v.reward_eligible === false ? 'No' : 'Yes') : 'No' },
              { header: 'Status', value: (v: any) => v.is_active ? 'Active' : 'Inactive' },
            ]} />
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          <button className="btn btn-primary" onClick={openAdd}><Plus size={16} /> Add Voucher</button>
        </div>
      </div>

      {pageErr && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{pageErr}</div></div>}
      {notice && <div className="alert alert-success" role="status"><span>✓</span><div>{notice}</div></div>}

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
                    <td>{kindBadge(v.voucher_kind)}
                      {categoryText(v) && <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 3 }}>{categoryText(v)}</div>}
                      {v.voucher_kind === 'normal' && v.reward_eligible === false &&
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 3 }}>Not given as a reward</div>}</td>
                    <td style={{ fontSize: 13 }}>
                      {v.voucher_kind === 'fixed_discount' ? money(v.discount_amount ?? 0)
                        : v.voucher_kind === 'percentage_discount' ? `${v.discount_percent}%${v.max_discount_cap ? ` (cap ${money(v.max_discount_cap)})` : ''}`
                        : '—'}
                    </td>
                    <td style={{ fontSize: 12.5 }}>
                      {v.qty_type === 'unlimited' ? <span className="badge badge-muted">Unlimited</span>
                        : <span>{stockFancy(v.id).reduce((s, x) => s + x.current_qty, 0)} in stock</span>}
                    </td>
                    {/* Red only after the last valid day, in Singapore. */}
                    <td style={{ fontSize: 11.5, color: isPastValidUntil(v.valid_until, today) ? 'var(--danger)' : 'var(--text-muted)' }}>{validityText(v)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(v.selling_price)}</td>
                    <td><div style={{ display: 'flex', gap: 4 }}>
                      {v.qty_type === 'limited' && <button className="btn btn-secondary btn-sm" onClick={() => openStock(v)}><Boxes size={13} /> Stock</button>}
                      <button className="btn btn-secondary btn-sm" title="Per-store selling prices" onClick={() => setMnmFor({ id: v.id, name: v.name })}>Prices</button>
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => openEdit(v)}><Pencil size={13} /></button>
                      <button className="btn btn-danger btn-sm btn-icon" aria-label={`Delete ${v.name}`} onClick={() => handleDelete(v)}><Trash2 size={13} /></button>
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
                  <option value="normal">{VOUCHER_KIND_LABELS.normal}</option>
                  <option value="fixed_discount">{VOUCHER_KIND_LABELS.fixed_discount}</option>
                  <option value="percentage_discount">{VOUCHER_KIND_LABELS.percentage_discount}</option>
                </select>
              </div>
              <div className="form-group">
                <label>Selling Price (S$)</label>
                <input type="number" min={0} step={0.01} value={form.selling_price || ''} onChange={e => setForm(f => ({ ...f, selling_price: +e.target.value }))} placeholder="0.00" />
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, marginTop: 6, fontWeight: 400 }}>
                  <input type="checkbox" style={{ width: 'auto' }} checked={applyPriceEverywhere}
                    onChange={e => setApplyPriceEverywhere(e.target.checked)} />
                  Use this price at every store
                </label>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                  {editId
                    ? (applyPriceEverywhere
                        ? 'Every store\'s price becomes this price when you save. A store where it is switched off stays off. A store with no price yet starts selling it.'
                        : 'Store prices stay as they are. Tick this to give every store this price.')
                    : 'Every store gets this price and sells it. Untick it to set prices per store under Prices.'}
                </div>
              </div>
            </div>

            {form.voucher_kind === 'normal' && (
              <div className="form-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', fontWeight: 400 }}>
                  <input type="checkbox" style={{ width: 'auto' }} checked={form.reward_eligible}
                    onChange={e => setForm(f => ({ ...f, reward_eligible: e.target.checked }))} />
                  <span style={{ fontSize: 13 }}>Can be given as a reward</span>
                </label>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                  Staff can pick it when they hand out free reward vouchers. Untick it to keep it for sale only.
                  Discount vouchers are never rewards.
                </div>
              </div>
            )}
            {form.voucher_kind !== 'normal' && (
              <div className="form-grid-2">
                <div className="form-group">
                  <label htmlFor="voucher-discount-category">Offered on an invoice line as</label>
                  <select id="voucher-discount-category" value={form.discount_category}
                    onChange={e => setForm(f => ({ ...f, discount_category: e.target.value as VoucherDiscountCategory }))}>
                    <option value="voucher">Voucher</option>
                    <option value="birthday">Birthday discount</option>
                    <option value="staff">Staff discount</option>
                  </select>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                    Which choice of a line's Discount lists this voucher: Vouchers, Birthday discount or Staff discount.
                  </div>
                </div>
                {form.discount_category === 'birthday' && (
                  <div className="form-group">
                    <label htmlFor="voucher-birthday-rule">Birthday rule *</label>
                    <select id="voucher-birthday-rule" value={form.birthday_rule}
                      onChange={e => setForm(f => ({ ...f, birthday_rule: e.target.value as BirthdayRule | '' }))}>
                      <option value="">— Choose —</option>
                      <option value="actual_date">On the birthday (the actual date)</option>
                      <option value="whole_month">In the birth month (the whole month)</option>
                    </select>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                      Checked against the customer's date of birth on the invoice date. One birthday-discount
                      invoice per customer per year.
                    </div>
                  </div>
                )}
              </div>
            )}
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
      {delFor && (
        <Modal title={`Delete ${delFor.voucher.name}?`} maxWidth={480} onClose={() => setDelFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setDelFor(null)}>Keep it</button>
            <button className="btn btn-danger" onClick={() => void confirmDelete()} disabled={delBusy || !delReason.trim()}>
              {delBusy ? 'Deleting…' : 'Delete anyway'}</button></>}>
          <div className="form-grid">
            <div className="alert alert-warning" style={{ marginBottom: 0 }}>
              <span>⚠</span>
              <div>
                <strong>This voucher is still in use.</strong>
                <ul style={{ margin: '6px 0 0 18px' }}>
                  {voucherDependents(delFor.answer).map((line, i) => <li key={i}>{line}</li>)}
                </ul>
                <div style={{ marginTop: 6 }}>
                  Deleting it stops it being sold or offered. Past invoices still show it.
                </div>
              </div>
            </div>
            {delErr && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{delErr}</div></div>}
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label htmlFor="voucher-delete-reason">Reason *</label>
              <textarea id="voucher-delete-reason" rows={2} value={delReason} placeholder="For example: the event is over"
                onChange={e => { setDelReason(e.target.value); setDelErr(null); }} />
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>Kept in the history, with your name.</div>
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
