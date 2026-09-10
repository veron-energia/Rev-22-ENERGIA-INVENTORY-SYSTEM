import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { SettlementSummary, currentSgtMonth } from '../components/tiktok/SettlementSummary';
import { useAuth } from '../context/AuthContext';
import {
  Invoice, Store, Product, Commission, Customer,
  WarehouseInventory, StoreInventory, Warehouse, isManagerOrAbove,
} from '../types';
import { NoAccess } from '../components/ui';
import { RefreshCw, BarChart3, TrendingUp, Package, Star, Users, Download, Ticket, Package2, KeyRound, UserCircle, Award, CreditCard, Sparkles, Gift } from 'lucide-react';
import { SearchSelect } from '../components/SearchSelect';
import { MiniBarChart } from '../components/MiniBarChart';
import { ExcelExportButton } from '../components/ExcelExport';
import { singaporeToday } from '../lib/invoices/business';

const money = (n: number) => `S$${n.toFixed(2)}`;

async function fetchReportRows(build: () => any, orderBy = ['id']): Promise<any[]> {
  const rows: any[] = [];
  for (let offset = 0; ; offset += 1000) {
    let query = build();
    for (const column of orderBy) query = query.order(column, { ascending: true });
    const { data, error } = await query.range(offset, offset + 999);
    if (error) throw new Error(error.message);
    rows.push(...(data ?? []));
    if ((data ?? []).length < 1000) return rows;
  }
}

type SalesEvent = { invoice_id: string; event_id: string; sales_date: string; amount: number; event_kind: string };

// Receipts follow discounted line weights. Refunds follow the recorded refund
// lines, including when the outcome is stored on another payment-source row.
function buildLineSales(items: any[], events: SalesEvent[], refunds: any[]) {
  const byLine = new Map<string, number>();
  const linesByInvoice = new Map<string, any[]>();
  const lineInvoices = new Map(items.map(it => [it.id, it.invoice_id]));
  const refundById = new Map(refunds.map(r => [r.id, r]));
  const outcomes = new Map<string, any[]>();
  const unallocated: { invoice_id: string; event_id: string; amount: number; reason: string }[] = [];
  const requestKey = (r: any) => `${r.invoice_id}:${r.request_id || r.id}`;
  items.forEach(it => linesByInvoice.set(it.invoice_id, [...(linesByInvoice.get(it.invoice_id) ?? []), it]));
  refunds.forEach(r => {
    if (Array.isArray(r.outcome?.lines) && r.outcome.lines.length) outcomes.set(requestKey(r), r.outcome.lines);
  });
  for (const event of events) {
    const cents = Math.round(Number(event.amount) * 100);
    if (!cents) continue;
    const refund = refundById.get(event.event_id);
    const weights: { id: string | null; value: number }[] = event.event_kind === 'refund'
      ? (refund ? outcomes.get(requestKey(refund)) ?? [] : []).map(x => ({ id: x.invoice_item_id || null, value: Number(x.amount) }))
      : (linesByInvoice.get(event.invoice_id) ?? []).map(it => ({ id: it.id, value: Math.max(Number(it.line_total) - Number(it.line_discount || 0), 0) }));
    const valid = weights.filter(x => Number.isFinite(x.value) && x.value > 0);
    const total = valid.reduce((sum, x) => sum + x.value, 0);
    if (!total) {
      unallocated.push({ ...event, amount: cents / 100, reason: 'No recorded line allocation' });
      continue;
    }
    let cumulativeWeight = 0, allocatedCents = 0;
    for (const weight of valid) {
      cumulativeWeight += weight.value;
      // Symmetric rounding makes a bookkeeping reversal cancel the original
      // line allocation exactly, including half-cent shares.
      const nextCents = Math.sign(cents) * Math.round(Math.abs(cents) * cumulativeWeight / total);
      const amount = (nextCents - allocatedCents) / 100;
      allocatedCents = nextCents;
      if (weight.id && lineInvoices.get(weight.id) === event.invoice_id) byLine.set(weight.id, (byLine.get(weight.id) ?? 0) + amount);
      else if (amount) unallocated.push({ ...event, amount, reason: weight.id ? 'Original line is unavailable' : 'Invoice-level correction refund' });
    }
  }
  return { byLine, unallocated };
}

type Tab = 'sales_store' | 'sales_affiliate' | 'commission' | 'stock' | 'top_products' | 'customers' | 'vouchers' | 'promotions' | 'specials' | 'sales_creator' | 'sales_service_staff' | 'r_pricing' | 'r_affiliate' | 'r_therapy' | 'r_discounts' | 'r_foc' | 'r_sources' | 'r_tiktok' | 'r_exchange_inv' | 'r_transfers' | 'r_salesrecon';

const ReportsPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isManagerOrAbove(profile?.role);
  const [tab, setTab] = useState<Tab>('sales_store');
  // Period filter for the sales-based reports. Catalogue and stock reports
  // describe the present, so they ignore it.
  const [dFrom, setDFrom] = useState('');
  const [dTo, setDTo] = useState('');
  const [loading, setLoading] = useState(true);

  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [commissions, setCommissions] = useState<Commission[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [whInv, setWhInv] = useState<WarehouseInventory[]>([]);
  const [stInv, setStInv] = useState<StoreInventory[]>([]);
  const [items, setItems] = useState<any[]>([]);
  const [vouchers, setVouchers] = useState<any[]>([]);
  const [promotions, setPromotions] = useState<any[]>([]);
  const [redemptions, setRedemptions] = useState<any[]>([]);
  const [specialSales, setSpecialSales] = useState<any[]>([]);
  const [rentals, setRentals] = useState<any[]>([]);
  const [specialProducts, setSpecialProducts] = useState<any[]>([]);
  const [profiles, setProfiles] = useState<any[]>([]);
  const [serviceStaff, setServiceStaff] = useState<any[]>([]);
  const [repPricing, setRepPricing] = useState<any[]>([]);
  const [repAffiliate, setRepAffiliate] = useState<any[]>([]);
  const [repTherapy, setRepTherapy] = useState<any[]>([]);
  const [repDiscounts, setRepDiscounts] = useState<any[]>([]);
  const [repFoc, setRepFoc] = useState<any[]>([]);
  const [repSources, setRepSources] = useState<any[]>([]);
  // Phase 17 — TikTok settlement.
  const [ttSummary, setTtSummary] = useState<any>(null);
  // Phase 18 — extended reports (fetched when their tab opens).
  const [ttDaily, setTtDaily] = useState<any[]>([]);
  // The payment report is on the SETTLED-date basis only; the order-created
  // basis was removed in migration 210 because a period struck on it can never
  // tie to what TikTok actually paid.
  const [ttMonth, setTtMonth] = useState(() => currentSgtMonth());
  const [ttByStore, setTtByStore] = useState<any[]>([]);
  const [ttQty, setTtQty] = useState<any[]>([]);
  const [ttByStatus, setTtByStatus] = useState<any[]>([]);
  const [exchInv, setExchInv] = useState<any[]>([]);
  const [trReceipts, setTrReceipts] = useState<any[]>([]);
  const [trDisc, setTrDisc] = useState<any[]>([]);
  const [trOverdue, setTrOverdue] = useState<any[]>([]);
  const [salesRecon, setSalesRecon] = useState<any[]>([]);
  const [ttRows, setTtRows] = useState<any[]>([]);
  const [focSummary, setFocSummary] = useState<any>(null);

  const [salesError, setSalesError] = useState('');
  const [periodError, setPeriodError] = useState('');
  const [periodLoading, setPeriodLoading] = useState(true);
  const [salesEvents, setSalesEvents] = useState<SalesEvent[]>([]);
  const [refunds, setRefunds] = useState<any[]>([]);
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [inv, st, pr, co, cu, wh, wi, si, it, vc, pm, rd, ss, re, sp, prof, iss, rf, events] = await Promise.all([
        fetchReportRows(() => supabase.from('invoices').select('*').is('deleted_at', null)),
        fetchReportRows(() => supabase.from('stores').select('*')),
        fetchReportRows(() => supabase.from('products').select('*')),
        fetchReportRows(() => supabase.from('commissions').select('*')),
        fetchReportRows(() => supabase.from('customers').select('*')),
        fetchReportRows(() => supabase.from('warehouses').select('*')),
        fetchReportRows(() => supabase.from('warehouse_inventory').select('*')),
        fetchReportRows(() => supabase.from('store_inventory').select('*')),
        fetchReportRows(() => supabase.from('invoice_items').select('id,product_id,special_product_id,quantity,line_total,line_discount,invoice_id,line_kind,voucher_id,promotion_id,topup_amount')),
        fetchReportRows(() => supabase.from('vouchers').select('*')),
        fetchReportRows(() => supabase.from('promotions').select('*')),
        fetchReportRows(() => supabase.from('voucher_redemptions').select('*')),
        fetchReportRows(() => supabase.from('special_sales').select('*')),
        fetchReportRows(() => supabase.from('rentals').select('*')),
        fetchReportRows(() => supabase.from('special_products').select('*')),
        fetchReportRows(() => supabase.from('profiles').select('id,full_name,role')),
        fetchReportRows(() => supabase.from('invoice_service_staff').select('id,invoice_id,staff_id')),
        fetchReportRows(() => supabase.from('invoice_refunds').select('id,invoice_id,request_id,amount,credit_returned,outcome')),
        fetchReportRows(() => supabase.rpc('invoice_sales_ledger'), ['sales_date', 'event_id']),
      ]);
      const [ra, rt, rsrc, tts, ttr] = await Promise.all([
        fetchReportRows(() => supabase.rpc('report_affiliates'), ['customer_id']),
        fetchReportRows(() => supabase.rpc('report_therapy'), ['entitlement_no', 'customer_name']),
        fetchReportRows(() => supabase.rpc('report_customer_sources', { p_from: null, p_to: null }), ['source_label', 'is_active']),
        fetchReportRows(() => supabase.rpc('report_tiktok_settlement_summary', { p_store_id: null, p_from: null, p_to: null }), ['total_settlement']),
        fetchReportRows(() => supabase.rpc('report_tiktok_settlement', { p_store_id: null, p_from: null, p_to: null }), ['row_id']),
      ]);
      setInvoices(inv as Invoice[]); setStores(st as Store[]); setProducts(pr as Product[]);
      setCommissions(co as Commission[]); setCustomers(cu as Customer[]); setWarehouses(wh as Warehouse[]);
      setWhInv(wi as WarehouseInventory[]); setStInv(si as StoreInventory[]); setItems(it);
      setVouchers(vc); setPromotions(pm); setRedemptions(rd); setSpecialSales(ss); setRentals(re);
      setSpecialProducts(sp); setProfiles(prof); setServiceStaff(iss); setRefunds(rf); setSalesEvents(events as SalesEvent[]);
      setRepAffiliate(ra); setRepTherapy(rt); setRepSources(rsrc);
      setTtSummary(tts[0] ?? null); setTtRows(ttr); setSalesError('');
    } catch (error: any) {
      setSalesError(error.message || 'Unable to load all report records.');
    } finally { setLoading(false); }
  }, []);
  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    let cancelled = false;
    const dated = (name: string) => {
      let query = supabase.rpc(name);
      if (dFrom) query = query.gte('paid_date', dFrom);
      if (dTo) query = query.lte('paid_date', dTo);
      return query;
    };
    const loadPeriodReports = async () => {
      setPeriodLoading(true);
      try {
        const [pricing, discounts, focLines, focSummaryResult, reconciliation] = await Promise.all([
          fetchReportRows(() => dated('report_pricing'), ['invoice_id', 'line_kind', 'item_name', 'quantity', 'unit_price']),
          fetchReportRows(() => dated('report_discounts'), ['invoice_id']),
          fetchReportRows(() => supabase.rpc('report_foc_lines', { p_from: dFrom || null, p_to: dTo || null, p_store_id: null }), ['invoice_id', 'line_kind', 'description', 'quantity', 'foc_quantity']),
          supabase.rpc('report_foc_summary', { p_from: dFrom || null, p_to: dTo || null, p_store_id: null }),
          fetchReportRows(() => supabase.rpc('report_sales_reconciliation', { p_store_id: null, p_from: dFrom || null, p_to: dTo || null }), ['channel']),
        ]);
        if (focSummaryResult.error) throw new Error(focSummaryResult.error.message);
        if (!cancelled) {
          setRepPricing(pricing); setRepDiscounts(discounts); setRepFoc(focLines);
          setFocSummary(focSummaryResult.data); setSalesRecon(reconciliation); setPeriodError('');
        }
      } catch (error: any) { if (!cancelled) setPeriodError(error.message || 'Unable to load the selected period.'); }
      finally { if (!cancelled) setPeriodLoading(false); }
    };
    loadPeriodReports();
    return () => { cancelled = true; };
  }, [dFrom, dTo, salesEvents]);

  // Actual eligible receipts on invoice business dates; refund reductions on
  // their own dates. Invoice totals are never substituted for received money.
  const periodEvents = salesEvents.filter(e => (!dFrom || e.sales_date >= dFrom) && (!dTo || e.sales_date <= dTo));
  const recognized = new Map<string, number>();
  const receiptTotals = new Map<string, number>();
  for (const e of periodEvents) {
    recognized.set(e.invoice_id, (recognized.get(e.invoice_id) ?? 0) + Number(e.amount));
    if (e.event_kind !== 'refund') receiptTotals.set(e.invoice_id, (receiptTotals.get(e.invoice_id) ?? 0) + Number(e.amount));
  }
  const receiptInvoiceIds = new Set([...receiptTotals].filter(([, amount]) => amount > 0).map(([id]) => id));
  const paid = invoices.filter(i => recognized.has(i.id)).map(i => ({ ...i, total_amount: recognized.get(i.id)! }));
  const lineSales = buildLineSales(items, periodEvents, refunds);
  const lineRevenue = (it: any) => lineSales.byLine.get(it.id) ?? 0;
  const invoicedQuantity = (it: any) => receiptInvoiceIds.has(it.invoice_id) ? Number(it.quantity) : 0;
  const unallocatedAmount = lineSales.unallocated.reduce((sum, e) => sum + e.amount, 0);
  const inPeriod = (date: string | null | undefined) => !!date && (!dFrom || date >= dFrom) && (!dTo || date <= dTo);
  const singaporeDate = (value: string | null | undefined) => value
    ? new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(value)) : '';
  const pName = (id: string) => products.find(p => p.id === id)?.name ?? '—';

  // Sales by store
  const salesByStore = stores.map(s => {
    const sInv = paid.filter(i => i.store_id === s.id);
    return { name: s.name, count: sInv.length, total: sInv.reduce((a, i) => a + Number(i.total_amount), 0) };
  }).filter(r => r.count > 0).sort((a, b) => b.total - a.total);

  // Sales by referrer (from the two-tier commission model): Tier-1 rows carry
  // the after-discount commissionable value of each referred paid invoice line.
  const referrerIds = Array.from(new Set(commissions.map(c => c.referrer_customer_id)));
  const cName = (id: string) => customers.find(x => x.id === id)?.full_name ?? '—';
  const salesByReferrer = referrerIds.map(rid => {
    const t1 = commissions.filter(c => c.referrer_customer_id === rid && c.tier === 'tier1' && (c.status === 'earned' || c.status === 'paid'));
    const attributed = Array.from(new Set(t1.map(c => c.invoice_id))).filter(id =>
      t1.filter(c => c.invoice_id === id).reduce((sum, c) => sum + Number(c.commission_amount), 0) > 0 && recognized.has(id));
    const invoiceCount = attributed.length;
    const salesValue = attributed.reduce((sum, id) => sum + (recognized.get(id) ?? 0), 0);
    const all = commissions.filter(c => c.referrer_customer_id === rid && (c.status === 'earned' || c.status === 'paid'));
    const commission = all.reduce((s, c) => s + Number(c.commission_amount), 0);
    return { name: cName(rid), count: invoiceCount, total: salesValue, commission };
  }).filter(r => r.count > 0).sort((a, b) => b.total - a.total);

  // Commission report by referrer (earned incl. paid-out; reversed separate).
  const commissionRows = referrerIds.map(rid => {
    const rc = commissions.filter(c => c.referrer_customer_id === rid);
    const earned = rc.filter(c => c.status === 'earned' || c.status === 'paid').reduce((s, c) => s + Number(c.commission_amount), 0);
    const paidOut = rc.filter(c => c.status === 'paid').reduce((s, c) => s + Number(c.commission_amount), 0);
    const reversed = rc.filter(c => c.status === 'reversed').reduce((s, c) => s + Number(c.commission_amount), 0);
    return { name: cName(rid), earned, paidOut, reversed, net: earned };
  }).filter(r => r.earned > 0 || r.reversed > 0).sort((a, b) => b.net - a.net);

  // Top products (by qty sold across paid invoices)
  const paidIds = new Set(paid.map(i => i.id));
  const prodAgg: Record<string, { qty: number; revenue: number }> = {};
  items.filter(it => it.product_id && paidIds.has(it.invoice_id)).forEach(it => {
    (prodAgg[it.product_id] ??= { qty: 0, revenue: 0 });
    prodAgg[it.product_id].qty += invoicedQuantity(it);
    prodAgg[it.product_id].revenue += lineRevenue(it);
  });
  const topProducts = Object.entries(prodAgg).map(([id, v]) => ({ name: pName(id), ...v })).sort((a, b) => b.qty - a.qty);

  // Customers report
  const genderLabel = (c: any) => c.gender === 'other' ? (c.gender_other || 'Other') : c.gender ? (c.gender.charAt(0).toUpperCase() + c.gender.slice(1)) : '';
  const custRows = customers.map(c => {
    const cInv = paid.filter(i => i.customer_id === c.id);
    return { name: c.full_name, phone: c.phone, dob: (c as any).date_of_birth ?? '', gender: genderLabel(c), occupation: (c as any).occupation ?? '', count: cInv.length, total: cInv.reduce((s, i) => s + Number(i.total_amount), 0) };
  }).filter(r => r.count > 0).sort((a, b) => b.total - a.total);

  const staffPName = (id: string) => profiles.find(p => p.id === id)?.full_name ?? '—';

  // Sales by invoice creator (created_by).
  const salesByCreator = (() => {
    const map = new Map<string, { name: string; count: number; total: number }>();
    paid.forEach(i => {
      const id = (i as any).created_by; if (!id) return;
      const g = map.get(id) ?? { name: staffPName(id), count: 0, total: 0 };
      g.count += 1; g.total += Number(i.total_amount); map.set(id, g);
    });
    return Array.from(map.values()).filter(r => r.count > 0).sort((a, b) => b.total - a.total);
  })();

  // Sales by service staff — shared performance, equal split of each paid
  // invoice's total across its service staff.
  const salesByServiceStaff = (() => {
    const byInv = new Map<string, string[]>();
    serviceStaff.forEach(r => {
      const arr = byInv.get(r.invoice_id) ?? []; arr.push(r.staff_id); byInv.set(r.invoice_id, arr);
    });
    const map = new Map<string, { name: string; invoices: number; shared: number; fullTotal: number }>();
    paid.forEach(i => {
      const staff = byInv.get(i.id); if (!staff || staff.length === 0) return;
      const share = Number(i.total_amount) / staff.length;
      staff.forEach(sid => {
        const g = map.get(sid) ?? { name: staffPName(sid), invoices: 0, shared: 0, fullTotal: 0 };
        g.invoices += 1; g.shared += share; g.fullTotal += Number(i.total_amount); map.set(sid, g);
      });
    });
    return Array.from(map.values()).filter(r => r.invoices > 0).sort((a, b) => b.shared - a.shared);
  })();

  const totalRevenue = paid.reduce((s, i) => s + Number(i.total_amount), 0);

  // On-demand loads for the Phase 18 tabs.
  useEffect(() => {
    const fetchExtras = async () => {
      if (tab === 'r_tiktok') {
        const [d, bs, q, st] = await Promise.all([
          supabase.rpc('report_tiktok_settlement_daily', { p_store_id: null, p_from: null, p_to: null }),
          supabase.rpc('report_tiktok_settlement_by_store', { p_from: null, p_to: null }),
          supabase.rpc('report_tiktok_qty_sold', { p_store_id: null, p_from: null, p_to: null }),
          supabase.rpc('report_tiktok_orders_by_status', { p_store_id: null }),
        ]);
        setTtDaily((d.data as any[]) ?? []); setTtByStore((bs.data as any[]) ?? []);
        setTtQty((q.data as any[]) ?? []); setTtByStatus((st.data as any[]) ?? []);
      } else if (tab === 'r_exchange_inv') {
        const { data } = await supabase.rpc('report_exchange_invoices', { p_store_id: null, p_from: null, p_to: null });
        setExchInv((data as any[]) ?? []);
      } else if (tab === 'r_transfers') {
        const [rc, dc, od] = await Promise.all([
          supabase.rpc('report_transfer_receipts', { p_from: null, p_to: null }),
          supabase.rpc('report_transfer_discrepancies'),
          supabase.rpc('report_transfers_overdue', { p_days: 7 }),
        ]);
        setTrReceipts((rc.data as any[]) ?? []); setTrDisc((dc.data as any[]) ?? []); setTrOverdue((od.data as any[]) ?? []);

      }
    };
    fetchExtras();
  }, [tab, ttMonth]);

  // Grouping shown as a sublabel in the picker, so 21 reports are findable.
  const REPORT_GROUP: Record<string, string> = {
    sales_store: 'Sales', top_products: 'Sales', sales_creator: 'Sales',
    sales_service_staff: 'Sales', sales_affiliate: 'Sales', r_tiktok: 'Sales',
    r_salesrecon: 'Sales',
    vouchers: 'Products & Offers', promotions: 'Products & Offers',
    specials: 'Products & Offers', r_therapy: 'Products & Offers',
    r_pricing: 'Products & Offers',
    stock: 'Stock', r_transfers: 'Stock', r_exchange_inv: 'Stock',
    commission: 'People', r_affiliate: 'People', customers: 'People', r_sources: 'People',
    r_discounts: 'Finance', r_foc: 'Finance',
  };

  const TABS: { id: Tab; label: string; icon: React.ReactNode }[] = [
    { id: 'sales_store', label: 'Sales by Store', icon: <TrendingUp size={15} /> },
    { id: 'top_products', label: 'Top Products', icon: <Package size={15} /> },
    { id: 'sales_creator', label: 'Sales by Creator', icon: <UserCircle size={15} /> },
    { id: 'sales_service_staff', label: 'Sales by Service Staff', icon: <Award size={15} /> },
    { id: 'sales_affiliate', label: 'Sales by Referrer', icon: <Star size={15} /> },
    { id: 'vouchers', label: 'Vouchers', icon: <Ticket size={15} /> },
    { id: 'promotions', label: 'Promotions', icon: <Package2 size={15} /> },
    { id: 'specials', label: 'Specials & Rentals', icon: <KeyRound size={15} /> },
    { id: 'commission', label: 'Commission', icon: <BarChart3 size={15} /> },
    { id: 'customers', label: 'Customers', icon: <Users size={15} /> },
    { id: 'stock', label: 'Stock Balance', icon: <Package size={15} /> },
    { id: 'r_pricing', label: 'Pricing', icon: <KeyRound size={15} /> },
    { id: 'r_affiliate', label: 'Affiliate', icon: <Star size={15} /> },
    { id: 'r_therapy', label: 'Therapy', icon: <Sparkles size={15} /> },
    { id: 'r_discounts', label: 'Discounts', icon: <Ticket size={15} /> },
    { id: 'r_foc', label: 'FOC', icon: <Gift size={15} /> },
    { id: 'r_sources', label: 'Sources', icon: <Users size={15} /> },
    { id: 'r_tiktok', label: 'TikTok', icon: <TrendingUp size={15} /> },
    { id: 'r_exchange_inv', label: 'Exchange Invoices', icon: <Ticket size={15} /> },
    { id: 'r_transfers', label: 'Transfers', icon: <Package size={15} /> },
    { id: 'r_salesrecon', label: 'Sales Reconciliation', icon: <BarChart3 size={15} /> },
  ];

  // 5G-2: voucher / promotion / special reports (paid invoices only).
  const paidInvIds = new Set(paid.map(i => i.id));
  const voucherRows = vouchers.map(v => {
    const sold = items.filter(it => it.line_kind === 'voucher' && it.voucher_id === v.id && paidInvIds.has(it.invoice_id));
    const reds = redemptions.filter(r => r.voucher_id === v.id && inPeriod(singaporeDate(r.created_at)));
    return {
      name: v.name, kind: v.voucher_kind,
      sold_qty: sold.reduce((s, it) => s + invoicedQuantity(it), 0),
      sales_value: sold.reduce((s, it) => s + lineRevenue(it), 0),
      redemptions: reds.length,
      discount_given: reds.reduce((s, r) => s + Number(r.discount_applied), 0),
    };
  }).filter(r => r.sold_qty > 0 || r.redemptions > 0 || r.sales_value !== 0).sort((a, b) => b.sales_value - a.sales_value);

  const promoRows = promotions.map(p => {
    const sold = items.filter(it => it.line_kind === 'promotion' && it.promotion_id === p.id && paidInvIds.has(it.invoice_id));
    return {
      name: p.name, code: p.code,
      sold_qty: sold.reduce((s, it) => s + invoicedQuantity(it), 0),
      topups: sold.filter(it => receiptInvoiceIds.has(it.invoice_id)).reduce((s, it) => s + Number(it.topup_amount ?? 0), 0),
      revenue: sold.reduce((s, it) => s + lineRevenue(it), 0),
    };
  }).filter(r => r.sold_qty > 0 || r.revenue !== 0).sort((a, b) => b.revenue - a.revenue);

  const specialRows = specialProducts.map(p => {
    const invoiceLines = items.filter(it => it.special_product_id === p.id && paidInvIds.has(it.invoice_id));
    const saleLines = invoiceLines.filter(it => it.line_kind === 'special_product');
    const rentalLines = invoiceLines.filter(it => it.line_kind === 'rental');
    // Standalone documents have no invoice sales event. Keep their billed
    // amounts separate instead of treating a charge as proof of a receipt.
    const standaloneSales = specialSales.filter(s => s.special_product_id === p.id && !s.invoice_id && s.status === 'paid' && inPeriod(singaporeDate(s.created_at)));
    const standaloneRentals = rentals.filter(r => r.special_product_id === p.id && !r.invoice_id && !['draft', 'cancelled'].includes(r.status) && inPeriod(singaporeDate(r.paid_at || r.created_at)));
    const lateCharges = rentals.filter(r => r.special_product_id === p.id && !['draft', 'cancelled'].includes(r.status) && inPeriod(singaporeDate(r.returned_at)));
    return {
      name: p.name,
      units_sold: saleLines.reduce((sum, it) => sum + invoicedQuantity(it), 0),
      sales_revenue: saleLines.reduce((sum, it) => sum + lineRevenue(it), 0),
      rentals: rentalLines.filter(it => receiptInvoiceIds.has(it.invoice_id)).length,
      rental_fees: rentalLines.reduce((sum, it) => sum + lineRevenue(it), 0),
      standalone_sales_billed: standaloneSales.reduce((sum, row) => sum + Number(row.total_amount), 0),
      standalone_rental_fees_billed: standaloneRentals.reduce((sum, row) => sum + Number(row.rental_fee), 0),
      late_fees: lateCharges.reduce((sum, row) => sum + Number(row.late_fee_total), 0),
    };
  }).filter(r => r.units_sold > 0 || r.rentals > 0 || r.sales_revenue !== 0 || r.rental_fees !== 0 || r.standalone_sales_billed !== 0 || r.standalone_rental_fees_billed !== 0 || r.late_fees !== 0)
    .sort((a, b) => (b.sales_revenue + b.rental_fees) - (a.sales_revenue + a.rental_fees));

  const reportDump = (): Record<string, any[]> => {
    const stockExport = [
      ...warehouses.map(w => { const rws = whInv.filter(i => i.warehouse_id === w.id && i.current_qty > 0);
        return { location: w.name, type: 'Warehouse', products_stocked: rws.length, total_units: rws.reduce((s, i) => s + i.current_qty, 0) }; }),
      ...stores.map(st => { const rws = stInv.filter(i => i.store_id === st.id && i.current_qty > 0);
        return { location: st.name, type: 'Store', products_stocked: rws.length, total_units: rws.reduce((s, i) => s + i.current_qty, 0) }; }),
    ];
    const dump: Record<string, any[]> = {
      sales_store: salesByStore, sales_affiliate: salesByReferrer, commission: commissionRows,
      top_products: topProducts, customers: custRows, stock: stockExport,
      vouchers: voucherRows, promotions: promoRows, specials: specialRows,
      sales_creator: salesByCreator, sales_service_staff: salesByServiceStaff,
      r_pricing: repPricing.map(({ paid_date, ...row }) => ({ ...row, business_date: paid_date })), r_affiliate: repAffiliate,
      r_therapy: repTherapy,
      r_discounts: repDiscounts.map(({ paid_date, ...row }) => ({ ...row, business_date: paid_date })),
      r_foc: repFoc.map(({ settled_at, ...row }) => ({ ...row, business_date: singaporeDate(settled_at) })),
      r_sources: repSources, r_tiktok: ttRows, r_exchange_inv: exchInv, r_transfers: trReceipts, r_salesrecon: salesRecon,
    };
    return dump;
  };
  const currentReportRows = (): any[] => (reportDump()[tab] ?? []) as any[];
  const isPeriodReport = ['r_pricing', 'r_discounts', 'r_foc', 'r_salesrecon'].includes(tab);
  const reportBusy = loading || (isPeriodReport && periodLoading);
  const reportFailed = !!salesError || (isPeriodReport && !!periodError);

  if (!hasAccess) return <NoAccess message="Only Owners, Admins, and Managers can view reports." />;


  return (
    <div>
      {(salesError || periodError) && <div role="alert" className="alert alert-danger">Reports could not be fully loaded: {salesError || periodError}</div>}
      <div className="page-header">
        <div><h2>Reports</h2><p>Overview across sales, stock, referrers, and customers. Recognized invoice sales: <strong style={{ color: 'var(--primary)' }}>{money(totalRevenue)}</strong></p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={currentReportRows()}
            filename={`report-${tab}`}
            sheetName={(TABS.find(t => t.id === tab)?.label ?? 'Report').slice(0, 31)}
            label="Export Excel"
            disabled={reportBusy || reportFailed}
            columns={Object.keys(currentReportRows()[0] ?? {}).map(k => ({
              header: k.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
              value: (r: any) => r[k],
            }))} /><button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button></div>
      </div>

      <div className="card" style={{ padding: 12, marginBottom: 14 }}>
        <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start', flexWrap: 'wrap' }}>
          <div style={{ flex: '1 1 280px', maxWidth: 360 }}>
            <label style={{ fontSize: 11.5, color: 'var(--text-muted)', display: 'block', marginBottom: 3 }}>Report</label>
            <SearchSelect
              value={tab}
              onChange={v => v && setTab(v as Tab)}
              placeholder="Search reports…"
              options={TABS.map(t => ({
                value: t.id,
                label: t.label,
                sublabel: REPORT_GROUP[t.id] ?? undefined,
                search: `${t.label} ${REPORT_GROUP[t.id] ?? ''}`,
              }))} />
          </div>
          <div>
            <label style={{ fontSize: 11.5, color: 'var(--text-muted)', display: 'block', marginBottom: 3 }}>Period</label>
            <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
              <input type="date" value={dFrom} max={dTo || undefined} onChange={e => setDFrom(e.target.value)} style={{ width: 150 }} />
              <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>to</span>
              <input type="date" value={dTo} min={dFrom || undefined} onChange={e => setDTo(e.target.value)} style={{ width: 150 }} />
            </div>
          </div>
          <div style={{ alignSelf: 'flex-end' }}>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {([['Today', 0], ['7 days', 6], ['30 days', 29], ['This year', -1]] as [string, number][]).map(([lbl, days]) => (
                <button key={lbl} className="btn btn-secondary btn-sm" onClick={() => {
                  const end = singaporeToday();
                  if (days === -1) { setDFrom(`${end.slice(0, 4)}-01-01`); setDTo(end); }
                  else { const start = new Date(`${end}T12:00:00Z`); start.setUTCDate(start.getUTCDate() - days);
                         setDFrom(start.toISOString().slice(0, 10)); setDTo(end); }
                }}>{lbl}</button>
              ))}
              <button className="btn btn-secondary btn-sm" onClick={() => { setDFrom(''); setDTo(''); }}>All time</button>
            </div>
          </div>
        </div>
        <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 8 }}>
          {dFrom || dTo
            ? `Showing invoice sales ${dFrom ? `from ${dFrom.split('-').reverse().join('/')}` : ''}${dTo ? ` to ${dTo.split('-').reverse().join('/')}` : ''}. Receipts use the invoice business date; refunds use the refund date.`
            : 'Showing all time. Receipts use the invoice business date; refunds use the refund date.'}
          <div>Pricing, discounts and FOC show invoice measures by business date. Stock and catalogue reports show the current position; commission payouts retain their actual dates.</div>
        </div>
      </div>

      {lineSales.unallocated.length > 0 && <div className="alert alert-warning" role="status">
        {money(unallocatedAmount)} across {lineSales.unallocated.length} event allocations is included in invoice sales but cannot be assigned to a product line. Original line details or an invoice-level correction require review.
        <ExcelExportButton rows={lineSales.unallocated} filename="invoice-sales-allocation-review" label="Export allocation review" columns={[
          { header: 'Invoice', value: r => invoices.find(i => i.id === r.invoice_id)?.invoice_no ?? r.invoice_id },
          { header: 'Invoice ID', value: r => r.invoice_id },
          { header: 'Event ID', value: r => r.event_id },
          { header: 'Amount', value: r => r.amount },
          { header: 'Reason', value: r => r.reason },
        ]} />
      </div>}
      {['top_products', 'vouchers', 'promotions', 'specials'].includes(tab) && <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>
        Line sales use discounted receipt shares and the recorded refund lines. Mixed cash and wallet refunds allocate only the external-money share proportionally. Invoiced quantities count invoices with receipts in this period; they are not a stock-return measure.
      </p>}
      {tab === 'specials' && <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>
        Invoice sales and rental receipts follow the selected sales period. Standalone billed amounts use the document date and require payment review; late charges use the recorded return date. These charges are shown separately and are excluded from recognized invoice sales.
      </p>}
      {(() => {
        // Headline figures for the period, so the answer is visible before the table.
        const revenue = paid.reduce((a, i) => a + Number(i.total_amount ?? 0), 0);
        const invCount = paid.length;
        const avg = invCount > 0 ? revenue / invCount : 0;
        const customersServed = new Set(paid.map(i => i.customer_id).filter(Boolean)).size;
        const cards: [string, string][] = [
          ['Revenue', `S$${revenue.toFixed(2)}`],
          ['Invoices with sales activity', String(invCount)],
          ['Average invoice', `S$${avg.toFixed(2)}`],
          ['Customers served', String(customersServed)],
        ];
        const salesReport = !['stock', 'r_pricing', 'r_transfers'].includes(tab);
        if (!salesReport) return null;
        return (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 10, marginBottom: 14 }}>
            {cards.map(([k, v]) => (
              <div key={k} className="card" style={{ padding: '12px 14px' }}>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{k}</div>
                <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{v}</div>
              </div>
            ))}
          </div>
        );
      })()}

      {(() => {
        // One comparison chart, for the reports where ranking is the point.
        const chartFor: Record<string, { title: string; data: { label: string; value: number; sub?: string }[]; fmt?: (n: number) => string }> = {
          sales_store: { title: 'Revenue by store', data: salesByStore.map(r => ({ label: r.name, value: r.total, sub: `${r.count} invoice(s)` })), fmt: (n) => `S$${n.toFixed(2)}` },
          top_products: { title: 'Top products by invoiced quantity', data: topProducts.map((r: any) => ({ label: r.name, value: r.qty, sub: `S$${Number(r.revenue ?? 0).toFixed(2)}` })) },
          sales_affiliate: { title: 'Sales value by referrer', data: salesByReferrer.map(r => ({ label: r.name, value: r.total, sub: `${r.count} invoice(s)` })), fmt: (n) => `S$${n.toFixed(2)}` },
        };
        const c = chartFor[tab];
        if (!c) return null;
        return (
          <div className="card" style={{ marginBottom: 14 }}>
            <MiniBarChart title={c.title} data={c.data} format={c.fmt} limit={10} />
          </div>
        );
      })()}

      <div className="card">
        <div className="table-wrap">
          {reportBusy ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : reportFailed ? <div className="empty-state">The complete report is unavailable. Refresh to try again.</div>
          : (
            <>
              {tab === 'sales_store' && (
                <table>
                  <thead><tr><th>Store</th><th style={{ textAlign: 'right' }}>Invoices with sales activity</th><th style={{ textAlign: 'right' }}>Revenue</th></tr></thead>
                  <tbody>{salesByStore.length === 0 ? <tr><td colSpan={3} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No paid sales yet</td></tr>
                    : salesByStore.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.total)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'top_products' && (
                <table>
                  <thead><tr><th>Product</th><th style={{ textAlign: 'right' }}>Invoiced qty</th><th style={{ textAlign: 'right' }}>Revenue</th></tr></thead>
                  <tbody>{topProducts.length === 0 ? <tr><td colSpan={3} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No sales yet</td></tr>
                    : topProducts.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.qty}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.revenue)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'sales_affiliate' && (
                <table>
                  <thead><tr><th>Referrer</th><th style={{ textAlign: 'right' }}>Referred invoices with sales activity</th><th style={{ textAlign: 'right' }}>Recognized sales</th><th style={{ textAlign: 'right' }}>Commission</th></tr></thead>
                  <tbody>{salesByReferrer.length === 0 ? <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No referred sales yet — commission is earned when a referred customer's invoice is fully paid</td></tr>
                    : salesByReferrer.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.total)}</td><td style={{ textAlign: 'right', color: 'var(--primary)' }}>{money(r.commission)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'commission' && (
                <table>
                  <thead><tr><th>Referrer</th><th style={{ textAlign: 'right' }}>Earned (lifetime)</th><th style={{ textAlign: 'right' }}>Paid Out</th><th style={{ textAlign: 'right' }}>Reversed</th><th style={{ textAlign: 'right' }}>Net</th></tr></thead>
                  <tbody>{commissionRows.length === 0 ? <tr><td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No commissions yet</td></tr>
                    : commissionRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right', color: 'var(--success)' }}>{money(r.earned)}</td><td style={{ textAlign: 'right' }}>{r.paidOut > 0 ? money(r.paidOut) : '—'}</td><td style={{ textAlign: 'right', color: 'var(--danger)' }}>{r.reversed > 0 ? `−${money(r.reversed)}` : '—'}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.net)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'vouchers' && (
                <table>
                  <thead><tr><th>Voucher</th><th>Type</th><th style={{ textAlign: 'right' }}>Invoiced qty</th><th style={{ textAlign: 'right' }}>Sales Value</th><th style={{ textAlign: 'right' }}>Redemptions</th><th style={{ textAlign: 'right' }}>Discount Given</th></tr></thead>
                  <tbody>{voucherRows.length === 0 ? <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No voucher activity yet</td></tr>
                    : voucherRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ fontSize: 12 }}>{r.kind}</td><td style={{ textAlign: 'right' }}>{r.sold_qty}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.sales_value)}</td><td style={{ textAlign: 'right' }}>{r.redemptions}</td><td style={{ textAlign: 'right', color: 'var(--danger)' }}>{r.discount_given > 0 ? `−${money(r.discount_given)}` : '—'}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'promotions' && (
                <table>
                  <thead><tr><th>Promotion</th><th>Code</th><th style={{ textAlign: 'right' }}>Invoiced qty</th><th style={{ textAlign: 'right' }}>Top-ups</th><th style={{ textAlign: 'right' }}>Revenue</th></tr></thead>
                  <tbody>{promoRows.length === 0 ? <tr><td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No promotion sales yet</td></tr>
                    : promoRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ fontSize: 12 }}>{r.code}</td><td style={{ textAlign: 'right' }}>{r.sold_qty}</td><td style={{ textAlign: 'right' }}>{r.topups > 0 ? money(r.topups) : '—'}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.revenue)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'specials' && (
                <table>
                  <thead><tr><th>Special Product</th><th style={{ textAlign: 'right' }}>Invoiced units</th><th style={{ textAlign: 'right' }}>Invoice sales</th><th style={{ textAlign: 'right' }}>Invoiced rentals</th><th style={{ textAlign: 'right' }}>Invoice rental sales</th><th style={{ textAlign: 'right' }}>Standalone sales billed</th><th style={{ textAlign: 'right' }}>Standalone rental fees billed</th><th style={{ textAlign: 'right' }}>Late fees billed</th></tr></thead>
                  <tbody>{specialRows.length === 0 ? <tr><td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No special product activity yet</td></tr>
                    : specialRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.units_sold}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.sales_revenue)}</td><td style={{ textAlign: 'right' }}>{r.rentals}</td><td style={{ textAlign: 'right' }}>{money(r.rental_fees)}</td><td style={{ textAlign: 'right' }}>{money(r.standalone_sales_billed)}</td><td style={{ textAlign: 'right' }}>{money(r.standalone_rental_fees_billed)}</td><td style={{ textAlign: 'right', color: 'var(--danger)' }}>{r.late_fees > 0 ? money(r.late_fees) : '—'}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'sales_creator' && (
                <table>
                  <thead><tr><th>Invoice Creator</th><th style={{ textAlign: 'right' }}>Invoices</th><th style={{ textAlign: 'right' }}>Total Sales</th></tr></thead>
                  <tbody>{salesByCreator.length === 0 ? <tr><td colSpan={3} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No sales yet</td></tr>
                    : salesByCreator.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.total)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'sales_service_staff' && (
                <table>
                  <thead><tr><th>Service Staff</th><th style={{ textAlign: 'right' }}>Invoices Served</th><th style={{ textAlign: 'right' }}>Shared Sales (equal split)</th><th style={{ textAlign: 'right' }}>Invoice Value Touched</th></tr></thead>
                  <tbody>{salesByServiceStaff.length === 0 ? <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No service-staff sales yet — add "Served by" staff when creating invoices</td></tr>
                    : salesByServiceStaff.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.invoices}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.shared)}</td><td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{money(r.fullTotal)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'customers' && (
                <table>
                  <thead><tr><th>Customer</th><th>Phone</th><th>DOB</th><th>Gender</th><th>Occupation</th><th style={{ textAlign: 'right' }}>Purchases</th><th style={{ textAlign: 'right' }}>Total Spent</th></tr></thead>
                  <tbody>{custRows.length === 0 ? <tr><td colSpan={7} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No customer purchases yet</td></tr>
                    : custRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ fontSize: 12.5 }}>{r.phone}</td><td style={{ fontSize: 12.5 }}>{r.dob ? new Date(r.dob).toLocaleDateString() : '—'}</td><td style={{ fontSize: 12.5 }}>{r.gender || '—'}</td><td style={{ fontSize: 12.5 }}>{r.occupation || '—'}</td><td style={{ textAlign: 'right' }}>{r.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.total)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'stock' && (
                <table>
                  <thead><tr><th>Location</th><th>Type</th><th style={{ textAlign: 'right' }}>Products Stocked</th><th style={{ textAlign: 'right' }}>Total Units</th></tr></thead>
                  <tbody>
                    {warehouses.map(w => {
                      const rows = whInv.filter(i => i.warehouse_id === w.id && i.current_qty > 0);
                      return <tr key={w.id}><td><strong>🏭 {w.name}</strong></td><td>Warehouse</td><td style={{ textAlign: 'right' }}>{rows.length}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{rows.reduce((s, i) => s + i.current_qty, 0)}</td></tr>;
                    })}
                    {stores.map(s => {
                      const rows = stInv.filter(i => i.store_id === s.id && i.current_qty > 0);
                      return <tr key={s.id}><td><strong>🏪 {s.name}</strong></td><td>Store</td><td style={{ textAlign: 'right' }}>{rows.length}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{rows.reduce((s, i) => s + i.current_qty, 0)}</td></tr>;
                    })}
                  </tbody>
                </table>
              )}
              {tab === 'r_pricing' && (
                <table>
                  <thead><tr><th>Invoice</th><th>Business date</th><th>Store</th><th>Customer</th><th>Item</th><th>Kind</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>Price</th></tr></thead>
                  <tbody>{repPricing.length === 0 ? <tr><td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No invoice lines in this period</td></tr>
                    : repPricing.map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{r.paid_date ? r.paid_date.split('-').reverse().join('/') : 'Date pending review'}</td><td style={{ fontSize: 12 }}>{r.store_name}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td><td>{r.item_name}</td><td style={{ fontSize: 12 }}>{r.line_kind}</td><td style={{ textAlign: 'right' }}>{r.quantity}</td><td style={{ textAlign: 'right' }}>{money(Number(r.unit_price))}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'r_affiliate' && (
                <table>
                  <thead><tr><th>Customer</th><th>Eligibility</th><th>Store</th><th style={{ textAlign: 'right' }}>Referrals</th><th style={{ textAlign: 'right' }}>Tier 1</th><th style={{ textAlign: 'right' }}>Tier 2</th><th style={{ textAlign: 'right' }}>Earned</th><th style={{ textAlign: 'right' }}>Paid</th><th style={{ textAlign: 'right' }}>Reversed</th><th style={{ textAlign: 'right' }}>Blocked</th></tr></thead>
                  <tbody>{repAffiliate.length === 0 ? <tr><td colSpan={10} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No affiliates</td></tr>
                    : repAffiliate.map((r, i) => <tr key={i}><td><strong>{r.customer_name}</strong></td><td style={{ fontSize: 12 }}>{r.affiliate_state === 'active' ? 'Eligible' : (r.block_reason ?? r.affiliate_state)}</td><td style={{ fontSize: 12 }}>{r.store_name ?? '—'}</td><td style={{ textAlign: 'right' }}>{r.direct_referrals}</td><td style={{ textAlign: 'right' }}>{money(Number(r.tier1_earned))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.tier2_earned))}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.earned))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.paid))}</td><td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{money(Number(r.reversed))}</td><td style={{ textAlign: 'right', color: Number(r.blocked) > 0 ? 'var(--danger)' : 'var(--text-muted)' }}>{money(Number(r.blocked))}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'r_therapy' && (
                <table>
                  <thead><tr><th>No.</th><th>Customer</th><th>Package</th><th>Store</th><th style={{ textAlign: 'right' }}>Price</th><th>Purchased</th><th>Activation</th><th>Expiry</th><th>Status</th><th>Type</th></tr></thead>
                  <tbody>{repTherapy.length === 0 ? <tr><td colSpan={10} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No therapy</td></tr>
                    : repTherapy.map((r, i) => <tr key={i}><td>{r.entitlement_no}</td><td><strong>{r.customer_name}</strong></td><td>{r.package_name}</td><td style={{ fontSize: 12 }}>{r.store_name ?? '—'}</td><td style={{ textAlign: 'right' }}>{money(Number(r.price_snapshot))}</td><td style={{ fontSize: 12 }}>{r.purchase_date ? new Date(r.purchase_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ fontSize: 12 }}>{r.activation_date ? new Date(r.activation_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ fontSize: 12 }}>{r.expiry_date ? new Date(r.expiry_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ textTransform: 'capitalize' }}>{String(r.status).replace('_', ' ')}</td><td style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{r.is_legacy ? 'Legacy' : 'Purchased'}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'r_sources' && (
                <table>
                  <thead><tr><th>Source</th><th style={{ textAlign: 'right' }}>Customers (current source)</th><th style={{ textAlign: 'right' }}>Surveys (submission snapshot)</th><th>Status</th></tr></thead>
                  <tbody>{repSources.length === 0 ? <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No source data</td></tr>
                    : repSources.map((r, i) => <tr key={i}>
                        <td style={{ fontWeight: 600 }}>{r.source_label}</td>
                        <td style={{ textAlign: 'right' }}>{r.customers_count}</td>
                        <td style={{ textAlign: 'right' }}>{r.surveys_count}</td>
                        <td>{r.is_active ? <span className="badge badge-success">Active</span> : <span className="badge badge-muted">Inactive</span>}</td>
                      </tr>)}</tbody>
                </table>
              )}
              {tab === 'r_tiktok' && (
                <>
                  <SettlementSummary
                    storeId={null}
                    year={ttMonth.year}
                    month={ttMonth.month}
                    onChangeMonth={(year, month) => setTtMonth({ year, month })}
                  />
                  <h3 style={{ fontSize: 14, margin: '22px 0 4px' }}>Imported source totals (all periods)</h3>
                  <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 8 }}>
                    TikTok's own figures as imported, across every period — shown for reconciliation,
                    not as the reporting-month result.
                  </p>
                  {ttSummary && (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 12, marginBottom: 16 }}>
                      <div className="card" style={{ padding: 14 }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Total Settlement (main)</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(Number(ttSummary.total_settlement ?? 0))}</div>
                      </div>
                      <div className="card" style={{ padding: 14 }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Total Revenue</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(Number(ttSummary.total_revenue ?? 0))}</div>
                      </div>
                      <div className="card" style={{ padding: 14 }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Total Fees</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(Number(ttSummary.total_fees ?? 0))}</div>
                      </div>
                      <div className="card" style={{ padding: 14 }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Adjustments</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(Number(ttSummary.total_adjustments ?? 0))}</div>
                      </div>
                      <div className="card" style={{ padding: 14 }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Refunds</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(Number(ttSummary.total_refunds ?? 0))}</div>
                      </div>
                      <div className="card" style={{ padding: 14, borderLeft: Number(ttSummary.pending_count) > 0 ? '3px solid var(--warning, #d97706)' : undefined }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Pending order match</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{ttSummary.pending_count ?? 0}</div>
                      </div>
                      <div className="card" style={{ padding: 14, borderLeft: Number(ttSummary.unreconciled_count) > 0 ? '3px solid var(--danger)' : undefined }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Reconciliation warnings</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)', color: Number(ttSummary.unreconciled_count) > 0 ? 'var(--danger)' : 'inherit' }}>{ttSummary.unreconciled_count ?? 0}</div>
                      </div>
                    </div>
                  )}
                  <table>
                    <thead><tr><th>Date</th><th>Order/Adj ID</th><th>Type</th><th>Store</th><th>Match</th><th style={{ textAlign: 'right' }}>Settlement</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th><th>Reconciled</th></tr></thead>
                    <tbody>{ttRows.length === 0 ? <tr><td colSpan={9} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No settlement data</td></tr>
                      : ttRows.map((r, i) => <tr key={i}>
                          <td style={{ fontSize: 12 }}>{r.financial_date ? new Date(r.financial_date).toLocaleDateString('en-GB') : '—'}</td>
                          <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.order_adjustment_id}{r.version_no > 1 ? ` (v${r.version_no})` : ''}</td>
                          <td style={{ fontSize: 12, textTransform: 'capitalize' }}>{r.txn_class}</td>
                          <td style={{ fontSize: 12 }}>{r.store_name}</td>
                          <td>{r.match_status === 'matched' ? <span className="badge badge-success">Matched</span> : <span className="badge badge-warning">Pending</span>}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.settlement_amount ?? 0))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.revenue_amount ?? 0))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.fee_amount ?? 0))}</td>
                          <td>{r.reconciled === false ? <span className="badge badge-danger">⚠ Off</span> : r.reconciled === true ? <span className="badge badge-success">OK</span> : <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>—</span>}</td>
                        </tr>)}</tbody>
                  </table>

                  <h3 style={{ fontSize: 14, margin: '18px 0 4px' }}>Settlement by Day (settled date, SGT)</h3>
                  <table>
                    <thead><tr><th>Day</th><th style={{ textAlign: 'right' }}>Txns</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th><th style={{ textAlign: 'right' }}>Expense</th><th style={{ textAlign: 'right' }}>Income</th><th style={{ textAlign: 'right' }}>TikTok settlement</th></tr></thead>
                    <tbody>{ttDaily.length === 0 ? <tr><td colSpan={7} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 20 }}>No data</td></tr>
                      : ttDaily.map((r, i) => <tr key={i}>
                          <td style={{ fontSize: 12 }}>{new Date(r.day).toLocaleDateString('en-GB')}</td>
                          <td style={{ textAlign: 'right' }}>{r.transactions}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.revenue))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.fees))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.expense ?? 0))}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.income ?? 0))}</td>
                          <td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{money(Number(r.settlement))}</td>
                        </tr>)}</tbody>
                  </table>

                  <h3 style={{ fontSize: 14, margin: '18px 0 4px' }}>Settlement by Store</h3>
                  <table>
                    <thead><tr><th>Store</th><th style={{ textAlign: 'right' }}>Txns</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th><th style={{ textAlign: 'right' }}>Expense</th><th style={{ textAlign: 'right' }}>Income</th><th style={{ textAlign: 'right' }}>TikTok settlement</th><th style={{ textAlign: 'right' }}>Pending</th><th style={{ textAlign: 'right' }}>⚠ Recon</th></tr></thead>
                    <tbody>{ttByStore.map((r, i) => <tr key={i}>
                        <td style={{ fontWeight: 600 }}>{r.store_name}</td>
                        <td style={{ textAlign: 'right' }}>{r.transactions}</td>
                        <td style={{ textAlign: 'right' }}>{money(Number(r.revenue))}</td>
                        <td style={{ textAlign: 'right' }}>{money(Number(r.fees))}</td>
                        <td style={{ textAlign: 'right' }}>{money(Number(r.expense ?? 0))}</td>
                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.income ?? 0))}</td>
                        <td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{money(Number(r.settlement))}</td>
                        <td style={{ textAlign: 'right' }}>{r.pending_count}</td>
                        <td style={{ textAlign: 'right', color: Number(r.unreconciled_count) > 0 ? 'var(--danger)' : 'inherit' }}>{r.unreconciled_count}</td>
                      </tr>)}</tbody>
                  </table>

                  <h3 style={{ fontSize: 14, margin: '18px 0 4px' }}>Quantity Sold (net of returns)</h3>
                  <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 8, lineHeight: 1.5 }}>
                    Operational, from the order lifecycle — not settlement. It counts units on orders,
                    which is a different question from money settled, and the two are <strong>not
                    expected to reconcile</strong>: an order can ship in one period and settle in another.
                  </p>
                  <table>
                    <thead><tr><th>Dimension</th><th>Item</th><th style={{ textAlign: 'right' }}>Orders</th><th style={{ textAlign: 'right' }}>Net Units</th></tr></thead>
                    <tbody>{ttQty.length === 0 ? <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 20 }}>No confirmed TikTok sales</td></tr>
                      : ttQty.map((r, i) => <tr key={i}>
                          <td style={{ fontSize: 12, textTransform: 'capitalize' }}>{r.dimension}</td>
                          <td style={{ fontWeight: 600, fontSize: 12.5 }}>{r.item_name}</td>
                          <td style={{ textAlign: 'right' }}>{r.orders}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700 }}>{r.net_units}</td>
                        </tr>)}</tbody>
                  </table>

                  <h3 style={{ fontSize: 14, margin: '18px 0 4px' }}>Orders by Status</h3>
                  <table>
                    <thead><tr><th>Status</th><th style={{ textAlign: 'right' }}>Order Items</th><th style={{ textAlign: 'right' }}>Net Deducted</th></tr></thead>
                    <tbody>{ttByStatus.map((r, i) => <tr key={i}>
                        <td style={{ fontSize: 12.5 }}>{r.order_status}</td>
                        <td style={{ textAlign: 'right' }}>{r.order_items}</td>
                        <td style={{ textAlign: 'right' }}>{r.net_deducted}</td>
                      </tr>)}</tbody>
                  </table>
                </>
              )}
              {tab === 'r_exchange_inv' && (
                <table>
                  <thead><tr><th>Exchange</th><th>Invoice</th><th>Store</th><th>Customer</th><th>Date</th><th style={{ textAlign: 'right' }}>Credit</th><th style={{ textAlign: 'right' }}>Replacement</th><th style={{ textAlign: 'right' }}>Top-up</th><th style={{ textAlign: 'right' }}>Non-refundable</th><th>FOC</th></tr></thead>
                  <tbody>{exchInv.length === 0 ? <tr><td colSpan={10} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No exchanges</td></tr>
                    : exchInv.map((r, i) => <tr key={i}>
                        <td style={{ fontWeight: 600 }}>{r.exchange_no}</td>
                        <td style={{ fontSize: 12 }}>{r.invoice_no ?? '—'}</td>
                        <td style={{ fontSize: 12 }}>{r.store_name}</td>
                        <td style={{ fontSize: 12 }}>{r.customer_name ?? '—'}</td>
                        <td style={{ fontSize: 12 }}>{new Date(r.created_at).toLocaleDateString('en-GB')}</td>
                        <td style={{ textAlign: 'right' }}>{money(Number(r.returned_credit))}</td>
                        <td style={{ textAlign: 'right' }}>{money(Number(r.replacement_total))}</td>
                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{Number(r.topup_amount) > 0 ? money(Number(r.topup_amount)) : '—'}</td>
                        <td style={{ textAlign: 'right', color: Number(r.nonrefundable_amount) > 0 ? 'var(--danger)' : 'inherit' }}>{Number(r.nonrefundable_amount) > 0 ? money(Number(r.nonrefundable_amount)) : '—'}</td>
                        <td>{r.is_foc ? <span className="badge badge-success">FOC {money(Number(r.foc_amount))}</span> : '—'}</td>
                      </tr>)}</tbody>
                </table>
              )}
              {tab === 'r_transfers' && (
                <>
                  <h3 style={{ fontSize: 14, margin: '0 0 4px' }}>Overdue In Transit (&gt; 7 days)</h3>
                  <table>
                    <thead><tr><th>From</th><th>To</th><th>Dispatched</th><th style={{ textAlign: 'right' }}>Days</th><th style={{ textAlign: 'right' }}>Lines</th><th style={{ textAlign: 'right' }}>Units</th></tr></thead>
                    <tbody>{trOverdue.length === 0 ? <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 20 }}>Nothing overdue</td></tr>
                      : trOverdue.map((r, i) => <tr key={i}>
                          <td style={{ fontSize: 12.5 }}>{r.source_name}</td><td style={{ fontSize: 12.5 }}>{r.dest_name}</td>
                          <td style={{ fontSize: 12 }}>{new Date(r.dispatched_at).toLocaleDateString('en-GB')}</td>
                          <td style={{ textAlign: 'right', color: 'var(--danger)', fontWeight: 700 }}>{r.days_in_transit}</td>
                          <td style={{ textAlign: 'right' }}>{r.line_count}</td>
                          <td style={{ textAlign: 'right' }}>{r.units_in_transit}</td>
                        </tr>)}</tbody>
                  </table>
                  <h3 style={{ fontSize: 14, margin: '18px 0 4px' }}>Receipts</h3>
                  <table>
                    <thead><tr><th>From</th><th>To</th><th>Received</th><th>By</th><th style={{ textAlign: 'right' }}>Units</th><th>Discrepancy</th></tr></thead>
                    <tbody>{trReceipts.length === 0 ? <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 20 }}>No receipts</td></tr>
                      : trReceipts.map((r, i) => <tr key={i}>
                          <td style={{ fontSize: 12.5 }}>{r.source_name}</td><td style={{ fontSize: 12.5 }}>{r.dest_name}</td>
                          <td style={{ fontSize: 12 }}>{new Date(r.received_at).toLocaleString()}</td>
                          <td style={{ fontSize: 12 }}>{r.received_by_name ?? '—'}</td>
                          <td style={{ textAlign: 'right' }}>{r.received_units}</td>
                          <td>{r.had_discrepancy
                            ? (r.discrepancy_resolved ? <span className="badge badge-muted">Resolved</span> : <span className="badge badge-danger">Open</span>)
                            : <span className="badge badge-success">Clean</span>}</td>
                        </tr>)}</tbody>
                  </table>
                  <h3 style={{ fontSize: 14, margin: '18px 0 4px' }}>Discrepancy Lines</h3>
                  <table>
                    <thead><tr><th>Destination</th><th>Product</th><th style={{ textAlign: 'right' }}>Approved</th><th style={{ textAlign: 'right' }}>Received</th><th style={{ textAlign: 'right' }}>Δ</th><th>Reason</th><th>Resolution</th></tr></thead>
                    <tbody>{trDisc.length === 0 ? <tr><td colSpan={7} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 20 }}>No discrepancies</td></tr>
                      : trDisc.map((r, i) => <tr key={i}>
                          <td style={{ fontSize: 12.5 }}>{r.dest_name}</td>
                          <td style={{ fontSize: 12.5 }}>{r.product_name}</td>
                          <td style={{ textAlign: 'right' }}>{r.approved_quantity}</td>
                          <td style={{ textAlign: 'right' }}>{r.received_quantity}</td>
                          <td style={{ textAlign: 'right', color: 'var(--danger)', fontWeight: 700 }}>{r.discrepancy}</td>
                          <td style={{ fontSize: 12 }}>{r.discrepancy_reason ?? '—'}</td>
                          <td style={{ fontSize: 12 }}>{r.resolution ?? <span className="badge badge-danger">Open</span>}</td>
                        </tr>)}</tbody>
                  </table>
                </>
              )}
              {tab === 'r_salesrecon' && (
                <>
                  <p style={{ fontSize: 12.5, color: 'var(--text-muted)', marginBottom: 8 }}>
                    Three disjoint channels — normal invoices exclude exchange invoices, and TikTok sales never create invoices — so nothing is double-counted.
                  </p>
                  <table>
                    <thead><tr><th>Channel</th><th style={{ textAlign: 'right' }}>Transactions</th><th style={{ textAlign: 'right' }}>Amount</th></tr></thead>
                    <tbody>{salesRecon.map((r, i) => <tr key={i}>
                        <td style={{ fontWeight: 600, textTransform: 'capitalize' }}>{String(r.channel).replace(/_/g, ' ')}</td>
                        <td style={{ textAlign: 'right' }}>{r.transactions}</td>
                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.amount))}</td>
                      </tr>)}
                      <tr><td><strong>Total</strong></td>
                        <td style={{ textAlign: 'right' }}><strong>{salesRecon.reduce((a, r) => a + Number(r.transactions), 0)}</strong></td>
                        <td style={{ textAlign: 'right' }}><strong>{money(salesRecon.reduce((a, r) => a + Number(r.amount), 0))}</strong></td></tr>
                    </tbody>
                  </table>
                </>
              )}
              {tab === 'r_foc' && (
                <>
                  {focSummary && (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 12, marginBottom: 16 }}>
                      <div className="card" style={{ padding: 14 }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Normal value</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(Number(focSummary.normal_value ?? 0))}</div>
                      </div>
                      <div className="card" style={{ padding: 14 }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>FOC value given</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)', color: 'var(--success)' }}>{money(Number(focSummary.foc_value ?? 0))}</div>
                      </div>
                      <div className="card" style={{ padding: 14 }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Charged value</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{money(Number(focSummary.charged_value ?? 0))}</div>
                      </div>
                      <div className="card" style={{ padding: 14 }}>
                        <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>FOC invoices</div>
                        <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{Number(focSummary.full_foc_invoices ?? 0)} full · {Number(focSummary.mixed_foc_invoices ?? 0)} mixed</div>
                      </div>
                    </div>
                  )}
                  <table>
                    <thead><tr><th>Invoice</th><th>Business date</th><th>Customer</th><th>Kind</th><th>Item</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>FOC Qty</th><th style={{ textAlign: 'right' }}>Normal</th><th style={{ textAlign: 'right' }}>FOC</th><th style={{ textAlign: 'right' }}>Charged</th><th>Reason</th><th>By</th></tr></thead>
                    <tbody>{repFoc.length === 0 ? <tr><td colSpan={12} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No FOC in this period</td></tr>
                      : repFoc.map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{r.settled_at ? singaporeDate(r.settled_at).split('-').reverse().join('/') : 'Date pending review'}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td><td style={{ fontSize: 12 }}>{r.line_kind}</td><td style={{ fontSize: 12 }}>{r.description}</td><td style={{ textAlign: 'right' }}>{r.quantity}</td><td style={{ textAlign: 'right', fontWeight: 600 }}>{r.foc_quantity}</td><td style={{ textAlign: 'right' }}>{money(Number(r.normal_value))}</td><td style={{ textAlign: 'right', color: 'var(--success)', fontWeight: 700 }}>{money(Number(r.foc_value))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.charged_value))}</td><td style={{ fontSize: 11.5 }}>{r.foc_reason ?? '—'}</td><td style={{ fontSize: 11.5 }}>{r.foc_by_name ?? '—'}</td></tr>)}</tbody>
                  </table>
                </>
              )}
              {tab === 'r_discounts' && (
                <table>
                  <thead><tr><th>Invoice</th><th>Business date</th><th>Store</th><th>Staff</th><th>Customer</th><th style={{ textAlign: 'right' }}>Save Earth</th><th style={{ textAlign: 'right' }}>Voucher</th><th style={{ textAlign: 'right' }}>Promotion</th><th style={{ textAlign: 'right' }}>Line</th><th style={{ textAlign: 'right' }}>Manual</th><th style={{ textAlign: 'right' }}>Total</th></tr></thead>
                  <tbody>{repDiscounts.length === 0 ? <tr><td colSpan={11} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No discounts</td></tr>
                    : repDiscounts.map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{r.paid_date ? r.paid_date.split('-').reverse().join('/') : 'Date pending review'}</td><td style={{ fontSize: 12 }}>{r.store_name}</td><td style={{ fontSize: 12 }}>{r.staff_names ?? '—'}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td><td style={{ textAlign: 'right' }}>{money(Number(r.save_earth))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.voucher_discount))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.promotion_discount))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.line_discount))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.manual_discount))}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.total_discount))}</td></tr>)}</tbody>
                </table>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default ReportsPage;
