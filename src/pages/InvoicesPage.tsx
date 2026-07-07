import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Invoice, InvoiceItem, InvoicePayment, Store, Product, Customer,
  PaymentMethod, StoreProductPrice, InvoiceStatus, INVOICE_STATUS_LABELS, Voucher, Promotion, PromotionChoiceGroup, PromotionChoiceOption, isOwnerOrManager, Profile, SERVICE_STAFF_ROLES,
} from '../types';
import { Modal } from '../components/ui';
import { exportCsv } from '../lib/csv';
import {
  Plus, RefreshCw, FileText, Trash2, X, CreditCard, Eye, Search, CheckCircle2, Download, Printer,
} from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;

const StatusBadge: React.FC<{ s: InvoiceStatus }> = ({ s }) => {
  const cls = s === 'paid' ? 'badge-success' : s === 'partially_paid' ? 'badge-primary'
    : s === 'unpaid' || s === 'draft' ? 'badge-accent'
    : s === 'cancelled' || s === 'refunded' ? 'badge-muted' : 'badge-danger';
  return <span className={`badge ${cls}`}>{INVOICE_STATUS_LABELS[s]}</span>;
};

interface LineDraft { kind: 'product' | 'voucher' | 'promotion'; product_id: string; voucher_id: string; promotion_id: string; quantity: number; line_voucher_id: string; selections: Record<string, Record<string, number>>; }

