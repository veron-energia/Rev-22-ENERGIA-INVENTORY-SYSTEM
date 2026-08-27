import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { PRINT_CSS } from '../lib/printDoc';
import { sendViaWhatsAppLink, sendViaEmailAttachment, saveDocumentFile, whatsappNumber, emailAddress, DocFormat } from '../lib/sendDoc';
import { PdfDoc } from '../lib/invoicePdf';
import { ExcelExportButton } from '../components/ExcelExport';
import { PaymentSummaryExport } from '../components/PaymentSummaryExport';
import { XeroExportButton } from '../components/XeroExport';
import { supabase } from '../lib/supabase';
import { PaymentPriceReview, PriceReviewResult } from '../components/PricingControls';
import type { FocReason, InvoiceRevision } from '../types';
import { useAuth } from '../context/AuthContext';
import {
  Invoice, InvoiceItem, InvoicePayment, Store, Product, Customer,
  PaymentMethod, StoreProductPrice, InvoiceStatus, INVOICE_STATUS_LABELS, Voucher, Promotion, PromotionChoiceGroup, PromotionChoiceOption, isOwnerOrManager, isOwner, Profile, SERVICE_STAFF_ROLES, TherapyPackageRule } from '../types';
import { SearchSelect, CustomerSearchSelect } from '../components/SearchSelect';
import { Modal, ReasonModal } from '../components/ui';
import {
  Plus, RefreshCw, FileText, Trash2, X, CreditCard, Eye, Search, CheckCircle2, Download, Printer, Sparkles, Coins , MessageCircle, Mail} from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;

const StatusBadge: React.FC<{ s: InvoiceStatus }> = ({ s }) => {
  const cls = s === 'completed_foc' ? 'badge-success' : s === 'paid' ? 'badge-success' : s === 'partially_paid' ? 'badge-primary'
    : s === 'unpaid' || s === 'draft' ? 'badge-accent'
    : s === 'cancelled' || s === 'refunded' ? 'badge-muted' : 'badge-danger';
  return <span className={`badge ${cls}`}>{INVOICE_STATUS_LABELS[s]}</span>;
};

