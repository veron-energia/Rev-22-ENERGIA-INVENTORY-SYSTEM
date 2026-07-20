import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import MembershipBadge from '../components/MembershipBadge';
import { MembershipStatusPanel, MembershipSelector, MemberIdField, FullMembershipStatus } from '../components/MembershipInvoice';
import { LineOverrideModal, PaymentPriceReview, PriceReviewResult } from '../components/PricingControls';
import { useAuth } from '../context/AuthContext';
import TherapyQualifyModal, { TOPUP_GAP, sgTodayStr } from '../components/TherapyQualifyModal';
import {
  Invoice, InvoiceItem, InvoicePayment, Store, Product, Customer,
  PaymentMethod, StoreProductPrice, InvoiceStatus, INVOICE_STATUS_LABELS, Voucher, Promotion, PromotionChoiceGroup, PromotionChoiceOption, isOwnerOrManager, Profile, SERVICE_STAFF_ROLES, TherapyPackageRule } from '../types';
import { Modal } from '../components/ui';
import { exportCsv } from '../lib/csv';
import {
  Plus, RefreshCw, FileText, Trash2, X, CreditCard, Eye, Search, CheckCircle2, Download, Printer, Sparkles,
} from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;

const StatusBadge: React.FC<{ s: InvoiceStatus }> = ({ s }) => {
  const cls = s === 'paid' ? 'badge-success' : s === 'partially_paid' ? 'badge-primary'
    : s === 'unpaid' || s === 'draft' ? 'badge-accent'
    : s === 'cancelled' || s === 'refunded' ? 'badge-muted' : 'badge-danger';
  return <span className={`badge ${cls}`}>{INVOICE_STATUS_LABELS[s]}</span>;
};

