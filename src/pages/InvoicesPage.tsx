import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { PaymentPriceReview, PriceReviewResult } from '../components/PricingControls';
import type { FocReason, InvoiceRevision } from '../types';
import { useAuth } from '../context/AuthContext';
import {
  Invoice, InvoiceItem, InvoicePayment, Store, Product, Customer,
  PaymentMethod, StoreProductPrice, InvoiceStatus, INVOICE_STATUS_LABELS, Voucher, Promotion, PromotionChoiceGroup, PromotionChoiceOption, isOwnerOrManager, Profile, SERVICE_STAFF_ROLES, TherapyPackageRule } from '../types';
import { SearchSelect, CustomerSearchSelect } from '../components/SearchSelect';
import { Modal, ReasonModal } from '../components/ui';
import { exportCsv } from '../lib/csv';
import {
  Plus, RefreshCw, FileText, Trash2, X, CreditCard, Eye, Search, CheckCircle2, Download, Printer, Sparkles, Coins } from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;

const StatusBadge: React.FC<{ s: InvoiceStatus }> = ({ s }) => {
  const cls = s === 'completed_foc' ? 'badge-success' : s === 'paid' ? 'badge-success' : s === 'partially_paid' ? 'badge-primary'
    : s === 'unpaid' || s === 'draft' ? 'badge-accent'
    : s === 'cancelled' || s === 'refunded' ? 'badge-muted' : 'badge-danger';
  return <span className={`badge ${cls}`}>{INVOICE_STATUS_LABELS[s]}</span>;
};

interface LineDraft { kind: 'product' | 'voucher' | 'promotion' | 'therapy'; product_id: string; voucher_id: string; promotion_id: string; therapy_package_id?: string; quantity: number; line_voucher_id: string; selections: Record<string, Record<string, number>>; foc_quantity?: number; foc_reason_id?: string; foc_reason?: string; }

