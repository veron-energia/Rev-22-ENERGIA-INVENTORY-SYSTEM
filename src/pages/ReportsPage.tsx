import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { SettlementSummary, currentSgtMonth } from '../components/tiktok/SettlementSummary';
import { periodLabel, settlementPeriod, toIsoDate } from '../lib/tiktok/settlementPeriod.mjs';
import { useAuth } from '../context/AuthContext';
import {
  Invoice, Store, Product, Commission, Customer,
  WarehouseInventory, StoreInventory, Warehouse, isManagerOrAbove,
} from '../types';
import { NoAccess } from '../components/ui';
import { RefreshCw, BarChart3, TrendingUp, Package, Star, Users, Download, Ticket, Package2, KeyRound, UserCircle, Award, CreditCard, Sparkles, Gift, PartyPopper } from 'lucide-react';
import { SearchSelect } from '../components/SearchSelect';
import { MiniBarChart } from '../components/MiniBarChart';
import { ExcelExportButton, ExcelColumn } from '../components/ExcelExport';
import { singaporeToday } from '../lib/invoices/business';

const money = (n: number) => `S$${n.toFixed(2)}`;
// Money as an Excel number, to the cent, so a sheet never shows float residue.
const cents = (n: number) => Math.round(Number(n ?? 0) * 100) / 100;
// A date-only value (YYYY-MM-DD) shown as dd/mm/yyyy straight from the string.
// Parsed as a Date it becomes UTC midnight, a day early west of UTC.
const dateOnly = (d: string | null | undefined) => d ? String(d).slice(0, 10).split('-').reverse().join('/') : '—';
const time = (v: string | null | undefined) => v ? new Date(v).getTime() : 0;

// Each invoice's line discounts by type (owner, 3 Oct 2026), as
// report_discounts returns them since 384: Vouchers, Birthday, Staff,
// Manual and Percentage. A line saved before 384 with a voucher counts under
// that voucher's category; a line discount with neither is exchange credit,
// kept apart. The invoice-level manual discount and Discount Voucher keep
// their own columns. FOC has its own report.
const DISCOUNT_COLUMNS: { header: string; value: (r: any) => number }[] = [
  { header: 'Vouchers', value: r => Number(r.line_voucher_discount ?? 0) },
  { header: 'Birthday', value: r => Number(r.birthday_discount ?? 0) },
  { header: 'Staff discount', value: r => Number(r.staff_discount ?? 0) },
  { header: 'Manual (line)', value: r => Number(r.line_manual_discount ?? 0) },
  { header: 'Percentage', value: r => Number(r.line_percentage_discount ?? 0) },
  { header: 'Manual (invoice)', value: r => Number(r.manual_discount ?? 0) },
  { header: 'Invoice voucher', value: r => Number(r.voucher_discount ?? 0) },
  { header: 'Exchange credit', value: r => Number(r.exchange_credit ?? 0) },
  { header: 'Save Earth', value: r => Number(r.save_earth ?? 0) },
];

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

type ReportLoad<T> = { data: T; loading: boolean; error: string };
const NO_ROWS: any[] = [];

// A report loaded on its own, apart from the invoice records: its failure shows
// where it is used — never as an empty table, and never blanking the reports
// that do not use it. `key` names what was asked for (period, month, Refresh
// count); until the answer for the current key arrives the report counts as
// loading, so a table never says "nothing" while its data is on the way.
// Nothing is fetched while `enabled` is false (a tab that is not open).
function useReportLoad<T>(enabled: boolean, key: string, load: () => Promise<T>, empty: T): ReportLoad<T> {
  const [state, setState] = useState<{ key: string | null; data: T; error: string }>({ key: null, data: empty, error: '' });
  const loadedKey = state.key;
  useEffect(() => {
    if (!enabled || loadedKey === key) return;
    let cancelled = false;
    load().then(data => { if (!cancelled) setState({ key, data, error: '' }); },
      (error: any) => { if (!cancelled) setState({ key, data: empty, error: error?.message || 'Unable to load this report.' }); });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, key]);
  const current = state.key === key;
  return { data: current ? state.data : empty, loading: enabled && !current, error: current ? state.error : '' };
}

// TikTok returns a settlement row with no settled date first, then newest first,
// as report_tiktok_settlement orders them; paging by id would lose that order.
const newestSettledFirst = (a: any, b: any) =>
  (a.financial_date ? 1 : 0) - (b.financial_date ? 1 : 0)
  || String(b.financial_date ?? '').localeCompare(String(a.financial_date ?? ''))
  || String(a.order_adjustment_id ?? '').localeCompare(String(b.order_adjustment_id ?? ''));

type Tab = 'sales_store' | 'sales_affiliate' | 'commission' | 'stock' | 'top_products' | 'customers' | 'vouchers' | 'promotions' | 'specials' | 'sales_creator' | 'sales_service_staff' | 'r_pricing' | 'r_affiliate' | 'r_therapy' | 'r_discounts' | 'r_foc' | 'r_sources' | 'r_tiktok' | 'r_exchange_inv' | 'r_transfers' | 'r_salesrecon' | 'r_events';

// The tabs whose figures are invoice sales for the selected period; the
// headline cards belong to these only.
const INVOICE_SALES_TABS: Tab[] = ['sales_store', 'top_products', 'sales_creator', 'sales_service_staff', 'sales_affiliate',
  'vouchers', 'promotions', 'specials', 'customers', 'r_salesrecon'];
// Tabs that do not use the invoice records, so a failure there never blanks them.
const SEPARATE_TABS: Tab[] = ['r_affiliate', 'r_therapy', 'r_sources', 'r_tiktok', 'r_exchange_inv', 'r_transfers', 'r_events'];
// One line for each tab that does not simply follow the Period filter.
const PERIOD_NOTE: Partial<Record<Tab, string>> = {
  commission: 'Lifetime figures: the Period filter does not apply to this report.',
  r_affiliate: 'Lifetime figures: the Period filter does not apply to this report.',
  r_therapy: 'All therapy packages: the Period filter does not apply to this report.',
  stock: 'Current stock position: the Period filter does not apply. Stock held under deleted products is not counted, as on the inventory pages.',
  r_tiktok: 'Uses the reporting month chosen below, not the Period filter. Tables marked "all periods" cover every import.',
  r_transfers: 'Receipts follow the Period filter (received date, SGT). Overdue transfers and discrepancy lines are the current position.',
  r_sources: 'Surveys follow the Period filter (submitted date, SGT). Customers are counted by their current source, whatever the period.',
  r_events: 'Events with a day in the Period. Tickets count whenever they were bought; cancelled and refunded invoices are left out.',
};