interface LineDraft { kind: 'product' | 'voucher' | 'promotion'; product_id: string; voucher_id: string; promotion_id: string; quantity: number; line_voucher_id: string; selections: Record<string, Record<string, number>>; price_mode_override?: '' | 'member' | 'non_member'; override_reason?: string; }

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
  const [therapyRules, setTherapyRules] = useState<TherapyPackageRule[]>([]);
  const [qualifyFor, setQualifyFor] = useState<{ storeId: string; customerId: string } | null>(null);
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
  const [detailTherapy, setDetailTherapy] = useState<any>(null);
  const [detailServiceStaff, setDetailServiceStaff] = useState<string[]>([]);
  const [detailMembership, setDetailMembership] = useState<any>(null);   // customer_memberships row (paid invoices)
  const [detailResv, setDetailResv] = useState<string | null>(null);      // reserved Member ID for this invoice
  const [detailOwnedId, setDetailOwnedId] = useState<string | null>(null);// customer's permanent Member ID
  const [midInput, setMidInput] = useState('');
  const [midErr, setMidErr] = useState<string | null>(null);
  const [midBusy, setMidBusy] = useState(false);
  const [payLines, setPayLines] = useState<{ payment_method_id: string; amount: number }[]>([]);
  const [payErr, setPayErr] = useState<string | null>(null);
  const [payBusy, setPayBusy] = useState(false);
  // Phase 4: membership-aware pricing
  const [memberStatus, setMemberStatus] = useState<FullMembershipStatus | null>(null);
  const [cMembership, setCMembership] = useState<{ plan_id: string; member_id: string; fee: number; plan_name: string; owned_id?: string | null } | null>(null);
  const [priceReview, setPriceReview] = useState<PriceReviewResult | null>(null);
  const [overrideItem, setOverrideItem] = useState<InvoiceItem | null>(null);
  const [voucherStorePrices, setVoucherStorePrices] = useState<any[]>([]);
  const [promoStorePrices, setPromoStorePrices] = useState<any[]>([]);

  const loadAll = useCallback(async () => {
    setLoading(true);
    const [inv, st, pr, cu, pm, pp, vc, pm2, cg, co, si, prof, myStore, trules, vsp, psp] = await Promise.all([
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
      supabase.from('therapy_package_rules').select('*').is('deleted_at', null).eq('is_active', true),
      supabase.from('voucher_store_prices').select('*').is('deleted_at', null),
      supabase.from('promotion_store_prices').select('*').is('deleted_at', null),
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
    setTherapyRules((trules.data as TherapyPackageRule[]) ?? []);
    setVoucherStorePrices((vsp.data as any[]) ?? []);
    setPromoStorePrices((psp.data as any[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { loadAll(); }, [loadAll]);

  const storeName = (id: string) => stores.find(s => s.id === id)?.name ?? '—';
  const custName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';
  const prodName = (id: string) => products.find(p => p.id === id)?.name ?? '—';
  const methodName = (id: string) => methods.find(m => m.id === id)?.name ?? '—';
  const isStaff = profile?.role === 'staff';
  const activeStore = isStaff ? (assignedStoreId ?? '') : cStore;
  const effMember = (memberStatus?.is_member ?? false) || !!cMembership;
  // Strict mode-aware pricing (Phase 4): NO fallback to legacy selling_price.
  const priceRowFor = (storeId: string, productId: string) =>
    prices.find(p => p.store_id === storeId && p.product_id === productId);
  const priceFor = (storeId: string, productId: string, member: boolean = effMember) => {
    const r = priceRowFor(storeId, productId);
    if (!r) return null;
    return member ? (r.member_price ?? null) : (r.non_member_price ?? null);
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
    const autoM = effMember;
    const autoPrice = autoM ? r.member_price : r.non_member_price;
    const elig = r.eligibility ?? 'both';
    const autoEligible = elig === 'both' || (elig === 'member_only' && autoM) || (elig === 'non_member_only' && !autoM);
    if (autoEligible && autoPrice != null) return { ok: true, label: `${money(autoPrice)}`, needsOverride: false };
    // Not available automatically — is it available by override in the other mode?
    const other = autoM ? r.non_member_price : r.member_price;
    if (other != null) return { ok: true, label: `override → ${money(other)}`, needsOverride: true };
    if (autoPrice != null) return { ok: true, label: `override → ${money(autoPrice)}`, needsOverride: true };
    return { ok: false, label: 'missing price', needsOverride: false };
  };
  const storeProducts = useMemo(() =>
    activeStore ? products.filter(p => productAvail(p.id).ok && stockQty(activeStore, p.id) > 0) : [],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [activeStore, products, prices, storeInv, effMember, memberStatus, cMembership]);

  const voucherPrice = (id: string, member: boolean = effMember) => {
    const r = voucherStorePrices.find(x => x.voucher_id === id && x.store_id === activeStore && x.available_at_store !== false);
    if (!r) return null;
    return member ? (r.member_price ?? null) : (r.non_member_price ?? null);
  };

  const promoPrice = (id: string, member: boolean = effMember) => {
    const r = promoStorePrices.find(x => x.promotion_id === id && x.store_id === activeStore && x.available_at_store !== false);
    if (!r) return null;
    return member ? (r.member_price ?? null) : (r.non_member_price ?? null);
  };

  const lineMember = (l: LineDraft): boolean =>
    l.price_mode_override ? l.price_mode_override === 'member' : effMember;
  const lineUnit = (l: LineDraft): number | null =>
    l.kind === 'voucher' ? (l.voucher_id ? voucherPrice(l.voucher_id, lineMember(l)) : null)
    : l.kind === 'promotion' ? (l.promotion_id ? promoPrice(l.promotion_id, lineMember(l)) : null)
    : (activeStore && l.product_id ? priceFor(activeStore, l.product_id, lineMember(l)) : null);

  const membershipFee = cMembership?.fee ?? 0;
  const createSubtotal = useMemo(() =>
    cLines.reduce((sum, l) => {
      const price = lineUnit(l);
      return sum + (price ? price * l.quantity : 0);
    }, 0) + membershipFee,
    // B: every input that can change a line's applied price must be here,
    // or totals go stale when the pricing mode flips.
    [cLines, activeStore, prices, vouchers, promotions, voucherStorePrices, promoStorePrices, effMember, memberStatus, cMembership]);

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
      return s + (u ? u * l.quantity : 0);
    }, 0), [cLines, activeStore, prices, products, effMember, memberStatus, cMembership]);

  // Total top-up across all promotion lines (mirrors promotion_selections_topup).
  const topupPreview = useMemo(() => {
    if (!activeStore) return 0;
    let sum = 0;
    for (const l of cLines) {
      if (l.kind !== 'promotion' || !l.promotion_id) continue;
      const lm = l.price_mode_override ? l.price_mode_override === 'member' : effMember;
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
  }, [cLines, activeStore, prices, choiceGroups, choiceOptions, effMember, memberStatus, cMembership]);

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
    }, 0), [cLines, vouchers, activeStore, prices, voucherStorePrices, promoStorePrices, effMember, memberStatus, cMembership]);

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
    setCMembership(null); setMemberStatus(null);
  };

  const clearOverridesOnContextChange = (cls: LineDraft[]): LineDraft[] => {
    const hadOverrides = cls.some(l => l.price_mode_override);
    if (hadOverrides) {
      // M: an override reason entered for one customer/store must not silently
      // carry to another. Warn, then clear the manual modes back to Auto.
      setCErr('Customer or store changed — manual Member/Non-Member overrides were cleared. Re-apply if still needed.');
    }
    return cls.map(l => ({ ...l, price_mode_override: '', override_reason: '' }));
  };

  const handleCreate = async () => {
    if (isStaff && !assignedStoreId) { setCErr('You are not assigned to a store, so you cannot create invoices. Ask an Owner or Manager to assign you.'); return; }
    const effectiveStore = isStaff ? (assignedStoreId ?? '') : cStore;
    if (!effectiveStore) { setCErr('Select a store.'); return; }
    if (!cCustomer) { setCErr('Select a customer.'); return; }
    const activeLines = cLines.filter(l => l.quantity > 0 && (l.kind === 'product' ? l.product_id : l.kind === 'voucher' ? l.voucher_id : l.promotion_id));
    if (activeLines.length === 0 && !cMembership) { setCErr('Add at least one product, voucher, promotion or membership.'); return; }
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
    const ovr = (l: LineDraft) => l.price_mode_override
      ? { price_mode_override: l.price_mode_override, override_reason: l.override_reason || null }
      : {};
    const validLines = activeLines.map(l => l.kind === 'voucher'
      ? { kind: 'voucher', voucher_id: l.voucher_id, quantity: l.quantity, ...ovr(l) }
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
          ...ovr(l),
        }
      : { kind: 'product', product_id: l.product_id, quantity: l.quantity, line_voucher_id: (l.line_voucher_id && !isThirdParty(l.product_id)) ? l.line_voucher_id : null, ...ovr(l) });
    const allItems: any[] = [...validLines];
    if (cMembership) allItems.push({ kind: 'membership', plan_id: cMembership.plan_id, member_id: (cMembership.owned_id || cMembership.member_id) || null, quantity: 1 });
    setCSaving(true); setCErr(null);
    const { data: newInvId, error } = await supabase.rpc('create_invoice', {
      p_store_id: effectiveStore, p_customer_id: cCustomer, p_affiliate_id: null,
      p_items: allItems, p_discount_total: cDiscount || 0, p_notes: null,
      p_discount_voucher_id: cDiscountVoucher || null,
      p_service_staff: cServiceStaff,
    });
    setCSaving(false);
    if (error) { setCErr(error.message); return; }
    // E: record a create-time override audit + correct original_price per line.
    if (newInvId && allItems.some((it: any) => it.price_mode_override)) {
      const { data: createdItems } = await supabase.from('invoice_items')
        .select('id').eq('invoice_id', newInvId).eq('price_overridden', true);
      for (const it of (createdItems as any[]) ?? []) {
        await supabase.rpc('audit_create_time_override', { p_item_id: it.id });
      }
    }
    setCreateOpen(false); resetCreate(); loadAll();
  };

  const openDetail = async (inv: Invoice) => {
    setDetail(inv);
    setDetailTherapy(null);
    const [items, pays, svc, ther, memb, resv, owned] = await Promise.all([
      supabase.from('invoice_items').select('*').eq('invoice_id', inv.id),
      supabase.from('invoice_payments').select('*').eq('invoice_id', inv.id),
      supabase.from('invoice_service_staff').select('staff_id').eq('invoice_id', inv.id),
      supabase.rpc('invoice_therapy_summary', { p_invoice_id: inv.id }),
      supabase.from('customer_memberships').select('*').eq('invoice_id', inv.id).is('deleted_at', null).maybeSingle(),
      supabase.from('member_id_reservations').select('member_id').eq('invoice_id', inv.id).maybeSingle(),
      supabase.from('member_ids').select('member_id').eq('customer_id', inv.customer_id).maybeSingle(),
    ]);
    setDetailMembership(memb.data ?? null);
    setDetailResv((resv.data as any)?.member_id ?? null);
    setDetailOwnedId((owned.data as any)?.member_id ?? null);
    setMidInput(''); setMidErr(null);
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
    const paidStore = detail.store_id, paidCustomer = detail.customer_id;
    const { data, error } = await supabase.rpc('pay_invoice', { p_invoice_id: detail.id, p_payments: valid });
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
    // Auto-prompt therapy qualification if the customer's same-day eligible
    // total reaches (or is within TOPUP_GAP of) the smallest package.
    await maybePromptTherapy(paidStore, paidCustomer);
  };

  const maybePromptTherapy = async (storeId: string, customerId: string) => {
    if (therapyRules.length === 0) return;
    const smallest = Math.min(...therapyRules.map(r => Number(r.qualifying_amount)));
    const { data } = await supabase.rpc('therapy_eligible_invoices', { p_customer_id: customerId, p_store_id: storeId, p_sg_date: sgTodayStr() });
    const total = ((data as any[]) ?? []).reduce((s, r) => s + Number(r.total_amount), 0);
    if (total >= smallest - TOPUP_GAP) {
      setQualifyFor({ storeId, customerId });
    }
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
      it.line_kind === 'membership' ? `Membership: ${it.plan_name_snapshot ?? ''}`
      : it.line_kind === 'voucher' ? `Voucher: ${vouchers.find(v => v.id === it.voucher_id)?.name ?? ''}`
      : it.line_kind === 'promotion' ? `Promotion: ${promotions.find(p => p.id === (it as any).promotion_id)?.name ?? ''}`
      : prodName(it.product_id ?? '');
    const itemRows = detailItems.map(it => {
      const lv = (it as any).line_voucher_id
        ? `<div class="mut">Voucher ${esc(vouchers.find(v => v.id === (it as any).line_voucher_id)?.name ?? '')} −S$${Number((it as any).line_discount ?? 0).toFixed(2)}</div>` : '';
      const tu = Number((it as any).topup_amount ?? 0) > 0 ? `<div class="mut">incl. top-up S$${Number((it as any).topup_amount).toFixed(2)}</div>` : '';
      const modeBits: string[] = [];
      if (it.price_mode) modeBits.push(it.price_mode === 'member' ? 'Member price' : 'Non-Member price');
      if (it.member_price_snapshot != null) modeBits.push(`M S$${Number(it.member_price_snapshot).toFixed(2)}`);
      if (it.non_member_price_snapshot != null) modeBits.push(`NM S$${Number(it.non_member_price_snapshot).toFixed(2)}`);
      const md = modeBits.length ? `<div class="mut">${esc(modeBits.join(' · '))}</div>` : '';
      const ov = it.price_overridden ? `<div class="mut"><b>Manual Override</b>${it.override_reason ? ` — ${esc(it.override_reason)}` : ''}</div>` : '';
      const mem = it.line_kind === 'membership'
        ? `<div class="mut">${it.plan_months_snapshot ?? ''} months · Member ID ${esc(it.member_id_snapshot ?? '—')}</div>` : '';
      return `<tr><td>${esc(lineName(it))}${md}${ov}${mem}${lv}${tu}</td><td class="r">${it.quantity}</td><td class="r">S$${Number(it.unit_price).toFixed(2)}</td><td class="r"><b>S$${Number(it.line_total).toFixed(2)}</b></td></tr>` +
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
        <h2>Bill To</h2>
        <div>${esc(cust?.full_name ?? '—')}</div><div class="mut">${esc(cust?.phone ?? '')}</div>
        <h2>Items</h2>
        <table><thead><tr><th>Item</th><th class="r">Qty</th><th class="r">Unit</th><th class="r">Total</th></tr></thead><tbody>${itemRows}</tbody></table>
        <table class="totals">
          <tr><td>Subtotal</td><td class="r">S$${Number(detail.subtotal).toFixed(2)}</td></tr>
          <tr><td>Discount</td><td class="r">−S$${Number(detail.discount_total).toFixed(2)}</td></tr>
          ${gstEnabled && gstRate > 0 ? `<tr><td>GST (${gstRate}%, incl.)</td><td class="r">S$${gstAmount.toFixed(2)}</td></tr>` : ''}
          <tr class="grand"><td>Total</td><td class="r">S$${Number(detail.total_amount).toFixed(2)}</td></tr>
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
                  <select value={cStore} onChange={e => { setCStore(e.target.value); setCMembership(null); setCLines([{ kind: 'product', product_id: '', voucher_id: '', promotion_id: '', quantity: 1, line_voucher_id: '', selections: {} }]); }}>
                    <option value="">— Select store —</option>
                    {stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                  </select>
                )}
              </div>
              <div className="form-group">
                <label>Customer *</label>
                <select value={cCustomer} onChange={e => { setCCustomer(e.target.value); setCMembership(null); setMemberStatus(null); setCLines(ls => clearOverridesOnContextChange(ls)); }}>
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

            {cCustomer && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                <MembershipStatusPanel customerId={cCustomer} onStatus={setMemberStatus} />
                {activeStore && (
                  <MembershipSelector storeId={activeStore} memberStatus={memberStatus} customerId={cCustomer}
                    value={cMembership} onChange={setCMembership} />
                )}
                {cMembership && !memberStatus?.is_member && !cMembership.owned_id && (
                  <MemberIdField value={cMembership.member_id} isRenewal={false}
                    onChange={v => setCMembership(m => m ? { ...m, member_id: v } : m)} />
                )}
              </div>
            )}

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
                            {storeProducts.map(p => { const a = productAvail(p.id); return <option key={p.id} value={p.id}>{p.name} — {a.label}{a.needsOverride ? ' *' : ''}</option>; })}
                          </select>
                        ) : line.kind === 'voucher' ? (
                          <select value={line.voucher_id} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, voucher_id: e.target.value } : l))} style={{ flex: 1 }}>
                            <option value="">— Voucher —</option>
                            {sellableVouchers.map(v => <option key={v.id} value={v.id}>{v.name}{voucherPrice(v.id) != null ? ` — ${money(voucherPrice(v.id)!)}` : ' — no price for this store'}</option>)}
                          </select>
                        ) : (
                          <select value={line.promotion_id} onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, promotion_id: e.target.value } : l))} style={{ flex: 1 }}>
                            <option value="">— Promotion —</option>
                            {promotions.map(p => <option key={p.id} value={p.id}>{p.name}{promoPrice(p.id) != null ? ` — ${money(promoPrice(p.id)!)}` : ' — no price for this store'}</option>)}
                          </select>
                        )}
                        <input type="number" min={1} value={line.quantity || ''} placeholder="Qty" style={{ width: 70 }}
                          onChange={e => setCLines(ls => ls.map((l, j) => j === i ? { ...l, quantity: +e.target.value } : l))} />
                        <select title="Pricing mode — Auto follows membership; M*/NM* are manual overrides (reason required, may bypass eligibility)"
                          value={line.price_mode_override || 'auto'} style={{ width: 78 }}
                          onChange={e => {
                            const v = e.target.value;
                            if (v === 'auto') { setCLines(ls => ls.map((l, j) => j === i ? { ...l, price_mode_override: '', override_reason: '' } : l)); return; }
                            const reason = prompt('Override reason (required) — this may bypass Member/Non-Member eligibility:');
                            if (!reason?.trim()) { e.target.value = line.price_mode_override || 'auto'; return; }
                            setCLines(ls => ls.map((l, j) => j === i ? { ...l, price_mode_override: v as any, override_reason: reason.trim() } : l));
                          }}>
                          <option value="auto">{effMember ? 'Auto (M)' : 'Auto (NM)'}</option>
                          <option value="member">M *</option>
                          <option value="non_member">NM *</option>
                        </select>
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
                        const baseline = isProd ? groupBaseline(g.id, line.price_mode_override ? line.price_mode_override === 'member' : effMember) : null;
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
                                      const lm = line.price_mode_override ? line.price_mode_override === 'member' : effMember;
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
              <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
                {cMembership && <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--text-muted)' }}>incl. membership — {cMembership.plan_name} {money(membershipFee)}</div>}
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
              ? <><button className="btn btn-secondary" onClick={printInvoice}><Printer size={14} /> Print</button><button className="btn btn-secondary" onClick={() => setQualifyFor({ storeId: detail.store_id, customerId: detail.customer_id })}><Sparkles size={14} /> Qualify for Therapy</button><button className="btn btn-secondary" onClick={() => setDetail(null)}>Close</button><button className="btn btn-danger" onClick={() => { setActionType('invoice_refund'); setActionReturnStock(true); setActionReason(''); setActionErr(null); }}>Request Refund</button></>
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
                <div style={{ marginTop: 6 }}><MembershipBadge customerId={detail.customer_id} compact /></div>
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
                          <td>{it.line_kind === 'membership' ? `💳 ${it.plan_name_snapshot ?? 'Membership'}` : it.line_kind === 'voucher' ? `🎟 ${vouchers.find(v => v.id === it.voucher_id)?.name ?? 'Voucher'}` : isPromo ? `🧩 ${promotions.find(p => p.id === (it as any).promotion_id)?.name ?? 'Promotion'}` : prodName(it.product_id ?? '')}
                            {it.line_kind === 'membership' && (
                              <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                                {it.plan_months_snapshot ? `${it.plan_months_snapshot} months · ` : ''}Member ID: {it.member_id_snapshot ?? detailResv ?? detailOwnedId ?? 'pending'}
                                {detailMembership && <> · {detailMembership.is_renewal ? 'Renewal' : 'New'} · {new Date(detailMembership.start_date).toLocaleDateString('en-GB')} → {new Date(detailMembership.expiry_date).toLocaleDateString('en-GB')}</>}
                                {detail.status === 'unpaid' && Number(detail.paid_amount) === 0 && (
                                  <button className="btn btn-danger btn-sm" style={{ marginLeft: 8, padding: '1px 7px', fontSize: 10.5 }}
                                    onClick={async () => { const { error } = await supabase.rpc('remove_membership_line', { p_item_id: it.id }); if (error) alert(error.message); else { const { data: invRow } = await supabase.from('invoices').select('*').eq('id', detail.id).single(); if (invRow) await openDetail(invRow as Invoice); await loadAll(); } }}>
                                    Remove
                                  </button>
                                )}
                              </div>
                            )}
                            {it.price_mode && (
                              <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>
                                {it.price_mode === 'member' ? 'Member price' : 'Non-Member price'}
                                {it.member_price_snapshot != null && ` · M ${money(Number(it.member_price_snapshot))}`}
                                {it.non_member_price_snapshot != null && ` · NM ${money(Number(it.non_member_price_snapshot))}`}
                                {it.price_overridden && <span style={{ color: 'var(--danger)', fontWeight: 600 }}> · Override: {it.override_reason}</span>}
                                {['product','voucher','promotion'].includes(it.line_kind ?? '') && detail.status === 'unpaid' && Number(detail.paid_amount) === 0 && (
                                  <button className="btn btn-secondary btn-sm" style={{ marginLeft: 6, padding: '1px 7px', fontSize: 10.5 }} onClick={() => setOverrideItem(it)}>M/NM</button>
                                )}
                              </div>
                            )}
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

            {detailTherapy && !detailTherapy.used && detailTherapy.eligible && (
              <div className="alert alert-info" style={{ marginBottom: 0 }}>
                <span>💡</span>
                <div>This invoice hasn't been used for therapy qualification yet — it's still eligible.</div>
              </div>
            )}

            {/* Payment entry (only if not fully paid) */}
            {detail.status !== 'paid' && detail.status !== 'cancelled' && detail.status !== 'refunded' && (
              <div>
                {payErr && <div className="alert alert-danger"><span>⚠</span><div>{payErr}</div></div>}
                {detailItems.some(it => it.line_kind === 'membership') && (
                  <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10, marginBottom: 10, background: 'var(--surface-2)' }}>
                    <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 4 }}>Member ID — required before any payment</div>
                    {detailOwnedId ? (
                      <div style={{ fontSize: 12.5 }}>This customer permanently owns <strong>{detailOwnedId}</strong> — it is reused automatically. Nothing to enter.</div>
                    ) : detailResv ? (
                      <div style={{ fontSize: 12.5 }}>Reserved for this invoice: <strong>{detailResv}</strong>. It becomes permanent on full payment.</div>
                    ) : (
                      <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
                        <input value={midInput} onChange={e => { setMidInput(e.target.value); setMidErr(null); }}
                          placeholder="Enter physical Member ID" style={{ maxWidth: 220 }} />
                        <button className="btn btn-primary btn-sm" disabled={midBusy || !midInput.trim()}
                          onClick={async () => {
                            setMidBusy(true); setMidErr(null);
                            const { error } = await supabase.rpc('reserve_member_id', {
                              p_member_id: midInput.trim(), p_customer_id: detail.customer_id, p_invoice_id: detail.id });
                            setMidBusy(false);
                            if (error) { setMidErr(error.message); return; }
                            setDetailResv(midInput.trim()); setMidInput('');
                          }}>{midBusy ? 'Reserving…' : 'Reserve'}</button>
                      </div>
                    )}
                    {midErr && <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>{midErr}</div>}
                  </div>
                )}
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
      {qualifyFor && (
        <TherapyQualifyModal
          stores={stores} customers={customers} rules={therapyRules}
          prefill={{ storeId: qualifyFor.storeId, customerId: qualifyFor.customerId, sgDate: sgTodayStr(), autoFind: true }}
          onClose={() => setQualifyFor(null)}
          onCreated={(res) => { setQualifyFor(null); alert(`Created ${res?.entitlement_ids?.length ?? 0} therapy entitlement(s). Forfeited S$${Number(res?.forfeited ?? 0).toFixed(2)}.`); }}
        />
      )}

      {priceReview && detail && (
        <PaymentPriceReview review={priceReview} busy={payBusy}
          onClose={() => setPriceReview(null)}
          onConfirm={() => { setPriceReview(null); handlePay(); }} />
      )}
      {overrideItem && detail && (
        <LineOverrideModal item={overrideItem}
          lineName={overrideItem.line_kind === 'voucher' ? (vouchers.find(v => v.id === overrideItem.voucher_id)?.name ?? 'Voucher') : overrideItem.line_kind === 'promotion' ? (promotions.find(p => p.id === (overrideItem as any).promotion_id)?.name ?? 'Promotion') : prodName(overrideItem.product_id ?? '')}
          onClose={() => setOverrideItem(null)}
          onDone={async () => { setOverrideItem(null); const { data: invRow } = await supabase.from('invoices').select('*').eq('id', detail.id).single(); if (invRow) await openDetail(invRow as Invoice); await loadAll(); }} />
      )}
    </div>
  );
};

export default InvoicesPage;