const InvoicesPage: React.FC = () => {
  const { profile } = useAuth();
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [vouchers, setVouchers] = useState<Voucher[]>([]);
  const [promotions, setPromotions] = useState<Promotion[]>([]);
  const [choiceGroups, setChoiceGroups] = useState<PromotionChoiceGroup[]>([]);
  const [promoItems, setPromoItems] = useState<any[]>([]);
  const [choiceOptions, setChoiceOptions] = useState<PromotionChoiceOption[]>([]);
  const [storeInv, setStoreInv] = useState<any[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [assignedStoreId, setAssignedStoreId] = useState<string | null>(null);
  const [therapyRules, setTherapyRules] = useState<TherapyPackageRule[]>([]);
  const [therapyPackages, setTherapyPackages] = useState<any[]>([]);
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
  const [saveEarthOn, setSaveEarthOn] = useState(false);
  const [saveEarthLabel, setSaveEarthLabel] = useState('Save Earth Project');
  const [saveEarthAmount, setSaveEarthAmount] = useState(1);
  const [saveEarthDefault, setSaveEarthDefault] = useState<{ label: string; amount: number }>({ label: 'Save Earth Project', amount: 1 });
  const [seSettingsOpen, setSeSettingsOpen] = useState(false);
  const [seLabel, setSeLabel] = useState('Save Earth Project');
  const [seAmount, setSeAmount] = useState(1);
  const [seBusy, setSeBusy] = useState(false);
  const [cErr, setCErr] = useState<string | null>(null);
  const [cSaving, setCSaving] = useState(false);

  // Detail / payment modal
  const [detail, setDetail] = useState<Invoice | null>(null);
  const [detailItems, setDetailItems] = useState<InvoiceItem[]>([]);
  const [detailPromoItems, setDetailPromoItems] = useState<any[]>([]);      // fixed contents of promotions on this invoice
  const [detailSelections, setDetailSelections] = useState<any[]>([]);      // chosen items for this invoice
  const [detailPayments, setDetailPayments] = useState<InvoicePayment[]>([]);
  const [detailTherapy, setDetailTherapy] = useState<any>(null);
  const [detailServiceStaff, setDetailServiceStaff] = useState<string[]>([]);
  const [payLines, setPayLines] = useState<{ payment_method_id: string; amount: number }[]>([]);
  const [payErr, setPayErr] = useState<string | null>(null);
  const [payBusy, setPayBusy] = useState(false);
  const [priceReview, setPriceReview] = useState<PriceReviewResult | null>(null);
  const [focReasons, setFocReasons] = useState<FocReason[]>([]);
  const [focBusy, setFocBusy] = useState(false);
  // Phase 13 — edit mode + exchange detail + revision history
  const [editingInvoiceId, setEditingInvoiceId] = useState<string | null>(null);
  const [detailExchange, setDetailExchange] = useState<any>(null);
  const [detailRevisions, setDetailRevisions] = useState<InvoiceRevision[]>([]);
  const [affiliateOptions, setAffiliateOptions] = useState<{ affiliate_id: string; full_name: string; phone: string }[]>([]);
  const [affiliateBusy, setAffiliateBusy] = useState(false);
  const [affiliateErr, setAffiliateErr] = useState<string | null>(null);
  const [effAffiliate, setEffAffiliate] = useState<any>(null);
  const [invLegacy, setInvLegacy] = useState<any[]>([]);
  const [buyOpen, setBuyOpen] = useState(false);
  const [buyPkgs, setBuyPkgs] = useState<any[]>([]);
  const [buyBundles, setBuyBundles] = useState<any[]>([]);
  const [buyVouchers, setBuyVouchers] = useState<any[]>([]);
  const [buyKind, setBuyKind] = useState<'credit_package' | 'premium_bundle'>('credit_package');
  const [buyId, setBuyId] = useState('');
  const [buyCustomer, setBuyCustomer] = useState('');
  const [buyBasket, setBuyBasket] = useState<Record<string, number>>({});
  const [buyBusy, setBuyBusy] = useState(false);
  const [buyErr, setBuyErr] = useState<string | null>(null);
  const [legacyDiag, setLegacyDiag] = useState<any>(null);
  const [payWallet, setPayWallet] = useState<any>(null);
  const [warehouses, setWarehouses] = useState<any[]>([]);
  const [fulfilBusy, setFulfilBusy] = useState(false);
  const [fulfilErr, setFulfilErr] = useState<string | null>(null);
  const setFulfilment = async (warehouseId: string | null) => {
    if (!detail) return;
    setFulfilBusy(true); setFulfilErr(null);
    const { error } = await supabase.rpc('set_invoice_fulfilment_warehouse',
      { p_invoice_id: detail.id, p_warehouse_id: warehouseId });
    setFulfilBusy(false);
    if (error) { setFulfilErr(error.message); return; }
    const { data: inv } = await supabase.from('invoices').select('*').eq('id', detail.id).single();
    if (inv) await openDetail(inv as Invoice);
    await loadAll();
  };
  const [focLine, setFocLine] = useState<InvoiceItem | null>(null);
  const [focQty, setFocQty] = useState(1);
  const [focReasonId, setFocReasonId] = useState('');
  const [focNote, setFocNote] = useState('');
  const [focErr, setFocErr] = useState<string | null>(null);
  const [refundLine, setRefundLine] = useState<InvoiceItem | null>(null);
  const [refundBusy, setRefundBusy] = useState(false);
  const [voucherStorePrices, setVoucherStorePrices] = useState<any[]>([]);
  const [promoStorePrices, setPromoStorePrices] = useState<any[]>([]);

  const loadAll = useCallback(async () => {
    setLoading(true);
    const [inv, st, pr, cu, pm, pp, vc, pm2, cg, pit, co, si, prof, myStore, trules, utpk, utsp, aset, vsp, psp, focr] = await Promise.all([
      supabase.from('invoices').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('stores').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('customers').select('*').is('deleted_at', null).order('full_name'),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('store_product_prices').select('*').is('deleted_at', null),
      supabase.from('vouchers').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('promotions').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('promotion_choice_groups').select('*'),
      supabase.from('promotion_items').select('*'),
      supabase.from('promotion_choice_options').select('*'),
      supabase.from('store_inventory').select('store_id,product_id,current_qty'),
      supabase.from('profiles').select('id,full_name,role,work_phone,is_active').is('deleted_at', null).eq('is_active', true),
      supabase.rpc('my_assigned_store_id'),
      supabase.from('therapy_package_rules').select('*').is('deleted_at', null).eq('is_active', true),
      supabase.from('unlimited_therapy_packages').select('*').is('deleted_at', null).eq('is_active', true).order('duration_months'),
      supabase.from('unlimited_therapy_store_prices').select('*').is('deleted_at', null),
      supabase.from('app_settings').select('save_earth_label, save_earth_amount').maybeSingle(),
      supabase.from('voucher_store_prices').select('*').is('deleted_at', null),
      supabase.from('promotion_store_prices').select('*').is('deleted_at', null),
      supabase.rpc('active_foc_reasons'),
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
    setPromoItems((pit.data as any[]) ?? []);
    setChoiceOptions((co.data as PromotionChoiceOption[]) ?? []);
    setStoreInv((si.data as any[]) ?? []);
    const allProfiles = (prof.data as Profile[]) ?? [];
    setProfiles(allProfiles);
    setAssignedStoreId((myStore.data as string | null) ?? null);
    setTherapyRules((trules.data as TherapyPackageRule[]) ?? []);
    setTherapyPackages((utpk?.data as any[]) ?? []);
    setTherapyPrices((utsp?.data as any[]) ?? []);
    const se = aset?.data as any;
    if (se) setSaveEarthDefault({ label: se.save_earth_label ?? 'Save Earth Project', amount: Number(se.save_earth_amount ?? 1) });
    setVoucherStorePrices((vsp.data as any[]) ?? []);
    setPromoStorePrices((psp.data as any[]) ?? []);
    setFocReasons((focr?.data as FocReason[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { loadAll(); }, [loadAll]);

  const storeName = (id: string) => stores.find(s => s.id === id)?.name ?? '—';
  const custName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';
  const prodName = (id: string) => products.find(p => p.id === id)?.name ?? '—';
  const methodName = (id: string) => methods.find(m => m.id === id)?.name ?? '—';
  const isStaff = profile?.role === 'staff';
  const activeStore = isStaff ? (assignedStoreId ?? '') : cStore;

  const openBuy = async () => {
    setBuyErr(null); setBuyId(''); setBuyBasket({}); setBuyCustomer('');
    setBuyKind('credit_package'); setBuyOpen(true);
    const store = activeStore;
    if (!store) return;
    const { data: cp } = await supabase.rpc('credit_packages_for_store', { p_store_id: store, p_day: null });
    setBuyPkgs((cp as any[]) ?? []);
    const { data: pb } = await supabase.rpc('premium_bundles_for_store', { p_store_id: store, p_day: null });
    setBuyBundles((pb as any[]) ?? []);
  };
  useEffect(() => {
    if (!buyOpen || buyKind !== 'premium_bundle' || !buyId) { return; }
    (async () => {
      const { data } = await supabase.from('premium_bundle_vouchers').select('voucher_id').eq('bundle_id', buyId);
      const ids = ((data as any[]) ?? []).map(x => x.voucher_id);
      const { data: vs } = await supabase.rpc('legacy_reward_voucher_options',
        { p_store_id: activeStore });
      setBuyVouchers(((vs as any[]) ?? []).filter(v => ids.includes(v.voucher_id)));
      setBuyBasket({});
    })();
  }, [buyOpen, buyKind, buyId, activeStore]);
  const submitBuy = async () => {
    setBuyBusy(true); setBuyErr(null);
    const line: any = { kind: buyKind, id: buyId };
    if (buyKind === 'premium_bundle') {
      line.voucher_selection = Object.entries(buyBasket).filter(([, q]) => q > 0)
        .map(([voucher_id, quantity]) => ({ voucher_id, quantity }));
    }
    const { data, error } = await supabase.rpc('create_credit_purchase_invoice', {
      p_store_id: activeStore, p_customer_id: buyCustomer,
      p_lines: [line], p_affiliate_id: null, p_discount_total: 0, p_notes: null,
    });
    setBuyBusy(false);
    if (error) { setBuyErr(error.message); return; }
    setBuyOpen(false); await loadAll();
    const { data: invRow } = await supabase.from('invoices').select('*').eq('id', data).single();
    if (invRow) await openDetail(invRow as Invoice);
  };
  // Phase 19: one selling price. The former Member Price is the single price.
  const effMember = true;
  // Strict mode-aware pricing (Phase 4): NO fallback to legacy selling_price.
  const priceRowFor = (storeId: string, productId: string) =>
    prices.find(p => p.store_id === storeId && p.product_id === productId);
  const priceFor = (storeId: string, productId: string, _member: boolean = effMember) => {
    const r = priceRowFor(storeId, productId);
    if (!r) return null;
    return r.selling_price ?? r.member_price ?? null;
  };

  // Products available at the chosen store (those with a price).
  const stockQty = (storeId: string, productId: string): number =>
    storeInv.find(s => s.store_id === storeId && s.product_id === productId)?.current_qty ?? 0;

  // D: a product is offered if it has a usable price in SOME mode (auto or via
  // override) and has stock. We classify rather than hide, so an override
  // candidate (e.g. member-only product for a non-member) stays selectable
  // with a clear label. Only truly unpriced/inactive items are dropped.
  const productAvail = (pid: string): { ok: boolean; label: string; needsOverride: boolean } => {
    const r = prices.find(x => x.store_id === activeStore && x.product_id === pid);
    if (!r) return { ok: false, label: 'no price', needsOverride: false };
    const val = r.selling_price ?? r.member_price;
    if (val != null) return { ok: true, label: `${money(val)}`, needsOverride: false };
    return { ok: false, label: 'missing price', needsOverride: false };
  };
  const storeProducts = useMemo(() =>
    activeStore ? products.filter(p => productAvail(p.id).ok && stockQty(activeStore, p.id) > 0) : [],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [activeStore, products, prices, storeInv]);

  const [therapyPrices, setTherapyPrices] = useState<any[]>([]);
  const therapyPrice = (pkgId: string, _member: boolean = effMember): number | null => {
    const r = therapyPrices.find(x => x.package_id === pkgId && x.store_id === activeStore && x.available_at_store !== false);
    if (!r) return null;
    return r.selling_price ?? r.member_price ?? null;
  };
  const voucherPrice = (id: string, _member: boolean = effMember) => {
    const r = voucherStorePrices.find(x => x.voucher_id === id && x.store_id === activeStore && x.available_at_store !== false);
    if (!r) return null;
    return r.selling_price ?? r.member_price ?? null;
  };

  const promoPrice = (id: string, _member: boolean = effMember) => {
    const r = promoStorePrices.find(x => x.promotion_id === id && x.store_id === activeStore && x.available_at_store !== false);
    if (!r) return null;
    return r.selling_price ?? r.member_price ?? null;
  };

  const lineMember = (_l: LineDraft): boolean => effMember;
  const lineUnit = (l: LineDraft): number | null =>
    l.kind === 'therapy' ? (l.therapy_package_id ? therapyPrice(l.therapy_package_id, lineMember(l)) : null)
    : l.kind === 'voucher' ? (l.voucher_id ? voucherPrice(l.voucher_id, lineMember(l)) : null)
    : l.kind === 'promotion' ? (l.promotion_id ? promoPrice(l.promotion_id, lineMember(l)) : null)
    : (activeStore && l.product_id ? priceFor(activeStore, l.product_id, lineMember(l)) : null);

  // Phase 12 — the charged quantity is what the customer actually pays for.
  const paidQty = (l: LineDraft) => Math.max(0, l.quantity - (l.foc_quantity ?? 0));
  const focValuePreview = useMemo(() =>
    cLines.reduce((sum, l) => {
      const price = lineUnit(l);
      return sum + (price ? price * (l.foc_quantity ?? 0) : 0);
    }, 0),
    [cLines, activeStore, prices, vouchers, promotions, voucherStorePrices, promoStorePrices, therapyPrices, therapyPackages]);
  const createSubtotal = useMemo(() =>
    cLines.reduce((sum, l) => {
      const price = lineUnit(l);
      return sum + (price ? price * paidQty(l) : 0);
    }, 0),
    // B: every input that can change a line's applied price must be here,
    // or totals go stale when the pricing mode flips.
    [cLines, activeStore, prices, vouchers, promotions, voucherStorePrices, promoStorePrices, therapyPrices, therapyPackages]);

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
  // The promotion's fixed contents. These are always part of the bundle and are
  // not chosen by the cashier, so they were never rendered — which made the
  // invoice look as though half the bundle was missing.
  const includedFor = (promoId: string) => promoItems
    .filter(i => i.promotion_id === promoId)
    .map(i => {
      const label =
        i.item_type === 'product' ? (products.find(p => p.id === i.product_id)?.name ?? 'Product')
        : i.item_type === 'voucher' ? (vouchers.find(v => v.id === i.voucher_id)?.name ?? 'Voucher')
        : i.item_type === 'promotion' ? (promotions.find(p => p.id === i.child_promotion_id)?.name ?? 'Promotion')
        : i.item_type === 'therapy' ? (therapyPackages.find((t: any) => t.id === i.therapy_package_id)?.name ?? 'Therapy')
        : i.item_type === 'credit_package' ? 'Credit package'
        : (i.treatment_name ?? 'Item');
      return { id: i.id, label, qty: i.quantity, kind: i.item_type };
    });
  const optionsFor = (groupId: string) => choiceOptions.filter(o => o.group_id === groupId);
  const selSum = (l: LineDraft, gId: string) => Object.values(l.selections[gId] ?? {}).reduce((s, n) => s + (n || 0), 0);

  // Baseline of a product group = cheapest listed option at the chosen store.
  // G: baseline follows the applied pricing mode — a top-up computed under the
  // previous mode is never reused (the memo recomputes on mode change).
  // C: baseline resolves in the promotion LINE's applied mode, not the
  // invoice-wide automatic mode.
  const groupBaseline = (gId: string, member: boolean = effMember): number | null => {
    if (!activeStore) return null;
    const opts = optionsFor(gId)
      .map(o => (o.product_id ? priceFor(activeStore, o.product_id, member) : null))
      .filter((p): p is number => p != null);
    return opts.length ? Math.min(...opts) : null;
  };

  // 3rd-party product lines are discount-proof: invoice-level discounts never touch them.
  const isThirdParty = (productId: string) => products.find(p => p.id === productId)?.product_type === 'third_party';
  const thirdPartySum = useMemo(() =>
    cLines.reduce((s, l) => {
      if (l.kind !== 'product' || !l.product_id || !isThirdParty(l.product_id)) return s;
      const u = lineUnit(l);
      return s + (u ? u * paidQty(l) : 0);
    }, 0), [cLines, activeStore, prices, products]);

  // Total top-up across all promotion lines (mirrors promotion_selections_topup).
  const topupPreview = useMemo(() => {
    if (!activeStore) return 0;
    let sum = 0;
    for (const l of cLines) {
      if (l.kind !== 'promotion' || !l.promotion_id) continue;
      const lm = effMember;
      for (const g of groupsFor(l.promotion_id)) {
        if (g.item_kind !== 'product') continue;
        const baseline = groupBaseline(g.id, lm);
        if (baseline == null) continue;
        // Listed options never pay a top-up — only picks outside the options do.
        const listed = new Set(optionsFor(g.id).map(o => o.product_id).filter(Boolean));
        for (const [pid, q] of Object.entries(l.selections[g.id] ?? {})) {
          if (!q || listed.has(pid)) continue;
          const pr = priceFor(activeStore, pid, lm);
          if (pr != null && pr > baseline) sum += (pr - baseline) * q;
        }
      }
    }
    return sum;
  }, [cLines, activeStore, prices, choiceGroups, choiceOptions]);

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
      // Discounts apply to the PAID value only.
      return sum + voucherDiscAmount(vouchers.find(v => v.id === l.line_voucher_id), unit * paidQty(l));
    }, 0), [cLines, vouchers, activeStore, prices, voucherStorePrices, promoStorePrices]);

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
    const se = saveEarthOn ? Math.max(0, saveEarthAmount || 0) : 0;
    return Math.max(0, createSubtotal + topupPreview - lineVoucherDiscountPreview - invLevel - se);
  }, [createSubtotal, topupPreview, thirdPartySum, cDiscount, lineVoucherDiscountPreview, voucherDiscountPreview, saveEarthOn, saveEarthAmount]);


  // All vouchers can be sold as a line item (a discount voucher sold now is
  // redeemed by the buyer on a future invoice). Only discount vouchers can be
  // used in the Discount Voucher slot (Normal vouchers have no discount value).
  const sellableVouchers = useMemo(() => vouchers, [vouchers]);

  const resetCreate = () => {
    setCStore(isStaff ? (assignedStoreId ?? '') : '');
    setCCustomer('');
    setCLines([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]); setCDiscount(0);
    setCDiscountVoucher(''); setCServiceStaff([]); setCErr(null);
    setSaveEarthOn(false); setSaveEarthLabel(saveEarthDefault.label); setSaveEarthAmount(saveEarthDefault.amount);
  };

  const handleCreate = async () => {
    if (isStaff && !assignedStoreId) { setCErr('You are not assigned to a store, so you cannot create invoices. Ask an Owner or Manager to assign you.'); return; }
    const effectiveStore = isStaff ? (assignedStoreId ?? '') : cStore;
    if (!effectiveStore) { setCErr('Select a store.'); return; }
    if (!cCustomer) { setCErr('Select a customer.'); return; }
    const activeLines = cLines.filter(l => l.quantity > 0 && (l.kind === 'product' ? l.product_id : l.kind === 'voucher' ? l.voucher_id : l.kind === 'therapy' ? l.therapy_package_id : l.promotion_id));
    if (activeLines.length === 0) { setCErr('Add at least one product, voucher, promotion or therapy line.'); return; }
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
    const ovr = (_l: LineDraft) => ({});
    // Phase 12 — FOC travels with the line. `quantity` stays the full quantity;
    // the server derives the charged value from (quantity - foc_quantity).
    const foc = (l: LineDraft) => (l.foc_quantity ?? 0) > 0
      ? { foc_quantity: l.foc_quantity, foc_reason_id: l.foc_reason_id || null, foc_reason: l.foc_reason || null }
      : {};
    const validLines = activeLines.map(l => l.kind === 'voucher'
      ? { kind: 'voucher', voucher_id: l.voucher_id, quantity: l.quantity, ...ovr(l), ...foc(l) }
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
          ...ovr(l), ...foc(l),
        }
      : l.kind === 'therapy'
      ? { kind: 'therapy', therapy_package_id: l.therapy_package_id, quantity: 1, ...ovr(l), ...foc(l) }
      : { kind: 'product', product_id: l.product_id, quantity: l.quantity, line_voucher_id: (l.line_voucher_id && !isThirdParty(l.product_id)) ? l.line_voucher_id : null, ...ovr(l), ...foc(l) });
    const focMissing = activeLines.find(l => (l.foc_quantity ?? 0) > 0 && !l.foc_reason_id && !(l.foc_reason ?? '').trim());
    if (focMissing) { setCErr('A FOC reason is required on every FOC line.'); return; }
    const allItems: any[] = validLines.filter(Boolean);
    // create_invoice requires at least one product/voucher/promotion line
    // to open the invoice. Therapy is added right after. For a therapy-ONLY sale,
    // create the invoice, then it gets the therapy line — but we need a seed, so
    // require another line, OR fall back to creating an empty
    // invoice shell is not supported. Guide the user in that rare case.

    setCSaving(true); setCErr(null);
    // Phase 13: the same payload edits an existing unpaid invoice in place —
    // update_invoice revalidates every rule exactly as create_invoice does.
    const { data: rpcId, error } = editingInvoiceId
      ? await supabase.rpc('update_invoice', {
          p_invoice_id: editingInvoiceId, p_customer_id: cCustomer, p_affiliate_id: null,
          p_items: allItems, p_discount_total: cDiscount || 0, p_notes: null,
          p_discount_voucher_id: cDiscountVoucher || null,
          p_service_staff: cServiceStaff, p_edit_reason: null,
        })
      : await supabase.rpc('create_invoice', {
          p_store_id: effectiveStore, p_customer_id: cCustomer, p_affiliate_id: null,
          p_items: allItems, p_discount_total: cDiscount || 0, p_notes: null,
          p_discount_voucher_id: cDiscountVoucher || null,
          p_service_staff: cServiceStaff,
        });
    setCSaving(false);
    if (error) { setCErr(error.message); return; }
    const newInvId = editingInvoiceId ?? (rpcId as string | null);
    // Save Earth (post-create; on edit this also handles switching it off).
    if (newInvId && (saveEarthOn || editingInvoiceId)) {
      await supabase.rpc('set_invoice_save_earth', {
        p_invoice_id: newInvId, p_applied: saveEarthOn,
        p_label: saveEarthLabel || null, p_amount: saveEarthAmount,
      });
    }
    // E: record a create-time override audit + correct original_price per line.
    if (false) {
      const { data: createdItems } = await supabase.from('invoice_items')
        .select('id').eq('invoice_id', newInvId).eq('price_overridden', true);
      for (const it of (createdItems as any[]) ?? []) {
        await supabase.rpc('audit_create_time_override', { p_item_id: it.id });
      }
    }
    setCreateOpen(false); resetCreate(); setEditingInvoiceId(null); loadAll();
  };

  // Phase 13 — prefill the builder modal from an unpaid invoice and switch it
  // into edit mode. Store is shown but locked; number/date never change.
  const openEdit = () => {
    if (!detail) return;
    const selByItem: Record<string, Record<string, Record<string, number>>> = {};
    for (const s0 of detailSelections) {
      const it = s0.invoice_item_id as string, g = s0.group_id as string;
      const key = (s0.product_id ?? s0.voucher_id) as string;
      if (!key) continue;
      selByItem[it] = selByItem[it] ?? {};
      selByItem[it][g] = selByItem[it][g] ?? {};
      selByItem[it][g][key] = (selByItem[it][g][key] ?? 0) + Number(s0.quantity ?? 0);
    }
    const lines: LineDraft[] = [];
    for (const it of detailItems) {
      const ovr = {};
      const foc = Number(it.foc_quantity ?? 0) > 0
        ? { foc_quantity: Number(it.foc_quantity), foc_reason_id: (it as any).foc_reason_id ?? '', foc_reason: '' }
        : {};
      if (it.line_kind === 'therapy') {
        lines.push({ kind: 'therapy', product_id: '', voucher_id: '', promotion_id: '', therapy_package_id: (it as any).therapy_package_id ?? '', quantity: 1, line_voucher_id: '', selections: {}, ...ovr, ...foc });
      } else if (it.line_kind === 'voucher') {
        lines.push({ kind: 'voucher', product_id: '', voucher_id: (it as any).voucher_id ?? '', promotion_id: '', quantity: it.quantity, line_voucher_id: '', selections: {}, ...ovr, ...foc });
      } else if (it.line_kind === 'promotion') {
        lines.push({ kind: 'promotion', product_id: '', voucher_id: '', promotion_id: (it as any).promotion_id ?? '', quantity: it.quantity, line_voucher_id: '', selections: selByItem[it.id] ?? {}, ...ovr, ...foc });
      } else {
        lines.push({ kind: 'product', product_id: it.product_id ?? '', voucher_id: '', promotion_id: '', quantity: it.quantity, line_voucher_id: (it as any).line_voucher_id ?? '', selections: {}, ...ovr, ...foc });
      }
    }
    setCStore(detail.store_id);
    setCCustomer(detail.customer_id);
    setCLines(lines.length ? lines : [{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]);
    setCDiscount(Number((detail as any).manual_discount ?? 0));
    setCDiscountVoucher((detail as any).discount_voucher_id ?? '');
    setCServiceStaff(detailServiceStaff);
    setSaveEarthOn(!!(detail as any).save_earth_applied);
    setSaveEarthLabel((detail as any).save_earth_label ?? saveEarthDefault.label);
    setSaveEarthAmount(Number((detail as any).save_earth_amount ?? saveEarthDefault.amount));
    setEditingInvoiceId(detail.id);
    setDetail(null);
    setCErr(null);
    setCreateOpen(true);
  };

  const loadAffiliateOptions = async () => {
    const { data } = await supabase.rpc('active_affiliates_for_picker');
    setAffiliateOptions((data as any[]) ?? []);
  };

  // The affiliate that will actually be credited: the explicit choice on the
  // invoice, or the customer's own referrer (Tier 1) when nothing is chosen.
  const loadEffectiveAffiliate = async (invoiceId: string) => {
    const { data } = await supabase.rpc('invoice_effective_affiliate', { p_invoice_id: invoiceId });
    setEffAffiliate(data ?? null);
  };

  // Legacy therapy this invoice's same-day qualification earned the customer.
  const loadInvoiceLegacy = async (invoiceId: string, inv?: Invoice) => {
    const { data } = await supabase.rpc('invoice_legacy_entitlements', { p_invoice_id: invoiceId });
    setInvLegacy((data as any[]) ?? []);
    // If nothing was earned, find out why so staff aren't left guessing.
    const src = inv ?? detail;
    if ((!data || (data as any[]).length === 0) && src?.customer_id && src?.store_id) {
      const day = src.paid_at ? new Date(src.paid_at).toISOString().slice(0, 10) : null;
      const { data: dg } = await supabase.rpc('legacy_qualification_diagnose', {
        p_customer_id: src.customer_id, p_store_id: src.store_id, p_day: day,
      });
      setLegacyDiag(dg ?? null);
    } else {
      setLegacyDiag(null);
    }
  };

  const changeInvoiceAffiliate = async (affiliateId: string | null) => {
    if (!detail) return;
    setAffiliateBusy(true); setAffiliateErr(null);
    const { error } = await supabase.rpc('set_invoice_affiliate', { p_invoice_id: detail.id, p_affiliate_id: affiliateId });
    setAffiliateBusy(false);
    if (error) { setAffiliateErr(error.message); return; }
    await loadEffectiveAffiliate(detail.id);
    const { data: invRow } = await supabase.from('invoices').select('*').eq('id', detail.id).single();
    if (invRow) await openDetail(invRow as Invoice);
    await loadAll();
  };

  const openDetail = async (inv: Invoice) => {
    setDetail(inv);
    setDetailTherapy(null);
    void loadAffiliateOptions();
    void loadEffectiveAffiliate(inv.id);
    void loadInvoiceLegacy(inv.id, inv);
    if (warehouses.length === 0) {
      supabase.from('warehouses').select('id,name').is('deleted_at', null).order('name')
        .then(({ data }) => setWarehouses((data as any[]) ?? []));
    }
    if (inv.customer_id) {
      supabase.rpc('customer_credit_balances', { p_customer_id: inv.customer_id })
        .then(({ data }) => setPayWallet(data ?? null));
    } else { setPayWallet(null); }
    const [items, pays, svc, ther] = await Promise.all([
      supabase.from('invoice_items').select('*').eq('invoice_id', inv.id),
      supabase.from('invoice_payments').select('*').eq('invoice_id', inv.id),
      supabase.from('invoice_service_staff').select('staff_id').eq('invoice_id', inv.id),
      supabase.rpc('invoice_therapy_summary', { p_invoice_id: inv.id }),
    ]);
    setDetailTherapy(ther.data ?? null);
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
    // Phase 13 — exchange context + revision history.
    if ((inv as any).is_exchange) {
      const { data: exd } = await supabase.rpc('exchange_invoice_details', { p_invoice_id: inv.id });
      setDetailExchange(exd ?? null);
    } else setDetailExchange(null);
    const { data: revs } = await supabase.from('invoice_revisions')
      .select('id, invoice_id, revision_no, edited_by, edit_reason, edited_at')
      .eq('invoice_id', inv.id).order('revision_no', { ascending: false });
    setDetailRevisions((revs as InvoiceRevision[]) ?? []);
    const remaining = inv.total_amount - inv.paid_amount;
    setPayLines([{ payment_method_id: methods[0]?.id ?? '', amount: remaining > 0 ? remaining : 0 }]);
    setPayErr(null);
  };

  const payTotal = useMemo(() => payLines.reduce((s, p) => s + (p.amount || 0), 0), [payLines]);

  // Phase 12 — close a fully-FOC invoice with no payment.
  const handleConfirmFoc = async () => {
    if (!detail) return;
    setFocBusy(true); setFocErr(null);
    const { data, error } = await supabase.rpc('confirm_foc_invoice', { p_invoice_id: detail.id, p_note: null });
    setFocBusy(false);
    if (error) { setFocErr(error.message); return; }
    const res = data as any;
    if (res && res.review_required) {
      setFocErr('Prices changed since this invoice was created — reopen it and review before confirming.');
      await loadAll(); return;
    }
    setDetail(null); await loadAll();
  };

  const handleApplyLineFoc = async () => {
    if (!focLine) return;
    if (!focReasonId && !focNote.trim()) { setFocErr('A FOC reason is required.'); return; }
    setFocBusy(true); setFocErr(null);
    const { error } = await supabase.rpc('apply_line_foc', {
      p_invoice_item_id: focLine.id, p_foc_quantity: focQty,
      p_reason_id: focReasonId || null, p_reason_text: focNote.trim() || null,
    });
    setFocBusy(false);
    if (error) { setFocErr(error.message); return; }
    setFocLine(null);
    if (detail) { const { data: invRow } = await supabase.from('invoices').select('*').eq('id', detail.id).single(); if (invRow) await openDetail(invRow as Invoice); }
    await loadAll();
  };

  const handleRemoveLineFoc = async (itemId: string) => {
    setFocBusy(true); setFocErr(null);
    const { error } = await supabase.rpc('remove_line_foc', { p_invoice_item_id: itemId, p_reason: null });
    setFocBusy(false);
    if (error) { setFocErr(error.message); return; }
    if (detail) { await openDetail(detail); }
    await loadAll();
  };

  const handlePay = async () => {
    if (!detail) return;
    const valid = payLines.filter(p => p.payment_method_id && p.amount > 0);
    if (valid.length === 0) { setPayErr('Add at least one payment.'); return; }
    setPayBusy(true); setPayErr(null);
    const paidStore = detail.store_id, paidCustomer = detail.customer_id;
    // pay_invoice_with_wallet allocates any wallet credit lot-by-lot first,
    // then settles the invoice exactly as pay_invoice always did.
    const { data, error } = await supabase.rpc('pay_invoice_with_wallet', { p_invoice_id: detail.id, p_payments: valid });
    setPayBusy(false);
    if (error) { setPayErr(error.message); return; }
    const res: any = data;
    if (res?.review_required) {
      // Prices changed; nothing was charged. Refresh the (repriced) invoice
      // and show the review so staff confirm the new total with the customer.
      const { data: invRow } = await supabase.from('invoices').select('*').eq('id', detail.id).single();
      if (invRow) await openDetail(invRow as Invoice);
      setPriceReview(res as PriceReviewResult);
      return;
    }
    setDetail(null); await loadAll();
    // Phase 6: target-based therapy qualification is retired. Unlimited Therapy
    // is sold as an invoice line instead; no post-payment qualify prompt.
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
      const md = '';
      const ov = it.price_overridden ? `<div class="mut"><b>Manual Override</b>${it.override_reason ? ` — ${esc(it.override_reason)}` : ''}</div>` : '';
      const mem = '';
      const focQty = Number((it as any).foc_quantity ?? 0);
      const focAmt = Number((it as any).foc_amount ?? 0);
      const fc = focQty > 0
        ? `<div class="mut"><b>FOC</b> ${focQty === it.quantity ? '(full line)' : `${focQty} of ${it.quantity} free`} — value S$${focAmt.toFixed(2)}${(it as any).foc_reason ? ` — ${esc(String((it as any).foc_reason))}` : ''}</div>`
        : '';
      const amountCell = focQty === it.quantity && focQty > 0
        ? `<s>S$${(Number(it.line_total) + focAmt).toFixed(2)}</s> <b>FOC</b>`
        : `<b>S$${Number(it.line_total).toFixed(2)}</b>`;
      return `<tr><td>${esc(lineName(it))}${md}${ov}${mem}${lv}${tu}${fc}</td><td class="r">${it.quantity}</td><td class="r">S$${Number(it.unit_price).toFixed(2)}</td><td class="r">${amountCell}</td></tr>` +
        (it.line_kind === 'promotion' ? subFor(it) : '');
    }).join('');
    const payRows = detailPayments.map(p =>
      `<tr><td>${esc(methods.find(m => m.id === p.payment_method_id)?.name ?? '')}${p.payment_reference ? ' · ' + esc(p.payment_reference) : ''}</td><td class="r">S$${Number(p.amount).toFixed(2)}</td></tr>`).join('');

    // Service Provided By = the invoice's service staff, each with their work phone.
    const staffRows = detailServiceStaff
      .map(id => profiles.find(p => p.id === id))
      .filter((p): p is Profile => !!p);
    const authorisedBlock = staffRows.length
      ? `<h2>Service Provided By</h2><div>${staffRows.map(p =>
          `<div>${esc(p.full_name)}${p.work_phone ? ` — ${esc(p.work_phone)}` : ''}</div>`).join('')}</div>`
      : '';

    const totalPaid = detailPayments.reduce((s, p) => s + Number(p.amount), 0);
    const ex = detailExchange?.found ? detailExchange : null;
    const exchangeBlock = ex ? `
      <h2>Exchange Details</h2>
      <div class="mut">Exchange ${esc(ex.exchange_no ?? '')} · Original invoice <b>${esc(ex.original_invoice_no ?? '')}</b>${ex.reason ? ` · Reason: ${esc(ex.reason)}` : ''}</div>
      <table><thead><tr><th>Returned Item</th><th class="r">Qty</th><th class="r">Value</th></tr></thead><tbody>
        ${(ex.returned_items ?? []).map((r: any) => `<tr><td>${esc(r.product ?? '')}</td><td class="r">${r.quantity}</td><td class="r">S$${Number(r.line_total).toFixed(2)}</td></tr>`).join('')}
        <tr><td colspan="2"><b>Returned value (exchange credit)</b></td><td class="r"><b>S$${Number(ex.returned_total ?? 0).toFixed(2)}</b></td></tr>
      </tbody></table>` : '';
    const focTotal = Number((detail as any).foc_total ?? 0);
    const focStamp = focTotal > 0
      ? `<div class="mut"><b>${(detail as any).is_full_foc ? 'FREE OF CHARGE' : 'INCLUDES FOC ITEMS'}</b> — FOC value S$${focTotal.toFixed(2)}</div>`
      : '';
    const st: any = store ?? {};
    const storePhone = st.phone ?? '';
    const gstEnabled = !!st.gst_enabled;
    const gstRate = Number(st.gst_rate ?? 0);
    // GST treated as inclusive of the shown Total (common SG retail); the line
    // is informational: Total already equals what the customer pays.
    const gstAmount = gstEnabled && gstRate > 0
      ? Number(detail.total_amount) - Number(detail.total_amount) / (1 + gstRate / 100)
      : 0;

    const logosTop = (st.company_logo_url || st.store_logo_url)
      ? `<div style="display:flex;gap:16px;align-items:center;margin-bottom:10px">
          ${st.company_logo_url ? `<img src="${esc(st.company_logo_url)}" style="max-height:48px;max-width:180px;object-fit:contain" />` : ''}
          ${st.store_logo_url ? `<img src="${esc(st.store_logo_url)}" style="max-height:48px;max-width:180px;object-fit:contain" />` : ''}
        </div>` : '';

    // "How to Pay" — QR images + PayNow UEN + Bank Account together in one row.
    const qrs = [
      [st.qr_paynow_url, 'PayNow'], [st.qr_grabpay_url, 'GrabPay'], [st.qr_atome_url, 'Atome'],
    ].filter(([u]) => !!u) as [string, string][];
    const payDetailBits = [
      st.paynow_uen ? `PayNow UEN: ${esc(st.paynow_uen)}` : '',
      st.bank_account ? `Bank: ${esc(st.bank_account)}` : '',
    ].filter(Boolean);
    const payRow = (qrs.length || payDetailBits.length)
      ? `<div class="payrow">
          ${qrs.map(([u, label]) => `<div class="qr"><img src="${esc(u)}" /><div class="mut">${label}</div></div>`).join('')}
          ${payDetailBits.length ? `<div class="paydetail">${payDetailBits.map(b => `<div>${b}</div>`).join('')}</div>` : ''}
        </div>`
      : '';

    const footerBits = [
      storePhone ? `DID: ${esc(storePhone)}` : '',
      st.email ? `Email: ${esc(st.email)}` : '',
      st.website ? `Website: ${esc(st.website)}` : '',
      st.co_reg_no ? `Co. Reg No.: ${esc(st.co_reg_no)}` : '',
    ].filter(Boolean).join(' &nbsp;|&nbsp; ');

    // Therapy block for print (spec 4.12) — only when this invoice qualified one.
    const th = detailTherapy;
    const therapyBlock = (th && th.used) ? `
      <h2>Unlimited Therapy</h2>
      <div class="ther">
        <div class="mut">
          Eligible: S$${Number(th.eligible_total).toFixed(2)}${Number(th.topup_amount) > 0 ? ` &nbsp;|&nbsp; Qualification top-up: S$${Number(th.topup_amount).toFixed(2)}` : ''} &nbsp;|&nbsp; Applied: S$${Number(th.qualified_total).toFixed(2)}${Number(th.forfeited_total) > 0 ? ` &nbsp;|&nbsp; Forfeited: S$${Number(th.forfeited_total).toFixed(2)}` : ''}
        </div>
        ${(th.linked_invoices ?? []).length > 1
          ? `<div class="mut">Combined invoices: ${(th.linked_invoices ?? []).map((li: any) => `${esc(li.invoice_no)} (S$${Number(li.contributed_amount).toFixed(2)})`).join(', ')}</div>`
          : ''}
        ${(th.entitlements ?? []).map((en: any) => `
          <div class="entb">
            <div><strong>${esc(en.package_name)}</strong> — ${en.entitlement_kind === 'unlimited' ? `${en.duration_months} month(s) unlimited` : `${en.voucher_qty} voucher(s)`}</div>
            <div class="mut">${esc(en.entitlement_no)} &nbsp;|&nbsp; Created: ${new Date(en.created_at).toLocaleDateString()} &nbsp;|&nbsp; Activate by: ${new Date(en.activation_deadline).toLocaleDateString()} &nbsp;|&nbsp; Status: ${esc(String(en.status).replace(/_/g, ' '))}</div>
            ${(en.beneficiaries ?? []).length
              ? `<table class="bentbl"><thead><tr><th>Beneficiary</th><th>Portion</th><th>Activated</th><th>Ends</th><th>Status</th></tr></thead><tbody>
                  ${(en.beneficiaries ?? []).map((b: any) => `<tr>
                    <td>${esc(b.name)}</td>
                    <td>${b.portion_months ? `${b.portion_months} mo` : `${b.portion_vouchers} vouchers`}</td>
                    <td>${b.activation_date ? new Date(b.activation_date).toLocaleDateString() : '—'}</td>
                    <td>${b.ending_date ? new Date(b.ending_date).toLocaleDateString() : (b.portion_vouchers ? 'No expiry' : '—')}</td>
                    <td>${esc(String(b.status).replace(/_/g, ' '))}</td>
                  </tr>`).join('')}
                </tbody></table>`
              : `<div class="mut">No beneficiary assigned yet.</div>`}
          </div>`).join('')}
      </div>` : '';

    // One invoice copy — rendered twice (customer + store) on a single A4 page.
    const copyHtml = `
      <div class="copy">
        ${logosTop}
        <div class="head">
          <div><h1>Energia</h1><div class="mut">Wellness &amp; Retail</div></div>
          <div style="text-align:right"><h1>${esc(detail.invoice_no)}</h1>
            <div class="mut">${esc(store?.name ?? '')}</div>
            ${st.address ? `<div class="mut">${esc(st.address)}</div>` : ''}
            ${storePhone ? `<div class="mut">Tel: ${esc(storePhone)}</div>` : ''}
            <div class="mut">Date: ${new Date(detail.created_at).toLocaleDateString()}</div>
            <div class="mut">Status: ${esc(detail.status)}</div></div>
        </div>
        ${focStamp}
        ${ex ? `<div class="mut"><b>EXCHANGE INVOICE</b> — replaces items from ${esc(ex.original_invoice_no ?? '')}</div>` : ''}
        <h2>Bill To</h2>
        <div>${esc(cust?.full_name ?? '—')}</div><div class="mut">${esc(cust?.phone ?? '')}</div>
        <h2>Items</h2>
        ${exchangeBlock}
        <table><thead><tr><th>${ex ? 'Replacement Item' : 'Item'}</th><th class="r">Qty</th><th class="r">Unit</th><th class="r">Total</th></tr></thead><tbody>${itemRows}</tbody></table>
        <table class="totals">
          ${focTotal > 0 ? `<tr><td>Normal value</td><td class="r">S$${(Number(detail.subtotal) + focTotal).toFixed(2)}</td></tr>
          <tr><td>FOC (free of charge)</td><td class="r">−S$${focTotal.toFixed(2)}</td></tr>` : ''}
          <tr><td>Subtotal${focTotal > 0 ? ' (chargeable)' : ''}</td><td class="r">S$${Number(detail.subtotal).toFixed(2)}</td></tr>
          <tr><td>${ex ? 'Exchange credit applied' : 'Discount'}</td><td class="r">−S$${Number(detail.discount_total).toFixed(2)}</td></tr>
          ${ex && Number(ex.foc_waived ?? 0) > 0 ? `<tr><td>incl. FOC waived top-up</td><td class="r">−S$${Number(ex.foc_waived).toFixed(2)}</td></tr>` : ''}
          ${gstEnabled && gstRate > 0 ? `<tr><td>GST (${gstRate}%, incl.)</td><td class="r">S$${gstAmount.toFixed(2)}</td></tr>` : ''}
          <tr class="grand"><td>${ex ? 'Net Top-Up' : 'Total'}</td><td class="r">S$${Number(detail.total_amount).toFixed(2)}</td></tr>
        </table>
        ${payRows ? `<h2>Payment Methods</h2><table class="paytbl"><tbody>${payRows}<tr><td><strong>Total Paid</strong></td><td class="r"><strong>S$${totalPaid.toFixed(2)}</strong></td></tr></tbody></table>` : ''}
        ${therapyBlock}
        ${authorisedBlock}
        ${payRow ? `<h2>How to Pay</h2>${payRow}` : ''}
        <div class="signrow">
          <div class="sign"><div class="signline"></div>Customer Signature</div>
        </div>
        <div class="terms">Goods and services sold are neither refundable nor exchangeable. Goods and services have been checked and collected.</div>
        ${footerBits ? `<div class="footer">${footerBits}</div>` : ''}
      </div>`;

    const html = `<!doctype html><html><head><title>${esc(detail.invoice_no)}</title><style>
      @page { size: A4; margin: 10mm; }
      body{font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#111;margin:0;}
      h1{font-size:18px;margin:0;} h2{font-size:12px;margin:12px 0 4px;text-transform:uppercase;letter-spacing:0.04em;color:#333;}
      .mut{color:#666;font-size:10.5px;} .r{text-align:right;}
      table{width:100%;border-collapse:collapse;margin-top:4px;}
      th{font-size:10px;text-transform:uppercase;color:#666;text-align:left;border-bottom:1px solid #999;padding:4px 6px;}
      th.r{text-align:right;} td{padding:4px 6px;border-bottom:1px solid #eee;vertical-align:top;}
      tr.sub td{border-bottom:none;padding:1px 6px 1px 18px;font-size:11px;color:#555;}
      .ther{border:1px solid #ddd;border-radius:4px;padding:6px 8px;margin-top:4px;}
      .entb{margin-top:6px;padding-top:6px;border-top:1px solid #eee;}
      .entb:first-of-type{border-top:none;padding-top:0;margin-top:4px;}
      .bentbl{margin-top:3px;} .bentbl th{font-size:9px;padding:2px 4px;border-bottom:1px solid #ccc;}
      .bentbl td{font-size:10.5px;padding:2px 4px;border-bottom:1px solid #f2f2f2;}
      .totals{margin-top:8px;width:260px;margin-left:auto;} .totals td{border:none;padding:2px 6px;}
      .paytbl td{border:none;padding:2px 6px;}
      .grand{font-size:15px;font-weight:bold;border-top:1px solid #999;}
      .head{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:2px solid #111;padding-bottom:10px;}
      .payrow{display:flex;gap:20px;align-items:center;flex-wrap:wrap;margin-top:6px;}
      .payrow .qr{text-align:center;} .payrow .qr img{width:92px;height:92px;object-fit:contain;}
      .payrow .paydetail{font-size:11px;line-height:1.7;color:#333;}
      .signrow{margin-top:30px;} .sign{width:250px;font-size:11px;color:#333;}
      .signline{border-bottom:1px solid #333;height:34px;margin-bottom:4px;}
      .terms{margin-top:14px;padding-top:8px;border-top:1px solid #ccc;font-size:11px;color:#333;}
      .footer{margin-top:8px;padding-top:6px;border-top:1px solid #ccc;font-size:10px;color:#444;line-height:1.6;text-align:center;}
      .copy{padding:2mm 0;box-sizing:border-box;}
    </style></head><body>
      ${copyHtml}
      <script>window.onload=function(){window.print();}</script>
    </body></html>`;
    const w = window.open('', '_blank');
    if (!w) { alert('Please allow pop-ups to print.'); return; }
    w.document.write(html); w.document.close();
    // Audit: record that this invoice was printed.
    supabase.rpc('write_audit', {
      p_table: 'invoices', p_record: detail.id, p_action: 'invoice_printed',
      p_old: null, p_new: { invoice_no: detail.invoice_no },
    }).then(() => {}, () => {});
  };

  const statusOptions: ('all' | InvoiceStatus)[] = ['all', 'unpaid', 'partially_paid', 'paid', 'cancelled', 'refunded'];

  return (
    <div>
      <div className="page-header">
        <div><h2>Invoices</h2><p>Create invoices for a store. Stock is deducted only when an invoice is fully paid.</p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button className="btn btn-secondary" onClick={loadAll}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
          {canExport && <button className="btn btn-secondary" onClick={doExport}><Download size={15} /> Export CSV</button>}
          {isOwnerOrManager(profile?.role) && <button className="btn btn-secondary" onClick={() => { setSeLabel(saveEarthDefault.label); setSeAmount(saveEarthDefault.amount); setSeSettingsOpen(true); }} title="Save Earth defaults">🌱 Save Earth</button>}
          <button className="btn btn-secondary" onClick={openBuy}><Coins size={15} /> Buy Credit</button>
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
                        {inv.status !== 'paid' && inv.status !== 'partially_paid' && inv.status !== 'cancelled' && inv.status !== 'refunded' && Number(inv.paid_amount) === 0 && (
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
      {buyOpen && (
        <Modal title="Buy Credit" maxWidth={520} onClose={() => setBuyOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setBuyOpen(false)}>Cancel</button>
            <button className="btn btn-primary" onClick={submitBuy}
              disabled={buyBusy || !buyId || !buyCustomer}>{buyBusy ? 'Creating…' : 'Create Invoice'}</button></>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              Creates an invoice for a Credit Package or Premium Bundle. The credit, bonus credit and reward vouchers are issued automatically once the invoice is fully paid. Wallet credit cannot pay for it.
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Customer *</label>
              <CustomerSearchSelect value={buyCustomer} onChange={setBuyCustomer} />
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>What are they buying?</label>
              <select value={buyKind} onChange={e => { setBuyKind(e.target.value as any); setBuyId(''); setBuyBasket({}); }}>
                <option value="credit_package">Credit Package</option>
                <option value="premium_bundle">Premium Bundle</option>
              </select>
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>{buyKind === 'credit_package' ? 'Credit Package' : 'Premium Bundle'} *</label>
              <SearchSelect placeholder="Search package or bundle name…"
                value={buyId} onChange={setBuyId}
                options={(buyKind === 'credit_package' ? buyPkgs : buyBundles).map((x: any) => ({
                  value: x.id,
                  label: `${x.name} — pays ${money(buyKind === 'credit_package' ? x.customer_price : x.customer_payment_amount)}${buyKind === 'premium_bundle' ? ` · ${x.free_voucher_qty} vouchers` : ''}`,
                  search: x.name }))} />
            </div>

            {buyKind === 'premium_bundle' && buyId && (() => {
              const b: any = buyBundles.find((x: any) => x.id === buyId);
              const need = b ? b.free_voucher_qty : 0;
              const chosen = Object.values(buyBasket).reduce((a, c) => a + (c || 0), 0);
              return (
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Choose {need} reward voucher(s) — {chosen}/{need} selected</label>
                  <div style={{ maxHeight: 200, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
                    {buyVouchers.length === 0 && <div style={{ padding: 10, fontSize: 12, color: 'var(--text-muted)' }}>No eligible vouchers available at this store.</div>}
                    {buyVouchers.map((v: any) => {
                      const cur = buyBasket[v.voucher_id] ?? 0;
                      const cap = v.available_qty == null ? need : Math.min(need, v.available_qty);
                      return (
                        <div key={v.voucher_id} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, padding: '6px 9px', borderBottom: '1px solid var(--border)' }}>
                          <div style={{ fontSize: 12.5 }}>{v.name}
                            <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{v.available_qty == null ? 'unlimited' : `${v.available_qty} in stock`}</div>
                          </div>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                            <button className="btn btn-secondary btn-sm" disabled={cur <= 0}
                              onClick={() => setBuyBasket(bk => ({ ...bk, [v.voucher_id]: Math.max(0, (bk[v.voucher_id] ?? 0) - 10) }))}>−10</button>
                            <span style={{ minWidth: 30, textAlign: 'center', fontSize: 13 }}>{cur}</span>
                            <button className="btn btn-secondary btn-sm" disabled={chosen >= need || cur >= cap}
                              onClick={() => setBuyBasket(bk => ({ ...bk, [v.voucher_id]: Math.min(cap, (bk[v.voucher_id] ?? 0) + 10) }))}>+10</button>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                    Mix any eligible vouchers up to the required quantity. Stock is checked before the invoice is created.
                  </div>
                </div>
              );
            })()}

            {buyErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{buyErr}</div></div>}
          </div>
        </Modal>
      )}

      {createOpen && (
        <Modal title={editingInvoiceId ? "Edit Invoice" : "New Invoice"} wide onClose={() => { setCreateOpen(false); setEditingInvoiceId(null); }}
          footer={<><button className="btn btn-secondary" onClick={() => { setCreateOpen(false); setEditingInvoiceId(null); }}>Cancel</button><button className="btn btn-primary" onClick={handleCreate} disabled={cSaving}>{cSaving ? 'Saving…' : editingInvoiceId ? 'Save Changes' : 'Create Invoice'}</button></>}>
          <div className="form-grid">
            {cErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{cErr}</div></div>}
            <div className="form-grid-2">
              <div className="form-group">
                <label>Store *</label>
                {isStaff ? (
                  <input value={stores.find(s => s.id === (assignedStoreId ?? ''))?.name ?? 'No store assigned'} disabled style={{ background: 'var(--surface-2)' }} />
                ) : (
                  <select value={cStore} disabled={!!editingInvoiceId} title={editingInvoiceId ? "The store cannot be changed on an existing invoice" : undefined} onChange={e => { setCStore(e.target.value); setCLines([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]); }}>
                    <option value="">— Select store —</option>
                    {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>
                )}
              </div>
              <div className="form-group">
                <label>Customer *</label>
                <CustomerSearchSelect value={cCustomer} onChange={v => { setCCustomer(v); setCLines(ls => ls); }} />
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
                        <select value={line.kind} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, kind: e.target.value as LineDraft['kind'], product_id: '', voucher_id: '', promotion_id: '', therapy_package_id: '' } : l))} style={{ width: 110 }}>
                          <option value="product">Product</option>
                          <option value="voucher">Voucher</option>
                          <option value="promotion">Promotion</option>
                          {therapyPackages.length > 0 && <option value="therapy">Therapy</option>}
                        </select>
                        {line.kind === 'product' ? (
                          <SearchSelect style={{ flex: 1 }} placeholder="Search product name or SKU…"
                            value={line.product_id}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, product_id: v } : l))}
                            options={storeProducts.map(p => { const a = productAvail(p.id); return {
                              value: p.id, label: `${p.name} — ${a.label}${a.needsOverride ? ' *' : ''}`,
                              sublabel: (p as any).sku, search: `${p.name} ${(p as any).sku ?? ''}` }; })} />
                        ) : line.kind === 'voucher' ? (
                          <SearchSelect style={{ flex: 1 }} placeholder="Search voucher name or code…"
                            value={line.voucher_id}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, voucher_id: v } : l))}
                            options={sellableVouchers.map(v => ({
                              value: v.id,
                              label: `${v.name}${voucherPrice(v.id) != null ? ` — ${money(voucherPrice(v.id)!)}` : ' — no price for this store'}`,
                              sublabel: (v as any).code, search: `${v.name} ${(v as any).code ?? ''}` }))} />
                        ) : line.kind === 'therapy' ? (
                          <SearchSelect style={{ flex: 1 }} placeholder="Search therapy package…"
                            value={line.therapy_package_id ?? ''}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, therapy_package_id: v } : l))}
                            options={therapyPackages.map(p => { const pr = therapyPrice(p.id); return {
                              value: p.id,
                              label: `${p.name} (${p.duration_months}mo)${pr != null ? ` — ${money(pr)}` : ' — no price for this store'}`,
                              search: p.name }; })} />
                        ) : (
                          <SearchSelect style={{ flex: 1 }} placeholder="Search promotion name or code…"
                            value={line.promotion_id}
                            onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, promotion_id: v } : l))}
                            options={promotions.map(p => ({
                              value: p.id,
                              label: `${p.name}${promoPrice(p.id) != null ? ` — ${money(promoPrice(p.id)!)}` : ' — no price for this store'}`,
                              sublabel: (p as any).code, search: `${p.name} ${(p as any).code ?? ''}` }))} />
                        )}
                        <input type="number" min={1} value={line.quantity || ''} placeholder="Qty" style={{ width: 70 }}
                          onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, quantity: +e.target.value } : l))} />
                        <span style={{ width: 78, textAlign: 'right', fontSize: 13, fontWeight: 600 }}>{price ? money(price * line.quantity) : '—'}</span>
                        <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setCLines(ls => ls.filter((_, j) => j !== i))} disabled={cLines.length === 1}><X size={13} /></button>
                      </div>
                      {/* Phase 12 — FOC. Quantity stays full (stock still moves); only the charge drops. */}
                      {(line.kind !== 'product' || line.product_id) && (line.quantity ?? 0) > 0 && (
                        <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginLeft: 118, marginTop: -2, flexWrap: 'wrap' }}>
                          <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>FOC:</span>
                          <select
                            value={String(line.foc_quantity ?? 0)}
                            onChange={e => { const q = +e.target.value; setCLines(ls => ls.map((l, j) => j === i ? { ...l, foc_quantity: q, ...(q === 0 ? { foc_reason_id: '', foc_reason: '' } : {}) } : l)); }}
                            style={{ width: 108, fontSize: 12.5 }}>
                            <option value="0">None</option>
                            {Array.from({ length: line.quantity }, (_, k) => k + 1).map(q => (
                              <option key={q} value={q}>{q === line.quantity ? `All ${q} free` : `${q} free`}</option>
                            ))}
                          </select>
                          {(line.foc_quantity ?? 0) > 0 && (
                            <>
                              <select value={line.foc_reason_id ?? ''}
                                onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, foc_reason_id: e.target.value } : l))}
                                style={{ flex: 1, maxWidth: 220, fontSize: 12.5 }}>
                                <option value="">— Reason (required) —</option>
                                {focReasons.map(r => <option key={r.id} value={r.id}>{r.label}{r.requires_note ? ' *' : ''}</option>)}
                              </select>
                              <input type="text" placeholder="Note" value={line.foc_reason ?? ''}
                                onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, foc_reason: e.target.value } : l))}
                                style={{ flex: 1, maxWidth: 200, fontSize: 12.5 }} />
                              {price ? (
                                <span style={{ fontSize: 11.5, color: 'var(--success)' }}>
                                  free {money(price * (line.foc_quantity ?? 0))}
                                </span>
                              ) : null}
                            </>
                          )}
                        </div>
                      )}
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
                      {line.kind === 'promotion' && line.promotion_id && includedFor(line.promotion_id).length > 0 && (
                        <div style={{ marginLeft: 28, marginTop: 6, marginBottom: 6, border: '1px solid var(--border)',
                                      borderRadius: 'var(--radius-sm)', overflow: 'hidden' }}>
                          <div style={{ padding: '6px 10px', background: 'var(--bg)', fontSize: 12, fontWeight: 700 }}>
                            Included in this bundle ({includedFor(line.promotion_id).length})
                          </div>
                          {includedFor(line.promotion_id).map(it => (
                            <div key={it.id} style={{ display: 'flex', justifyContent: 'space-between',
                                                      padding: '5px 10px', fontSize: 12.5, borderTop: '1px solid var(--border)' }}>
                              <span>
                                {it.kind === 'voucher' ? '🎟 ' : it.kind === 'therapy' ? '✨ ' : it.kind === 'credit_package' ? '💳 ' : '📦 '}
                                {it.label}
                              </span>
                              <span style={{ color: 'var(--text-muted)' }}>
                                × {it.qty * line.quantity}
                              </span>
                            </div>
                          ))}
                          <div style={{ padding: '5px 10px', fontSize: 11, color: 'var(--text-muted)', borderTop: '1px solid var(--border)' }}>
                            Always included — no choice needed. The bundle price already covers these.
                          </div>
                        </div>
                      )}
                      {line.kind === 'promotion' && line.promotion_id && groupsFor(line.promotion_id).map(g => {
                        const need = g.choose_qty * line.quantity;
                        const got = selSum(line, g.id);
                        const done = got === need;
                        const isProd = g.item_kind === 'product';
                        const baseline = isProd ? groupBaseline(g.id, effMember) : null;
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
                        // Display value inside a promotion choice picker. Products use
                        // the mode-aware store price; the voucher branch shows its
                        // Member/Non-Member store price (no legacy selling_price).
                        const itemPrice = (id: string): number | null => isProd
                          ? priceFor(activeStore, id)
                          : voucherPrice(id);
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
                                      const lm = effMember;
                                      const pr = priceFor(activeStore, p.id, lm);
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
              <div className="form-group" style={{ gridColumn: '1 / -1' }}>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                  <input type="checkbox" checked={saveEarthOn} style={{ width: 'auto' }}
                    onChange={e => { setSaveEarthOn(e.target.checked); if (e.target.checked) { setSaveEarthLabel(saveEarthDefault.label); setSaveEarthAmount(saveEarthDefault.amount); } }} />
                  {saveEarthDefault.label} (S${Number(saveEarthDefault.amount).toFixed(2)})
                </label>
                {saveEarthOn && (
                  <div style={{ display: 'flex', gap: 6, marginTop: 6, flexWrap: 'wrap' }}>
                    <input value={saveEarthLabel} onChange={e => setSaveEarthLabel(e.target.value)} placeholder="Label for this invoice" style={{ flex: 1, minWidth: 160 }} />
                    <input type="number" min={0} step={0.01} value={saveEarthAmount} onChange={e => setSaveEarthAmount(Math.max(0, +e.target.value))} style={{ width: 110 }} />
                  </div>
                )}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
                <div style={{ textAlign: 'right', fontSize: 13, color: 'var(--text-secondary)' }}>Subtotal: <strong>{money(createSubtotal)}</strong></div>
                {focValuePreview > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--success)' }}>FOC given: {money(focValuePreview)}</div>}
                {topupPreview > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>+ top-up {money(topupPreview)}</div>}
                {(cDiscount || 0) > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− manual discount {money(cDiscount)}</div>}
                {lineVoucherDiscountPreview > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− line vouchers {money(lineVoucherDiscountPreview)}</div>}
                {cDiscountVoucher && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− voucher discount {money(voucherDiscountPreview)}</div>}
                {saveEarthOn && (saveEarthAmount || 0) > 0 && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>− {saveEarthLabel || 'Save Earth'} {money(saveEarthAmount)}</div>}
                <div style={{ textAlign: 'right', fontSize: 16, fontWeight: 700, marginTop: 2 }}>Total: {money(previewTotal)}</div>
              </div>
            </div>
          </div>
        </Modal>
      )}

      {/* Invoice detail + payment modal */}
      {detail && (
        <Modal title={`Invoice ${detail.invoice_no}`} wide onClose={() => setDetail(null)}
          footer={
            detail.status === 'paid'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
                  <button className="btn btn-danger" onClick={() => { setActionType('invoice_refund'); setActionReturnStock(true); setActionReason(''); setActionErr(null); }}>{isOwnerOrManager(profile?.role) ? 'Refund/Cancel' : 'Request Refund'}</button></>
              : detail.status === 'cancelled' || detail.status === 'refunded' || detail.status === 'cancellation_requested' || detail.status === 'refund_requested'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button></>
              : (detail.status === 'unpaid' || detail.status === 'draft') && Number(detail.paid_amount) === 0
                  && !(detail as any).is_topup && !(detail as any).is_exchange && detailPayments.length === 0
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                  <button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
                  <button className="btn btn-secondary" onClick={openEdit}><FileText size={14} /> Edit Invoice</button>
                  {detail.is_full_foc && Number(detail.total_amount) <= 0
                    ? <button className="btn btn-primary" onClick={handleConfirmFoc} disabled={focBusy}><Sparkles size={15} /> {focBusy ? 'Confirming…' : 'Confirm FOC Invoice'}</button>
                    : <button className="btn btn-primary" onClick={handlePay} disabled={payBusy}><CreditCard size={15} /> {payBusy ? 'Processing…' : 'Record Payment'}</button>}</>
              : detail.status === 'completed_foc'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button></>
              : <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
                  {detail.is_full_foc && Number(detail.total_amount) <= 0
                    ? <button className="btn btn-primary" onClick={handleConfirmFoc} disabled={focBusy}><Sparkles size={15} /> {focBusy ? 'Confirming…' : 'Confirm FOC Invoice'}</button>
                    : <button className="btn btn-primary" onClick={handlePay} disabled={payBusy}><CreditCard size={15} /> {payBusy ? 'Processing…' : 'Record Payment'}</button>}</>
          }>
          <div className="form-grid">
            {focErr && <div className="alert alert-danger" style={{ fontSize: 12.5 }}>{focErr}</div>}
            {detailExchange?.found && (
              <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '10px 12px', background: 'var(--surface-2)', fontSize: 12.5 }}>
                <div style={{ fontWeight: 700, marginBottom: 4 }}>Exchange Invoice — {detailExchange.exchange_no}</div>
                <div style={{ color: 'var(--text-muted)' }}>Original invoice: <b>{detailExchange.original_invoice_no}</b>{detailExchange.reason ? <> · Reason: {detailExchange.reason}</> : null}</div>
                <div style={{ marginTop: 6 }}>
                  <div style={{ fontWeight: 600 }}>Returned</div>
                  {(detailExchange.returned_items ?? []).map((r: any, i: number) => (
                    <div key={i} style={{ display: 'flex', justifyContent: 'space-between' }}><span>{r.product} × {r.quantity}</span><span>{money(Number(r.line_total))}</span></div>
                  ))}
                  <div style={{ fontWeight: 600, marginTop: 4 }}>Replacement</div>
                  {(detailExchange.replacement_items ?? []).map((r: any, i: number) => (
                    <div key={i} style={{ display: 'flex', justifyContent: 'space-between' }}><span>{r.product} × {r.quantity}</span><span>{money(Number(r.line_total))}</span></div>
                  ))}
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4, color: 'var(--success)' }}><span>Exchange credit</span><span>− {money(Number(detailExchange.exchange_credit_applied ?? 0))}</span></div>
                  {Number(detailExchange.nonrefundable ?? 0) > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--text-muted)' }}><span>Non-refundable difference</span><span>{money(Number(detailExchange.nonrefundable))}</span></div>}
                  {Number(detailExchange.foc_waived ?? 0) > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--success)' }}><span>FOC (waived top-up)</span><span>− {money(Number(detailExchange.foc_waived))}</span></div>}
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700, marginTop: 2 }}><span>Net top-up paid</span><span>{money(Number(detailExchange.net_topup ?? 0))}</span></div>
                </div>
                <div style={{ color: 'var(--text-muted)', marginTop: 6 }}>Processed by {detailExchange.processed_by ?? '—'} · {detailExchange.processing_store ?? ''}</div>
              </div>
            )}
            {/* Summary */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{storeName(detail.store_id)} · {custName(detail.customer_id)}</div>
                <div style={{ marginTop: 4 }}><StatusBadge s={detail.status} /></div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 20, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(detail.total_amount)}</div>
                <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Paid {money(detail.paid_amount)}</div>
                {Number(detail.foc_total ?? 0) > 0 && (
                  <div style={{ fontSize: 12, color: 'var(--success)', fontWeight: 600 }}>
                    {detail.is_full_foc ? 'Fully FOC' : 'Incl. FOC'} {money(Number(detail.foc_total))}
                  </div>
                )}
              </div>
            </div>

            {/* Affiliate selector — only while the invoice is unpaid and unlocked. */}
            {(detail.status === 'unpaid' || detail.status === 'draft') && Number(detail.paid_amount) === 0
              && !(detail as any).is_topup && !(detail as any).is_exchange && detailPayments.length === 0 && (
              <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '10px 12px' }}>
                <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6 }}>Affiliate</div>
                <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                  <select
                    value={(detail as any).affiliate_id ?? (effAffiliate?.affiliate_id ?? '')}
                    disabled={affiliateBusy}
                    style={{ maxWidth: 280 }}
                    onChange={e => changeInvoiceAffiliate(e.target.value === '' ? null : e.target.value)}>
                    <option value="">— No affiliate —</option>
                    {affiliateOptions.map(a => (
                      <option key={a.affiliate_id} value={a.affiliate_id}>{a.full_name}{a.phone ? ` · ${a.phone}` : ''}</option>
                    ))}
                  </select>
                  {affiliateBusy && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>Saving…</span>}
                </div>
                {affiliateErr && <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>{affiliateErr}</div>}
                {effAffiliate?.has_affiliate ? (
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 5 }}>
                    {effAffiliate.source === 'invoice'
                      ? <>Chosen for this invoice: <strong>{effAffiliate.full_name}</strong> earns Tier 1.</>
                      : <>From this customer's referrer: <strong>{effAffiliate.full_name}</strong> earns Tier 1{effAffiliate.tier2_name ? <> and {effAffiliate.tier2_name} earns Tier 2</> : null}.</>}
                    {effAffiliate.is_registered_affiliate === false && (
                      <span style={{ color: 'var(--danger)' }}> This person is not a registered affiliate, so no commission will be paid.</span>
                    )}
                    {effAffiliate.is_registered_affiliate && effAffiliate.is_active_affiliate === false && (
                      <span style={{ color: 'var(--danger)' }}> Their affiliate account is not active, so commission will be blocked.</span>
                    )}
                  </div>
                ) : (
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 5 }}>
                    This customer has no referrer, so no affiliate is credited unless you choose one.
                  </div>
                )}
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                  Choose a different affiliate to credit this sale instead. This can be changed until the invoice is paid.
                </div>
              </div>
            )}

            {isOwnerOrManager(profile?.role) && ['draft','unpaid','partially_paid'].includes(detail.status) && (
              <div>
                <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 4 }}>Fulfil from</div>
                <select value={(detail as any).fulfil_warehouse_id ?? ''} disabled={fulfilBusy} style={{ maxWidth: 280 }}
                  onChange={e => setFulfilment(e.target.value === '' ? null : e.target.value)}>
                  <option value="">This store's stock</option>
                  {warehouses.map(w => <option key={w.id} value={w.id}>{w.name} (warehouse)</option>)}
                </select>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                  Choosing a warehouse takes the goods out of warehouse stock instead of this store's.
                  The invoice still belongs to the store for pricing, commission and reporting.
                  Owner/Manager only.
                </div>
                {fulfilErr && <div className="alert alert-danger" style={{ marginTop: 6, marginBottom: 0 }}><span>⚠</span><div>{fulfilErr}</div></div>}
              </div>
            )}

            {invLegacy.length > 0 && (
              <div style={{ border: '1px solid var(--success)', background: 'var(--success-light)', borderRadius: 'var(--radius-sm)', padding: '10px 12px' }}>
                <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6 }}>
                  Legacy therapy earned {invLegacy.length > 1 ? `(${invLegacy.length})` : ''}
                </div>
                {invLegacy.map(e => (
                  <div key={e.id} style={{ fontSize: 12, marginBottom: 3 }}>
                    <strong>{e.entitlement_no}</strong> · {e.package_name}
                    {e.entitlement_kind === 'voucher' ? ` · ${e.voucher_qty ?? 0} voucher(s)` : e.duration_months ? ` · ${e.duration_months} months` : ''}
                    {' · '}
                    {e.status === 'pending_activation'
                      ? <span>unclaimed — claim by {e.activation_deadline ? new Date(e.activation_deadline).toLocaleDateString('en-GB') : '—'} under Therapy → Legacy Therapy</span>
                      : <span>{String(e.status).replace('_', ' ')}{e.expiry_date ? ` until ${new Date(e.expiry_date).toLocaleDateString('en-GB')}` : ''}</span>}
                  </div>
                ))}
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                  Earned from this customer's same-day paid total at this store.
                </div>
              </div>
            )}

            {detailRevisions.length > 0 && (
              <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                <b>Edit history:</b> {detailRevisions.map(r =>
                  `#${r.revision_no} ${new Date(r.edited_at).toLocaleString('en-GB')}${r.edit_reason ? ` — ${r.edit_reason}` : ''}`
                ).join(' · ')}
              </div>
            )}
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
                            {Number(it.foc_quantity ?? 0) === 0 && detail.status !== 'paid' && detail.status !== 'completed_foc'
                              && detail.status !== 'cancelled' && detail.status !== 'refunded' && Number(detail.paid_amount) === 0 && (
                              <div style={{ fontSize: 11 }}>
                                <button className="btn btn-secondary btn-sm" style={{ padding: '1px 7px', fontSize: 10.5 }}
                                  onClick={() => { setFocLine(it); setFocQty(it.quantity); setFocReasonId(''); setFocNote(''); setFocErr(null); }}>
                                  Make FOC
                                </button>
                              </div>
                            )}
                            {Number(it.foc_quantity ?? 0) > 0 && (
                              <div style={{ fontSize: 11, color: 'var(--success)', fontWeight: 600 }}>
                                {it.is_foc ? 'FOC' : `FOC ${it.foc_quantity} of ${it.quantity}`} — free {money(Number(it.foc_amount ?? 0))}
                                {it.foc_reason ? <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}> · {it.foc_reason}</span> : null}
                                {detail.status !== 'paid' && detail.status !== 'completed_foc' && detail.status !== 'cancelled' && detail.status !== 'refunded' && Number(detail.paid_amount) === 0 && (
                                  <button className="btn btn-secondary btn-sm" style={{ marginLeft: 6, padding: '1px 7px', fontSize: 10.5 }}
                                    disabled={focBusy} onClick={() => handleRemoveLineFoc(it.id)}>Remove FOC</button>
                                )}
                              </div>
                            )}
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

            {/* Therapy (spec 4.12) */}
            {detailTherapy?.used && (
              <div>
                <label>Unlimited Therapy</label>
                <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 12, marginTop: 4 }}>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 16px', fontSize: 12.5, marginBottom: 8 }}>
                    <span>Eligible amount: <strong>{money(detailTherapy.eligible_total)}</strong></span>
                    {Number(detailTherapy.topup_amount) > 0 && <span>Qualification top-up: <strong>{money(detailTherapy.topup_amount)}</strong></span>}
                    <span>Applied to packages: <strong>{money(detailTherapy.qualified_total)}</strong></span>
                    {Number(detailTherapy.forfeited_total) > 0 &&
                      <span style={{ color: 'var(--danger)' }}>Forfeited balance: <strong>{money(detailTherapy.forfeited_total)}</strong></span>}
                  </div>

                  {(detailTherapy.linked_invoices ?? []).length > 1 && (
                    <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 8 }}>
                      Combined invoices: {(detailTherapy.linked_invoices ?? []).map((li: any, i: number) => (
                        <span key={i}>{i > 0 && ', '}
                          <strong style={{ color: li.is_this_invoice ? 'var(--primary)' : undefined }}>{li.invoice_no}</strong> ({money(li.contributed_amount)})
                        </span>
                      ))}
                    </div>
                  )}

                  {(detailTherapy.entitlements ?? []).map((en: any, i: number) => (
                    <div key={i} style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 10, marginBottom: 6 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 6 }}>
                        <div style={{ fontSize: 13 }}>
                          <strong>{en.package_name}</strong>
                          <span style={{ color: 'var(--text-muted)' }}> · {en.entitlement_kind === 'unlimited' ? `${en.duration_months} month(s) unlimited` : `${en.voucher_qty} voucher(s)`}</span>
                          <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                            {en.entitlement_no} · created {new Date(en.created_at).toLocaleDateString()} · activate by {new Date(en.activation_deadline).toLocaleDateString()}
                          </div>
                        </div>
                        <span className={`badge ${en.status === 'expired_before_activation' || en.status === 'cancelled' ? 'badge-danger' : en.status === 'activated' ? 'badge-success' : 'badge-muted'}`}>
                          {String(en.status).replace(/_/g, ' ')}
                        </span>
                      </div>
                      {(en.beneficiaries ?? []).length > 0 && (
                        <div style={{ marginTop: 6, borderTop: '1px solid var(--border)', paddingTop: 6 }}>
                          {(en.beneficiaries ?? []).map((b: any, j: number) => (
                            <div key={j} style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 6, fontSize: 12, marginBottom: 2 }}>
                              <span>
                                <strong>{b.name}</strong>
                                <span style={{ color: 'var(--text-muted)' }}> · {b.portion_months ? `${b.portion_months} mo` : `${b.portion_vouchers} vouchers`}</span>
                                {b.transferred_from && <span style={{ color: 'var(--text-muted)' }}> · transferred from {b.transferred_from}</span>}
                              </span>
                              <span style={{ color: 'var(--text-secondary)' }}>
                                {b.activation_date
                                  ? <>{new Date(b.activation_date).toLocaleDateString()}{b.ending_date ? ` → ${new Date(b.ending_date).toLocaleDateString()}` : ' · no expiry'}</>
                                  : 'not activated'}
                                {' '}<span className={`badge ${b.status === 'active' ? 'badge-success' : b.status === 'scheduled' ? 'badge-primary' : b.status === 'cancelled' || b.status === 'expired_before_activation' ? 'badge-danger' : 'badge-muted'}`} style={{ fontSize: 10 }}>{String(b.status).replace(/_/g, ' ')}</span>
                              </span>
                            </div>
                          ))}
                        </div>
                      )}
                      {(en.beneficiaries ?? []).length === 0 && (
                        <div style={{ marginTop: 6, fontSize: 11.5, color: 'var(--text-muted)' }}>No beneficiary assigned yet.</div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {detailTherapy && !detailTherapy.used && detailTherapy.eligible && legacyDiag && (
              <div className={`alert ${legacyDiag.qualifies ? 'alert-info' : 'alert-warning'}`} style={{ marginBottom: 0 }}>
                <span>💡</span>
                <div>
                  <div>No Legacy therapy from this invoice yet. {legacyDiag.reason}</div>
                  {legacyDiag.day_charged != null && (
                    <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 3 }}>
                      Same-day paid total at this store: {money(Number(legacyDiag.day_charged))}
                      {legacyDiag.best_tier_amount ? ` · qualifying tier ${money(Number(legacyDiag.best_tier_amount))}` : ''}
                    </div>
                  )}
                </div>
              </div>
            )}
            {detailTherapy && !detailTherapy.used && detailTherapy.eligible && !legacyDiag && (
              <div className="alert alert-info" style={{ marginBottom: 0 }}>
                <span>💡</span>
                <div>This invoice hasn't been used for therapy qualification yet.</div>
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
                        <optgroup label="Payment methods">
                          {methods.filter((m: any) => !m.is_wallet_credit).map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                        </optgroup>
                        <optgroup label="Wallet credit">
                          {methods.filter((m: any) => m.is_wallet_credit).map((m: any) => {
                            const bal = Number(payWallet?.categories?.[m.wallet_category] ?? 0);
                            return <option key={m.id} value={m.id} disabled={bal <= 0}>
                              {m.name} — {money(bal)} available
                            </option>;
                          })}
                        </optgroup>
                      </select>
                      <input type="number" min={0} step={0.01} value={pl.amount || ''} placeholder="Amount" style={{ width: 110 }}
                        onChange={e => setPayLines(ls => ls.map((l, j) => j === i ? { ...l, amount: +e.target.value } : l))} />
                      <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setPayLines(ls => ls.filter((_, j) => j !== i))} disabled={payLines.length === 1}><X size={13} /></button>
                    </div>
                  ))}
                </div>
                <button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => setPayLines(ls => [...ls, { payment_method_id: methods[0]?.id ?? '', amount: 0 }])}><Plus size={13} /> Split Payment</button>
                {payWallet && Number(payWallet.available_total ?? 0) > 0 && (
                  <div style={{ marginTop: 10, fontSize: 11.5, color: 'var(--text-muted)' }}>
                    Wallet: <strong>{money(Number(payWallet.available_total))}</strong> available —
                    {' '}{(['paid','bonus','legacy','promotional','exchange'] as const)
                      .filter(k => Number(payWallet.categories?.[k] ?? 0) > 0)
                      .map(k => `${k} ${money(Number(payWallet.categories[k]))}`).join(' · ')}
                    <div>Bonus Credit is always spent first, then the oldest eligible credit. Credit-funded value earns no commission.</div>
                  </div>
                )}

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

      {refundLine && detail && (
        <ReasonModal title={`Refund line`} label="Refund reason"
          placeholder="Why is this line being refunded?"
          confirmLabel="Refund line" onClose={() => setRefundLine(null)}
          onSubmit={async (reason) => {
            setRefundBusy(true);
            const { error } = await supabase.rpc('refund_invoice_line', { p_invoice_item_id: refundLine.id, p_reason: reason, p_return_stock: refundLine.line_kind === 'product' });
            setRefundBusy(false); setRefundLine(null);
            if (error) { alert(error.message); return; }
            const { data: invRow } = await supabase.from('invoices').select('*').eq('id', detail.id).single();
            if (invRow) await openDetail(invRow as Invoice); await loadAll();
          }} />
      )}
      {priceReview && detail && (
        <PaymentPriceReview review={priceReview} busy={payBusy}
          onClose={() => setPriceReview(null)}
          onConfirm={() => { setPriceReview(null); handlePay(); }} />
      )}
      {focLine && (
        <Modal title="Make line FOC" maxWidth={420} onClose={() => setFocLine(null)}
          footer={<>
            <button className="btn btn-secondary" onClick={() => setFocLine(null)}>Cancel</button>
            <button className="btn btn-primary" onClick={handleApplyLineFoc} disabled={focBusy}>
              {focBusy ? 'Applying…' : 'Apply FOC'}
            </button>
          </>}>
          <div className="form-grid">
            {focErr && <div className="alert alert-danger" style={{ fontSize: 12.5 }}>{focErr}</div>}
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              The full quantity still leaves inventory and any entitlement is still created — only the charge is waived.
            </div>
            <div>
              <label>Free quantity (of {focLine.quantity})</label>
              <select value={String(focQty)} onChange={e => setFocQty(+e.target.value)}>
                {Array.from({ length: focLine.quantity }, (_, k) => k + 1).map(q => (
                  <option key={q} value={q}>{q === focLine.quantity ? `All ${q} (full FOC)` : `${q} free`}</option>
                ))}
              </select>
            </div>
            <div>
              <label>Reason <span style={{ color: 'var(--danger)' }}>*</span></label>
              <select value={focReasonId} onChange={e => setFocReasonId(e.target.value)}>
                <option value="">— Select a reason —</option>
                {focReasons.map(r => <option key={r.id} value={r.id}>{r.label}{r.requires_note ? ' (note required)' : ''}</option>)}
              </select>
            </div>
            <div>
              <label>Note</label>
              <input value={focNote} onChange={e => setFocNote(e.target.value)} placeholder="Optional unless the reason requires it" />
            </div>
          </div>
        </Modal>
      )}

      {seSettingsOpen && (
        <Modal title="Save Earth Project — Global Defaults" maxWidth={420} onClose={() => setSeSettingsOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setSeSettingsOpen(false)}>Cancel</button>
            <button className="btn btn-primary" disabled={seBusy} onClick={async () => {
              setSeBusy(true);
              const { error } = await supabase.rpc('set_save_earth_defaults', { p_label: seLabel, p_amount: seAmount });
              setSeBusy(false);
              if (error) { alert(error.message); return; }
              setSaveEarthDefault({ label: seLabel, amount: seAmount });
              setSeSettingsOpen(false);
            }}>Save</button></>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>These defaults are copied onto each invoice when the cashier ticks Save Earth. Editing them here does not change past invoices.</div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Default label</label><input value={seLabel} onChange={e => setSeLabel(e.target.value)} /></div>
            <div className="form-group" style={{ marginBottom: 0 }}><label>Default amount (S$)</label><input type="number" min={0} step={0.01} value={seAmount} onChange={e => setSeAmount(Math.max(0, +e.target.value))} /></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default InvoicesPage;
