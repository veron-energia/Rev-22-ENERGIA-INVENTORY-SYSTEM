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

type Tab = 'sales_store' | 'sales_affiliate' | 'commission' | 'stock' | 'top_products' | 'customers' | 'vouchers' | 'promotions' | 'specials' | 'sales_creator' | 'sales_service_staff' | 'r_membership' | 'r_pricing' | 'r_affiliate' | 'r_therapy' | 'r_discounts' | 'r_foc';

const ReportsPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isManagerOrAbove(profile?.role)) return <NoAccess message="Only Owners, Admins, and Managers can view reports." />;

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
  const [repMembership, setRepMembership] = useState<any[]>([]);
  const [repPricing, setRepPricing] = useState<any[]>([]);
  const [repAffiliate, setRepAffiliate] = useState<any[]>([]);
  const [repTherapy, setRepTherapy] = useState<any[]>([]);
  const [repDiscounts, setRepDiscounts] = useState<any[]>([]);
  const [repFoc, setRepFoc] = useState<any[]>([]);
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
    const [rm, rp, ra, rt, rdc, rfl, rfs] = await Promise.all([
      supabase.rpc('report_memberships'),
      supabase.rpc('report_pricing'),
      supabase.rpc('report_affiliates'),
      supabase.rpc('report_therapy'),
      supabase.rpc('report_discounts'),
      // Phase 12 — FOC. Defaults to the last 30 days on the server.
      supabase.rpc('report_foc_lines', { p_from: null, p_to: null, p_store_id: null }),
      supabase.rpc('report_foc_summary', { p_from: null, p_to: null, p_store_id: null }),
    ]);
    setRepMembership((rm.data as any[]) ?? []);
    setRepPricing((rp.data as any[]) ?? []);
    setRepAffiliate((ra.data as any[]) ?? []);
    setRepTherapy((rt.data as any[]) ?? []);
    setRepDiscounts((rdc.data as any[]) ?? []);
    setRepFoc((rfl.data as any[]) ?? []);
    setFocSummary(rfs.data ?? null);
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
    { id: 'r_membership', label: 'Membership', icon: <CreditCard size={15} /> },
    { id: 'r_pricing', label: 'Pricing', icon: <KeyRound size={15} /> },
    { id: 'r_affiliate', label: 'Affiliate', icon: <Star size={15} /> },
    { id: 'r_therapy', label: 'Therapy', icon: <Sparkles size={15} /> },
    { id: 'r_discounts', label: 'Discounts', icon: <Ticket size={15} /> },
    { id: 'r_foc', label: 'FOC', icon: <Gift size={15} /> },
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
      r_membership: repMembership, r_pricing: repPricing, r_affiliate: repAffiliate,
      r_therapy: repTherapy, r_discounts: repDiscounts, r_foc: repFoc,
    };
    exportCsv(`report-${tab}.csv`, (dump[tab] ?? []) as any[]);
  };

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
              {tab === 'r_membership' && (
                <table>
                  <thead><tr><th>Membership</th><th>Customer</th><th>Member ID</th><th>Plan</th><th>Store</th><th>Start</th><th>Expiry</th><th>Status</th><th style={{ textAlign: 'right' }}>Days Left</th></tr></thead>
                  <tbody>{repMembership.length === 0 ? <tr><td colSpan={9} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No memberships</td></tr>
                    : repMembership.map((r, i) => <tr key={i}><td>{r.membership_no}</td><td><strong>{r.customer_name}</strong></td><td style={{ color: r.missing_member_id ? 'var(--danger)' : undefined }}>{r.member_id ?? 'missing'}</td><td>{r.plan_name ?? '—'}</td><td style={{ color: r.missing_store ? 'var(--danger)' : undefined }}>{r.store_name ?? 'missing'}</td><td style={{ fontSize: 12 }}>{r.start_date ? new Date(r.start_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ fontSize: 12 }}>{r.expiry_date ? new Date(r.expiry_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ textTransform: 'capitalize' }}>{r.is_complimentary ? 'complimentary' : r.status}</td><td style={{ textAlign: 'right' }}>{r.days_left ?? '—'}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'r_pricing' && (
                <table>
                  <thead><tr><th>Invoice</th><th>Date</th><th>Store</th><th>Customer</th><th>Item</th><th>Kind</th><th style={{ textAlign: 'right' }}>Qty</th><th style={{ textAlign: 'right' }}>Price</th><th>Mode</th><th>Override</th></tr></thead>
                  <tbody>{repPricing.length === 0 ? <tr><td colSpan={10} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No paid lines</td></tr>
                    : repPricing.slice(0, 500).map((r, i) => <tr key={i}><td>{r.invoice_no}</td><td style={{ fontSize: 12 }}>{r.paid_date ? new Date(r.paid_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ fontSize: 12 }}>{r.store_name}</td><td style={{ fontSize: 12 }}>{r.customer_name}</td><td>{r.item_name}</td><td style={{ fontSize: 12 }}>{r.line_kind}</td><td style={{ textAlign: 'right' }}>{r.quantity}</td><td style={{ textAlign: 'right' }}>{money(Number(r.unit_price))}</td><td>{r.price_mode === 'member' ? 'Member' : r.price_mode === 'non_member' ? 'Non-Member' : '—'}</td><td style={{ fontSize: 11.5, color: r.price_overridden ? 'var(--danger)' : 'var(--text-muted)' }}>{r.price_overridden ? (r.override_reason ?? 'yes') : '—'}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'r_affiliate' && (
                <table>
                  <thead><tr><th>Customer</th><th>Member ID</th><th>Eligibility</th><th>Store</th><th style={{ textAlign: 'right' }}>Referrals</th><th style={{ textAlign: 'right' }}>Tier 1</th><th style={{ textAlign: 'right' }}>Tier 2</th><th style={{ textAlign: 'right' }}>Earned</th><th style={{ textAlign: 'right' }}>Paid</th><th style={{ textAlign: 'right' }}>Reversed</th><th style={{ textAlign: 'right' }}>Blocked</th></tr></thead>
                  <tbody>{repAffiliate.length === 0 ? <tr><td colSpan={11} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No affiliates</td></tr>
                    : repAffiliate.map((r, i) => <tr key={i}><td><strong>{r.customer_name}</strong></td><td>{r.member_id ?? '—'}</td><td style={{ fontSize: 12 }}>{r.affiliate_state === 'active' ? 'Eligible' : (r.block_reason ?? r.affiliate_state)}</td><td style={{ fontSize: 12 }}>{r.store_name ?? '—'}</td><td style={{ textAlign: 'right' }}>{r.direct_referrals}</td><td style={{ textAlign: 'right' }}>{money(Number(r.tier1_earned))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.tier2_earned))}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.earned))}</td><td style={{ textAlign: 'right' }}>{money(Number(r.paid))}</td><td style={{ textAlign: 'right', color: 'var(--text-muted)' }}>{money(Number(r.reversed))}</td><td style={{ textAlign: 'right', color: Number(r.blocked) > 0 ? 'var(--danger)' : 'var(--text-muted)' }}>{money(Number(r.blocked))}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'r_therapy' && (
                <table>
                  <thead><tr><th>No.</th><th>Customer</th><th>Package</th><th>Store</th><th style={{ textAlign: 'right' }}>Price</th><th>Mode</th><th>Purchased</th><th>Activation</th><th>Expiry</th><th>Status</th><th>Type</th></tr></thead>
                  <tbody>{repTherapy.length === 0 ? <tr><td colSpan={11} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No therapy</td></tr>
                    : repTherapy.map((r, i) => <tr key={i}><td>{r.entitlement_no}</td><td><strong>{r.customer_name}</strong></td><td>{r.package_name}</td><td style={{ fontSize: 12 }}>{r.store_name ?? '—'}</td><td style={{ textAlign: 'right' }}>{money(Number(r.price_snapshot))}</td><td>{r.price_mode === 'member' ? 'M' : r.price_mode === 'non_member' ? 'NM' : '—'}</td><td style={{ fontSize: 12 }}>{r.purchase_date ? new Date(r.purchase_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ fontSize: 12 }}>{r.activation_date ? new Date(r.activation_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ fontSize: 12 }}>{r.expiry_date ? new Date(r.expiry_date).toLocaleDateString('en-GB') : '—'}</td><td style={{ textTransform: 'capitalize' }}>{String(r.status).replace('_', ' ')}</td><td style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{r.is_legacy ? 'Legacy' : 'Purchased'}</td></tr>)}</tbody>
                </table>
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