type TableExport = { rows: any[]; columns: ExcelColumn<any>[]; sheet: string; name?: string };

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
  // Bumped by Refresh, so every separately loaded report is fetched again too.
  const [refreshKey, setRefreshKey] = useState(0);

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
  const [specialSales, setSpecialSales] = useState<any[]>([]);
  const [rentals, setRentals] = useState<any[]>([]);
  const [specialProducts, setSpecialProducts] = useState<any[]>([]);
  const [profiles, setProfiles] = useState<any[]>([]);
  // Sales by Service Staff, computed on the server (358) so it reconciles to
  // revenue to the cent and credits invoices with no "Served by" to their creator.
  const [staffSales, setStaffSales] = useState<any>(null);
  const [staffLoading, setStaffLoading] = useState(false);
  const [repPricing, setRepPricing] = useState<any[]>([]);
  const [repDiscounts, setRepDiscounts] = useState<any[]>([]);
  const [repFoc, setRepFoc] = useState<any[]>([]);
  // The payment report is on the SETTLED-date basis only; the order-created
  // basis was removed in migration 210 because a period struck on it can never
  // tie to what TikTok actually paid.
  const [ttMonth, setTtMonth] = useState(() => currentSgtMonth());
  const [salesRecon, setSalesRecon] = useState<any[]>([]);
  const [focSummary, setFocSummary] = useState<any>(null);

  const [salesError, setSalesError] = useState('');
  // Whether the invoice records have loaded at least once, so the headline and
  // cards never show S$0.00 before there is anything to count.
  const [coreLoaded, setCoreLoaded] = useState(false);
  const [periodError, setPeriodError] = useState('');
  const [periodLoading, setPeriodLoading] = useState(true);
  const [salesEvents, setSalesEvents] = useState<SalesEvent[]>([]);
  const [refunds, setRefunds] = useState<any[]>([]);
  // The invoice records every sales report is built from: all or nothing, so a
  // partial set can never pass for a complete total.
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [inv, st, pr, co, cu, wh, wi, si, it, vc, pm, ss, re, sp, prof, rf, events] = await Promise.all([
        fetchReportRows(() => supabase.from('invoices').select('*').is('deleted_at', null)),
        fetchReportRows(() => supabase.from('stores').select('*')),
        fetchReportRows(() => supabase.from('products').select('*')),
        fetchReportRows(() => supabase.from('commissions').select('*')),
        fetchReportRows(() => supabase.from('customers').select('*')),
        fetchReportRows(() => supabase.from('warehouses').select('*')),
        fetchReportRows(() => supabase.from('warehouse_inventory').select('*')),
        fetchReportRows(() => supabase.from('store_inventory').select('*')),
        fetchReportRows(() => supabase.from('invoice_items').select('id,product_id,special_product_id,quantity,line_total,line_discount,invoice_id,line_kind,voucher_id,promotion_id,topup_amount,line_voucher_id')),
        fetchReportRows(() => supabase.from('vouchers').select('*')),
        fetchReportRows(() => supabase.from('promotions').select('*')),
        fetchReportRows(() => supabase.from('special_sales').select('*')),
        fetchReportRows(() => supabase.from('rentals').select('*')),
        fetchReportRows(() => supabase.from('special_products').select('*')),
        fetchReportRows(() => supabase.from('profiles').select('id,full_name,role')),
        fetchReportRows(() => supabase.from('invoice_refunds').select('id,invoice_id,request_id,amount,credit_returned,outcome')),
        fetchReportRows(() => supabase.rpc('invoice_sales_ledger'), ['sales_date', 'event_id']),
      ]);
      setInvoices(inv as Invoice[]); setStores(st as Store[]); setProducts(pr as Product[]);
      setCommissions(co as Commission[]); setCustomers(cu as Customer[]); setWarehouses(wh as Warehouse[]);
      setWhInv(wi as WarehouseInventory[]); setStInv(si as StoreInventory[]); setItems(it);
      setVouchers(vc); setPromotions(pm); setSpecialSales(ss); setRentals(re);
      setSpecialProducts(sp); setProfiles(prof); setRefunds(rf); setSalesEvents(events as SalesEvent[]);
      setSalesError(''); setCoreLoaded(true);
    } catch (error: any) {
      setSalesError(error.message || 'Unable to load all report records.');
    } finally { setLoading(false); }
  }, []);
  useEffect(() => { load(); }, [load]);
  const refresh = () => { load(); setRefreshKey(k => k + 1); };

  // Reports loaded apart from the invoice records, each with its own error,
  // shown on the tab that uses it.
  const affiliatesLoad = useReportLoad(true, String(refreshKey), async () =>
    // Paged by id, then by name as report_affiliates orders them.
    (await fetchReportRows(() => supabase.rpc('report_affiliates'), ['customer_id']))
      .sort((a, b) => String(a.customer_name ?? '').localeCompare(String(b.customer_name ?? ''))), NO_ROWS);
  const therapyLoad = useReportLoad(true, String(refreshKey), () =>
    fetchReportRows(() => supabase.rpc('report_therapy'), ['entitlement_no', 'customer_name']), NO_ROWS);
  // A handful of rows, fetched without a paging key so the owner's configured
  // option order (sort_order) is kept.
  const sourcesLoad = useReportLoad(true, `${refreshKey}|${dFrom}|${dTo}`, () =>
    fetchReportRows(() => supabase.rpc('report_customer_sources', { p_from: dFrom || null, p_to: dTo || null }), []), NO_ROWS);
  // Phase 17 — TikTok settlement, all periods.
  const ttSummaryLoad = useReportLoad<any>(true, String(refreshKey), async () =>
    (await fetchReportRows(() => supabase.rpc('report_tiktok_settlement_summary', { p_store_id: null, p_from: null, p_to: null }), ['total_settlement']))[0] ?? null, null);
  const ttRowsLoad = useReportLoad(true, String(refreshKey), async () =>
    (await fetchReportRows(() => supabase.rpc('report_tiktok_settlement', { p_store_id: null, p_from: null, p_to: null }), ['row_id'])).sort(newestSettledFirst), NO_ROWS);

  // Phase 18 — extended reports, fetched when their tab opens. The TikTok day
  // and store tables cover the chosen reporting month: the same settled-date
  // range (SGT) as the month's cards above them.
  const ttPeriod = settlementPeriod(ttMonth.year, ttMonth.month);
  const ttFrom = toIsoDate(ttPeriod.start), ttTo = toIsoDate(ttPeriod.end);
  const onTikTok = tab === 'r_tiktok', onTransfers = tab === 'r_transfers';
  const ttDailyLoad = useReportLoad(onTikTok, `${refreshKey}|${ttFrom}|${ttTo}`, () =>
    fetchReportRows(() => supabase.rpc('report_tiktok_settlement_daily', { p_store_id: null, p_from: ttFrom, p_to: ttTo }), ['day']), NO_ROWS);
  const ttByStoreLoad = useReportLoad(onTikTok, `${refreshKey}|${ttFrom}|${ttTo}`, () =>
    fetchReportRows(() => supabase.rpc('report_tiktok_settlement_by_store', { p_from: ttFrom, p_to: ttTo }), ['store_name']), NO_ROWS);
  const ttQtyLoad = useReportLoad(onTikTok, String(refreshKey), async () =>
    (await fetchReportRows(() => supabase.rpc('report_tiktok_qty_sold', { p_store_id: null, p_from: null, p_to: null }), ['dimension', 'item_key']))
      .sort((a, b) => String(a.dimension).localeCompare(String(b.dimension)) || Number(b.net_units) - Number(a.net_units)), NO_ROWS);
  const ttStatusLoad = useReportLoad(onTikTok, String(refreshKey), async () =>
    (await fetchReportRows(() => supabase.rpc('report_tiktok_orders_by_status', { p_store_id: null }), ['order_status']))
      .sort((a, b) => Number(b.order_items) - Number(a.order_items)), NO_ROWS);
  // One entry per event: its days, tickets by option, and event sales by store (370).
  const eventsLoad = useReportLoad(tab === 'r_events', `${refreshKey}|${dFrom}|${dTo}`, async () => {
    const { data, error } = await supabase.rpc('report_events', { p_from: dFrom || null, p_to: dTo || null });
    if (error) throw error;
    return (data as any[]) ?? [];
  }, NO_ROWS);
  const exchLoad = useReportLoad(tab === 'r_exchange_inv', `${refreshKey}|${dFrom}|${dTo}`, async () =>
    (await fetchReportRows(() => supabase.rpc('report_exchange_invoices', { p_store_id: null, p_from: dFrom || null, p_to: dTo || null }), ['exchange_id']))
      .sort((a, b) => time(b.created_at) - time(a.created_at)), NO_ROWS);
  const trOverdueLoad = useReportLoad(onTransfers, String(refreshKey), async () =>
    (await fetchReportRows(() => supabase.rpc('report_transfers_overdue', { p_days: 7 }), ['transfer_id']))
      .sort((a, b) => time(a.dispatched_at) - time(b.dispatched_at)), NO_ROWS);
  const trReceiptsLoad = useReportLoad(onTransfers, `${refreshKey}|${dFrom}|${dTo}`, async () =>
    (await fetchReportRows(() => supabase.rpc('report_transfer_receipts', { p_from: dFrom || null, p_to: dTo || null }), ['transfer_id']))
      .sort((a, b) => time(b.received_at) - time(a.received_at)), NO_ROWS);
  // Newest receipt first, lines not yet received last — the function's own
  // order, which the paging sort replaces.
  const trDiscLoad = useReportLoad(onTransfers, String(refreshKey), async () =>
    (await fetchReportRows(() => supabase.rpc('report_transfer_discrepancies'), ['transfer_id', 'product_id', 'product_name', 'approved_quantity', 'received_quantity']))
      .sort((a, b) => (b.received_at ? time(b.received_at) : -Infinity) - (a.received_at ? time(a.received_at) : -Infinity)), NO_ROWS);
  const repAffiliate = affiliatesLoad.data, repTherapy = therapyLoad.data, repSources = sourcesLoad.data;
  const ttSummary = ttSummaryLoad.data, ttRows = ttRowsLoad.data;

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
      // Sales by Service Staff loads on its own: a failure in it never blanks the
      // other period reports, and a failure in them never blanks it.
      setStaffLoading(true);
      supabase.rpc('report_sales_by_service_staff', { p_from: dFrom || null, p_to: dTo || null, p_store_id: null })
        .then(r => { if (!cancelled) setStaffSales(r.error ? { error: r.error.message } : r.data); },
              (e: any) => { if (!cancelled) setStaffSales({ error: e?.message || 'Unable to load the selected period.' }); })
        .then(() => { if (!cancelled) setStaffLoading(false); });
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

  // Lookups by id, so no report scans a whole list for every row. Everything
  // derived below is memoised on its data and the period: switching tabs
  // recomputes nothing.
  const productById = useMemo(() => new Map(products.map(p => [p.id, p])), [products]);
  const customerById = useMemo(() => new Map(customers.map(c => [c.id, c])), [customers]);
  const staffNameById = useMemo(() => new Map(profiles.map(p => [p.id, p.full_name])), [profiles]);
  const invoiceById = useMemo(() => new Map(invoices.map(i => [i.id, i])), [invoices]);

  // Actual eligible receipts on the day the money was received (SGT); refund
  // reductions on their refund dates. Invoice totals are never substituted for
  // received money.
  const basis = useMemo(() => {
    const periodEvents = salesEvents.filter(e => (!dFrom || e.sales_date >= dFrom) && (!dTo || e.sales_date <= dTo));
    const recognized = new Map<string, number>();
    const receiptTotals = new Map<string, number>();
    for (const e of periodEvents) {
      recognized.set(e.invoice_id, (recognized.get(e.invoice_id) ?? 0) + Number(e.amount));
      if (e.event_kind !== 'refund') receiptTotals.set(e.invoice_id, (receiptTotals.get(e.invoice_id) ?? 0) + Number(e.amount));
    }
    const receiptInvoiceIds = new Set([...receiptTotals].filter(([, amount]) => amount > 0).map(([id]) => id));
    const paid = invoices.filter(i => recognized.has(i.id)).map(i => ({ ...i, total_amount: recognized.get(i.id)! }));
    return { recognized, receiptInvoiceIds, paid, paidIds: new Set(paid.map(i => i.id)), lineSales: buildLineSales(items, periodEvents, refunds) };
  }, [salesEvents, invoices, items, refunds, dFrom, dTo]);
  const { recognized, receiptInvoiceIds, paid, paidIds, lineSales } = basis;
  const lineRevenue = (it: any) => lineSales.byLine.get(it.id) ?? 0;
  const invoicedQuantity = (it: any) => receiptInvoiceIds.has(it.invoice_id) ? Number(it.quantity) : 0;
  const unallocatedAmount = lineSales.unallocated.reduce((sum, e) => sum + e.amount, 0);
  const inPeriod = (date: string | null | undefined) => !!date && (!dFrom || date >= dFrom) && (!dTo || date <= dTo);
  const singaporeDate = (value: string | null | undefined) => value
    ? new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(value)) : '';
  const pName = (id: string) => productById.get(id)?.name ?? '—';
  // A referrer or buyer the customers table no longer returns has been deleted.
  const cName = (id: string) => customerById.get(id)?.full_name ?? 'Deleted customer';

  // Sales by store
  const salesByStore = useMemo(() => stores.map(s => {
    const sInv = paid.filter(i => i.store_id === s.id);
    return { name: s.name, count: sInv.length, total: sInv.reduce((a, i) => a + Number(i.total_amount), 0) };
  }).filter(r => r.count > 0).sort((a, b) => b.total - a.total), [stores, paid]);

  // Sales by referrer (from the two-tier commission model): Tier-1 rows carry
  // the after-discount commissionable value of each referred paid invoice line.
  const referrerIds = useMemo(() => Array.from(new Set(commissions.map(c => c.referrer_customer_id))), [commissions]);
  const salesByReferrer = useMemo(() => referrerIds.map(rid => {
    const t1 = commissions.filter(c => c.referrer_customer_id === rid && c.tier === 'tier1' && (c.status === 'earned' || c.status === 'paid'));
    const attributed = Array.from(new Set(t1.map(c => c.invoice_id))).filter(id =>
      t1.filter(c => c.invoice_id === id).reduce((sum, c) => sum + Number(c.commission_amount), 0) > 0 && recognized.has(id));
    const invoiceCount = attributed.length;
    const salesValue = attributed.reduce((sum, id) => sum + (recognized.get(id) ?? 0), 0);
    // The tier-1 commission on exactly the invoices counted in this row, so the
    // column follows the period like the sales beside it.
    const listed = new Set(attributed);
    const commission = t1.filter(c => listed.has(c.invoice_id)).reduce((s, c) => s + Number(c.commission_amount), 0);
    return { name: cName(rid), count: invoiceCount, total: salesValue, commission };
  }).filter(r => r.count > 0).sort((a, b) => b.total - a.total),
  [referrerIds, commissions, recognized, customerById]);

  // Commission report by referrer (earned incl. paid-out; reversed separate).
  //
  // "Paid Out" is the money that actually left, and it is NOT the sum of the
  // commissions marked paid. A payout may settle part of a commission —
  // affiliate_payout_save allocates `least(remaining, available)` and then sets
  // the whole row to 'paid' — so counting commission_amount for every paid row
  // reported a S$100 commission with S$20 allocated as S$100 paid out.
  //
  // report_affiliates() is already loaded above and answers this from the
  // payout records themselves (`sum(total_amount) from commission_payouts
  // where status = 'paid'`), which is the same basis the Commissions page and
  // the payout panel use. The two screens used to disagree; now they do not.
  //
  // "Outstanding" is what is still owed: earned less paid out, the basis
  // affiliate_month_balances uses.
  const commissionRows = useMemo(() => {
    const paidByCustomer = new Map<string, number>(
      (repAffiliate ?? []).map((a: any) => [String(a.customer_id), Number(a.paid ?? 0)]),
    );
    return referrerIds.map(rid => {
      const rc = commissions.filter(c => c.referrer_customer_id === rid);
      const earned = rc.filter(c => c.status === 'earned' || c.status === 'paid').reduce((s, c) => s + Number(c.commission_amount), 0);
      const paidOut = paidByCustomer.get(String(rid)) ?? 0;
      const reversed = rc.filter(c => c.status === 'reversed').reduce((s, c) => s + Number(c.commission_amount), 0);
      return { name: cName(rid), earned, paidOut, reversed, outstanding: earned - paidOut };
    }).filter(r => r.earned > 0 || r.reversed > 0).sort((a, b) => b.earned - a.earned);
  }, [referrerIds, commissions, repAffiliate, customerById]);

  // Top products (by qty sold across paid invoices)
  const topProducts = useMemo(() => {
    const prodAgg: Record<string, { qty: number; revenue: number }> = {};
    items.filter(it => it.product_id && paidIds.has(it.invoice_id)).forEach(it => {
      (prodAgg[it.product_id] ??= { qty: 0, revenue: 0 });
      prodAgg[it.product_id].qty += invoicedQuantity(it);
      prodAgg[it.product_id].revenue += lineRevenue(it);
    });
    return Object.entries(prodAgg).map(([id, v]) => ({ name: pName(id), ...v })).sort((a, b) => b.qty - a.qty);
  }, [items, basis, productById]);

  // Customers report: built from the recognized invoices themselves, grouped by
  // customer, so its total is always the Revenue card's less walk-in sales. A
  // customer deleted since is still listed, as 'Deleted customer': the
  // customers table no longer returns them, but their sales still count.
  const genderLabel = (c: any) => c.gender === 'other' ? (c.gender_other || 'Other') : c.gender ? (c.gender.charAt(0).toUpperCase() + c.gender.slice(1)) : '';
  const custRows = useMemo(() => {
    const byCustomer = new Map<string, { count: number; total: number }>();
    for (const i of paid) {
      if (!i.customer_id) continue;
      const g = byCustomer.get(i.customer_id) ?? { count: 0, total: 0 };
      g.count += 1; g.total += Number(i.total_amount); byCustomer.set(i.customer_id, g);
    }
    return Array.from(byCustomer, ([id, g]) => {
      const c: any = customerById.get(id);
      return { name: c?.full_name ?? 'Deleted customer', phone: c?.phone ?? '', dob: c?.date_of_birth ?? '', gender: c ? genderLabel(c) : '', occupation: c?.occupation ?? '', count: g.count, total: g.total };
    }).sort((a, b) => b.total - a.total);
  }, [paid, customerById]);

  const staffPName = (id: string) => staffNameById.get(id) ?? '—';

  // Sales by invoice creator (created_by).
  const salesByCreator = useMemo(() => {
    const map = new Map<string, { name: string; count: number; total: number }>();
    paid.forEach(i => {
      const id = (i as any).created_by; if (!id) return;
      const g = map.get(id) ?? { name: staffPName(id), count: 0, total: 0 };
      g.count += 1; g.total += Number(i.total_amount); map.set(id, g);
    });
    return Array.from(map.values()).filter(r => r.count > 0).sort((a, b) => b.total - a.total);
  }, [paid, staffNameById]);

  // Sales by service staff: one row per person from report_sales_by_service_staff.
  const salesByServiceStaff: any[] = useMemo(() => ((staffSales?.rows as any[]) ?? []).map(r => ({
    name: r.staff_name ?? '—', is_active: r.is_active !== false,
    invoices: Number(r.invoices_served), shared: Number(r.shared_sales),
    as_creator: Number(r.credited_as_creator), moved_in: Number(r.backfilled_in),
    fullTotal: Number(r.receipts_on_invoices_served),
  })), [staffSales]);

  const totalRevenue = useMemo(() => paid.reduce((s, i) => s + Number(i.total_amount), 0), [paid]);
  const coreReady = coreLoaded && !salesError;

  // Grouping shown as a sublabel in the picker, so 22 reports are findable.
  const REPORT_GROUP: Record<string, string> = {
    sales_store: 'Sales', top_products: 'Sales', sales_creator: 'Sales',
    sales_service_staff: 'Sales', sales_affiliate: 'Sales', r_tiktok: 'Sales',
    r_salesrecon: 'Sales', r_events: 'Sales',
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
    { id: 'r_events', label: 'Events', icon: <PartyPopper size={15} /> },
  ];

  // 5G-2: voucher / promotion / special reports (paid invoices only). A voucher,
  // promotion or special product since removed from the catalogue keeps its
  // sales, under a 'Deleted …' name, rather than silently dropping out.
  //
  // Voucher uses are read from the sale invoices themselves: each line redeemed
  // with the voucher (its line discount), and each invoice given the voucher as
  // an invoice-level discount — on invoices with receipts in the period. Not
  // from voucher_redemptions, which is written as a side effect of full payment
  // and is not a complete record.
  const voucherRows = useMemo(() => {
    const voucherById = new Map(vouchers.map(v => [v.id, v]));
    const rows = new Map<string, { sold_qty: number; sales_value: number; redemptions: number; discount_given: number }>();
    const row = (id: string) => {
      if (!rows.has(id)) rows.set(id, { sold_qty: 0, sales_value: 0, redemptions: 0, discount_given: 0 });
      return rows.get(id)!;
    };
    const counted = (invoiceId: string) => paidIds.has(invoiceId) && receiptInvoiceIds.has(invoiceId);
    const lineDiscounts = new Map<string, number>();
    for (const it of items) {
      lineDiscounts.set(it.invoice_id, (lineDiscounts.get(it.invoice_id) ?? 0) + Number(it.line_discount || 0));
      if (it.line_kind === 'voucher' && it.voucher_id && paidIds.has(it.invoice_id)) {
        const r = row(it.voucher_id);
        r.sold_qty += invoicedQuantity(it); r.sales_value += lineRevenue(it);
      }
      if (it.line_voucher_id && counted(it.invoice_id)) {
        const r = row(it.line_voucher_id);
        r.redemptions += 1; r.discount_given += Number(it.line_discount || 0);
      }
    }
    for (const id of paidIds) {
      const inv: any = invoiceById.get(id);
      if (!inv?.discount_voucher_id || !counted(id)) continue;
      // The invoice-level voucher amount, read from the invoice as the Discounts
      // report does (366): the discount total less the manual, Save Earth and
      // line discounts, never below zero.
      const amount = Math.max(Math.round((Number(inv.discount_total || 0) - Number(inv.manual_discount || 0)
        - (inv.save_earth_applied ? Number(inv.save_earth_amount || 0) : 0) - (lineDiscounts.get(id) ?? 0)) * 100) / 100, 0);
      const r = row(inv.discount_voucher_id);
      r.redemptions += 1; r.discount_given += amount;
    }
    return Array.from(rows, ([id, r]) => ({
      name: voucherById.get(id)?.name ?? 'Deleted voucher', kind: voucherById.get(id)?.voucher_kind ?? '—', ...r,
    })).filter(r => r.sold_qty > 0 || r.redemptions > 0 || r.sales_value !== 0).sort((a, b) => b.sales_value - a.sales_value);
  }, [vouchers, items, basis, invoiceById]);

  const promoRows = useMemo(() => {
    const promotionById = new Map(promotions.map(p => [p.id, p]));
    const sold = new Map<string, any[]>();
    items.filter(it => it.line_kind === 'promotion' && it.promotion_id && paidIds.has(it.invoice_id))
      .forEach(it => sold.set(it.promotion_id, [...(sold.get(it.promotion_id) ?? []), it]));
    return Array.from(sold, ([id, lines]) => ({
      name: promotionById.get(id)?.name ?? 'Deleted promotion', code: promotionById.get(id)?.code ?? '—',
      sold_qty: lines.reduce((s, it) => s + invoicedQuantity(it), 0),
      topups: lines.filter(it => receiptInvoiceIds.has(it.invoice_id)).reduce((s, it) => s + Number(it.topup_amount ?? 0), 0),
      revenue: lines.reduce((s, it) => s + lineRevenue(it), 0),
    })).filter(r => r.sold_qty > 0 || r.revenue !== 0).sort((a, b) => b.revenue - a.revenue);
  }, [promotions, items, basis]);

  const specialRows = useMemo(() => {
    const nameById = new Map(specialProducts.map(p => [p.id, p.name]));
    const ids = new Set<string>([...specialProducts.map(p => p.id), ...items.map(it => it.special_product_id),
      ...specialSales.map(s => s.special_product_id), ...rentals.map(r => r.special_product_id)].filter(Boolean));
    return Array.from(ids, id => {
      const invoiceLines = items.filter(it => it.special_product_id === id && paidIds.has(it.invoice_id));
      const saleLines = invoiceLines.filter(it => it.line_kind === 'special_product');
      const rentalLines = invoiceLines.filter(it => it.line_kind === 'rental');
      // Standalone documents have no invoice sales event. Keep their billed
      // amounts separate instead of treating a charge as proof of a receipt.
      const standaloneSales = specialSales.filter(s => s.special_product_id === id && !s.invoice_id && s.status === 'paid' && inPeriod(singaporeDate(s.created_at)));
      const standaloneRentals = rentals.filter(r => r.special_product_id === id && !r.invoice_id && !['draft', 'cancelled'].includes(r.status) && inPeriod(singaporeDate(r.paid_at || r.created_at)));
      const lateCharges = rentals.filter(r => r.special_product_id === id && !['draft', 'cancelled'].includes(r.status) && inPeriod(singaporeDate(r.returned_at)));
      return {
        name: nameById.get(id) ?? 'Deleted special product',
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
  }, [specialProducts, items, specialSales, rentals, basis]);

  // Stock held under a deleted product is left out, as the inventory pages
  // leave it out, so the two screens agree.
  const stockRows = useMemo(() => {
    const held = (i: WarehouseInventory | StoreInventory) => {
      const p = productById.get(i.product_id);
      return i.current_qty > 0 && !!p && !p.deleted_at;
    };
    return [
      ...warehouses.map(w => { const rws = whInv.filter(i => i.warehouse_id === w.id && held(i));
        return { id: w.id, location: w.name, type: 'Warehouse', products_stocked: rws.length, total_units: rws.reduce((s, i) => s + i.current_qty, 0) }; }),
      ...stores.map(st => { const rws = stInv.filter(i => i.store_id === st.id && held(i));
        return { id: st.id, location: st.name, type: 'Store', products_stocked: rws.length, total_units: rws.reduce((s, i) => s + i.current_qty, 0) }; }),
    ];
  }, [warehouses, stores, whInv, stInv, productById]);

  // What each tab's table shows, cell for cell, so the Excel sheet carries the
  // same headings, columns and order as the screen.
  const ttMatch = (r: any) => r.match_status === 'matched' ? 'Matched' : r.match_status === 'no_match_needed' ? 'No match needed' : 'Pending';
  const pricingDate = (r: any) => r.paid_date ? r.paid_date.split('-').reverse().join('/') : 'Date pending review';
  const focDate = (r: any) => r.settled_at ? singaporeDate(r.settled_at).split('-').reverse().join('/') : 'Date pending review';
  const dobText = (r: any) => r.dob ? new Date(r.dob).toLocaleDateString() : '—';
  const eligibility = (r: any) => r.affiliate_state === 'active' ? 'Eligible' : (r.block_reason ?? r.affiliate_state);
  const staffName = (r: any) => `${r.name}${r.is_active ? '' : ' · inactive'}`;
  const orDash = (n: number, show: (n: number) => number | string) => n > 0 ? show(n) : null;
  const col = (header: string, value: ExcelColumn<any>['value']): ExcelColumn<any> => ({ header, value });
  const ttDailyExport: TableExport = { rows: ttDailyLoad.data, sheet: 'TikTok by day', name: 'by-day', columns: [
    col('Day', r => dateOnly(r.day)), col('Txns', r => Number(r.transactions)), col('Revenue', r => cents(r.revenue)), col('Fees', r => cents(r.fees)),
    col('Expense', r => cents(r.expense ?? 0)), col('Income', r => cents(r.income ?? 0)), col('TikTok settlement', r => cents(r.settlement))] };
  const ttByStoreExport: TableExport = { rows: ttByStoreLoad.data, sheet: 'TikTok by store', name: 'by-store', columns: [
    col('Store', r => r.store_name), col('Txns', r => Number(r.transactions)), col('Revenue', r => cents(r.revenue)), col('Fees', r => cents(r.fees)),
    col('Expense', r => cents(r.expense ?? 0)), col('Income', r => cents(r.income ?? 0)), col('TikTok settlement', r => cents(r.settlement)),
    col('Pending', r => Number(r.pending_count)), col('⚠ Recon', r => Number(r.unreconciled_count))] };
  const ttQtyExport: TableExport = { rows: ttQtyLoad.data, sheet: 'TikTok quantity sold', name: 'quantity-sold', columns: [
    col('Dimension', r => r.dimension), col('Item', r => r.item_name), col('Orders', r => Number(r.orders)), col('Net Units', r => Number(r.net_units))] };
  const ttStatusExport: TableExport = { rows: ttStatusLoad.data, sheet: 'TikTok orders by status', name: 'orders-by-status', columns: [
    col('Status', r => r.order_status), col('Order Items', r => Number(r.order_items)), col('Net Deducted', r => Number(r.net_deducted))] };
  const trOverdueExport: TableExport = { rows: trOverdueLoad.data, sheet: 'Transfers overdue', name: 'overdue', columns: [
    col('From', r => r.source_name), col('To', r => r.dest_name), col('Dispatched', r => new Date(r.dispatched_at).toLocaleDateString('en-GB')),
    col('Days', r => Number(r.days_in_transit)), col('Lines', r => Number(r.line_count)), col('Units', r => Number(r.units_in_transit))] };
  const trDiscExport: TableExport = { rows: trDiscLoad.data, sheet: 'Transfer discrepancy lines', name: 'discrepancies', columns: [
    col('Destination', r => r.dest_name), col('Product', r => r.product_name), col('Approved', r => Number(r.approved_quantity)),
    col('Received', r => Number(r.received_quantity)), col('Δ', r => Number(r.discrepancy)), col('Reason', r => r.discrepancy_reason ?? null),
    col('Resolution', r => r.resolution ?? 'Open')] };
  const exportFor = (t: Tab): TableExport => {
    switch (t) {
      case 'sales_store': return { rows: salesByStore, sheet: 'Sales by Store', columns: [
        col('Store', r => r.name), col('Invoices with sales activity', r => r.count), col('Revenue', r => cents(r.total))] };
      case 'top_products': return { rows: topProducts, sheet: 'Top Products', columns: [
        col('Product', r => r.name), col('Invoiced qty', r => r.qty), col('Revenue', r => cents(r.revenue))] };
      case 'sales_creator': return { rows: salesByCreator, sheet: 'Sales by Creator', columns: [
        col('Invoice Creator', r => r.name), col('Invoices', r => r.count), col('Total Sales', r => cents(r.total))] };
      case 'sales_service_staff': return { rows: salesByServiceStaff, sheet: 'Sales by Service Staff', columns: [
        col('Staff', staffName), col('Invoices Served', r => r.invoices), col('Shared Sales', r => cents(r.shared)),
        col('Of which: no "Served by"', r => r.as_creator ? cents(r.as_creator) : null),
        col('Of which: earlier part payments', r => r.moved_in ? cents(r.moved_in) : null),
        col('Receipts on Invoices Served', r => cents(r.fullTotal))] };
      case 'sales_affiliate': return { rows: salesByReferrer, sheet: 'Sales by Referrer', columns: [
        col('Referrer', r => r.name), col('Referred invoices with sales activity', r => r.count), col('Recognized sales', r => cents(r.total)),
        col('Commission on these invoices', r => cents(r.commission))] };
      case 'commission': return { rows: commissionRows, sheet: 'Commission', columns: [
        col('Referrer', r => r.name), col('Earned (lifetime)', r => cents(r.earned)), col('Paid Out', r => orDash(r.paidOut, cents)),
        col('Reversed', r => orDash(r.reversed, n => -cents(n))), col('Outstanding', r => cents(r.outstanding))] };
      case 'vouchers': return { rows: voucherRows, sheet: 'Vouchers', columns: [
        col('Voucher', r => r.name), col('Type', r => r.kind), col('Invoiced qty', r => r.sold_qty), col('Sales Value', r => cents(r.sales_value)),
        col('Uses', r => r.redemptions), col('Discount Given', r => orDash(r.discount_given, n => -cents(n)))] };
      case 'promotions': return { rows: promoRows, sheet: 'Promotions', columns: [
        col('Promotion', r => r.name), col('Code', r => r.code), col('Invoiced qty', r => r.sold_qty), col('Top-ups', r => orDash(r.topups, cents)),
        col('Revenue', r => cents(r.revenue))] };
      case 'specials': return { rows: specialRows, sheet: 'Specials & Rentals', columns: [
        col('Special Product', r => r.name), col('Invoiced units', r => r.units_sold), col('Invoice sales', r => cents(r.sales_revenue)),
        col('Invoiced rentals', r => r.rentals), col('Invoice rental sales', r => cents(r.rental_fees)),
        col('Standalone sales billed', r => cents(r.standalone_sales_billed)), col('Standalone rental fees billed', r => cents(r.standalone_rental_fees_billed)),
        col('Late fees billed', r => orDash(r.late_fees, cents))] };
      case 'customers': return { rows: custRows, sheet: 'Customers', columns: [
        col('Customer', r => r.name), col('Phone', r => r.phone), col('DOB', r => r.dob ? dobText(r) : null), col('Gender', r => r.gender || null),
        col('Occupation', r => r.occupation || null), col('Purchases', r => r.count), col('Total Spent', r => cents(r.total))] };
      case 'stock': return { rows: stockRows, sheet: 'Stock Balance', columns: [
        col('Location', r => r.location), col('Type', r => r.type), col('Products Stocked', r => r.products_stocked), col('Total Units', r => r.total_units)] };
      case 'r_pricing': return { rows: repPricing, sheet: 'Pricing', columns: [
        col('Invoice', r => r.invoice_no), col('Business date', pricingDate), col('Store', r => r.store_name), col('Customer', r => r.customer_name),
        col('Item', r => r.item_name), col('Kind', r => r.line_kind), col('Qty', r => Number(r.quantity)), col('Price', r => cents(r.unit_price))] };
      case 'r_affiliate': return { rows: repAffiliate, sheet: 'Affiliate', columns: [
        col('Customer', r => r.customer_name), col('Eligibility', eligibility), col('Store', r => r.store_name ?? null),
        col('Referrals', r => Number(r.direct_referrals)), col('Tier 1', r => cents(r.tier1_earned)), col('Tier 2', r => cents(r.tier2_earned)),
        col('Earned', r => cents(r.earned)), col('Paid', r => cents(r.paid)), col('Reversed', r => cents(r.reversed)), col('Blocked', r => cents(r.blocked))] };
      case 'r_therapy': return { rows: repTherapy, sheet: 'Therapy', columns: [
        col('No.', r => r.entitlement_no), col('Customer', r => r.customer_name), col('Package', r => r.package_name), col('Store', r => r.store_name ?? null),
        col('Price', r => cents(r.price_snapshot)), col('Purchased', r => r.purchase_date ? dateOnly(r.purchase_date) : null),
        col('Activation', r => r.activation_date ? dateOnly(r.activation_date) : null), col('Expiry', r => r.expiry_date ? dateOnly(r.expiry_date) : null),
        col('Status', r => String(r.status).replace('_', ' ')), col('Type', r => r.is_legacy ? 'Legacy' : 'Purchased')] };
      case 'r_discounts': return { rows: repDiscounts, sheet: 'Discounts', columns: [
        col('Invoice', r => r.invoice_no), col('Business date', pricingDate), col('Store', r => r.store_name), col('Staff', r => r.staff_names ?? null),
        col('Customer', r => r.customer_name), ...DISCOUNT_COLUMNS.map(c => col(c.header, r => cents(c.value(r)))),
        col('Total', r => cents(r.total_discount))] };
      case 'r_foc': return { rows: repFoc, sheet: 'FOC', columns: [
        col('Invoice', r => r.invoice_no), col('Business date', focDate), col('Customer', r => r.customer_name), col('Kind', r => r.line_kind),
        col('Item', r => r.description), col('Qty', r => Number(r.quantity)), col('FOC Qty', r => Number(r.foc_quantity)),
        col('Normal', r => cents(r.normal_value)), col('FOC', r => cents(r.foc_value)), col('Charged', r => cents(r.charged_value)),
        col('Reason', r => r.foc_reason ?? null), col('By', r => r.foc_by_name ?? null)] };
      case 'r_sources': return { rows: repSources, sheet: 'Sources', columns: [
        col('Source', r => r.source_label), col('Customers (current source)', r => Number(r.customers_count)),
        col('Surveys (submission snapshot)', r => Number(r.surveys_count)), col('Status', r => r.is_active ? 'Active' : 'Inactive')] };
      case 'r_tiktok': return { rows: ttRows, sheet: 'TikTok settlement rows', name: 'settlement rows', columns: [
        col('Date', r => r.financial_date ? dateOnly(r.financial_date) : null),
        col('Order/Adj ID', r => `${r.order_adjustment_id}${r.version_no > 1 ? ` (v${r.version_no})` : ''}`),
        col('Type', r => r.txn_class), col('Store', r => r.store_name), col('Match', ttMatch),
        col('Settlement', r => cents(r.settlement_amount ?? 0)), col('Revenue', r => cents(r.revenue_amount ?? 0)), col('Fees', r => cents(r.fee_amount ?? 0)),
        col('Reconciled', r => r.reconciled === false ? 'Off' : r.reconciled === true ? 'OK' : null)] };
      case 'r_exchange_inv': return { rows: exchLoad.data, sheet: 'Exchange Invoices', columns: [
        col('Exchange', r => r.exchange_no), col('Invoice', r => r.invoice_no ?? null), col('Store', r => r.store_name), col('Customer', r => r.customer_name ?? null),
        col('Date', r => new Date(r.created_at).toLocaleDateString('en-GB')), col('Credit', r => cents(r.returned_credit)),
        col('Replacement', r => cents(r.replacement_total)), col('Top-up', r => orDash(Number(r.topup_amount), cents)),
        col('Non-refundable', r => orDash(Number(r.nonrefundable_amount), cents)), col('FOC', r => r.is_foc ? `FOC ${money(Number(r.foc_amount))}` : null)] };
      case 'r_transfers': return { rows: trReceiptsLoad.data, sheet: 'Transfer receipts', name: 'receipts', columns: [
        col('From', r => r.source_name), col('To', r => r.dest_name), col('Received', r => new Date(r.received_at).toLocaleString()),
        col('By', r => r.received_by_name ?? null), col('Units', r => Number(r.received_units)),
        col('Discrepancy', r => r.had_discrepancy ? (r.discrepancy_resolved ? 'Resolved' : 'Open') : 'Clean')] };
      case 'r_events': return { rows: eventsLoad.data.flatMap((e: any) => (e.options ?? []).map((o: any) => ({ ...o, event: e }))),
        sheet: 'Event tickets', columns: [
        col('Event', r => r.event.name), col('First day', r => r.event.first_day), col('Last day', r => r.event.last_day),
        col('Ticket', r => r.name), col('Days covered', r => Number(r.days_count)), col('Price', r => cents(r.price)),
        col('People', r => Number(r.people)), col('Early bird', r => Number(r.early_bird_people)),
        col('FOC', r => Number(r.foc_people)), col('Money', r => cents(r.revenue))] };
      case 'r_salesrecon': return { rows: [...salesRecon, { channel: 'Total', transactions: salesRecon.reduce((a, r) => a + Number(r.transactions), 0),
        amount: salesRecon.reduce((a, r) => a + Number(r.amount), 0), total: true }], sheet: 'Sales Reconciliation', columns: [
        col('Channel', r => r.total ? 'Total' : String(r.channel).replace(/_/g, ' ')), col('Transactions', r => Number(r.transactions)),
        col('Amount', r => cents(r.amount))] };
    }
  };

  const isPeriodReport = ['r_pricing', 'r_discounts', 'r_foc', 'r_salesrecon'].includes(tab);
  const staffTab = tab === 'sales_service_staff';
  const usesCore = !SEPARATE_TABS.includes(tab);
  // The separately loaded report behind a single-table tab.
  const tabLoad: ReportLoad<any> | null = tab === 'commission' || tab === 'r_affiliate' ? affiliatesLoad
    : tab === 'r_therapy' ? therapyLoad : tab === 'r_sources' ? sourcesLoad : tab === 'r_exchange_inv' ? exchLoad
    : tab === 'r_events' ? eventsLoad : null;
  // TikTok and Transfers show several tables, each with its own loading and
  // error state; the page Export carries the main one.
  const multiTable = onTikTok || onTransfers;
  const mainLoad = onTikTok ? ttRowsLoad : trReceiptsLoad;
  const reportBusy = (usesCore && loading) || (isPeriodReport && periodLoading) || (staffTab && staffLoading) || !!tabLoad?.loading;
  const reportFailed = (usesCore && !!salesError) || (isPeriodReport && !!periodError) || !!tabLoad?.error;
  // Its error is shown on the tab itself; the export must not produce an empty sheet.
  const staffFailed = staffTab && !!staffSales?.error;
  const currentExport = exportFor(tab);
  const exportDisabled = multiTable ? mainLoad.loading || !!mainLoad.error : reportBusy || reportFailed || staffFailed;
  const tabLabel = TABS.find(t => t.id === tab)?.label ?? 'Report';

  if (!hasAccess) return <NoAccess message="Only Owners, Admins, and Managers can view reports." />;

  // A heading with its own export, for the tabs that show several tables.
  const tableHeading = (title: React.ReactNode, exp: TableExport, l: ReportLoad<any>, margin = '18px 0 4px') => (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, flexWrap: 'wrap', margin }}>
      <h3 style={{ fontSize: 14, margin: 0 }}>{title}</h3>
      <ExcelExportButton rows={exp.rows} columns={exp.columns} filename={`report-${tab}-${exp.name}`} sheetName={exp.sheet.slice(0, 31)}
        label="Export" disabled={l.loading || !!l.error} />
    </div>
  );
  // The body of a table fed by its own load: a spinner while it loads, the
  // error when it failed, and the empty text only when it truly returned nothing.
  const loadedRows = (l: ReportLoad<any[]>, span: number, emptyText: string, row: (r: any, i: number) => React.ReactNode) =>
    l.loading ? <tr><td colSpan={span} style={{ textAlign: 'center', padding: 20 }}><RefreshCw size={18} className="spin" style={{ opacity: 0.4 }} /></td></tr>
    : l.error ? <tr><td colSpan={span} role="alert" style={{ textAlign: 'center', color: 'var(--danger)', padding: 20 }}>Could not be loaded: {l.error}. Refresh to try again.</td></tr>
    : l.data.length === 0 ? <tr><td colSpan={span} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 20 }}>{emptyText}</td></tr>
    : l.data.map(row);

  return (
    <div>
      {(salesError || periodError) && <div role="alert" className="alert alert-danger">Reports could not be fully loaded: {salesError || periodError}</div>}
      <div className="page-header">
        <div><h2>Reports</h2><p>Overview across sales, stock, referrers, and customers. Recognized invoice sales: <strong style={{ color: 'var(--primary)' }}>{salesError ? 'unavailable' : coreLoaded ? money(totalRevenue) : '…'}</strong></p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={currentExport.rows}
            filename={`report-${tab}${currentExport.name ? `-${currentExport.name.replace(/ /g, '-')}` : ''}`}
            sheetName={currentExport.sheet.slice(0, 31)}
            label={multiTable ? `Export ${currentExport.name}` : 'Export Excel'}
            disabled={exportDisabled}
            columns={currentExport.columns} /><button className="btn btn-secondary" onClick={refresh}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button></div>
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
            ? `Showing invoice sales ${dFrom ? `from ${dFrom.split('-').reverse().join('/')}` : ''}${dTo ? ` to ${dTo.split('-').reverse().join('/')}` : ''}. Receipts use the date the money was received; refunds use the refund date.`
            : 'Showing all time. Receipts use the date the money was received; refunds use the refund date.'}
          <div>Pricing, discounts and FOC show invoice measures by business date. Stock and catalogue reports show the current position; commission payouts retain their actual dates.</div>
          {PERIOD_NOTE[tab] && <div data-testid="period-note" style={{ fontWeight: 600, marginTop: 2 }}>{PERIOD_NOTE[tab]}</div>}
        </div>
      </div>

      {lineSales.unallocated.length > 0 && <div className="alert alert-warning" role="status">
        {money(unallocatedAmount)} across {lineSales.unallocated.length} event allocations is included in invoice sales but cannot be assigned to a product line. Original line details or an invoice-level correction require review.
        <ExcelExportButton rows={lineSales.unallocated} filename="invoice-sales-allocation-review" label="Export allocation review" columns={[
          { header: 'Invoice', value: r => invoiceById.get(r.invoice_id)?.invoice_no ?? r.invoice_id },
          { header: 'Invoice ID', value: r => r.invoice_id },
          { header: 'Event ID', value: r => r.event_id },
          { header: 'Amount', value: r => r.amount },
          { header: 'Reason', value: r => r.reason },
        ]} />
      </div>}
      {['top_products', 'vouchers', 'promotions', 'specials'].includes(tab) && <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>
        Line sales use discounted receipt shares and the recorded refund lines. Mixed cash and wallet refunds allocate only the external-money share proportionally. Invoiced quantities count invoices with receipts in this period; they are not a stock-return measure.
      </p>}
      {tab === 'r_discounts' && <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>
        Each line discount under its own type: Vouchers, Birthday and Staff (by the voucher's category), Manual and Percentage.
        The invoice-level manual discount and Discount Voucher have their own columns. Exchange credit is the value returned on
        an exchange, not a discount, and is kept apart. FOC has its own report.
      </p>}
      {tab === 'vouchers' && <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>
        Uses and Discount Given are read from the invoices with receipts in this period: each line redeemed with the voucher, and each invoice given it as an invoice-level discount.
      </p>}
      {tab === 'specials' && <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>
        Invoice sales and rental receipts follow the selected sales period. Standalone billed amounts use the document date and require payment review; late fees use the recorded return date. Standalone amounts are shown separately and are excluded from recognized invoice sales. A late fee charged at a rental's Return is invoiced on an invoice of its own, so it is in invoice sales too; older late fees collected on the rental are not.
      </p>}
      {(() => {
        // Headline figures for the invoice-sales period, so the answer is visible
        // before the table. Only on the tabs that follow that period, and only
        // from invoice records that loaded: a failed load shows no figures
        // rather than S$0.00 as if there were no sales.
        if (!INVOICE_SALES_TABS.includes(tab) || !coreReady) return null;
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
        return (
          <>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 10, marginBottom: 6 }}>
              {cards.map(([k, v]) => (
                <div key={k} className="card" style={{ padding: '12px 14px' }}>
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{k}</div>
                  <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{v}</div>
                </div>
              ))}
            </div>
            <p data-testid="wallet-note" style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 14 }}>
              Purchases paid entirely with wallet credit are not counted here: the credit was counted when it was bought.
            </p>
          </>
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
        if (!c || !coreReady) return null;
        return (
          <div className="card" style={{ marginBottom: 14 }}>
            <MiniBarChart title={c.title} data={c.data} format={c.fmt} limit={10} />
          </div>
        );
      })()}

      <div className="card">
        <div className="table-wrap">
          {!multiTable && reportBusy ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : !multiTable && reportFailed ? <>
              {tabLoad?.error && <div role="alert" className="alert alert-danger" style={{ margin: 12 }}>{tabLabel} could not be loaded: {tabLoad.error}</div>}
              <div className="empty-state">The complete report is unavailable. Refresh to try again.</div>
            </>
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
                  <thead><tr><th>Referrer</th><th style={{ textAlign: 'right' }}>Referred invoices with sales activity</th><th style={{ textAlign: 'right' }}>Recognized sales</th><th style={{ textAlign: 'right' }}>Commission on these invoices</th></tr></thead>
                  <tbody>{salesByReferrer.length === 0 ? <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No referred sales yet in this period</td></tr>
                    : salesByReferrer.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.total)}</td><td style={{ textAlign: 'right', color: 'var(--primary)' }}>{money(r.commission)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'commission' && (
                <table>
                  <thead><tr><th>Referrer</th><th style={{ textAlign: 'right' }}>Earned (lifetime)</th><th style={{ textAlign: 'right' }}>Paid Out</th><th style={{ textAlign: 'right' }}>Reversed</th><th style={{ textAlign: 'right' }}>Outstanding</th></tr></thead>
                  <tbody>{commissionRows.length === 0 ? <tr><td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No commissions yet</td></tr>
                    : commissionRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right', color: 'var(--success)' }}>{money(r.earned)}</td><td style={{ textAlign: 'right' }}>{r.paidOut > 0 ? money(r.paidOut) : '—'}</td><td style={{ textAlign: 'right', color: 'var(--danger)' }}>{r.reversed > 0 ? `−${money(r.reversed)}` : '—'}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.outstanding)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'vouchers' && (
                <table>
                  <thead><tr><th>Voucher</th><th>Type</th><th style={{ textAlign: 'right' }}>Invoiced qty</th><th style={{ textAlign: 'right' }}>Sales Value</th><th style={{ textAlign: 'right' }}>Uses</th><th style={{ textAlign: 'right' }}>Discount Given</th></tr></thead>
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
                <>
                  {staffSales?.error && <div role="alert" className="alert alert-danger" style={{ margin: 12 }}>
                    Sales by Service Staff could not be loaded: {staffSales.error}</div>}
                  {staffSales && !staffSales.error && (() => {
                    const revenue = Number(staffSales.revenue ?? 0), movedIn = Number(staffSales.backfill_in ?? 0);
                    const movedOut = Number(staffSales.backfill_out ?? 0), staffTotal = Number(staffSales.staff_total ?? 0);
                    // 396: rental late fees are revenue credited to no member of staff.
                    const lateFees = Number(staffSales.late_fees_not_credited ?? 0);
                    const off = Math.abs(Number(staffSales.difference ?? 0)) >= 0.005;
                    // The headline comes from the money loaded when the page opened (or was
                    // refreshed); this report is fetched again for every period. Money
                    // recorded in between makes them differ until Refresh.
                    const headlineOff = !off && coreReady && Math.abs(revenue - totalRevenue) >= 0.005;
                    return (
                      <div style={{ padding: '10px 14px', fontSize: 12.5, borderBottom: '1px solid var(--border)' }}>
                        <div>
                          Revenue <strong>{money(revenue)}</strong>
                          {lateFees !== 0 && <> − rental late fees, credited to no one <strong>{money(lateFees)}</strong></>}
                          {movedIn !== 0 &&<> + earlier part payments credited to this period <strong>{money(movedIn)}</strong></>}
                          {movedOut !== 0 && <> − part payments credited to a later period <strong>{money(movedOut)}</strong></>}
                          {' '}= staff total <strong>{money(staffTotal)}</strong>
                          {Number(staffSales.credited_as_creator ?? 0) !== 0 && <span style={{ color: 'var(--text-muted)' }}>
                            {' '}· {money(Number(staffSales.credited_as_creator))} is on invoices with no "Served by", credited to whoever created them</span>}
                        </div>
                        {Number(staffSales.wallet_credit_not_counted ?? 0) !== 0 && <div style={{ color: 'var(--text-muted)', marginTop: 2 }}>
                          Not counted: {money(Number(staffSales.wallet_credit_not_counted))} of purchases paid with wallet credit — credit bought with money was counted when it was bought; adjusted and opening-balance credit was never revenue.
                        </div>}
                        {off && <div role="alert" className="alert alert-danger" style={{ marginTop: 8, marginBottom: 0 }}>
                          The staff total is {money(Number(staffSales.difference))} away from revenue for this period. Please report this.
                        </div>}
                        {headlineOff && <div role="status" className="alert alert-warning" style={{ marginTop: 8, marginBottom: 0 }}>
                          Money was recorded or changed after this page loaded: this report counts {money(revenue)}, the headline
                          still shows {money(totalRevenue)}. Press Refresh to bring them together.
                        </div>}
                      </div>
                    );
                  })()}
                  {!staffSales?.error && <table>
                    <thead><tr><th>Staff</th><th style={{ textAlign: 'right' }}>Invoices Served</th><th style={{ textAlign: 'right' }}>Shared Sales</th><th style={{ textAlign: 'right' }}>Of which: no "Served by"</th><th style={{ textAlign: 'right' }}>Of which: earlier part payments</th><th style={{ textAlign: 'right' }}>Receipts on Invoices Served</th></tr></thead>
                    <tbody>{salesByServiceStaff.length === 0 ? <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No sales in this period</td></tr>
                      : salesByServiceStaff.map((r, i) => <tr key={i}>
                          <td><strong>{r.name}</strong>{!r.is_active && <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}> · inactive</span>}</td>
                          <td style={{ textAlign: 'right' }}>{r.invoices}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.shared)}</td>
                          <td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{r.as_creator ? money(r.as_creator) : '—'}</td>
                          <td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{r.moved_in ? money(r.moved_in) : '—'}</td>
                          <td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{money(r.fullTotal)}</td>
                        </tr>)}</tbody>
                  </table>}
                </>
              )}
              {tab === 'customers' && (
                <table>
                  <thead><tr><th>Customer</th><th>Phone</th><th>DOB</th><th>Gender</th><th>Occupation</th><th style={{ textAlign: 'right' }}>Purchases</th><th style={{ textAlign: 'right' }}>Total Spent</th></tr></thead>
                  <tbody>{custRows.length === 0 ? <tr><td colSpan={7} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No customer purchases yet</td></tr>
                    : custRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ fontSize: 12.5 }}>{r.phone}</td><td style={{ fontSize: 12.5 }}>{dobText(r)}</td><td style={{ fontSize: 12.5 }}>{r.gender || '—'}</td><td style={{ fontSize: 12.5 }}>{r.occupation || '—'}</td><td style={{ textAlign: 'right' }}>{r.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.total)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'stock' && (
                <table>
                  <thead><tr><th>Location</th><th>Type</th><th style={{ textAlign: 'right' }}>Products Stocked</th><th style={{ textAlign: 'right' }}>Total Units</th></tr></thead>
                  <tbody>
                    {stockRows.map(r => <tr key={`${r.type}-${r.id}`}><td><strong>{r.type === 'Warehouse' ? '🏭' : '🏪'} {r.location}</strong></td><td>{r.type}</td><td style={{ textAlign: 'right' }}>{r.products_stocked}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{r.total_units}</td></tr>)}
                  </tbody>
                </table>
              )}
              {tab === 'r_pricing' && (
                <table>
                  <thead><tr><th>Invoice</th><th>Business date</th><th>Store</th><th>Customer</th><th>Item</th><th>Kind</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>Price</th></tr></thead>
                  <tbody>{repPricing.length === 0 ? <tr><td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No invoice lines in this period</td></tr>
                    : repPricing.map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{pricingDate(r)}</td><td style={{ fontSize: 12 }}>{r.store_name}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td><td>{r.item_name}</td><td style={{ fontSize: 12 }}>{r.line_kind}</td><td style={{ textAlign: 'right' }}>{r.quantity}</td><td style={{ textAlign: 'right' }}>{money(Number(r.unit_price))}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'r_affiliate' && (
                <table>
                  <thead><tr><th>Customer</th><th>Eligibility</th><th>Store</th><th style={{ textAlign: 'right' }}>Referrals</th><th style={{ textAlign: 'right' }}>Tier 1</th><th style={{ textAlign: 'right' }}>Tier 2</th><th style={{ textAlign: 'right' }}>Earned</th><th style={{ textAlign: 'right' }}>Paid</th><th style={{ textAlign: 'right' }}>Reversed</th><th style={{ textAlign: 'right' }}>Blocked</th></tr></thead>
                  <tbody>{repAffiliate.length === 0 ? <tr><td colSpan={10} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No affiliates</td></tr>
                    : repAffiliate.map((r, i) => <tr key={i}><td><strong>{r.customer_name}</strong></td><td style={{ fontSize: 12 }}>{eligibility(r)}</td><td style={{ fontSize: 12 }}>{r.store_name ?? '—'}</td><td style={{ textAlign: 'right' }}>{r.direct_referrals}</td><td style={{ textAlign: 'right' }}>{money(Number(r.tier1_earned))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.tier2_earned))}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.earned))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.paid))}</td><td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{money(Number(r.reversed))}</td><td style={{ textAlign: 'right', color: Number(r.blocked) > 0 ? 'var(--danger)' : 'var(--text-muted)' }}>{money(Number(r.blocked))}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'r_therapy' && (
                <table>
                  <thead><tr><th>No.</th><th>Customer</th><th>Package</th><th>Store</th><th style={{ textAlign: 'right' }}>Price</th><th>Purchased</th><th>Activation</th><th>Expiry</th><th>Status</th><th>Type</th></tr></thead>
                  <tbody>{repTherapy.length === 0 ? <tr><td colSpan={10} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No therapy</td></tr>
                    : repTherapy.map((r, i) => <tr key={i}><td>{r.entitlement_no}</td><td><strong>{r.customer_name}</strong></td><td>{r.package_name}</td><td style={{ fontSize: 12 }}>{r.store_name ?? '—'}</td><td style={{ textAlign: 'right' }}>{money(Number(r.price_snapshot))}</td><td style={{ fontSize: 12 }}>{dateOnly(r.purchase_date)}</td><td style={{ fontSize: 12 }}>{dateOnly(r.activation_date)}</td><td style={{ fontSize: 12 }}>{dateOnly(r.expiry_date)}</td><td style={{ textTransform: 'capitalize' }}>{String(r.status).replace('_', ' ')}</td><td style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{r.is_legacy ? 'Legacy' : 'Purchased'}</td></tr>)}</tbody>
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
                    reloadKey={refreshKey}
                  />
                  <h3 style={{ fontSize: 14, margin: '22px 0 4px' }}>Imported source totals (all periods)</h3>
                  <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 8 }}>
                    TikTok's own figures as imported, across every period — shown for reconciliation,
                    not as the reporting-month result. Each card totals one imported column, so they are
                    not parts of the net settlement and are not expected to add up to it.
                  </p>
                  {ttSummaryLoad.loading ? <div style={{ padding: 12 }}><RefreshCw size={18} className="spin" style={{ opacity: 0.4 }} /></div>
                  : ttSummaryLoad.error ? <div role="alert" className="alert alert-danger">Imported source totals could not be loaded: {ttSummaryLoad.error}</div>
                  : ttSummary && (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 12, marginBottom: 16 }}>
                      {([
                        ['TikTok reported net settlement', money(Number(ttSummary.total_settlement ?? 0)), "TikTok's Settlement column, after advertising."],
                        ['Revenue as imported', money(Number(ttSummary.total_revenue ?? 0)), "TikTok's Revenue column."],
                        ['Fees as imported', money(Number(ttSummary.total_fees ?? 0)), "TikTok's Fee column, with TikTok's sign (costs are negative)."],
                        ['Adjustment rows', money(Number(ttSummary.total_adjustments ?? 0)), 'Settlement of rows TikTok classes as adjustments. Ad payments are finance rows, not in this card.'],
                        ['Refund rows', money(Number(ttSummary.total_refunds ?? 0)), 'Settlement of rows TikTok classes as refunds.'],
                      ] as [string, string, string][]).map(([k, v, hint]) => (
                        <div key={k} className="card" style={{ padding: 14 }}>
                          <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{k}</div>
                          <div style={{ fontSize: 19, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{v}</div>
                          <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4, lineHeight: 1.45 }}>{hint}</div>
                        </div>
                      ))}
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
                  <h3 style={{ fontSize: 14, margin: '0 0 4px' }}>Settlement rows (all periods, newest settled date first)</h3>
                  <table>
                    <thead><tr><th>Date</th><th>Order/Adj ID</th><th>Type</th><th>Store</th><th>Match</th><th style={{ textAlign: 'right' }}>Settlement</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th><th>Reconciled</th></tr></thead>
                    <tbody>{loadedRows(ttRowsLoad, 9, 'No settlement data', (r, i) => <tr key={i}>
                          <td style={{ fontSize: 12 }}>{dateOnly(r.financial_date)}</td>
                          <td style={{ fontFamily: 'var(--font-display)', fontSize: 12 }}>{r.order_adjustment_id}{r.version_no > 1 ? ` (v${r.version_no})` : ''}</td>
                          <td style={{ fontSize: 12, textTransform: 'capitalize' }}>{r.txn_class}</td>
                          <td style={{ fontSize: 12 }}>{r.store_name}</td>
                          <td>{r.match_status === 'matched' ? <span className="badge badge-success">Matched</span>
                            : r.match_status === 'no_match_needed' ? <span className="badge badge-muted" title="A TikTok platform payment, not a customer order — nothing to match">No match needed</span>
                            : <span className="badge badge-warning">Pending</span>}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.settlement_amount ?? 0))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.revenue_amount ?? 0))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.fee_amount ?? 0))}</td>
                          <td>{r.reconciled === false ? <span className="badge badge-danger">⚠ Off</span> : r.reconciled === true ? <span className="badge badge-success">OK</span> : <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>—</span>}</td>
                        </tr>)}</tbody>
                  </table>

                  {tableHeading(`Settlement by Day (settled date, SGT) — reporting month ${periodLabel(ttMonth.year, ttMonth.month)}`, ttDailyExport, ttDailyLoad)}
                  <table>
                    <thead><tr><th>Day</th><th style={{ textAlign: 'right' }}>Txns</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th><th style={{ textAlign: 'right' }}>Expense</th><th style={{ textAlign: 'right' }}>Income</th><th style={{ textAlign: 'right' }}>TikTok settlement</th></tr></thead>
                    <tbody>{loadedRows(ttDailyLoad, 7, 'No data', (r, i) => <tr key={i}>
                          <td style={{ fontSize: 12 }}>{dateOnly(r.day)}</td>
                          <td style={{ textAlign: 'right' }}>{r.transactions}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.revenue))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.fees))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.expense ?? 0))}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.income ?? 0))}</td>
                          <td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{money(Number(r.settlement))}</td>
                        </tr>)}</tbody>
                  </table>

                  {tableHeading(`Settlement by Store — reporting month ${periodLabel(ttMonth.year, ttMonth.month)}`, ttByStoreExport, ttByStoreLoad)}
                  <table>
                    <thead><tr><th>Store</th><th style={{ textAlign: 'right' }}>Txns</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th><th style={{ textAlign: 'right' }}>Expense</th><th style={{ textAlign: 'right' }}>Income</th><th style={{ textAlign: 'right' }}>TikTok settlement</th><th style={{ textAlign: 'right' }}>Pending</th><th style={{ textAlign: 'right' }}>⚠ Recon</th></tr></thead>
                    <tbody>{loadedRows(ttByStoreLoad, 9, 'No data', (r, i) => <tr key={i}>
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

                  {tableHeading('Quantity Sold (net of returns) — all periods', ttQtyExport, ttQtyLoad)}
                  <p style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 8, lineHeight: 1.5 }}>
                    Operational, from the order lifecycle — not settlement. It counts units on orders,
                    which is a different question from money settled, and the two are <strong>not
                    expected to reconcile</strong>: an order can ship in one period and settle in another.
                  </p>
                  <table>
                    <thead><tr><th>Dimension</th><th>Item</th><th style={{ textAlign: 'right' }}>Orders</th><th style={{ textAlign: 'right' }}>Net Units</th></tr></thead>
                    <tbody>{loadedRows(ttQtyLoad, 4, 'No confirmed TikTok sales', (r, i) => <tr key={i}>
                          <td style={{ fontSize: 12, textTransform: 'capitalize' }}>{r.dimension}</td>
                          <td style={{ fontWeight: 600, fontSize: 12.5 }}>{r.item_name}</td>
                          <td style={{ textAlign: 'right' }}>{r.orders}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700 }}>{r.net_units}</td>
                        </tr>)}</tbody>
                  </table>

                  {tableHeading('Orders by Status — all periods', ttStatusExport, ttStatusLoad)}
                  <table>
                    <thead><tr><th>Status</th><th style={{ textAlign: 'right' }}>Order Items</th><th style={{ textAlign: 'right' }}>Net Deducted</th></tr></thead>
                    <tbody>{loadedRows(ttStatusLoad, 3, 'No orders', (r, i) => <tr key={i}>
                        <td style={{ fontSize: 12.5 }}>{r.order_status}</td>
                        <td style={{ textAlign: 'right' }}>{r.order_items}</td>
                        <td style={{ textAlign: 'right' }}>{r.net_deducted}</td>
                      </tr>)}</tbody>
                  </table>
                </>
              )}
              {tab === 'r_events' && (() => {
                // The page Export carries the first table: tickets by event and option.
                const day = (d: string) => new Date(`${d}T00:00:00`).toLocaleDateString('en-SG', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
                const rows = exportFor('r_events')?.rows ?? [];
                return (
                  <>
                    <table>
                      <thead><tr><th>Event</th><th>First day</th><th>Last day</th><th>Ticket</th><th style={{ textAlign: 'right' }}>Days covered</th><th style={{ textAlign: 'right' }}>Price</th><th style={{ textAlign: 'right' }}>People</th><th style={{ textAlign: 'right' }}>Early bird</th><th style={{ textAlign: 'right' }}>FOC</th><th style={{ textAlign: 'right' }}>Money</th></tr></thead>
                      <tbody>{rows.length === 0 ? <tr><td colSpan={10} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No events in this period</td></tr>
                        : rows.map((o: any) => (
                          <tr key={o.option_id}>
                            <td style={{ fontWeight: 600 }}>{o.event.name}</td>
                            <td style={{ fontSize: 12 }}>{o.event.first_day}</td>
                            <td style={{ fontSize: 12 }}>{o.event.last_day}</td>
                            <td>{o.name}</td>
                            <td style={{ textAlign: 'right' }}>{o.days_count}</td>
                            <td style={{ textAlign: 'right' }}>{money(Number(o.price))}</td>
                            <td style={{ textAlign: 'right' }}>{o.people}</td>
                            <td style={{ textAlign: 'right' }}>{o.early_bird_people}</td>
                            <td style={{ textAlign: 'right' }}>{o.foc_people}</td>
                            <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(o.revenue))}</td>
                          </tr>))}</tbody>
                    </table>
                    {eventsLoad.data.map((e: any) => (
                      <div key={e.event_id} style={{ marginTop: 18 }}>
                        <h3 style={{ margin: '4px 0 6px', fontSize: 15 }}>{e.name}
                          <span style={{ fontWeight: 400, color: 'var(--text-muted)', fontSize: 12.5, marginLeft: 8 }}>
                            {e.first_day === e.last_day ? day(e.first_day) : `${day(e.first_day)} – ${day(e.last_day)}`}
                            {e.early_bird_until ? ` · early bird until ${day(e.early_bird_until)}` : ''}
                          </span>
                        </h3>
                        <table>
                          <thead><tr><th>Day</th><th style={{ textAlign: 'right' }}>Capacity</th><th style={{ textAlign: 'right' }}>Registered</th><th style={{ textAlign: 'right' }}>Ticket</th><th style={{ textAlign: 'right' }}>Free</th><th style={{ textAlign: 'right' }}>Attended</th></tr></thead>
                          <tbody>{(e.days ?? []).map((d: any) => (
                            <tr key={d.day}>
                              <td>{day(d.day)}</td>
                              <td style={{ textAlign: 'right' }}>{d.capacity ?? '—'}</td>
                              <td style={{ textAlign: 'right', color: d.capacity != null && Number(d.registered) > Number(d.capacity) ? 'var(--danger)' : 'inherit', fontWeight: 600 }}>{d.registered}</td>
                              <td style={{ textAlign: 'right' }}>{d.ticket}</td>
                              <td style={{ textAlign: 'right' }}>{d.free}</td>
                              <td style={{ textAlign: 'right' }}>{d.attended}</td>
                            </tr>))}</tbody>
                        </table>
                        <table style={{ marginTop: 8 }}>
                          <thead><tr><th>Event sales by store</th><th style={{ textAlign: 'right' }}>Invoices</th><th style={{ textAlign: 'right' }}>Total</th><th style={{ textAlign: 'right' }}>Paid</th></tr></thead>
                          <tbody>{(e.sales ?? []).length === 0 ? <tr><td colSpan={4} style={{ color: 'var(--text-muted)' }}>No event sales</td></tr>
                            : (e.sales ?? []).map((x: any) => (
                              <tr key={x.store_id}>
                                <td>{x.store_name}</td>
                                <td style={{ textAlign: 'right' }}>{x.invoices}</td>
                                <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(x.total_amount))}</td>
                                <td style={{ textAlign: 'right' }}>{money(Number(x.paid_amount))}</td>
                              </tr>))}</tbody>
                        </table>
                      </div>
                    ))}
                  </>
                );
              })()}
              {tab === 'r_exchange_inv' && (
                <table>
                  <thead><tr><th>Exchange</th><th>Invoice</th><th>Store</th><th>Customer</th><th>Date</th><th style={{ textAlign: 'right' }}>Credit</th><th style={{ textAlign: 'right' }}>Replacement</th><th style={{ textAlign: 'right' }}>Top-up</th><th style={{ textAlign: 'right' }}>Non-refundable</th><th>FOC</th></tr></thead>
                  <tbody>{exchLoad.data.length === 0 ? <tr><td colSpan={10} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No exchanges</td></tr>
                    : exchLoad.data.map((r, i) => <tr key={i}>
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
                  {tableHeading(<>Overdue In Transit (&gt; 7 days)</>, trOverdueExport, trOverdueLoad, '0 0 4px')}
                  <table>
                    <thead><tr><th>From</th><th>To</th><th>Dispatched</th><th style={{ textAlign: 'right' }}>Days</th><th style={{ textAlign: 'right' }}>Lines</th><th style={{ textAlign: 'right' }}>Units</th></tr></thead>
                    <tbody>{loadedRows(trOverdueLoad, 6, 'Nothing overdue', (r, i) => <tr key={i}>
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
                    <tbody>{loadedRows(trReceiptsLoad, 6, 'No receipts', (r, i) => <tr key={i}>
                          <td style={{ fontSize: 12.5 }}>{r.source_name}</td><td style={{ fontSize: 12.5 }}>{r.dest_name}</td>
                          <td style={{ fontSize: 12 }}>{new Date(r.received_at).toLocaleString()}</td>
                          <td style={{ fontSize: 12 }}>{r.received_by_name ?? '—'}</td>
                          <td style={{ textAlign: 'right' }}>{r.received_units}</td>
                          <td>{r.had_discrepancy
                            ? (r.discrepancy_resolved ? <span className="badge badge-muted">Resolved</span> : <span className="badge badge-danger">Open</span>)
                            : <span className="badge badge-success">Clean</span>}</td>
                        </tr>)}</tbody>
                  </table>
                  {tableHeading('Discrepancy Lines', trDiscExport, trDiscLoad)}
                  <table>
                    <thead><tr><th>Destination</th><th>Product</th><th style={{ textAlign: 'right' }}>Approved</th><th style={{ textAlign: 'right' }}>Received</th><th style={{ textAlign: 'right' }}>Δ</th><th>Reason</th><th>Resolution</th></tr></thead>
                    <tbody>{loadedRows(trDiscLoad, 7, 'No discrepancies', (r, i) => <tr key={i}>
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
                      : repFoc.map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{focDate(r)}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td><td style={{ fontSize: 12 }}>{r.line_kind}</td><td style={{ fontSize: 12 }}>{r.description}</td><td style={{ textAlign: 'right' }}>{r.quantity}</td><td style={{ textAlign: 'right', fontWeight: 600 }}>{r.foc_quantity}</td><td style={{ textAlign: 'right' }}>{money(Number(r.normal_value))}</td><td style={{ textAlign: 'right', color: 'var(--success)', fontWeight: 700 }}>{money(Number(r.foc_value))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.charged_value))}</td><td style={{ fontSize: 11.5 }}>{r.foc_reason ?? '—'}</td><td style={{ fontSize: 11.5 }}>{r.foc_by_name ?? '—'}</td></tr>)}</tbody>
                  </table>
                </>
              )}
              {tab === 'r_discounts' && (
                <table>
                  <thead><tr><th>Invoice</th><th>Business date</th><th>Store</th><th>Staff</th><th>Customer</th>
                    {DISCOUNT_COLUMNS.map(c => <th key={c.header} style={{ textAlign: 'right' }}>{c.header}</th>)}<th style={{ textAlign: 'right' }}>Total</th></tr></thead>
                  <tbody>{repDiscounts.length === 0 ? <tr><td colSpan={6 + DISCOUNT_COLUMNS.length} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No discounts</td></tr>
                    : repDiscounts.map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{pricingDate(r)}</td><td style={{ fontSize: 12 }}>{r.store_name}</td><td style={{ fontSize: 12 }}>{r.staff_names ?? '—'}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td>
                      {DISCOUNT_COLUMNS.map(c => <td key={c.header} style={{ textAlign: 'right' }}>{money(c.value(r))}</td>)}
                      <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.total_discount))}</td></tr>)}</tbody>
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