const InvoicesPage: React.FC = () => {
  const { profile } = useAuth();
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [promotions, setPromotions] = useState<Promotion[]>([]);
  const [choiceGroups, setChoiceGroups] = useState<PromotionChoiceGroup[]>([]);
  const [choiceOptions, setChoiceOptions] = useState<PromotionChoiceOption[]>([]);
  const [storeInv, setStoreInv] = useState<any[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [assignedStoreId, setAssignedStoreId] = useState<string | null>(null);
  const [cServiceStaff, setCServiceStaff] = useState<string[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [prices, setPrices] = useState<StoreProductPrice[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<'all' | InvoiceStatus>('all');

  // Create modal
  const [createOpen, setCreateOpen] = useState(false);
  const [cStore, setCStore] = useState('');
  const [cCustomer, setCCustomer] = useState('');
  const [cLines, setCLines] = useState<LineDraft[]>([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]);
  const [cDiscountVoucher, setCDiscountVoucher] = useState('');
  const [cDiscount, setCDiscount] = useState(0);
  const [cErr, setCErr] = useState<string | null>(null);
  const [cSaving, setCSaving] = useState(false);

  // Detail / payment modal
  const [detail, setDetail] = useState<Invoice | null>(null);
  const [detailItems, setDetailItems] = useState<InvoiceItem[]>([]);
  const [detailPromoItems, setDetailPromoItems] = useState<any[]>([]);      // fixed contents of promotions on this invoice
  const [detailSelections, setDetailSelections] = useState<any[]>([]);      // chosen items for this invoice
  const [detailPayments, setDetailPayments] = useState<InvoicePayment[]>([]);
  const [detailServiceStaff, setDetailServiceStaff] = useState<string[]>([]);
  const [payLines, setPayLines] = useState<{ payment_method_id: string; amount: number }[]>([]);
  const [payErr, setPayErr] = useState<string | null>(null);
  const [payBusy, setPayBusy] = useState(false);

  const loadAll = useCallback(async () => {
    setLoading(true);
    const [inv, st, pr, cu, pm, pp, vc, pm2, cg, co, si, prof, myStore] = await Promise.all([
      supabase.from('invoices').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('*').is('deleted_at', null).order('full_name'),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('store_product_prices').select('*').is('deleted_at', null),
      supabase.from('vouchers').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('promotions').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('promotion_choice_groups').select('*'),
      supabase.from('promotion_choice_options').select('*'),
      supabase.from('store_inventory').select('store_id,product_id,current_qty'),
      supabase.from('profiles').select('id,full_name,role,work_phone,is_active').is('deleted_at', null).eq('is_active', true),
      supabase.rpc('my_assigned_store_id'),
    ]);
    setInvoices((inv.data as Invoice[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setProducts((pr.data as Product[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    setMethods((pm.data as PaymentMethod[]) ?? []);
    setPrices((pp.data as StoreProductPrice[]) ?? []);
    setVouchers((vc.data as Voucher[]) ?? []);
    setPromotions((pm2.data as Promotion[]) ?? []);
    setChoiceGroups((cg.data as PromotionChoiceGroup[]) ?? []);
    setChoiceOptions((co.data as PromotionChoiceOption[]) ?? []);
    setStoreInv((si.data as any[]) ?? []);
    const allProfiles = (prof.data as Profile[]) ?? [];
    setProfiles(allProfiles);
    setAssignedStoreId((myStore.data as string | null) ?? null);
    setLoading(false);
  }, []);
  useEffect(() => { loadAll(); }, [loadAll]);

  const storeName = (id: string) => stores.find(s => s.id === id)?.name ?? '—';
  const custName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';
  const prodName = (id: string) => products.find(p => p.id === id)?.name ?? '—';
  const methodName = (id: string) => methods.find(m => m.id === id)?.name ?? '—';
  const priceFor = (storeId: string, productId: string) =>
    prices.find(p => p.store_id === storeId && p.product_id === productId)?.selling_price ?? null;

  // Products available at the chosen store (those with a price).
  const stockQty = (storeId: string, productId: string): number =>
    storeInv.find(s => s.store_id === storeId && s.product_id === productId)?.current_qty ?? 0;

  const storeProducts = useMemo(() =>
    cStore ? products.filter(p => priceFor(cStore, p.id) !== null && stockQty(cStore, p.id) > 0) : [],
    [cStore, products, prices, storeInv]);

  const voucherPrice = (id: string) => vouchers.find(v => v.id === id)?.selling_price ?? null;

  const promoPrice = (id: string) => promotions.find(p => p.id === id)?.fixed_price ?? null;

  const lineUnit = (l: LineDraft): number | null =>
    l.kind === 'voucher' ? (l.voucher_id ? voucherPrice(l.voucher_id) : null)
    : l.kind === 'promotion' ? (l.promotion_id ? promoPrice(l.promotion_id) : null)
    : (cStore && l.product_id ? priceFor(cStore, l.product_id) : null);

  const createSubtotal = useMemo(() =>
    cLines.reduce((sum, l) => {
      const price = lineUnit(l);
      return sum + (price ? price * l.quantity : 0);
    }, 0), [cLines, cStore, prices, vouchers]);

  // Discount vouchers selectable for redemption (fixed/percentage kinds).
  // Discount slots only show vouchers valid TODAY (not-yet-valid and expired are hidden).
  // They can still be SOLD as line items (the buyer redeems later, once valid).
  const isDateValid = (v: Voucher) => {
    const d = new Date();
    const today = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    return (!v.valid_from || v.valid_from <= today) && (!v.valid_until || v.valid_until >= today);
  };
  const discountVouchers = useMemo(() => vouchers.filter(v => v.voucher_kind !== 'normal' && isDateValid(v)), [vouchers]);

  const groupsFor = (promoId: string) => choiceGroups.filter(g => g.promotion_id === promoId);
  const optionsFor = (groupId: string) => choiceOptions.filter(o => o.group_id === groupId);
  const selSum = (l: LineDraft, gId: string) => Object.values(l.selections[gId] ?? {}).reduce((s, n) => s + (n || 0), 0);

  // Baseline of a product group = cheapest listed option at the chosen store.
  const groupBaseline = (gId: string): number | null => {
    if (!cStore) return null;
    const prices = optionsFor(gId)
      .map(o => (o.product_id ? priceFor(cStore, o.product_id) : null))
      .filter((p): p is number => p != null);
    return prices.length ? Math.min(...prices) : null;
  };

  // 3rd-party product lines are discount-proof: invoice-level discounts never touch them.
  const isThirdParty = (productId: string) => products.find(p => p.id === productId)?.product_type === 'third_party';
  const thirdPartySum = useMemo(() =>
    cLines.reduce((s, l) => {
      if (l.kind !== 'product' || !l.product_id || !isThirdParty(l.product_id)) return s;
      const u = lineUnit(l);
      return s + (u ? u * l.quantity : 0);
    }, 0), [cLines, cStore, prices, products]);

  // Total top-up across all promotion lines (mirrors promotion_selections_topup).
  const topupPreview = useMemo(() => {
    if (!cStore) return 0;
    let sum = 0;
    for (const l of cLines) {
      if (l.kind !== 'promotion' || !l.promotion_id) continue;
      for (const g of groupsFor(l.promotion_id)) {
        if (g.item_kind !== 'product') continue;
        const baseline = groupBaseline(g.id);
        if (baseline == null) continue;
        // Listed options never pay a top-up — only picks outside the options do.
        const listed = new Set(optionsFor(g.id).map(o => o.product_id).filter(Boolean));
        for (const [pid, q] of Object.entries(l.selections[g.id] ?? {})) {
          if (!q || listed.has(pid)) continue;
          const pr = priceFor(cStore, pid);
          if (pr != null && pr > baseline) sum += (pr - baseline) * q;
        }
      }
    }
    return sum;
  }, [cLines, cStore, prices, choiceGroups, choiceOptions]);

  // Mirror of SQL voucher_discount_amount for previews.
  const voucherDiscAmount = (v: Voucher | undefined, base: number): number => {
    if (!v) return 0;
    let disc = 0;
    if (v.voucher_kind === 'fixed_discount') {
      disc = v.discount_amount ?? 0;
      if (base <= disc) return 0;   // fixed vouchers need the base STRICTLY above
    }
    else if (v.voucher_kind === 'percentage_discount') {
      disc = Math.round(base * (v.discount_percent ?? 0)) / 100;
      if (v.max_discount_cap != null && disc > v.max_discount_cap) disc = v.max_discount_cap;
    }
    if (disc > base) disc = base;
    return disc < 0 ? 0 : disc;
  };

  // Per-line voucher discounts (product lines only).
  const lineVoucherDiscountPreview = useMemo(() =>
    cLines.reduce((sum, l) => {
      if (l.kind !== 'product' || !l.line_voucher_id) return sum;
      const unit = lineUnit(l);
      if (!unit) return sum;
      return sum + voucherDiscAmount(vouchers.find(v => v.id === l.line_voucher_id), unit * l.quantity);
    }, 0), [cLines, vouchers, cStore, prices]);

  // Whole-invoice voucher: base = subtotal − manual − line-voucher discounts (matches SQL).
  const voucherDiscountPreview = useMemo(() => {
    if (!cDiscountVoucher) return 0;
    const base = Math.max(0, createSubtotal + topupPreview - thirdPartySum - (cDiscount || 0) - lineVoucherDiscountPreview);
    return voucherDiscAmount(vouchers.find(x => x.id === cDiscountVoucher), base);
  }, [cDiscountVoucher, vouchers, createSubtotal, topupPreview, thirdPartySum, cDiscount, lineVoucherDiscountPreview]);

  const hasPromoLine = useMemo(() => cLines.some(l => l.kind === 'promotion' && l.promotion_id), [cLines]);

  // Whole-invoice voucher eligibility: fixed vouchers need the discountable
  // base (excl. 3rd-party lines) to be STRICTLY above their amount.
  const wholeVoucherBase = useMemo(() =>
    Math.max(0, createSubtotal + topupPreview - thirdPartySum - (cDiscount || 0) - lineVoucherDiscountPreview),
    [createSubtotal, topupPreview, thirdPartySum, cDiscount, lineVoucherDiscountPreview]);
  const eligibleWholeVouchers = useMemo(() =>
    discountVouchers.filter(v => v.voucher_kind !== 'fixed_discount' || (v.discount_amount ?? 0) < wholeVoucherBase),
    [discountVouchers, wholeVoucherBase]);
  useEffect(() => {
    if (cDiscountVoucher && !eligibleWholeVouchers.some(v => v.id === cDiscountVoucher)) setCDiscountVoucher('');
  }, [cDiscountVoucher, eligibleWholeVouchers]);
  useEffect(() => { if (hasPromoLine && cDiscountVoucher) setCDiscountVoucher(''); }, [hasPromoLine, cDiscountVoucher]);

  const previewTotal = useMemo(() => {
    const discountable = Math.max(0, createSubtotal + topupPreview - thirdPartySum - lineVoucherDiscountPreview);
    const invLevel = Math.min((cDiscount || 0) + voucherDiscountPreview, discountable);
    return Math.max(0, createSubtotal + topupPreview - lineVoucherDiscountPreview - invLevel);
  }, [createSubtotal, topupPreview, thirdPartySum, cDiscount, lineVoucherDiscountPreview, voucherDiscountPreview]);


  // All vouchers can be sold as a line item (a discount voucher sold now is
  // redeemed by the buyer on a future invoice). Only discount vouchers can be
  // used in the Discount Voucher slot (Normal vouchers have no discount value).
  const sellableVouchers = useMemo(() => vouchers, [vouchers]);

  const resetCreate = () => {
    setCStore(isStaff ? (assignedStoreId ?? '') : '');
    setCCustomer('');
    setCLines([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]); setCDiscount(0);
    setCDiscountVoucher(''); setCServiceStaff([]); setCErr(null);
  };

  const handleCreate = async () => {
    if (isStaff && !assignedStoreId) { setCErr('You are not assigned to a store, so you cannot create invoices. Ask an Owner or Manager to assign you.'); return; }
    const effectiveStore = isStaff ? (assignedStoreId ?? '') : cStore;
    if (!effectiveStore) { setCErr('Select a store.'); return; }
    if (!cCustomer) { setCErr('Select a customer.'); return; }
    const activeLines = cLines.filter(l => l.quantity > 0 && (l.kind === 'product' ? l.product_id : l.kind === 'voucher' ? l.voucher_id : l.promotion_id));
    if (activeLines.length === 0) { setCErr('Add at least one product or voucher.'); return; }
    // Choice-group completeness check (client-side; server re-validates).
    for (const l of activeLines) {
      if (l.kind !== 'promotion') continue;
      for (const g of groupsFor(l.promotion_id)) {
        const need = g.choose_qty * l.quantity;
        const got = selSum(l, g.id);
        if (got !== need) {
          setCErr(`"${promotions.find(p => p.id === l.promotion_id)?.name}" — ${g.label}: choose exactly ${need} (currently ${got}).`);
          return;
        }
      }
    }
    const validLines = activeLines.map(l => l.kind === 'voucher'
      ? { kind: 'voucher', voucher_id: l.voucher_id, quantity: l.quantity }
      : l.kind === 'promotion'
      ? {
          kind: 'promotion', promotion_id: l.promotion_id, quantity: l.quantity,
          selections: groupsFor(l.promotion_id).map(g => ({
            group_id: g.id,
            options: Object.entries(l.selections[g.id] ?? {})
              .filter(([, q]) => (q || 0) > 0)
              .map(([itemId, q]) => (g.item_kind === 'product'
                ? { product_id: itemId, voucher_id: null, quantity: q }
                : { product_id: null, voucher_id: itemId, quantity: q })),
          })),
        }
      : { kind: 'product', product_id: l.product_id, quantity: l.quantity, line_voucher_id: (l.line_voucher_id && !isThirdParty(l.product_id)) ? l.line_voucher_id : null });
    setCSaving(true); setCErr(null);
    const { error } = await supabase.rpc('create_invoice', {
      p_store_id: effectiveStore, p_customer_id: cCustomer, p_affiliate_id: null,
      p_items: validLines, p_discount_total: cDiscount || 0, p_notes: null,
      p_discount_voucher_id: cDiscountVoucher || null,
      p_service_staff: cServiceStaff,
    });
    setCSaving(false);
    if (error) { setCErr(error.message); return; }
    setCreateOpen(false); resetCreate(); loadAll();
  };

  const openDetail = async (inv: Invoice) => {
    setDetail(inv);
    const [items, pays, svc] = await Promise.all([
      supabase.from('invoice_items').select('*').eq('invoice_id', inv.id),
      supabase.from('invoice_payments').select('*').eq('invoice_id', inv.id),
      supabase.from('invoice_service_staff').select('staff_id').eq('invoice_id', inv.id),
    ]);
    const its = (items.data as InvoiceItem[]) ?? [];
    setDetailItems(its);
    setDetailPayments((pays.data as InvoicePayment[]) ?? []);
    setDetailServiceStaff(((svc.data as any[]) ?? []).map(r => r.staff_id));
    // Promotion contents: fixed items of the promotions on this invoice + this invoice's chosen selections.
    const promoIds = its.filter(i => i.line_kind === 'promotion' && (i as any).promotion_id).map(i => (i as any).promotion_id);
    const itemIds = its.map(i => i.id);
    const [pi, sel] = await Promise.all([
      promoIds.length ? supabase.from('promotion_items').select('*').in('promotion_id', promoIds) : Promise.resolve({ data: [] } as any),
      itemIds.length ? supabase.from('invoice_promotion_selections').select('*').in('invoice_item_id', itemIds) : Promise.resolve({ data: [] } as any),
    ]);
    setDetailPromoItems((pi.data as any[]) ?? []);
    setDetailSelections((sel.data as any[]) ?? []);
    const remaining = inv.total_amount - inv.paid_amount;
    setPayLines([{ payment_method_id: methods[0]?.id ?? '', amount: remaining > 0 ? remaining : 0 }]);
    setPayErr(null);
  };

  const payTotal = useMemo(() => payLines.reduce((s, p) => s + (p.amount || 0), 0), [payLines]);

  const handlePay = async () => {
    if (!detail) return;
    const valid = payLines.filter(p => p.payment_method_id && p.amount > 0);
    if (valid.length === 0) { setPayErr('Add at least one payment.'); return; }
    setPayBusy(true); setPayErr(null);
    const { error } = await supabase.rpc('pay_invoice', { p_invoice_id: detail.id, p_payments: valid });
    setPayBusy(false);
    if (error) { setPayErr(error.message); return; }
    setDetail(null); loadAll();
  };

  const handleDelete = async (inv: Invoice) => {
    if (inv.status === 'paid') { alert('Paid invoices cannot be deleted.'); return; }
    if (!confirm(`Delete invoice ${inv.invoice_no}?`)) return;
    const { error } = await supabase.rpc('delete_invoice', { p_invoice_id: inv.id });
    if (error) { alert(error.message); return; }
    loadAll();
  };

  // Phase 4: request refund or cancellation
  const [actionType, setActionType] = useState<'invoice_refund' | 'invoice_cancel' | null>(null);
  const [actionReturnStock, setActionReturnStock] = useState(true);
  const [actionReason, setActionReason] = useState('');
  const [actionBusy, setActionBusy] = useState(false);
  const [actionErr, setActionErr] = useState<string | null>(null);

  const submitAction = async () => {
    if (!detail || !actionType) return;
    if (!actionReason.trim()) { setActionErr('A reason is required.'); return; }
    setActionBusy(true); setActionErr(null);
    const { error } = await supabase.rpc('request_invoice_action', {
      p_invoice_id: detail.id, p_type: actionType,
      p_return_stock: actionReturnStock, p_reason: actionReason.trim(),
    });
    setActionBusy(false);
    if (error) { setActionErr(error.message); return; }
    setActionType(null); setActionReason(''); setDetail(null); loadAll();
  };

  const canExport = isOwnerOrManager(profile?.role);
  const isStaff = profile?.role === 'staff';
  const serviceStaffOptions = useMemo(() => profiles.filter(p => SERVICE_STAFF_ROLES.includes(p.role)), [profiles]);
  const staffName = (id: string) => profiles.find(p => p.id === id)?.full_name ?? '—';
  const effectiveStore = isStaff ? (assignedStoreId ?? '') : cStore;

  const filtered = invoices.filter(i => statusFilter === 'all' || i.status === statusFilter);

  const doExport = () => exportCsv(`invoices-${new Date().toISOString().slice(0,10)}.csv`,
    filtered.map(i => ({
      invoice_no: i.invoice_no,
      date: new Date(i.created_at).toLocaleDateString(),
      store: stores.find(s => s.id === i.store_id)?.name ?? '',
      customer: customers.find(cu => cu.id === i.customer_id)?.full_name ?? '',
      subtotal: Number(i.subtotal).toFixed(2),
      discount: Number(i.discount_total).toFixed(2),
      total: Number(i.total_amount).toFixed(2),
      paid: Number(i.paid_amount).toFixed(2),
      status: i.status,
    })));

  const printInvoice = () => {
    if (!detail) return;
    const store = stores.find(s => s.id === detail.store_id);
    const cust = customers.find(cu => cu.id === detail.customer_id);
    const esc = (s: any) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;');
    const subFor = (it: InvoiceItem) => {
      const fixed = detailPromoItems.filter(p => p.promotion_id === (it as any).promotion_id);
      const chosen = detailSelections.filter(s => s.invoice_item_id === it.id);
      const nameOf = (x: any) => x.product_id ? (products.find(p => p.id === x.product_id)?.name ?? '')
        : x.voucher_id ? (vouchers.find(v => v.id === x.voucher_id)?.name ?? '')
        : x.child_promotion_id ? (promotions.find(p => p.id === x.child_promotion_id)?.name ?? '')
        : (x.treatment_name ?? '');
      return [
        ...fixed.map(f => `<tr class="sub"><td colspan="3">— ${esc(nameOf(f))} × ${f.quantity * it.quantity} (included)</td><td></td></tr>`),
        ...chosen.map(s => `<tr class="sub"><td colspan="3">— ${esc(nameOf(s))} × ${s.quantity} (chosen)</td><td></td></tr>`),
      ].join('');
    };
    const lineName = (it: InvoiceItem) =>
      it.line_kind === 'voucher' ? `Voucher: ${vouchers.find(v => v.id === it.voucher_id)?.name ?? ''}`
      : it.line_kind === 'promotion' ? `Promotion: ${promotions.find(p => p.id === (it as any).promotion_id)?.name ?? ''}`
      : prodName(it.product_id ?? '');
    const itemRows = detailItems.map(it => {
      const lv = (it as any).line_voucher_id
        ? `<div class="mut">Voucher ${esc(vouchers.find(v => v.id === (it as any).line_voucher_id)?.name ?? '')} −S$${Number((it as any).line_discount ?? 0).toFixed(2)}</div>` : '';
      const tu = Number((it as any).topup_amount ?? 0) > 0 ? `<div class="mut">incl. top-up S$${Number((it as any).topup_amount).toFixed(2)}</div>` : '';
      return `<tr><td>${esc(lineName(it))}${lv}${tu}</td><td class="r">${it.quantity}</td><td class="r">S$${Number(it.unit_price).toFixed(2)}</td><td class="r"><b>S$${Number(it.line_total).toFixed(2)}</b></td></tr>` +
        (it.line_kind === 'promotion' ? subFor(it) : '');
    }).join('');
    const payRows = detailPayments.map(p =>
      `<tr><td>${esc(methods.find(m => m.id === p.payment_method_id)?.name ?? '')}${p.payment_reference ? ' · ' + esc(p.payment_reference) : ''}</td><td class="r">S$${Number(p.amount).toFixed(2)}</td></tr>`).join('');
    const html = `<!doctype html><html><head><title>${esc(detail.invoice_no)}</title><style>
      body{font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#111;margin:32px;}
      h1{font-size:20px;margin:0;} h2{font-size:14px;margin:18px 0 6px;}
      .mut{color:#666;font-size:11px;} .r{text-align:right;}
      table{width:100%;border-collapse:collapse;margin-top:6px;}
      th{font-size:11px;text-transform:uppercase;color:#666;text-align:left;border-bottom:1px solid #999;padding:5px 6px;}
      th.r{text-align:right;} td{padding:5px 6px;border-bottom:1px solid #eee;vertical-align:top;}
      tr.sub td{border-bottom:none;padding:1px 6px 1px 18px;font-size:11.5px;color:#555;}
      .totals{margin-top:10px;width:280px;margin-left:auto;} .totals td{border:none;padding:3px 6px;}
      .grand{font-size:16px;font-weight:bold;border-top:1px solid #999;}
      .head{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #111;padding-bottom:12px;}
    </style></head><body>
      <div class="head">
        <div><h1>Energia</h1><div class="mut">${esc(store?.name ?? '')}</div><div class="mut">${esc((store as any)?.address ?? '')}</div></div>
        <div style="text-align:right"><h1>${esc(detail.invoice_no)}</h1>
          <div class="mut">Date: ${new Date(detail.created_at).toLocaleDateString()}</div>
          <div class="mut">Status: ${esc(detail.status)}</div></div>
      </div>
      <h2>Bill To</h2>
      <div>${esc(cust?.full_name ?? '—')}</div><div class="mut">${esc(cust?.phone ?? '')}</div>
      <h2>Items</h2>
      <table><thead><tr><th>Item</th><th class="r">Qty</th><th class="r">Unit</th><th class="r">Total</th></tr></thead><tbody>${itemRows}</tbody></table>
      <table class="totals">
        <tr><td>Subtotal</td><td class="r">S$${Number(detail.subtotal).toFixed(2)}</td></tr>
        <tr><td>Discount</td><td class="r">−S$${Number(detail.discount_total).toFixed(2)}</td></tr>
        <tr class="grand"><td>Total</td><td class="r">S$${Number(detail.total_amount).toFixed(2)}</td></tr>
        <tr><td>Paid</td><td class="r">S$${Number(detail.paid_amount).toFixed(2)}</td></tr>
      </table>
      ${payRows ? `<h2>Payments</h2><table><tbody>${payRows}</tbody></table>` : ''}
      <p class="mut" style="margin-top:28px">Thank you for shopping with Energia.</p>
      <script>window.onload=function(){window.print();}</script>
    </body></html>`;
    const w = window.open('', '_blank');
    if (!w) { alert('Please allow pop-ups to print.'); return; }
    w.document.write(html); w.document.close();
  };

  const statusOptions: ('all' | InvoiceStatus)[] = ['all', 'unpaid', 'partially_paid', 'paid', 'cancelled', 'refunded'];

  return (
    <div>
      <div className="page-header">
        <div><h2>Invoices</h2><p>Create invoices for a store. Stock is deducted only when an invoice is fully paid.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={loadAll}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          {canExport && <button className="btn btn-secondary" onClick={doExport}><Download size={15} /> Export CSV</button>}
          <button className="btn btn-primary" onClick={() => { resetCreate(); setCreateOpen(true); }}><Plus size={16} /> New Invoice</button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 14, flexWrap: 'wrap' }}>
        {statusOptions.map(s => (
          <button key={s} className={`btn btn-sm ${statusFilter === s ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setStatusFilter(s)}>
            {s === 'all' ? 'All' : INVOICE_STATUS_LABELS[s]}
          </button>
        ))}
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : filtered.length === 0 ? <div className="empty-state"><FileText size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No invoices yet</p></div>
          : (
            <table>
              <thead><tr><th>Invoice</th><th>Date</th><th>Store</th><th>Customer</th><th style={{ textAlign: 'right' }}>Total</th><th style={{ textAlign: 'right' }}>Paid</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {filtered.map(inv => (
                  <tr key={inv.id}>
                    <td><strong style={{ fontFamily: 'var(--font-display)' }}>{inv.invoice_no}</strong></td>
                    <td style={{ fontSize: 12.5, whiteSpace: 'nowrap' }}>{new Date(inv.created_at).toLocaleDateString()}</td>
                    <td style={{ fontSize: 12.5 }}>{storeName(inv.store_id)}</td>
                    <td style={{ fontSize: 13 }}>{custName(inv.customer_id)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(inv.total_amount)}</td>
                    <td style={{ textAlign: 'right', color: inv.paid_amount >= inv.total_amount ? 'var(--success)' : 'var(--text-muted)' }}>{money(inv.paid_amount)}</td>
                    <td><StatusBadge s={inv.status} /></td>
                    <td>
                      <div style={{ display: 'flex', gap: 4 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => openDetail(inv)}><Eye size={13} /> View</button>
                        {inv.status !== 'paid' && inv.status !== 'cancelled' && inv.status !== 'refunded' && (
                          <button className="btn btn-danger btn-sm btn-icon" onClick={() => handleDelete(inv)}><Trash2 size={13} /></button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Create invoice modal */}
      {createOpen && (
        <Modal title="New Invoice" maxWidth={640} onClose={() => setCreateOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setCreateOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={handleCreate} disabled={cSaving}>{cSaving ? 'Creating…' : 'Create Invoice'}</button></>}>
          <div className="form-grid">
            {cErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{cErr}</div></div>}
            <div className="form-grid-2">
              <div className="form-group">
                <label>Store *</label>
                {isStaff ? (
                  <input value={stores.find(s => s.id === (assignedStoreId ?? ''))?.name ?? 'No store assigned'} disabled style={{ background: 'var(--surface-2)' }} />
                ) : (
                  <select value={cStore} onChange={e => { setCStore(e.target.value); setCLines([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]); }}>
                    <option value="">— Select store —</option>
                    {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>
                )}
              </div>
              <div className="form-group">
                <label>Customer *</label>
                <select value={cCustomer} onChange={e => setCCustomer(e.target.value)}>
                  <option value="">— Select customer —</option>
                  {customers.map(c => <option key={c.id} value={c.id}>{c.full_name} ({c.phone})</option>)}
                </select>
              </div>
            </div>
            {cCustomer && (() => {
              const cust = customers.find(c => c.id === cCustomer);
              const referrer = cust?.referred_by ? customers.find(c => c.id === cust.referred_by) : null;
              return (
                <div className="alert alert-info" style={{ marginBottom: 0 }}>
                  <span>ℹ️</span>
                  <div>{referrer
                    ? <>Commission referrer: <strong>{referrer.full_name}</strong> earns Tier 1 when this invoice is fully paid{referrer.referred_by ? ', and their referrer earns Tier 2.' : '.'}</>
                    : <>This customer has no referrer set, so no commission will be earned. You can set a referrer on the Customers page.</>}</div>
                </div>
              );
            })()}

            {effectiveStore && (
              <div>
                <label>Served by <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— select everyone who served this customer (Owner / Manager / Staff)</span></label>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 6 }}>
                  {serviceStaffOptions.length === 0 && <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No eligible staff found.</span>}
                  {serviceStaffOptions.map(s => {
                    const on = cServiceStaff.includes(s.id);
                    return (
                      <button key={s.id} type="button"
                        className={`btn btn-sm ${on ? 'btn-primary' : 'btn-secondary'}`}
                        onClick={() => setCServiceStaff(prev => on ? prev.filter(x => x !== s.id) : [...prev, s.id])}>
                        {on ? '✓ ' : ''}{s.full_name}
                      </button>
                    );
                  })}
                </div>
                {cServiceStaff.length > 0 && <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 6 }}>Staff commission will be split equally among {cServiceStaff.length} selected once the invoice is paid.</div>}
              </div>
            )}

            {effectiveStore && (
              <div>
                <label>Items <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— products (priced at this store) or sellable vouchers</span></label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 6 }}>
                  {cLines.map((line, i) => {
                    const price = lineUnit(line);
                    return (
                    <React.Fragment key={i}>
                      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                        <select value={line.kind} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, kind: e.target.value as LineDraft['kind'], product_id: '', voucher_id: '', promotion_id: '' } : l))} style={{ width: 110 }}>
                          <option value="product">Product</option>
                          <option value="voucher">Voucher</option>
                          <option value="promotion">Promotion</option>
                        </select>
                        {line.kind === 'product' ? (
                          <select value={line.product_id} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, product_id: e.target.value } : l))} style={{ flex: 1 }}>
                            <option value="">— Product —</option>
                            {storeProducts.map(p => <option key={p.id} value={p.id}>{p.name} — {money(priceFor(cStore, p.id)!)}</option>)}
                          </select>
                        ) : line.kind === 'voucher' ? (
                          <select value={line.voucher_id} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, voucher_id: e.target.value } : l))} style={{ flex: 1 }}>
                            <option value="">— Voucher —</option>
                            {sellableVouchers.map(v => <option key={v.id} value={v.id}>{v.name} — {money(v.selling_price)}</option>)}
                          </select>
                        ) : (
                          <select value={line.promotion_id} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, promotion_id: e.target.value } : l))} style={{ flex: 1 }}>
                            <option value="">— Promotion —</option>
                            {promotions.map(p => <option key={p.id} value={p.id}>{p.name} — {money(p.fixed_price)}</option>)}
                          </select>
                        )}
                        <input type="number" min={1} value={line.quantity || ''} placeholder="Qty" style={{ width: 70 }}
                          onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, quantity: +e.target.value } : l))} />
                        <span style={{ width: 78, textAlign: 'right', fontSize: 13, fontWeight: 600 }}>{price ? money(price * line.quantity) : '—'}</span>
                        <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setCLines(ls => ls.filter((_, j) => j !== i))} disabled={cLines.length === 1}><X size={13} /></button>
                      </div>
                      {line.kind === 'product' && line.product_id && isThirdParty(line.product_id) && (
                        <div style={{ marginLeft: 118, marginTop: -2, fontSize: 11.5, color: 'var(--text-muted)' }}>
                          3rd-party product — discounts don't apply.
                        </div>
                      )}
                      {line.kind === 'product' && line.product_id && !isThirdParty(line.product_id) && discountVouchers.length > 0 && (
                        <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginLeft: 118, marginTop: -2 }}>
                          <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Line voucher:</span>
                          <select value={line.line_voucher_id} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, line_voucher_id: e.target.value } : l))} style={{ flex: 1, maxWidth: 320, fontSize: 12.5 }}>
                            <option value="">— None —</option>
                            {discountVouchers.filter(v => v.voucher_kind !== 'fixed_discount' || (v.discount_amount ?? 0) < (lineUnit(line) ?? 0) * line.quantity).map(v => (
                              <option key={v.id} value={v.id}>
                                {v.name} — {v.voucher_kind === 'fixed_discount' ? money(v.discount_amount ?? 0) + ' off' : `${v.discount_percent}% off${v.max_discount_cap ? ` (cap ${money(v.max_discount_cap)})` : ''}`}
                              </option>
                            ))}
                          </select>
                          {line.line_voucher_id && price ? <span style={{ fontSize: 11.5, color: 'var(--success)' }}>− {money(voucherDiscAmount(vouchers.find(v => v.id === line.line_voucher_id), price * line.quantity))}</span> : null}
                        </div>
                      )}
                      {line.kind === 'promotion' && line.promotion_id && groupsFor(line.promotion_id).map(g => {
                        const need = g.choose_qty * line.quantity;
                        const got = selSum(line, g.id);
                        const done = got === need;
                        const isProd = g.item_kind === 'product';
                        const baseline = isProd ? groupBaseline(g.id) : null;
                        const optionItemIds = optionsFor(g.id)
                          .map(o => (isProd ? o.product_id : o.voucher_id))
                          .filter((x): x is string => !!x)
                          .filter(x => !isProd || stockQty(cStore, x) > 0);
                        const pickedIds = Object.entries(line.selections[g.id] ?? {}).filter(([, q]) => (q || 0) > 0).map(([id]) => id);
                        const extraIds = pickedIds.filter(id => !optionItemIds.includes(id));
                        const displayIds = [...optionItemIds, ...extraIds];
                        const itemName = (id: string) => isProd
                          ? (products.find(p => p.id === id)?.name ?? '—')
                          : (vouchers.find(v => v.id === id)?.name ?? '—');
                        const itemPrice = (id: string): number | null => isProd
                          ? priceFor(cStore, id)
                          : (vouchers.find(v => v.id === id)?.selling_price ?? null);
                        const setQty = (itemId: string, q: number) => setCLines(ls => ls.map((l, j) => j === i
                          ? { ...l, selections: { ...l.selections, [g.id]: { ...(l.selections[g.id] ?? {}), [itemId]: Math.max(0, q) } } }
                          : l));
                        return (
                          <div key={g.id} style={{ marginLeft: 118, border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', overflow: 'hidden' }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 12px', background: 'var(--surface-2)' }}>
                              <strong style={{ flex: 1, fontSize: 12.5 }}>{g.label}</strong>
                              {isProd && baseline != null && <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>base {money(baseline)}</span>}
                              <span className={`badge ${done ? 'badge-success' : 'badge-danger'}`}>{got} / {need} chosen</span>
                            </div>
                            <div>
                              {displayIds.map(id => {
                                const pr = itemPrice(id);
                                const isListed = optionItemIds.includes(id);
                                const topup = isProd && !isListed && baseline != null && pr != null && pr > baseline ? pr - baseline : 0;
                                const val = line.selections[g.id]?.[id] ?? 0;
                                return (
                                  <div key={id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '7px 12px', borderTop: '1px solid var(--border)' }}>
                                    <span style={{ flex: 1, fontSize: 12.5, fontWeight: val > 0 ? 600 : 400 }}>{itemName(id)}</span>
                                    <span style={{ fontSize: 11.5, color: 'var(--text-muted)', minWidth: 62, textAlign: 'right' }}>{pr != null ? money(pr) : '—'}</span>
                                    <span style={{ fontSize: 11, minWidth: 74, textAlign: 'right', color: topup > 0 ? 'var(--danger)' : 'var(--text-muted)' }}>
                                      {topup > 0 ? `+${money(topup)} top-up` : isProd ? (isListed ? 'included' : 'no top-up') : ''}
                                    </span>
                                    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                                      <button className="btn btn-secondary btn-sm btn-icon" style={{ width: 26, height: 26, padding: 0 }} onClick={() => setQty(id, val - 1)} disabled={val <= 0}>−</button>
                                      <span style={{ minWidth: 20, textAlign: 'center', fontSize: 13, fontWeight: 600 }}>{val}</span>
                                      <button className="btn btn-secondary btn-sm btn-icon" style={{ width: 26, height: 26, padding: 0 }} onClick={() => setQty(id, val + 1)} disabled={done}>+</button>
                                    </div>
                                  </div>
                                );
                              })}
                              {isProd && (
                                <div style={{ display: 'flex', gap: 8, alignItems: 'center', padding: '8px 12px', borderTop: '1px solid var(--border)', background: 'var(--surface-2)' }}>
                                  <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Other product:</span>
                                  <select value="" onChange={e => { if (e.target.value) setQty(e.target.value, (line.selections[g.id]?.[e.target.value] ?? 0) + 1); }} style={{ flex: 1, fontSize: 12.5 }} disabled={done}>
                                    <option value="">— pick any product (top-up applies above base) —</option>
                                    {storeProducts.filter(p => !displayIds.includes(p.id)).map(p => {
                                      const pr = priceFor(cStore, p.id);
                                      const tu = baseline != null && pr != null && pr > baseline ? pr - baseline : 0;
                                      return <option key={p.id} value={p.id}>{p.name} — {pr != null ? money(pr) : '—'}{tu > 0 ? ` (+${money(tu)} top-up)` : ''}</option>;
                                    })}
                                  </select>
                                </div>
                              )}
                            </div>
                          </div>
                        );
                      })}
                    </React.Fragment>
                    );
                  })}
                </div>
                <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => setCLines(ls => [...ls, { kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }])}><Plus size={13} /> Add Item</button>
              </div>
            )}

            {cStore && discountVouchers.length > 0 && (
              <div className="form-group">
                <label>Discount Voucher (optional — one per invoice{hasPromoLine ? '; not available on bundle invoices' : ''})</label>
                <select value={cDiscountVoucher} onChange={e => setCDiscountVoucher(e.target.value)} disabled={hasPromoLine}>
                  <option value="">— None —</option>
                  {eligibleWholeVouchers.map(v => (
                    <option key={v.id} value={v.id}>
                      {v.name} — {v.voucher_kind === 'fixed_discount' ? money(v.discount_amount ?? 0) + ' off' : `${v.discount_percent}% off${v.max_discount_cap ? ` (cap ${money(v.max_discount_cap)})` : ''}`}
                    </option>
                  ))}
                </select>
                <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4, display: 'block' }}>Applied to the invoice subtotal. The exact amount is confirmed on the created invoice.</span>
              </div>
            )}

            <div className="form-grid-2">
              <div className="form-group"><label>Manual Discount (S$)</label><input type="number" min={0} step={0.01} value={cDiscount || ''} onChange={e => setCDiscount(+e.target.value)} placeholder="0.00" /></div>
              <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
                <div style={{ textAlign: 'right', fontSize: 13, color: 'var(--text-secondary)' }}>Subtotal: <strong>{money(createSubtotal)}</strong></div>
                {topupPreview > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>+ top-up {money(topupPreview)}</div>}
                {(cDiscount || 0) > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− manual discount {money(cDiscount)}</div>}
                {lineVoucherDiscountPreview > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− line vouchers {money(lineVoucherDiscountPreview)}</div>}
                {cDiscountVoucher && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− voucher discount {money(voucherDiscountPreview)}</div>}
                <div style={{ textAlign: 'right', fontSize: 16, fontWeight: 700, marginTop: 2 }}>Total: {money(previewTotal)}</div>
              </div>
            </div>
          </div>
        </Modal>
      )}

      {/* Invoice detail + payment modal */}
      {detail && (
        <Modal title={`Invoice ${detail.invoice_no}`} maxWidth={560} onClose={() => setDetail(null)}
          footer={
            detail.status === 'paid'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button><button className="btn btn-danger" onClick={() => { setActionType('invoice_refund'); setActionReturnStock(true); setActionReason(''); setActionErr(null); }}>Request Refund</button></>
              : detail.status === 'cancelled' || detail.status === 'refunded' || detail.status === 'cancellation_requested' || detail.status === 'refund_requested'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button></>
              : <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button><button className="btn btn-primary" onClick={handlePay} disabled={payBusy}><CreditCard size={15} /> {payBusy ? 'Processing…' : 'Record Payment'}</button></>
          }>
          <div className="form-grid">
            {/* Summary */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{storeName(detail.store_id)} · {custName(detail.customer_id)}</div>
                <div style={{ marginTop: 4 }}><StatusBadge s={detail.status} /></div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 20, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(detail.total_amount)}</div>
                <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Paid {money(detail.paid_amount)}</div>
              </div>
            </div>

            {/* Items */}
            <div>
              <label>Items</label>
              <table style={{ marginTop: 4 }}>
                <thead><tr><th>Product</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>Price</th><th style={{ textAlign: 'right' }}>Total</th></tr></thead>
                <tbody>
                  {detailItems.map(it => {
                    const isPromo = it.line_kind === 'promotion';
                    const fixed = isPromo ? detailPromoItems.filter(p => p.promotion_id === (it as any).promotion_id) : [];
                    const chosen = isPromo ? detailSelections.filter(s => s.invoice_item_id === it.id) : [];
                    const subLabel = (x: any): string => {
                      if (x.item_type === 'product' || x.product_id) return `📦 ${prodName(x.product_id ?? '')}`;
                      if (x.item_type === 'voucher' || x.voucher_id) return `🎟 ${vouchers.find(v => v.id === x.voucher_id)?.name ?? 'Voucher'}`;
                      if (x.item_type === 'promotion') return `🧩 ${promotions.find(p => p.id === x.child_promotion_id)?.name ?? 'Promotion'}`;
                      if (x.item_type === 'treatment') return `💆 ${x.treatment_name}`;
                      return '—';
                    };
                    return (
                      <React.Fragment key={it.id}>
                        <tr>
                          <td>{it.line_kind === 'voucher' ? `🎟 ${vouchers.find(v => v.id === it.voucher_id)?.name ?? 'Voucher'}` : isPromo ? `🧩 ${promotions.find(p => p.id === (it as any).promotion_id)?.name ?? 'Promotion'}` : prodName(it.product_id ?? '')}
                            {it.line_kind === 'product' && (it as any).line_voucher_id ? <div style={{ fontSize: 11, color: 'var(--success)' }}>🎟 {vouchers.find(v => v.id === (it as any).line_voucher_id)?.name ?? 'Voucher'} − {money(Number((it as any).line_discount ?? 0))}</div> : null}
                            {isPromo && Number((it as any).topup_amount ?? 0) > 0 ? <div style={{ fontSize: 11, color: 'var(--danger)' }}>+ top-up {money(Number((it as any).topup_amount))}</div> : null}
                          </td>
                          <td style={{ textAlign: 'right' }}>{it.quantity}</td>
                          <td style={{ textAlign: 'right' }}>{money(it.unit_price)}</td>
                          <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(it.line_total)}</td>
                        </tr>
                        {fixed.map(f => (
                          <tr key={`f-${f.id}`}>
                            <td colSpan={4} style={{ paddingLeft: 26, fontSize: 12, color: 'var(--text-muted)', borderTop: 'none' }}>
                              └ {subLabel(f)} × {f.quantity * it.quantity} <span style={{ fontSize: 10.5 }}>(included)</span>
                            </td>
                          </tr>
                        ))}
                        {chosen.map(s => (
                          <tr key={`s-${s.id}`}>
                            <td colSpan={4} style={{ paddingLeft: 26, fontSize: 12, color: 'var(--text-muted)', borderTop: 'none' }}>
                              └ {subLabel(s)} × {s.quantity} <span style={{ fontSize: 10.5 }}>(chosen)</span>
                            </td>
                          </tr>
                        ))}
                      </React.Fragment>
                    );
                  })}
                </tbody>
              </table>
            </div>

            {/* Existing payments */}
            {detailServiceStaff.length > 0 && (
              <div>
                <label>Served by</label>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 4 }}>
                  {detailServiceStaff.map(id => <span key={id} className="badge badge-primary">{staffName(id)}</span>)}
                </div>
              </div>
            )}

            {detailPayments.length > 0 && (
              <div>
                <label>Payments Recorded</label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: 4 }}>
                  {detailPayments.map(p => (
                    <div key={p.id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13, padding: '6px 10px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                      <span>{methodName(p.payment_method_id)}</span>
                      <span style={{ fontWeight: 600 }}>{money(p.amount)}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Payment entry (only if not fully paid) */}
            {detail.status !== 'paid' && detail.status !== 'cancelled' && detail.status !== 'refunded' && (
              <div>
                {payErr && <div className="alert alert-danger"><span>⚠</span><div>{payErr}</div></div>}
                <label>Record Payment <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— split across methods if needed</span></label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 6 }}>
                  {payLines.map((pl, i) => (
                    <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                      <select value={pl.payment_method_id} onChange={e => setPayLines(ls => ls.map((l, j) => j === i ? { ...l, payment_method_id: e.target.value } : l))} style={{ flex: 1 }}>
                        <option value="">— Method —</option>
                        {methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                      </select>
                      <input type="number" min={0} step={0.01} value={pl.amount || ''} placeholder="Amount" style={{ width: 110 }}
                        onChange={e => setPayLines(ls => ls.map((l, j) => j === i ? { ...l, amount: +e.target.value } : l))} />
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setPayLines(ls => ls.filter((_, j) => j !== i))} disabled={payLines.length === 1}><X size={13} /></button>
                    </div>
                  ))}
                </div>
                <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => setPayLines(ls => [...ls, { payment_method_id: methods[0]?.id ?? '', amount: 0 }])}><Plus size={13} /> Split Payment</button>

                <div style={{ marginTop: 12, padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', fontSize: 13 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}><span>Remaining balance</span><strong>{money(detail.total_amount - detail.paid_amount)}</strong></div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4 }}><span>This payment</span><strong>{money(payTotal)}</strong></div>
                  {payTotal >= (detail.total_amount - detail.paid_amount) - 0.001 && payTotal > 0 && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 8, color: 'var(--success)', fontWeight: 600 }}>
                      <CheckCircle2 size={15} /> This completes the invoice — stock will be deducted.
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>
        </Modal>
      )}

      {/* Refund / cancel request modal */}
      {actionType && detail && (
        <Modal title={actionType === 'invoice_refund' ? 'Request Refund' : 'Request Cancellation'} maxWidth={440} onClose={() => setActionType(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setActionType(null)}>Back</button><button className="btn btn-danger" onClick={submitAction} disabled={actionBusy}>{actionBusy ? 'Submitting…' : 'Submit Request'}</button></>}>
          <div className="form-grid">
            {actionErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{actionErr}</div></div>}
            <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
              This sends a request for Owner/Manager approval. {actionType === 'invoice_refund' ? 'Refunds' : 'Cancellations'} reverse any affiliate commission.
            </p>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', padding: '10px 12px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
              <input type="checkbox" checked={actionReturnStock} onChange={e => setActionReturnStock(e.target.checked)} style={{ width: 'auto' }} />
              <div>
                <div style={{ fontSize: 13, fontWeight: 600 }}>Return stock to store</div>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Tick if items are resellable. Untick if damaged/lost.</div>
              </div>
            </label>
            <div className="form-group"><label>Reason *</label><textarea rows={2} value={actionReason} onChange={e => setActionReason(e.target.value)} placeholder="Why is this being requested?" autoFocus /></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default InvoicesPage;
