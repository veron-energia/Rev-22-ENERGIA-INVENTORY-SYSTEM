import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { exportCsv } from '../lib/csv';
import { useAuth } from '../context/AuthContext';
import {
  Invoice, Store, Product, Commission, Customer,
  WarehouseInventory, StoreInventory, Warehouse, isManagerOrAbove,
} from '../types';
import { NoAccess } from '../components/ui';
import { RefreshCw, BarChart3, TrendingUp, Package, Star, Users, Download, Ticket, Package2, KeyRound, UserCircle, Award, CreditCard, Sparkles, Gift } from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;

type Tab = 'sales_store' | 'sales_affiliate' | 'commission' | 'stock' | 'top_products' | 'customers' | 'vouchers' | 'promotions' | 'specials' | 'sales_creator' | 'sales_service_staff' | 'r_pricing' | 'r_affiliate' | 'r_therapy' | 'r_discounts' | 'r_foc' | 'r_sources' | 'r_tiktok' | 'r_exchange_inv' | 'r_transfers' | 'r_salesrecon';

const ReportsPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isManagerOrAbove(profile?.role);
  const [tab, setTab] = useState<Tab>('sales_store');
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
  const [ttBasis, setTtBasis] = useState<'created' | 'settled'>('created');
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

  const load = useCallback(async () => {
    setLoading(true);
    const [inv, st, pr, co, cu, wh, wi, si, it, vc, pm, rd, ss, re, sp, prof, iss] = await Promise.all([
      supabase.from('invoices').select('*').is('deleted_at', null),
      supabase.from('stores').select('*'),
      supabase.from('products').select('*'),
      supabase.from('commissions').select('*'),
      supabase.from('customers').select('*'),
      supabase.from('warehouses').select('*'),
      supabase.from('warehouse_inventory').select('*'),
      supabase.from('store_inventory').select('*'),
      supabase.from('invoice_items').select('product_id,quantity,line_total,invoice_id,line_kind,voucher_id,promotion_id,topup_amount'),
      supabase.from('vouchers').select('*').is('deleted_at', null),
      supabase.from('promotions').select('*').is('deleted_at', null),
      supabase.from('voucher_redemptions').select('*'),
      supabase.from('special_sales').select('*'),
      supabase.from('rentals').select('*'),
      supabase.from('special_products').select('*').is('deleted_at', null),
      supabase.from('profiles').select('id,full_name,role').is('deleted_at', null),
      supabase.from('invoice_service_staff').select('invoice_id,staff_id'),
    ]);
    setInvoices((inv.data as Invoice[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setProducts((pr.data as Product[]) ?? []);
    setCommissions((co.data as Commission[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    setWhInv((wi.data as WarehouseInventory[]) ?? []);
    setStInv((si.data as StoreInventory[]) ?? []);
    setItems((it.data as any[]) ?? []);
    setVouchers((vc.data as any[]) ?? []);
    setPromotions((pm.data as any[]) ?? []);
    setRedemptions((rd.data as any[]) ?? []);
    setSpecialSales((ss.data as any[]) ?? []);
    setRentals((re.data as any[]) ?? []);
    setSpecialProducts((sp.data as any[]) ?? []);
    setProfiles((prof.data as any[]) ?? []);
    setServiceStaff((iss.data as any[]) ?? []);
    // Phase 8 report views (via RPC).
    const [rp, ra, rt, rdc, rfl, rfs, rsrc, tts, ttr] = await Promise.all([
      supabase.rpc('report_pricing'),
      supabase.rpc('report_affiliates'),
      supabase.rpc('report_therapy'),
      supabase.rpc('report_discounts'),
      // Phase 12 — FOC. Defaults to the last 30 days on the server.
      supabase.rpc('report_foc_lines', { p_from: null, p_to: null, p_store_id: null }),
      supabase.rpc('report_foc_summary', { p_from: null, p_to: null, p_store_id: null }),
      // Phase 14 — customer sources (current vs survey snapshots).
      supabase.rpc('report_customer_sources', { p_from: null, p_to: null }),
      // Phase 17 — TikTok settlement (main figure: Total Settlement Amount).
      supabase.rpc('report_tiktok_settlement_summary', { p_store_id: null, p_from: null, p_to: null }),
      supabase.rpc('report_tiktok_settlement', { p_store_id: null, p_from: null, p_to: null }),
    ]);
    setRepPricing((rp.data as any[]) ?? []);
    setRepAffiliate((ra.data as any[]) ?? []);
    setRepTherapy((rt.data as any[]) ?? []);
    setRepDiscounts((rdc.data as any[]) ?? []);
    setRepFoc((rfl.data as any[]) ?? []);
    setFocSummary(rfs.data ?? null);
    setRepSources((rsrc.data as any[]) ?? []);
    setTtSummary(((tts.data as any[]) ?? [])[0] ?? null);
    setTtRows((ttr.data as any[]) ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const paid = invoices.filter(i => i.status === 'paid');
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
    const invoiceCount = new Set(t1.map(c => c.invoice_id)).size;
    const salesValue = t1.reduce((s, c) => s + Number(c.line_amount), 0);
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
    prodAgg[it.product_id].qty += it.quantity;
    prodAgg[it.product_id].revenue += Number(it.line_total);
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
          supabase.rpc('report_tiktok_settlement_daily', { p_store_id: null, p_from: null, p_to: null, p_basis: ttBasis }),
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
      } else if (tab === 'r_salesrecon') {
        const { data } = await supabase.rpc('report_sales_reconciliation', { p_store_id: null, p_from: null, p_to: null });
        setSalesRecon((data as any[]) ?? []);
      }
    };
    fetchExtras();
  }, [tab, ttBasis]);

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
    const reds = redemptions.filter(r => r.voucher_id === v.id);
    return {
      name: v.name, kind: v.voucher_kind,
      sold_qty: sold.reduce((s, it) => s + it.quantity, 0),
      sales_value: sold.reduce((s, it) => s + Number(it.line_total), 0),
      redemptions: reds.length,
      discount_given: reds.reduce((s, r) => s + Number(r.discount_applied), 0),
    };
  }).filter(r => r.sold_qty > 0 || r.redemptions > 0).sort((a, b) => b.sales_value - a.sales_value);

  const promoRows = promotions.map(p => {
    const sold = items.filter(it => it.line_kind === 'promotion' && it.promotion_id === p.id && paidInvIds.has(it.invoice_id));
    return {
      name: p.name, code: p.code,
      sold_qty: sold.reduce((s, it) => s + it.quantity, 0),
      topups: sold.reduce((s, it) => s + Number(it.topup_amount ?? 0), 0),
      revenue: sold.reduce((s, it) => s + Number(it.line_total), 0),
    };
  }).filter(r => r.sold_qty > 0).sort((a, b) => b.revenue - a.revenue);

  const specialRows = specialProducts.map(p => {
    const salesOf = specialSales.filter(s => s.special_product_id === p.id && s.status === 'paid');
    const rentsOf = rentals.filter(r => r.special_product_id === p.id && r.status !== 'draft' && r.status !== 'cancelled');
    return {
      name: p.name,
      units_sold: salesOf.reduce((s, x) => s + x.quantity, 0),
      sales_revenue: salesOf.reduce((s, x) => s + Number(x.total_amount), 0),
      rentals: rentsOf.length,
      rental_fees: rentsOf.reduce((s, x) => s + Number(x.rental_fee), 0),
      late_fees: rentsOf.reduce((s, x) => s + Number(x.late_fee_total), 0),
    };
  }).filter(r => r.units_sold > 0 || r.rentals > 0).sort((a, b) => (b.sales_revenue + b.rental_fees) - (a.sales_revenue + a.rental_fees));

  const doExport = () => {
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
      r_pricing: repPricing, r_affiliate: repAffiliate,
      r_therapy: repTherapy, r_discounts: repDiscounts, r_foc: repFoc, r_sources: repSources, r_tiktok: ttRows, r_exchange_inv: exchInv, r_transfers: trReceipts, r_salesrecon: salesRecon,
    };
    exportCsv(`report-${tab}.csv`, (dump[tab] ?? []) as any[]);
  };

  if (!hasAccess) return <NoAccess message="Only Owners, Admins, and Managers can view reports." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Reports</h2><p>Overview across sales, stock, referrers, and customers. Total paid revenue: <strong style={{ color: 'var(--primary)' }}>{money(totalRevenue)}</strong></p></div>
        <div style={{ display: 'flex', gap: 10 }}><button className="btn btn-secondary" onClick={doExport}><Download size={15} /> Export CSV</button><button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button></div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 16, flexWrap: 'wrap' }}>
        {TABS.map(t => (
          <button key={t.id} className={`btn btn-sm ${tab === t.id ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab(t.id)}>{t.icon} {t.label}</button>
        ))}
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : (
            <>
              {tab === 'sales_store' && (
                <table>
                  <thead><tr><th>Store</th><th style={{ textAlign: 'right' }}>Paid Invoices</th><th style={{ textAlign: 'right' }}>Revenue</th></tr></thead>
                  <tbody>{salesByStore.length === 0 ? <tr><td colSpan={3} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No paid sales yet</td></tr>
                    : salesByStore.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.total)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'top_products' && (
                <table>
                  <thead><tr><th>Product</th><th style={{ textAlign: 'right' }}>Qty Sold</th><th style={{ textAlign: 'right' }}>Revenue</th></tr></thead>
                  <tbody>{topProducts.length === 0 ? <tr><td colSpan={3} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No sales yet</td></tr>
                    : topProducts.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.qty}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.revenue)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'sales_affiliate' && (
                <table>
                  <thead><tr><th>Referrer</th><th style={{ textAlign: 'right' }}>Referred Paid Invoices</th><th style={{ textAlign: 'right' }}>Commissionable Value</th><th style={{ textAlign: 'right' }}>Commission</th></tr></thead>
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
                  <thead><tr><th>Voucher</th><th>Type</th><th style={{ textAlign: 'right' }}>Sold Qty</th><th style={{ textAlign: 'right' }}>Sales Value</th><th style={{ textAlign: 'right' }}>Redemptions</th><th style={{ textAlign: 'right' }}>Discount Given</th></tr></thead>
                  <tbody>{voucherRows.length === 0 ? <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No voucher activity yet</td></tr>
                    : voucherRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ fontSize: 12 }}>{r.kind}</td><td style={{ textAlign: 'right' }}>{r.sold_qty}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.sales_value)}</td><td style={{ textAlign: 'right' }}>{r.redemptions}</td><td style={{ textAlign: 'right', color: 'var(--danger)' }}>{r.discount_given > 0 ? `−${money(r.discount_given)}` : '—'}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'promotions' && (
                <table>
                  <thead><tr><th>Promotion</th><th>Code</th><th style={{ textAlign: 'right' }}>Sold Qty</th><th style={{ textAlign: 'right' }}>Top-ups</th><th style={{ textAlign: 'right' }}>Revenue</th></tr></thead>
                  <tbody>{promoRows.length === 0 ? <tr><td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No promotion sales yet</td></tr>
                    : promoRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ fontSize: 12 }}>{r.code}</td><td style={{ textAlign: 'right' }}>{r.sold_qty}</td><td style={{ textAlign: 'right' }}>{r.topups > 0 ? money(r.topups) : '—'}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.revenue)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'specials' && (
                <table>
                  <thead><tr><th>Special Product</th><th style={{ textAlign: 'right' }}>Units Sold</th><th style={{ textAlign: 'right' }}>Sales Revenue</th><th style={{ textAlign: 'right' }}>Rentals</th><th style={{ textAlign: 'right' }}>Rental Fees</th><th style={{ textAlign: 'right' }}>Late Fees</th></tr></thead>
                  <tbody>{specialRows.length === 0 ? <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No special product activity yet</td></tr>
                    : specialRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.units_sold}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.sales_revenue)}</td><td style={{ textAlign: 'right' }}>{r.rentals}</td><td style={{ textAlign: 'right' }}>{money(r.rental_fees)}</td><td style={{ textAlign: 'right', color: 'var(--danger)' }}>{r.late_fees > 0 ? money(r.late_fees) : '—'}</td></tr>)}</tbody>
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
                  <thead><tr><th>Invoice</th><th>Date</th><th>Store</th><th>Customer</th><th>Item</th><th>Kind</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>Price</th></tr></thead>
                  <tbody>{repPricing.length === 0 ? <tr><td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No paid lines</td></tr>
                    : repPricing.slice(0, 500).map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{r.paid_date ? new Date(r.paid_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ fontSize: 12 }}>{r.store_name}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td><td>{r.item_name}</td><td style={{ fontSize: 12 }}>{r.line_kind}</td><td style={{ textAlign: 'right' }}>{r.quantity}</td><td style={{ textAlign: 'right' }}>{money(Number(r.unit_price))}</td></tr>)}</tbody>
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

                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, margin: '18px 0 4px' }}>
                    <h3 style={{ fontSize: 14, flex: 1 }}>Settlement by Day</h3>
                    {(['created', 'settled'] as const).map(b => (
                      <button key={b} className={`btn btn-sm ${ttBasis === b ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTtBasis(b)}>
                        {b === 'created' ? 'Order-created date' : 'Settled date'}</button>
                    ))}
                  </div>
                  <table>
                    <thead><tr><th>Day</th><th style={{ textAlign: 'right' }}>Txns</th><th style={{ textAlign: 'right' }}>Settlement</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th></tr></thead>
                    <tbody>{ttDaily.length === 0 ? <tr><td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 20 }}>No data</td></tr>
                      : ttDaily.map((r, i) => <tr key={i}>
                          <td style={{ fontSize: 12 }}>{new Date(r.day).toLocaleDateString('en-GB')}</td>
                          <td style={{ textAlign: 'right' }}>{r.transactions}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.settlement))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.revenue))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(r.fees))}</td>
                        </tr>)}</tbody>
                  </table>

                  <h3 style={{ fontSize: 14, margin: '18px 0 4px' }}>Settlement by Store</h3>
                  <table>
                    <thead><tr><th>Store</th><th style={{ textAlign: 'right' }}>Txns</th><th style={{ textAlign: 'right' }}>Settlement</th><th style={{ textAlign: 'right' }}>Revenue</th><th style={{ textAlign: 'right' }}>Fees</th><th style={{ textAlign: 'right' }}>Pending</th><th style={{ textAlign: 'right' }}>⚠ Recon</th></tr></thead>
                    <tbody>{ttByStore.map((r, i) => <tr key={i}>
                        <td style={{ fontWeight: 600 }}>{r.store_name}</td>
                        <td style={{ textAlign: 'right' }}>{r.transactions}</td>
                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.settlement))}</td>
                        <td style={{ textAlign: 'right' }}>{money(Number(r.revenue))}</td>
                        <td style={{ textAlign: 'right' }}>{money(Number(r.fees))}</td>
                        <td style={{ textAlign: 'right' }}>{r.pending_count}</td>
                        <td style={{ textAlign: 'right', color: Number(r.unreconciled_count) > 0 ? 'var(--danger)' : 'inherit' }}>{r.unreconciled_count}</td>
                      </tr>)}</tbody>
                  </table>

                  <h3 style={{ fontSize: 14, margin: '18px 0 4px' }}>Quantity Sold (net of returns)</h3>
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
                    <thead><tr><th>Invoice</th><th>Date</th><th>Customer</th><th>Kind</th><th>Item</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>FOC Qty</th><th style={{ textAlign: 'right' }}>Normal</th><th style={{ textAlign: 'right' }}>FOC</th><th style={{ textAlign: 'right' }}>Charged</th><th>Reason</th><th>By</th></tr></thead>
                    <tbody>{repFoc.length === 0 ? <tr><td colSpan={12} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No FOC in this period</td></tr>
                      : repFoc.map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{r.settled_at ? new Date(r.settled_at).toLocaleDateString('en-GB') : '—'}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td><td style={{ fontSize: 12 }}>{r.line_kind}</td><td style={{ fontSize: 12 }}>{r.description}</td><td style={{ textAlign: 'right' }}>{r.quantity}</td><td style={{ textAlign: 'right', fontWeight: 600 }}>{r.foc_quantity}</td><td style={{ textAlign: 'right' }}>{money(Number(r.normal_value))}</td><td style={{ textAlign: 'right', color: 'var(--success)', fontWeight: 700 }}>{money(Number(r.foc_value))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.charged_value))}</td><td style={{ fontSize: 11.5 }}>{r.foc_reason ?? '—'}</td><td style={{ fontSize: 11.5 }}>{r.foc_by_name ?? '—'}</td></tr>)}</tbody>
                  </table>
                </>
              )}
              {tab === 'r_discounts' && (
                <table>
                  <thead><tr><th>Invoice</th><th>Date</th><th>Store</th><th>Staff</th><th>Customer</th><th style={{ textAlign: 'right' }}>Save Earth</th><th style={{ textAlign: 'right' }}>Voucher</th><th style={{ textAlign: 'right' }}>Promotion</th><th style={{ textAlign: 'right' }}>Line</th><th style={{ textAlign: 'right' }}>Manual</th><th style={{ textAlign: 'right' }}>Total</th></tr></thead>
                  <tbody>{repDiscounts.length === 0 ? <tr><td colSpan={11} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No discounts</td></tr>
                    : repDiscounts.map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{r.paid_date ? new Date(r.paid_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ fontSize: 12 }}>{r.store_name}</td><td style={{ fontSize: 12 }}>{r.staff_names ?? '—'}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td><td style={{ textAlign: 'right' }}>{money(Number(r.save_earth))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.voucher_discount))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.promotion_discount))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.line_discount))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.manual_discount))}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.total_discount))}</td></tr>)}</tbody>
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