interface LineDraft { kind: 'product' | 'voucher' | 'promotion' | 'therapy' | 'special_product' | 'rental';
  special_product_id?: string; rental_rate_type?: 'day' | 'week' | 'month' | 'year';
  rental_periods?: number; rental_start_date?: string; rental_return_date?: string; product_id: string; voucher_id: string; promotion_id: string; therapy_package_id?: string; quantity: number; line_voucher_id: string; selections: Record<string, Record<string, number>>; foc_quantity?: number; foc_reason_id?: string; foc_reason?: string; }

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
  // The customers array is capped at 1000 rows by Supabase, so an invoice for
  // a customer outside that set had no name to show. Names for the customers
  // actually referenced are fetched by id instead, which is correct at any
  // table size.
  const [customerById, setCustomerById] = useState<Record<string, any>>({});
  const ensureCustomers = useCallback(async (ids: (string | null | undefined)[]) => {
    const wanted = Array.from(new Set(ids.filter(Boolean) as string[]));
    if (wanted.length === 0) return;
    setCustomerById(prev => {
      const missing = wanted.filter(id => !prev[id]);
      if (missing.length === 0) return prev;
      (async () => {
        const found: Record<string, any> = {};
        for (let i = 0; i < missing.length; i += 200) {
          const { data } = await supabase.from('customers')
            .select('id, full_name, phone, email, referred_by')
            .in('id', missing.slice(i, i + 200));
          for (const c of (data as any[]) ?? []) found[c.id] = c;
        }
        if (Object.keys(found).length > 0) setCustomerById(cur => ({ ...cur, ...found }));
      })();
      return prev;
    });
  }, []);
  const [choiceOptions, setChoiceOptions] = useState<PromotionChoiceOption[]>([]);
  const [storeInv, setStoreInv] = useState<any[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [assignedStoreId, setAssignedStoreId] = useState<string | null>(null);
  // A staff member may be assigned to several stores; they choose among those.
  const [myStores, setMyStores] = useState<{ store_id: string; store_name: string; is_default: boolean }[]>([]);
  const [therapyRules, setTherapyRules] = useState<TherapyPackageRule[]>([]);
  const [therapyPackages, setTherapyPackages] = useState<any[]>([]);
  const [cServiceStaff, setCServiceStaff] = useState<string[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [prices, setPrices] = useState<StoreProductPrice[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<'all' | InvoiceStatus>('all');
  // Free-text search across invoice number, customer, store and date/time.
  const [invSearch, setInvSearch] = useState('');

  // Create modal
  const [createOpen, setCreateOpen] = useState(false);
  const [cStore, setCStore] = useState('');
  const [cCustomer, setCCustomer] = useState('');
  useEffect(() => { if (cCustomer) void ensureCustomers([cCustomer]); }, [cCustomer, ensureCustomers]);
  // Declared HERE, above lineUnit(), which reads it. A `const` is not hoisted:
  // declaring this further down put it in the temporal dead zone, so the first
  // render threw "Cannot access 'specialProducts' before initialization" and
  // the whole page went blank.
  const [specialProducts, setSpecialProducts] = useState<any[]>([]);
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
  // Payment methods per invoice for the whole list, so the table can show them
  // and the search can match on them. Keyed by invoice for a direct lookup.
  const [payMethodsByInvoice, setPayMethodsByInvoice] = useState<Record<string, string[]>>({});
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
  // Correcting a SETTLED invoice is a different, Owner/Manager-only operation:
  // it unwinds stock and commission, writes a revision, and needs a reason.
  const [editingPaid, setEditingPaid] = useState(false);
  const [editReason, setEditReason] = useState('');
  // Correcting the affiliate and the payment methods on a settled invoice.
  const [cAffiliate, setCAffiliate] = useState('');
  const [affTouched, setAffTouched] = useState(false);
  const [payFix, setPayFix] = useState<Record<string, string>>({});
  // Who the invoice is attributed to. Owner only — it changes what a printed
  // document says about who served the customer.
  const [cCreatedBy, setCCreatedBy] = useState('');
  // Snapshots taken when the correction opens: `detail` is cleared at that
  // point, so without these there is nothing to diff against on save.
  const [createdByBeforeEdit, setCreatedByBeforeEdit] = useState('');
  const [paymentsBeforeEdit, setPaymentsBeforeEdit] = useState<InvoicePayment[]>([]);
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
  // Buy Credit used to borrow the New Invoice form's store, which is empty
  // until that form is opened — so the package list silently came back empty.
  const [buyStore, setBuyStore] = useState('');
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
    const [inv, allPays, st, pr, cu, pm, pp, vc, pm2, cg, pit, co, si, prof, myStore, myStoreList, specialRes, trules, utpk, utsp, aset, vsp, psp, focr] = await Promise.all([
      supabase.from('invoices').select('*').is('deleted_at', null).order('created_at', { ascending: false }),
      supabase.from('invoice_payments').select('invoice_id,payment_method_id,amount'),
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
      supabase.rpc('my_assigned_stores'),
      supabase.from('special_products').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('therapy_package_rules').select('*').is('deleted_at', null).eq('is_active', true),
      supabase.from('unlimited_therapy_packages').select('*').is('deleted_at', null).eq('is_active', true).order('duration_months'),
      supabase.from('unlimited_therapy_store_prices').select('*').is('deleted_at', null),
      supabase.from('app_settings').select('save_earth_label, save_earth_amount').maybeSingle(),
      supabase.from('voucher_store_prices').select('*').is('deleted_at', null),
      supabase.from('promotion_store_prices').select('*').is('deleted_at', null),
      supabase.rpc('active_foc_reasons'),
    ]);
    setInvoices((inv.data as Invoice[]) ?? []);

    // Method NAMES per invoice, resolved once here rather than on every render.
    // Duplicates are collapsed: two cash payments on one invoice read as "Cash",
    // not "Cash, Cash".
    const methodName = new Map<string, string>(
      ((pm.data as any[]) ?? []).map(m => [m.id, m.name]));
    const byInvoice: Record<string, string[]> = {};
    for (const row of ((allPays.data as any[]) ?? [])) {
      const name = methodName.get(row.payment_method_id);
      if (!name) continue;
      const list = byInvoice[row.invoice_id] ?? (byInvoice[row.invoice_id] = []);
      if (!list.includes(name)) list.push(name);
    }
    setPayMethodsByInvoice(byInvoice);
    setStores((st.data as Store[]) ?? []);
    setProducts((pr.data as Product[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    // Names for every customer on the loaded invoices, regardless of where
    // they fall alphabetically.
    void ensureCustomers(((inv.data as Invoice[]) ?? []).map(i => i.customer_id));
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
    setMyStores((myStoreList.data as any[]) ?? []);
    setSpecialProducts((specialRes.data as any[]) ?? []);
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
  const customerOf = (id: string | null | undefined) =>
    (id ? customerById[id] : null) ?? customers.find(c => c.id === id) ?? null;
  const custName = (id: string) => customerOf(id)?.full_name ?? '—';
  const prodName = (id: string) => products.find(p => p.id === id)?.name ?? '—';
  const methodName = (id: string) => methods.find(m => m.id === id)?.name ?? '—';
  const isStaff = profile?.role === 'staff';
  // Staff choose among their assigned stores; with only one, it behaves as
  // before. Owners and Managers use the full store list.
  // With more than one assigned store nothing is preselected: the staff member
  // must choose deliberately, because the store decides the prices, the stock
  // the sale comes out of, and where the invoice is reported.
  const staffMustChooseStore = isStaff && myStores.length > 1;
  const storeOptions = isStaff
    ? myStores.map(m => ({ id: m.store_id, name: m.store_name }))
    : stores.map(s2 => ({ id: s2.id, name: s2.name }));
  const activeStore = isStaff
    ? (staffMustChooseStore ? cStore : (cStore || assignedStoreId || myStores[0]?.store_id || ''))
    : cStore;

  const openBuy = async () => {
    setBuyErr(null); setBuyId(''); setBuyBasket({}); setBuyCustomer('');
    setBuyKind('credit_package'); setBuyOpen(true);
    // Same rule as the invoice form: with several assigned stores, nothing is
    // chosen for the staff member.
    const store = staffMustChooseStore
      ? activeStore
      : (activeStore || storeOptions[0]?.id || '');
    setBuyStore(store);
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
        { p_store_id: buyStore });
      setBuyVouchers(((vs as any[]) ?? []).filter(v => ids.includes(v.voucher_id)));
      setBuyBasket({});
    })();
  }, [buyOpen, buyKind, buyId, activeStore]);
  useEffect(() => {
    if (!buyOpen || !buyStore) return;
    (async () => {
      const { data: cp } = await supabase.rpc('credit_packages_for_store', { p_store_id: buyStore, p_day: null });
      setBuyPkgs((cp as any[]) ?? []);
      const { data: pb } = await supabase.rpc('premium_bundles_for_store', { p_store_id: buyStore, p_day: null });
      setBuyBundles((pb as any[]) ?? []);
      setBuyId(''); setBuyBasket({});
    })();
  }, [buyOpen, buyStore]);

  const submitBuy = async () => {
    setBuyBusy(true); setBuyErr(null);
    const line: any = { kind: buyKind, id: buyId };
    if (buyKind === 'premium_bundle') {
      // Only send a selection when the bundle actually grants vouchers. A basket
      // left over from a previously selected bundle would otherwise be sent and
      // rejected — the server wants none, and "Voucher X is not an eligible
      // choice" or "Select exactly 0" would come back with nothing on screen to
      // explain it.
      const bundle: any = buyBundles.find((x: any) => x.id === buyId);
      const grants = !!(bundle && bundle.grants_reward && (bundle.free_voucher_qty ?? 0) > 0);
      line.voucher_selection = grants
        ? Object.entries(buyBasket).filter(([, q]) => q > 0)
            .map(([voucher_id, quantity]) => ({ voucher_id, quantity }))
        : [];
    }
    const { data, error } = await supabase.rpc('create_credit_purchase_invoice', {
      p_store_id: buyStore, p_customer_id: buyCustomer,
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
    l.kind === 'special_product' ? (() => {
      const sp = specialProducts.find((x: any) => x.id === l.special_product_id);
      return sp ? Number(sp.sale_price) : null;
    })()
    : l.kind === 'rental' ? (() => {
      const sp = specialProducts.find((x: any) => x.id === l.special_product_id);
      if (!sp) return null;
      const rate = Number(sp[`rate_${l.rental_rate_type ?? 'day'}`] ?? 0);
      return rate > 0 ? rate * Math.max(1, l.rental_periods ?? 1) : null;
    })()
    : l.kind === 'therapy' ? (l.therapy_package_id ? therapyPrice(l.therapy_package_id, lineMember(l)) : null)
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

  // Baseline of a product group, following the group's OWN base_mode.
  //
  // This previously always took the cheapest option, ignoring base_mode — so a
  // group set to "highest" showed one top-up on screen and the database
  // computed another when the invoice was saved. promotion_selections_topup()
  // has always honoured base_mode; only this preview did not.
  //
  // G: baseline follows the applied pricing mode — a top-up computed under the
  // previous mode is never reused (the memo recomputes on mode change).
  // C: baseline resolves in the promotion LINE's applied mode, not the
  // invoice-wide automatic mode.
  const groupBaseline = (gId: string, member: boolean = effMember): number | null => {
    if (!activeStore) return null;
    const opts = optionsFor(gId)
      .map(o => (o.product_id ? priceFor(activeStore, o.product_id, member) : null))
      .filter((p): p is number => p != null);
    if (!opts.length) return null;
    const highest = (choiceGroups.find(g => g.id === gId) as any)?.base_mode === 'highest';
    return highest ? Math.max(...opts) : Math.min(...opts);
  };

  // 3rd-party product lines cannot be discounted by VOUCHERS. Since migration 99
  // a manual discount does apply to them, so this sum is the voucher base only.
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
    // A discount voucher still cannot reach third-party value; the manual
    // discount is taken off first.
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
    // Mirrors migration 99: a MANUAL discount applies to the whole invoice,
    // third-party included; a VOUCHER discount keeps the narrower base.
    const gross = createSubtotal + topupPreview - lineVoucherDiscountPreview;
    const manual = Math.min(cDiscount || 0, Math.max(0, gross));
    const voucherBase = Math.max(0, createSubtotal + topupPreview - thirdPartySum - lineVoucherDiscountPreview - manual);
    const invLevel = manual + Math.min(voucherDiscountPreview, voucherBase);
    const se = saveEarthOn ? Math.max(0, saveEarthAmount || 0) : 0;
    return Math.max(0, gross - invLevel - se);
  }, [createSubtotal, topupPreview, thirdPartySum, cDiscount, lineVoucherDiscountPreview, voucherDiscountPreview, saveEarthOn, saveEarthAmount]);


  // All vouchers can be sold as a line item (a discount voucher sold now is
  // redeemed by the buyer on a future invoice). Only discount vouchers can be
  // used in the Discount Voucher slot (Normal vouchers have no discount value).
  const sellableVouchers = useMemo(() => vouchers, [vouchers]);

  const resetCreate = () => {
    // Blank when there is a real choice to make.
    setCStore(isStaff && myStores.length === 1
      ? (myStores[0]?.store_id ?? assignedStoreId ?? '') : '');
    setCCustomer('');
    setCLines([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]); setCDiscount(0);
    setCDiscountVoucher(''); setCServiceStaff([]); setCErr(null);
    setSaveEarthOn(false); setSaveEarthLabel(saveEarthDefault.label); setSaveEarthAmount(saveEarthDefault.amount);
  };

  const handleCreate = async () => {
    if (isStaff && myStores.length === 0) { setCErr('You are not assigned to a store, so you cannot create invoices. Ask an Owner or Manager to assign you.'); return; }
    const effectiveStore = isStaff
      ? (staffMustChooseStore ? cStore : (cStore || assignedStoreId || myStores[0]?.store_id || ''))
      : cStore;
    if (!effectiveStore) { setCErr('Choose which store this invoice belongs to.'); return; }
    if (!effectiveStore) { setCErr('Select a store.'); return; }
    if (!cCustomer) { setCErr('Select a customer.'); return; }
    const activeLines = cLines.filter(l => l.quantity > 0 && (
      l.kind === 'product' ? l.product_id
      : l.kind === 'voucher' ? l.voucher_id
      : l.kind === 'therapy' ? l.therapy_package_id
      : (l.kind === 'special_product' || l.kind === 'rental') ? l.special_product_id
      : l.promotion_id));
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
      : l.kind === 'special_product'
      ? { kind: 'special_product', special_product_id: l.special_product_id, quantity: l.quantity, ...ovr(l), ...foc(l) }
      : l.kind === 'rental'
      ? { kind: 'rental', special_product_id: l.special_product_id, quantity: l.quantity,
          rental_rate_type: l.rental_rate_type ?? 'day',
          rental_periods: Math.max(1, l.rental_periods ?? 1),
          rental_start_date: l.rental_start_date || null,
          rental_return_date: l.rental_return_date || null,
          ...ovr(l), ...foc(l) }
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
    if (editingPaid && !editReason.trim()) {
      setCErr('Give a reason for changing a paid invoice — it is kept in the revision history.');
      setCSaving(false); return;
    }

    const { data: rpcId, error } = editingInvoiceId && editingPaid
      ? await supabase.rpc('edit_paid_invoice', {
          p_invoice_id: editingInvoiceId, p_lines: allItems,
          p_reason: editReason.trim(), p_discount: cDiscount || 0,
          p_service_staff: cServiceStaff?.length ? cServiceStaff : null,
          // Correcting a sale rung up at the wrong till: the stock follows.
          p_store_id: cStore || null,
          // Only sent when the affiliate was actually touched, so an unrelated
          // correction never clears one by omission.
          p_affiliate_id: affTouched ? (cAffiliate || null) : null,
          p_set_affiliate: affTouched,
        })
      : editingInvoiceId
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
    if (error) { setCSaving(false); setCErr(error.message); return; }

    // ---- Corrections that are separate RPCs, applied only when correcting a
    //      settled invoice and only when the field was actually changed. ----
    if (editingPaid && editingInvoiceId) {
      // Who the invoice is attributed to (Owner only).
      if (isOwner(profile?.role) && cCreatedBy
          && cCreatedBy !== createdByBeforeEdit) {
        const { error: aErr } = await supabase.rpc('correct_invoice_created_by', {
          p_invoice_id: editingInvoiceId, p_staff_id: cCreatedBy,
          p_reason: editReason.trim() || null,
        });
        if (aErr) {
          setCSaving(false);
          setCErr(`The invoice was corrected, but who it is attributed to could not be: ${aErr.message}`);
          loadAll(); return;
        }
      }

      // Payment methods: only the attribution, never the amounts.
      const changedPayments = Object.entries(payFix)
        .filter(([id, mid]) => paymentsBeforeEdit.find((p2: InvoicePayment) => p2.id === id)?.payment_method_id !== mid)
        .map(([id, mid]) => ({ payment_id: id, payment_method_id: mid }));
      if (changedPayments.length > 0) {
        const { error: pErr } = await supabase.rpc('correct_invoice_payment_methods', {
          p_invoice_id: editingInvoiceId, p_payments: changedPayments,
          p_reason: editReason.trim() || null,
        });
        if (pErr) {
          setCSaving(false);
          setCErr(`The invoice was corrected, but the payment method could not be: ${pErr.message}`);
          loadAll(); return;
        }
      }
    }

    setCSaving(false);
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
    setCreateOpen(false); resetCreate(); setEditingInvoiceId(null);
    setEditingPaid(false); setEditReason(''); loadAll();
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
      } else if (it.line_kind === 'special_product' || it.line_kind === 'rental') {
        // Without this branch a special or rental line fell through to
        // 'product' with an empty product_id, and reopening the invoice
        // rendered a line the rest of the form could not describe.
        lines.push({ kind: it.line_kind as LineDraft['kind'], product_id: '', voucher_id: '', promotion_id: '',
          special_product_id: (it as any).special_product_id ?? '',
          rental_rate_type: (it as any).rental_rate_type ?? 'day',
          rental_periods: Number((it as any).rental_periods ?? 1),
          rental_start_date: (it as any).rental_start_date
            ? String((it as any).rental_start_date).slice(0, 10) : '',
          rental_return_date: (it as any).rental_return_date
            ? String((it as any).rental_return_date).slice(0, 10) : '',
          quantity: it.quantity, line_voucher_id: '', selections: {}, ...ovr, ...foc });
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
    setEditingPaid(['paid', 'partially_paid', 'completed_foc'].includes(String(detail.status)));
    setEditReason('');
    setCAffiliate((detail as any).affiliate_id ?? '');
    setAffTouched(false);
    setPayFix(Object.fromEntries(detailPayments.map(p2 => [p2.id, p2.payment_method_id])));
    setCCreatedBy((detail as any).created_by ?? '');
    setCreatedByBeforeEdit((detail as any).created_by ?? '');
    setPaymentsBeforeEdit(detailPayments);
    void loadAffiliateOptions();
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
    setSendErr(null); setSendNote(null);
    setRevisions([]);
    supabase.rpc('invoice_revision_history', { p_invoice_id: inv.id })
      .then(({ data }) => setRevisions((data as any[]) ?? []));
    setBillToSource('-');
    supabase.rpc('invoice_bill_to_source', { p_invoice_id: inv.id })
      .then(({ data }) => setBillToSource((data as string) || '-'));
    void loadInvoiceLegacy(inv.id, inv);
    void ensureCustomers([inv.customer_id]);
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
  const effectiveStore = isStaff
    ? (staffMustChooseStore ? cStore : (cStore || assignedStoreId || myStores[0]?.store_id || ''))
    : cStore;

  const filtered = useMemo(() => {
    const q = invSearch.trim().toLowerCase();
    return invoices.filter(i => {
      if (statusFilter !== 'all' && i.status !== statusFilter) return false;
      if (!q) return true;
      const when = i.created_at ? new Date(i.created_at) : null;
      // Several date renderings are searched, so "11/08", "2026-08-11",
      // "11 Aug" and a time such as "14:32" all find the same invoice.
      const haystack = [
        i.invoice_no,
        customerOf(i.customer_id)?.full_name,
        customerOf(i.customer_id)?.phone,
        stores.find(s2 => s2.id === i.store_id)?.name,
        when?.toLocaleDateString('en-GB'),
        when?.toLocaleDateString('en-CA'),
        when?.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }),
        when?.toLocaleTimeString('en-GB'),
        String(i.total_amount ?? ''),
        // So "Atome" or "cash" finds the invoices paid that way.
        ...(payMethodsByInvoice[i.id] ?? []),
      ].filter(Boolean).join(' ').toLowerCase();
      return haystack.includes(q);
    });
  }, [invoices, statusFilter, invSearch, customers, stores, payMethodsByInvoice]);

  // Shared by the printed document and the WhatsApp / email message.
  const lineName = (it: InvoiceItem) =>
    it.line_kind === 'voucher' ? `Voucher: ${vouchers.find(v => v.id === it.voucher_id)?.name ?? ''}`
    : it.line_kind === 'promotion' ? `Promotion: ${promotions.find(p => p.id === (it as any).promotion_id)?.name ?? ''}`
    : prodName(it.product_id ?? '');

  const [sendErr, setSendErr] = useState<string | null>(null);
  const [sendBusy, setSendBusy] = useState<'whatsapp' | 'email' | null>(null);

  // The customer copy as a real A5 PDF — same content as the printed customer
  // half. Built in src/lib/invoicePdf.ts.
  const buildPdfDoc = (): PdfDoc | null => {
    if (!detail) return null;
    const store: any = stores.find(s2 => s2.id === detail.store_id) ?? {};
    const cust = customerOf(detail.customer_id);
    const bal = Number(detail.total_amount ?? 0) - Number(detail.paid_amount ?? 0);
    return {
      kindLabel: 'Tax Invoice',
      docNo: detail.invoice_no,
      date: new Date(detail.created_at).toLocaleDateString('en-GB'),
      status: String(INVOICE_STATUS_LABELS[detail.status as InvoiceStatus] ?? detail.status).toUpperCase(),
      storeName: store.name ?? null,
      storeAddress: store.address ?? null,
      storePhone: [store.phone, store.whatsapp_phone ? `WhatsApp ${store.whatsapp_phone}` : '']
        .filter(Boolean).join(' · ') || null,
      customerName: `${cust?.full_name ?? '—'} (${billToSource || '-'})`,
      customerContact: [cust?.phone, cust?.email].filter(Boolean).join(' · ') || null,
      lines: detailItems.map(it => {
        const focQty = Number((it as any).foc_quantity ?? 0);
        const notes: string[] = [];
        if (focQty > 0) notes.push(`FOC ${focQty === it.quantity ? '(full line)' : `${focQty} of ${it.quantity} free`}`);
        if (it.price_overridden) notes.push('Manual price override');
        return {
          name: lineName(it), qty: it.quantity,
          unit: Number(it.unit_price ?? 0), total: Number(it.line_total ?? 0), notes,
        };
      }),
      totals: [
        ['Subtotal', `S$${Number(detail.subtotal ?? 0).toFixed(2)}`],
        ['Discount', `-S$${Number(detail.discount_total ?? 0).toFixed(2)}`],
        ...(Number(detail.paid_amount ?? 0) > 0
          ? [['Paid', `S$${Number(detail.paid_amount).toFixed(2)}`] as [string, string]] : []),
        ...(bal > 0 ? [['Balance', `S$${bal.toFixed(2)}`] as [string, string]] : []),
      ],
      grandTotal: ['Total', `S$${Number(detail.total_amount ?? 0).toFixed(2)}`],
      payments: detailPayments.map((pm: any) => [
        methods.find(m => m.id === pm.payment_method_id)?.name ?? 'Payment',
        `S$${Number(pm.amount ?? 0).toFixed(2)}`,
      ] as [string, string]),
      payDetails: [
        store.paynow_uen ? `CIMB UEN: ${store.paynow_uen}` : '',
        store.bank_account ? `CIMB corporate account: ${store.bank_account}` : '',
      ].filter(Boolean),
      staffName: (profiles.find(u => u.id === (detail as any).created_by)?.full_name) ?? profile?.full_name ?? '',
      policyText: store.policy_text ?? null,
      footerBits: [
        store.phone ? `DID: ${store.phone}` : '',
        store.email ? `Email: ${store.email}` : '',
        store.website ? `Website: ${store.website}` : '',
        store.co_reg_no ? `Co. Reg No.: ${store.co_reg_no}` : '',
      ].filter(Boolean),
    };
  };

  // Sends the invoice itself. On a phone the native share sheet opens with the
  // file already attached; on desktop the file downloads and the chat opens for
  // it to be attached, because desktop browsers cannot share files.
  const [sendNote, setSendNote] = useState<string | null>(null);
  const [revisions, setRevisions] = useState<any[]>([]);
  // Resolved server-side so the printed Bill To is right whether or not the
  // affiliate list happens to be loaded in the browser.
  const [billToSource, setBillToSource] = useState<string>('-');
  // WhatsApp gets a link to the PDF; email gets the PDF attached, sent by the
  // send-invoice-email Edge Function. See src/lib/sendDoc.ts.
  const sendPdf = async (channel: 'whatsapp' | 'email') => {
    const pdf = buildPdfDoc();
    if (!detail || !pdf) return;
    const cust = customerOf(detail.customer_id);
    setSendBusy(channel); setSendErr(null); setSendNote(null);
    const args = {
      pdf, kindLabel: 'Invoice', docNo: detail.invoice_no, docId: detail.id,
      docKind: 'invoice' as const, storeId: detail.store_id,
      customerId: detail.customer_id, customerName: cust?.full_name,
      phone: cust?.phone, email: cust?.email,
    };
    const r = channel === 'whatsapp'
      ? await sendViaWhatsAppLink(args)
      : await sendViaEmailAttachment(args);
    setSendBusy(null);
    if (!r.ok) { setSendErr(r.reason ?? 'Could not send.'); return; }
    if (channel === 'whatsapp') {
      setSendNote('WhatsApp has opened with a link to the invoice PDF.');
      return;
    }
    // Say which of the three routes was used, rather than implying the PDF was
    // attached when only a link went out.
    const outcome = (r as any).outcome as 'attached' | 'shared' | 'link' | undefined;
    setSendNote(
      outcome === 'attached' ? `The invoice PDF has been emailed to ${cust?.email}.`
      : outcome === 'shared' ? ((r as any).reason ?? 'Choose your email app — the PDF is attached.')
      : ((r as any).reason ?? 'Your mail client has opened with a link to the PDF.'));
  };
  const savePdf = () => { const d = buildPdfDoc(); if (d && detail) void saveDocumentFile(d, 'pdf', detail.invoice_no); };
  const saveImg = () => { const d = buildPdfDoc(); if (d && detail) void saveDocumentFile(d, 'image', detail.invoice_no); };

  const printInvoice = () => {
    if (!detail) return;
    const store = stores.find(s => s.id === detail.store_id);
    const cust = customerOf(detail.customer_id);
    // "First Last (Referrer, Source)" — a missing referrer or source prints
    // as a dash so the two slots stay readable.
    // Affiliate if the invoice has one, otherwise the customer's source,
    // otherwise a dash. Matches invoice_bill_to_source() in migration 103.
    const billTo = `${cust?.full_name ?? '—'} (${billToSource || '-'})`;
    // The staff signature is printed, not signed by hand. Use whoever raised the
    // invoice; fall back to the person printing it if that is not recorded.
    const signedByName =
      (profiles.find(u => u.id === (detail as any).created_by)?.full_name)
      ?? profile?.full_name ?? '';
    const esc = (s: any) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;');
    const subFor = (it: InvoiceItem) => {
      const fixed = detailPromoItems.filter(p => p.promotion_id === (it as any).promotion_id);
      const chosen = detailSelections.filter(s => s.invoice_item_id === it.id);
      // Therapy and credit packages were missing here, so a promotion containing
      // therapy printed "— × 1 (included)" with a blank name: the row appeared
      // but the therapy itself was invisible once the invoice was created. The
      // creation form resolves these correctly; this list did not.
      const nameOf = (x: any) => x.product_id ? (products.find(p => p.id === x.product_id)?.name ?? '')
        : x.voucher_id ? (vouchers.find(v => v.id === x.voucher_id)?.name ?? '')
        : x.child_promotion_id ? (promotions.find(p => p.id === x.child_promotion_id)?.name ?? '')
        : x.therapy_package_id ? (therapyPackages.find((t: any) => t.id === x.therapy_package_id)?.name ?? 'Therapy')
        : x.credit_package_id ? 'Credit package'
        : (x.treatment_name ?? '');
      return [
        ...fixed.map(f => `<tr class="sub"><td colspan="3">— ${esc(nameOf(f))} × ${f.quantity * it.quantity} (included)</td><td></td></tr>`),
        ...chosen.map(s => `<tr class="sub"><td colspan="3">— ${esc(nameOf(s))} × ${s.quantity} (chosen)</td><td></td></tr>`),
      ].join('');
    };
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

    // Payment details as text only. The QR codes were dropped so two copies fit
    // an A4 sheet, and they are printed at the foot rather than mid-document.
    const payDetailBits = [
      st.paynow_uen ? `CIMB UEN: ${esc(st.paynow_uen)}` : '',
      st.bank_account ? `CIMB corporate account: ${esc(st.bank_account)}` : '',
    ].filter(Boolean);
    const payRow = payDetailBits.length
      ? `<div class="paydetail">${payDetailBits.join(' &nbsp;·&nbsp; ')}</div>`
      : '';

    const footerBits = [
      storePhone ? `DID: ${esc(storePhone)}` : '',
      st.email ? `Email: ${esc(st.email)}` : '',
      st.website ? `Website: ${esc(st.website)}` : '',
      st.co_reg_no ? `Co. Reg No.: ${esc(st.co_reg_no)}` : '',
    ].filter(Boolean).join(' &nbsp;|&nbsp; ');

    // Therapy block for print (spec 4.12) — only when this invoice qualified one.
    //
    // TURNED OFF. The Unlimited Therapy qualification block is internal working:
    // eligible totals, qualification top-up, forfeited amounts, entitlement
    // numbers and beneficiary rows. It sits AFTER the totals and payment
    // methods, so hiding it changes no figure on the invoice — the customer's
    // copy still reconciles exactly as before.
    //
    // The markup is kept rather than deleted so it can be brought back by
    // setting this to true. The same block still shows on screen, so staff can
    // see the qualification without it going out to the customer.
    const PRINT_THERAPY_BLOCK = false;

    const th = detailTherapy;
    const therapyBlock = (PRINT_THERAPY_BLOCK && th && th.used) ? `
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
    const copyHtml = (copyLabel: string) => `
      <div class="copy">
        ${logosTop}
        <div class="head">
          <div><h1>Energia</h1><div class="mut">Wellness &amp; Retail</div>
            <div class="copytag">${copyLabel}</div></div>
          <div style="text-align:right"><h1>${esc(detail.invoice_no)}</h1>
            <div class="mut">${esc(store?.name ?? '')}</div>
            ${st.address ? `<div class="mut">${esc(st.address)}</div>` : ''}
            ${storePhone ? `<div class="mut">Tel: ${esc(storePhone)}</div>` : ''}
            ${st.whatsapp_phone ? `<div class="mut">Shop WhatsApp: ${esc(st.whatsapp_phone)}</div>` : ''}
            <div class="mut">Date: ${new Date(detail.created_at).toLocaleDateString()}</div>
            <div class="mut">Status: <b class="statusword">${esc(String(detail.status).replace(/_/g, ' ').toUpperCase())}</b></div></div>
        </div>
        ${focStamp}
        ${ex ? `<div class="mut"><b>EXCHANGE INVOICE</b> — replaces items from ${esc(ex.original_invoice_no ?? '')}</div>` : ''}
        <h2>Bill To</h2>
        <div>${esc(billTo)}</div><div class="mut">${esc(cust?.phone ?? '')}</div>
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
        <div class="signrow">
          <div class="sign">
            <div class="signline signed">${esc(signedByName)}</div>Staff Signature
          </div>
          <div class="sign"><div class="signline"></div>Customer Signature</div>
        </div>
        <div class="terms"><b>GOODS AND SERVICES SOLD ARE NEITHER REFUNDABLE NOR EXCHANGEABLE.
          GOODS AND SERVICES HAVE BEEN CHECKED AND COLLECTED.</b></div>
        ${st.policy_text ? `<div class="policy"><b>CANCELLATION / EXCHANGE / REFUND POLICY</b><br/>${esc(st.policy_text).replace(/\n/g, '<br/>')}</div>` : ''}
        ${payRow ? `<div class="payfoot"><strong>How to pay</strong> &nbsp; ${payRow}</div>` : ''}
        ${footerBits ? `<div class="footer">${footerBits}</div>` : ''}
      </div>`;

    const html = `<!doctype html><html><head><title>${esc(detail.invoice_no)}</title><style>
      /* Shared with the Special Products / Rentals receipts so the two cannot
         drift apart — see src/lib/printDoc.ts */
      ${PRINT_CSS}
    </style></head><body>
      <div class="sheet">
        ${copyHtml('CUSTOMER COPY')}
        <div class="cut"><span>✂  CUT HERE</span></div>
        ${copyHtml('OFFICE COPY')}
      </div>
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
          {isOwnerOrManager(profile?.role) && <button className="btn btn-secondary" onClick={() => { setSeLabel(saveEarthDefault.label); setSeAmount(saveEarthDefault.amount); setSeSettingsOpen(true); }} title="Save Earth defaults">🌱 Save Earth</button>}
          {/* canExport is already Owner/Manager only. */}
          {canExport && <XeroExportButton
            stores={stores.map(s2 => ({ id: s2.id, name: s2.name }))}
            defaultStoreId={activeStore ?? ''} />}
          {canExport && <PaymentSummaryExport
            stores={stores.map(s2 => ({ id: s2.id, name: s2.name }))}
            defaultStoreId={activeStore ?? ''} />}
          {canExport && <ExcelExportButton
            rows={filtered} filename="invoices" sheetName="Invoices"
            dateOf={(i: any) => i.created_at} dateLabel="Invoice date"
            columns={[
              { header: 'Invoice', value: (i: any) => i.invoice_no },
              { header: 'Date', value: (i: any) => new Date(i.created_at).toLocaleDateString('en-GB') },
              { header: 'Store', value: (i: any) => storeName(i.store_id) },
              { header: 'Customer', value: (i: any) => custName(i.customer_id) },
              { header: 'Total', value: (i: any) => Number(i.total_amount ?? 0) },
              { header: 'Paid', value: (i: any) => Number(i.paid_amount ?? 0) },
              // Kept in step with the table: the export mirrors these columns,
              // and a sheet missing a column the screen shows is confusing.
              { header: 'Payment', value: (i: any) => (payMethodsByInvoice[i.id] ?? []).join(', ') },
              { header: 'Status', value: (i: any) => INVOICE_STATUS_LABELS[i.status as InvoiceStatus] ?? i.status },
            ]} />}
          <button className="btn btn-secondary" onClick={openBuy}><Coins size={15} /> Buy Credit</button>
          <button className="btn btn-primary" onClick={() => { resetCreate(); setCreateOpen(true); }}><Plus size={16} /> New Invoice</button>
        </div>
      </div>

          <div style={{ marginBottom: 10 }}>
            <input value={invSearch} onChange={e => setInvSearch(e.target.value)}
              placeholder="Search invoice number, customer, store, payment method, date or time…"
              style={{ maxWidth: 460 }} />
            {invSearch && (
              <span style={{ marginLeft: 10, fontSize: 12.5, color: 'var(--text-muted)' }}>
                {filtered.length} match{filtered.length === 1 ? '' : 'es'}
                <button className="btn btn-secondary btn-sm" style={{ marginLeft: 8 }}
                  onClick={() => setInvSearch('')}>Clear</button>
              </span>
            )}
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
              <thead><tr><th>Invoice</th><th>Date</th><th>Store</th><th>Customer</th><th style={{ textAlign: 'right' }}>Total</th><th style={{ textAlign: 'right' }}>Paid</th><th>Payment</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {filtered.map(inv => (
                  <tr key={inv.id}>
                    <td><strong style={{ fontFamily: 'var(--font-display)' }}>{inv.invoice_no}</strong></td>
                    <td style={{ fontSize: 12.5, whiteSpace: 'nowrap' }}>{new Date(inv.created_at).toLocaleDateString()}</td>
                    <td style={{ fontSize: 12.5 }}>{storeName(inv.store_id)}</td>
                    <td style={{ fontSize: 13 }}>{custName(inv.customer_id)}</td>
                    <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(inv.total_amount)}</td>
                    <td style={{ textAlign: 'right', color: inv.paid_amount >= inv.total_amount ? 'var(--success)' : 'var(--text-muted)' }}>{money(inv.paid_amount)}</td>
                    <td style={{ fontSize: 12.5 }}>
                      {(payMethodsByInvoice[inv.id] ?? []).length > 0
                        ? (payMethodsByInvoice[inv.id] ?? []).join(', ')
                        : <span style={{ color: 'var(--text-muted)' }}>—</span>}
                    </td>
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
              disabled={buyBusy || !buyId || !buyCustomer || !buyStore}>{buyBusy ? 'Creating…' : 'Create Invoice'}</button></>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              Creates an invoice for a Credit Package or Premium Bundle. The credit, bonus credit and reward vouchers are issued automatically once the invoice is fully paid. Wallet credit cannot pay for it.
            </div>
            <div className="form-group" style={{ marginBottom: 0 }}>
              <label>Store *</label>
              <select value={buyStore} onChange={e => setBuyStore(e.target.value)}
                disabled={isStaff && myStores.length <= 1}>
                {(!isStaff || staffMustChooseStore) && <option value="">— Select store —</option>}
                {storeOptions.map(s2 => <option key={s2.id} value={s2.id}>{s2.name}</option>)}
              </select>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                Only packages and bundles available at this store are listed.
              </div>
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
                  label: `${x.name} — pays ${money(buyKind === 'credit_package' ? x.customer_price : x.customer_payment_amount)}${buyKind === 'premium_bundle' && x.grants_reward && (x.free_voucher_qty ?? 0) > 0 ? ` · ${x.free_voucher_qty} vouchers` : ''}`,
                  search: x.name }))} />
            </div>

            {buyKind === 'premium_bundle' && buyId && (() => {
              const b: any = buyBundles.find((x: any) => x.id === buyId);
              // Must match validate_bundle_voucher_selection(): a bundle that
              // grants no reward needs NO vouchers, whatever free_voucher_qty
              // says. Reading the quantity alone made the form ask for 150 on a
              // bundle the server wanted 0 for — so the sale could not be saved
              // however many were picked.
              const need = (b && b.grants_reward) ? (b.free_voucher_qty ?? 0) : 0;
              const chosen = Object.values(buyBasket).reduce((a, c) => a + (c || 0), 0);
              // Nothing to choose: showing an empty picker only invites someone
              // to select vouchers the sale will then refuse.
              if (need <= 0) {
                return (
                  <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                    This bundle grants no reward vouchers.
                  </div>
                );
              }
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
        <Modal title={editingPaid ? "Correct Paid Invoice" : editingInvoiceId ? "Edit Invoice" : "New Invoice"} wide onClose={() => { setCreateOpen(false); setEditingInvoiceId(null); setEditingPaid(false); }}
          footer={<><button className="btn btn-secondary" onClick={() => { setCreateOpen(false); setEditingInvoiceId(null); setEditingPaid(false); }}>Cancel</button><button className="btn btn-primary" onClick={handleCreate} disabled={cSaving}>{cSaving ? 'Saving…' : editingInvoiceId ? 'Save Changes' : 'Create Invoice'}</button></>}>
          <div className="form-grid">
            {editingPaid && (
              <div className="alert alert-warning" style={{ marginBottom: 0 }}>
                <span>⚠</span>
                <div>
                  <strong>This invoice has already been paid.</strong> Saving will return the stock
                  from the current lines and deduct it for the new ones, reverse the commission
                  earned and re-earn it on the corrected total, and keep a full copy of the invoice
                  as it stands now. The payment records themselves are never altered.
                  <div style={{ marginTop: 8 }}>
                    <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Reason for the correction *</div>
                    <input value={editReason} onChange={e => setEditReason(e.target.value)}
                      placeholder="e.g. Wrong quantity keyed at the till" />
                  </div>
                </div>
              </div>
            )}

            {editingPaid && (
              <div className="form-grid-2">
                {/* Referrer: add one that was missed, change it, or clear it. */}
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Referrer / affiliate</label>
                  <select value={cAffiliate}
                    onChange={e => { setCAffiliate(e.target.value); setAffTouched(true); }}>
                    <option value="">— None —</option>
                    {affiliateOptions.map(a => (
                      <option key={a.affiliate_id} value={a.affiliate_id}>
                        {a.full_name}{a.phone ? ` · ${a.phone}` : ''}
                      </option>
                    ))}
                  </select>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                    Changing this reverses the affiliate commission and re-earns it for whoever is
                    selected here.
                  </div>
                </div>

                {/* Who raised it. Owner only: this changes what the printed
                    document says about who served the customer. */}
                {isOwner(profile?.role) && (
                  <div className="form-group" style={{ marginBottom: 0 }}>
                    <label>Raised by</label>
                    <select value={cCreatedBy} onChange={e => setCCreatedBy(e.target.value)}>
                      <option value="">— Unchanged —</option>
                      {profiles
                        .filter(u => u.is_active !== false)
                        .map(u => (
                          <option key={u.id} value={u.id}>
                            {u.full_name}{u.role ? ` · ${u.role.replace(/_/g, ' ')}` : ''}
                          </option>
                        ))}
                    </select>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                      Changes the staff signature on the printed invoice. Commission is unaffected —
                      it follows the store's staff, not this field. The person must work at this store.
                    </div>
                  </div>
                )}

                {/* Payment method: how the money arrived, not how much. */}
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Payment method{detailPayments.length > 1 ? 's' : ''}</label>
                  {detailPayments.length === 0 ? (
                    <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>No payments recorded.</div>
                  ) : detailPayments.map(p2 => {
                    // A wallet payment consumed credit from the customer's
                    // wallet; the database refuses to reattribute it, so it is
                    // shown as fixed rather than offered and then rejected.
                    const isWallet = !!(methods.find(m => m.id === p2.payment_method_id) as any)?.is_wallet_credit;
                    return (
                      <div key={p2.id} style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 5 }}>
                        <span style={{ flex: '0 0 84px', fontSize: 12.5, fontWeight: 600,
                                       fontVariantNumeric: 'tabular-nums' }}>
                          {money(Number(p2.amount))}
                        </span>
                        {isWallet ? (
                          <span style={{ flex: 1, fontSize: 12.5, color: 'var(--text-muted)' }}>
                            {methods.find(m => m.id === p2.payment_method_id)?.name} — wallet credit, cannot be reattributed
                          </span>
                        ) : (
                          <select style={{ flex: 1 }} value={payFix[p2.id] ?? p2.payment_method_id}
                            onChange={e => setPayFix(m => ({ ...m, [p2.id]: e.target.value }))}>
                            {methods.filter(m => !(m as any).is_wallet_credit)
                              .map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
                          </select>
                        )}
                      </div>
                    );
                  })}
                  <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                    Only which method the money came through — the amounts cannot be changed here.
                  </div>
                </div>
              </div>
            )}
            {cErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{cErr}</div></div>}
            <div className="form-grid-2">
              <div className="form-group">
                <label>Store *</label>
                {/* Staff assigned to a single store see it fixed, as before.
                    Assigned to several, they choose among exactly those. */}
                {editingPaid && !isStaff ? (
                  <>
                    <select value={cStore} onChange={e => setCStore(e.target.value)}>
                      {storeOptions.map(s2 => <option key={s2.id} value={s2.id}>{s2.name}</option>)}
                    </select>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                      Moving the invoice returns its stock to the current store and takes it from
                      the new one.
                    </div>
                  </>
                ) : isStaff && myStores.length <= 1 ? (
                  <input value={myStores[0]?.store_name
                    ?? stores.find(s => s.id === (assignedStoreId ?? ''))?.name
                    ?? 'No store assigned'} disabled style={{ background: 'var(--surface-2)' }} />
                ) : (
                  <select value={activeStore} disabled={!!editingInvoiceId}
                    title={editingInvoiceId ? "The store cannot be changed on an existing invoice" : undefined}
                    onChange={e => { setCStore(e.target.value); setCLines([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]); }}>
                    {(!isStaff || staffMustChooseStore) && <option value="">— Select store —</option>}
                    {storeOptions.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>
                )}
                {isStaff && myStores.length > 1 && (
                  <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                    You are assigned to {myStores.length} stores, so none is chosen for you.
                    The invoice, its prices and its stock all belong to the one you select here.
                  </div>
                )}
              </div>
              <div className="form-group">
                <label>Customer *</label>
                <CustomerSearchSelect value={cCustomer} onChange={v => { setCCustomer(v); setCLines(ls => ls); }} />
              </div>
            </div>
            {cCustomer && (() => {
              const cust = customerOf(cCustomer);
              const referrer = cust?.referred_by ? customerOf(cust.referred_by) : null;
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
                        <select value={line.kind} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, kind: e.target.value as LineDraft['kind'], product_id: '', voucher_id: '', promotion_id: '', therapy_package_id: '',
                            special_product_id: '', rental_rate_type: 'day', rental_periods: 1,
                            rental_start_date: new Date().toISOString().slice(0, 10), rental_return_date: '' } : l))} style={{ width: 110 }}>
                          <option value="product">Product</option>
                          <option value="voucher">Voucher</option>
                          <option value="promotion">Promotion</option>
                          {therapyPackages.length > 0 && <option value="therapy">Therapy</option>}
                          {specialProducts.length > 0 && <option value="special_product">Special Product</option>}
                          {specialProducts.length > 0 && <option value="rental">Rental</option>}
                        </select>
                        {(line.kind === 'special_product' || line.kind === 'rental') ? (
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <SearchSelect value={line.special_product_id ?? ''}
                              onChange={v => setCLines(ls => ls.map((l, j) => j === i ? { ...l, special_product_id: v } : l))}
                              placeholder="Search special product…"
                              options={specialProducts
                                .filter((sp: any) => line.kind === 'special_product'
                                  ? Number(sp.sale_price) > 0
                                  : (Number(sp.rate_day) > 0 || Number(sp.rate_week) > 0
                                     || Number(sp.rate_month) > 0 || Number(sp.rate_year) > 0))
                                .map((sp: any) => ({
                                  value: sp.id,
                                  label: line.kind === 'special_product'
                                    ? `${sp.name} — ${money(Number(sp.sale_price))}`
                                    : sp.name,
                                  sublabel: sp.sku, search: `${sp.name} ${sp.sku ?? ''}`,
                                }))} />
                            {line.kind === 'rental' && line.special_product_id && (
                              <div style={{ display: 'flex', gap: 6, marginTop: 6, flexWrap: 'wrap', alignItems: 'flex-end' }}>
                                <div style={{ flex: '0 0 100px' }}>
                                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Rate</div>
                                  <select value={line.rental_rate_type ?? 'day'}
                                    onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, rental_rate_type: e.target.value as any } : l))}>
                                    {(() => {
                                      const sp = specialProducts.find((x: any) => x.id === line.special_product_id);
                                      const avail = (['day','week','month','year'] as const)
                                        .filter(rt => Number(sp?.[`rate_${rt}`] ?? 0) > 0);
                                      return avail.length > 0
                                        ? avail.map(rt => <option key={rt} value={rt}>Per {rt}</option>)
                                        : <option value="">No rental rate set</option>;
                                    })()}
                                  </select>
                                </div>
                                <div style={{ flex: '0 0 80px' }}>
                                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Periods</div>
                                  <input type="number" min={1} value={line.rental_periods ?? 1}
                                    onChange={e => setCLines(ls => ls.map((l, j) => j === i
                                      ? { ...l, rental_periods: Math.min(Math.max(1, Math.floor(+e.target.value || 1)), 3650) } : l))} />
                                </div>
                                <div style={{ flex: '0 0 140px' }}>
                                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>From</div>
                                  <input type="date" value={line.rental_start_date ?? ''}
                                    onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, rental_start_date: e.target.value } : l))} />
                                </div>
                                <div style={{ flex: '0 0 140px' }}>
                                  <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Due back</div>
                                  <input type="date" value={line.rental_return_date ?? ''} min={line.rental_start_date}
                                    onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, rental_return_date: e.target.value } : l))} />
                                </div>
                              </div>
                            )}
                          </div>
                        ) : line.kind === 'product' ? (
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
                        <input type="number" min={1} max={9999} value={line.quantity || ''} placeholder="Qty" style={{ width: 70 }}
                          onChange={e => setCLines(ls => ls.map((l, j) => j === i
                            ? { ...l, quantity: Math.min(Math.max(0, Math.floor(+e.target.value || 0)), 9999) } : l))} />
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
                            {Array.from({ length: Math.min(Math.max(0, Math.floor(line.quantity || 0)), 100) }, (_, k) => k + 1).map(q => (
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
                          3rd-party product — discount vouchers don't apply. A manual
                          discount still does.
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
                        // The quantity can now be TYPED, not only stepped, since a group
                        // may call for 60 or more. The cap lives here rather than on the
                        // "+" button alone, so a typed figure cannot exceed what the
                        // group needs — the invoice would be rejected otherwise.
                        const setQty = (itemId: string, q: number) => setCLines(ls => ls.map((l, j) => {
                          if (j !== i) return l;
                          const current = l.selections[g.id] ?? {};
                          const wanted = Math.max(0, Math.floor(Number.isFinite(q) ? q : 0));
                          const others = Object.entries(current)
                            .filter(([k]) => k !== itemId)
                            .reduce((a, [, v]) => a + (Number(v) || 0), 0);
                          const room = Math.max(0, (g.choose_qty * l.quantity) - others);
                          return { ...l, selections: { ...l.selections,
                            [g.id]: { ...current, [itemId]: Math.min(wanted, room) } } };
                        }));
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
                                      <input type="number" min={0} max={need} value={val === 0 ? '' : val}
                                        placeholder="0"
                                        onChange={e => setQty(id, e.target.value === '' ? 0 : +e.target.value)}
                                        onFocus={e => e.currentTarget.select()}
                                        style={{ width: 54, textAlign: 'center', fontSize: 13, fontWeight: 600,
                                                 padding: '2px 4px', height: 26 }} />
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
              <div className="form-group"><label>Manual Discount (S$)</label>
                <input type="number" min={0} step={0.01} value={cDiscount || ''} onChange={e => setCDiscount(+e.target.value)} placeholder="0.00" />
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
                  Applies to everything on the invoice — products, third-party items, vouchers,
                  promotions and therapy — capped at the subtotal.
                </div>
              </div>
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
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
                  {isOwnerOrManager(profile?.role) && (
                    <button className="btn btn-secondary" onClick={openEdit}
                      title="Correct this paid invoice — stock and commission are adjusted and a revision is kept">
                      <FileText size={14} /> Correct Invoice</button>
                  )}
                  <button className="btn btn-danger" onClick={() => { setActionType('invoice_refund'); setActionReturnStock(true); setActionReason(''); setActionErr(null); }}>{isOwnerOrManager(profile?.role) ? 'Refund/Cancel' : 'Request Refund'}</button></>
              : detail.status === 'cancelled' || detail.status === 'refunded' || detail.status === 'cancellation_requested' || detail.status === 'refund_requested'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button></>
              : (detail.status === 'unpaid' || detail.status === 'draft') && Number(detail.paid_amount) === 0
                  && !(detail as any).is_topup && !(detail as any).is_exchange && detailPayments.length === 0
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button>
                  <button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
                  <button className="btn btn-secondary" onClick={openEdit}><FileText size={14} /> Edit Invoice</button>
                  {detail.is_full_foc && Number(detail.total_amount) <= 0
                    ? <button className="btn btn-primary" onClick={handleConfirmFoc} disabled={focBusy}><Sparkles size={15} /> {focBusy ? 'Confirming…' : 'Confirm FOC Invoice'}</button>
                    : <button className="btn btn-primary" onClick={handlePay} disabled={payBusy}><CreditCard size={15} /> {payBusy ? 'Processing…' : 'Record Payment'}</button>}</>
              : detail.status === 'completed_foc'
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button></>
              : <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button>
                <button className="btn btn-secondary" onClick={savePdf} title="Download the customer copy as a PDF"><Download size={14} /> PDF</button>
                <button className="btn btn-secondary" onClick={saveImg} title="Download the customer copy as an image"><Download size={14} /> Image</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('whatsapp')}
                  disabled={!whatsappNumber(customerOf(detail.customer_id)?.phone)}
                  title={whatsappNumber(customerOf(detail.customer_id)?.phone)
                    ? 'Open WhatsApp with this invoice ready to send'
                    : 'This customer has no usable mobile number'}>
                  <MessageCircle size={14} /> {sendBusy === 'whatsapp' ? 'Preparing…' : 'WhatsApp'}</button>
                <button className="btn btn-secondary" onClick={() => sendPdf('email')}
                  disabled={!emailAddress(customerOf(detail.customer_id)?.email)}
                  title={emailAddress(customerOf(detail.customer_id)?.email)
                    ? 'Open your mail client with this invoice ready to send'
                    : 'This customer has no valid email address'}>
                  <Mail size={14} /> {sendBusy === 'email' ? 'Sending…' : 'Email'}</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button>
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
                  <SearchSelect style={{ maxWidth: 300, flex: 1 }}
                    placeholder="Search affiliate name, phone or email…"
                    value={(detail as any).affiliate_id ?? (effAffiliate?.affiliate_id ?? '')}
                    disabled={affiliateBusy}
                    onChange={v => changeInvoiceAffiliate(v === '' ? null : v)}
                    options={affiliateOptions.map((a: any) => ({
                      value: a.affiliate_id,
                      label: a.full_name,
                      sublabel: [a.phone, a.email].filter(Boolean).join(' · ') || undefined,
                      search: `${a.full_name} ${a.phone ?? ''} ${a.email ?? ''}`,
                    }))} />
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

            {revisions.length > 0 && (
              <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
                <div style={{ fontSize: 12, fontWeight: 700, marginBottom: 6 }}>
                  Corrections ({revisions.length})
                </div>
                {revisions.map(r => (
                  <div key={r.revision_no} style={{ fontSize: 12, marginBottom: 4 }}>
                    <strong>#{r.revision_no}</strong>{' '}
                    {new Date(r.edited_at).toLocaleString()} — {r.edited_by_name ?? 'Unknown'}
                    <div style={{ color: 'var(--text-muted)' }}>
                      Was S${Number(r.old_total ?? 0).toFixed(2)} ({String(r.from_status ?? '').replace(/_/g,' ')})
                      {r.edit_reason ? ` · ${r.edit_reason}` : ''}
                    </div>
                  </div>
                ))}
              </div>
            )}
            {sendErr && <div className="alert alert-danger"><span>⚠</span><div>{sendErr}</div></div>}
            {sendNote && <div className="alert alert-info"><span>ℹ</span><div>{sendNote}</div></div>}

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
                    // Therapy and credit packages fell through to "—", so a
                    // promotion containing therapy showed a row with no name
                    // once the invoice existed, even though the creation form
                    // named it correctly. Checked by id as well as item_type,
                    // since a chosen option carries the id without the type.
                    const subLabel = (x: any): string => {
                      if (x.item_type === 'product' || x.product_id) return `📦 ${prodName(x.product_id ?? '')}`;
                      if (x.item_type === 'voucher' || x.voucher_id) return `🎟 ${vouchers.find(v => v.id === x.voucher_id)?.name ?? 'Voucher'}`;
                      if (x.item_type === 'promotion') return `🧩 ${promotions.find(p => p.id === x.child_promotion_id)?.name ?? 'Promotion'}`;
                      if (x.item_type === 'therapy' || x.therapy_package_id)
                        return `🧖 ${therapyPackages.find((t: any) => t.id === x.therapy_package_id)?.name ?? 'Therapy'}`;
                      if (x.item_type === 'credit_package' || x.credit_package_id) return '💳 Credit package';
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
                    {/* DERIVED, not taken from the RPC.
                        forfeited_total is a SUM of a per-entitlement column,
                        but forfeiture belongs to the qualification as a whole —
                        so a group of 8 entitlements reported 8 x S$742 =
                        S$5,936 against an eligible total of S$7,094, which is
                        more than was ever eligible. Eligible less applied is the
                        definition and cannot be multiplied by a row count. */}
                    {(() => {
                      const derived = Math.max(
                        Math.round((Number(detailTherapy.eligible_total ?? 0)
                          - Number(detailTherapy.qualified_total ?? 0)) * 100) / 100, 0);
                      if (derived <= 0) return null;
                      return (
                        <span style={{ color: 'var(--danger)' }}>
                          Forfeited balance: <strong>{money(derived)}</strong>
                        </span>
                      );
                    })()}
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
                {Array.from({ length: Math.min(Math.max(0, Math.floor(focLine.quantity || 0)), 100) }, (_, k) => k + 1).map(q => (
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
