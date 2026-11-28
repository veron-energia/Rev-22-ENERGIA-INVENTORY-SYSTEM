import React, { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Voucher, VoucherKind, VOUCHER_KIND_LABELS, VoucherDiscountCategory, BirthdayRule } from '../types';
import { Modal } from './ui';
import { useChangedSinceOpened } from '../hooks/useChangedSinceOpened';

/**
 * The Vouchers page's Add / Edit Voucher window, moved here unchanged so the Class page (548) edits a class
 * voucher with exactly the same form, the same writes (a direct update of vouchers, then
 * set_voucher_price_all_stores when "Use this price at every store" is ticked) and the same rights: the
 * database lets only Owners and Managers write vouchers, and both pages show the button to them alone.
 * `voucher` null = a new voucher. It is mounted while the window is open.
 */
// reward_eligible is read here only (the Voucher type in types/index.ts does
// not carry it yet).
export type VoucherRow = Voucher & { reward_eligible?: boolean | null };

export const blank = (v?: VoucherRow) => ({
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

export const VoucherEditModal: React.FC<{ voucher: VoucherRow | null; onClose: () => void; onChanged: () => void }> = ({ voucher, onClose, onChanged }) => {
  const [form, setForm] = useState(() => blank(voucher ?? undefined));
  const [saving, setSaving] = useState(false);
  // Ticked for a new voucher only. On an edit it stays unticked unless staff
  // tick it, so saving a name change never touches the store prices.
  const [applyPriceEverywhere, setApplyPriceEverywhere] = useState(!voucher);
  const formChanged = useChangedSinceOpened(true, [form, applyPriceEverywhere]);
  const [err, setErr] = useState<string | null>(null);

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
    const res = voucher?.id
      ? await supabase.from('vouchers').update(payload).eq('id', voucher?.id).select().single()
      : await supabase.from('vouchers').insert(payload).select().single();
    if (res.error) { setErr(res.error.message); setSaving(false); return; }
    // Ticked, the price is applied to every store, so it never has to be typed
    // again in the Prices dialog. Each store keeps whether it sells the voucher
    // (p_available null; 423); a store with no price yet sells it.
    if (applyPriceEverywhere && res.data && form.selling_price > 0) {
      const { error: pErr } = await supabase.rpc('set_voucher_price_all_stores', {
        p_voucher_id: (res.data as any).id, p_price: form.selling_price, p_available: null,
      });
      if (pErr) { setErr(`Saved, but the store prices could not be set: ${pErr.message}`); setSaving(false); onChanged(); return; }
    }
    setSaving(false); onClose(); onChanged();
  };


  return (
        <Modal title={voucher ? 'Edit Voucher' : 'Add Voucher'} maxWidth={520} onClose={() => onClose()} confirmClose={formChanged}
      footer={<><button className="btn btn-secondary" onClick={() => onClose()}>Cancel</button><button className="btn btn-primary" onClick={handleSave} disabled={saving}>{saving ? 'Saving…' : 'Save'}</button></>}>
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
                  {voucher
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
  );
};

export default VoucherEditModal;
