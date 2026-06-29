import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import {
  Invoice, Store, Product, Affiliate, AffiliateCommission, Customer,
  WarehouseInventory, StoreInventory, Warehouse, isManagerOrAbove,
} from '../types';
import { NoAccess } from '../components/ui';
import { RefreshCw, BarChart3, TrendingUp, Package, Star, Users } from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;

type Tab = 'sales_store' | 'sales_affiliate' | 'commission' | 'stock' | 'top_products' | 'customers';

const ReportsPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isManagerOrAbove(profile?.role)) return <NoAccess message="Only Owners, Admins, and Managers can view reports." />;

  const [tab, setTab] = useState<Tab>('sales_store');
  const [loading, setLoading] = useState(true);

  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [stores, setStores] = useState<Store[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [affiliates, setAffiliates] = useState<Affiliate[]>([]);
  const [commissions, setCommissions] = useState<AffiliateCommission[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [whInv, setWhInv] = useState<WarehouseInventory[]>([]);
  const [stInv, setStInv] = useState<StoreInventory[]>([]);
  const [items, setItems] = useState<{ product_id: string; quantity: number; line_total: number; invoice_id: string }[]>([]);

  const load = useCallback(async () => {
    setLoading(true);
    const [inv, st, pr, af, co, cu, wh, wi, si, it] = await Promise.all([
      supabase.from('invoices').select('*').is('deleted_at', null),
      supabase.from('stores').select('*'),
      supabase.from('products').select('*'),
      supabase.from('affiliates').select('*'),
      supabase.from('affiliate_commissions').select('*'),
      supabase.from('customers').select('*'),
      supabase.from('warehouses').select('*'),
      supabase.from('warehouse_inventory').select('*'),
      supabase.from('store_inventory').select('*'),
      supabase.from('invoice_items').select('product_id,quantity,line_total,invoice_id'),
    ]);
    setInvoices((inv.data as Invoice[]) ?? []);
    setStores((st.data as Store[]) ?? []);
    setProducts((pr.data as Product[]) ?? []);
    setAffiliates((af.data as Affiliate[]) ?? []);
    setCommissions((co.data as AffiliateCommission[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    setWarehouses((wh.data as Warehouse[]) ?? []);
    setWhInv((wi.data as WarehouseInventory[]) ?? []);
    setStInv((si.data as StoreInventory[]) ?? []);
    setItems((it.data as any[]) ?? []);
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

  // Sales by affiliate
  const salesByAffiliate = affiliates.map(a => {
    const aInv = paid.filter(i => i.affiliate_id === a.id);
    return { name: a.name, count: aInv.length, total: aInv.reduce((s, i) => s + Number(i.total_amount), 0) };
  }).filter(r => r.count > 0).sort((a, b) => b.total - a.total);

  // Commission report
  const commissionRows = affiliates.map(a => {
    const ac = commissions.filter(c => c.affiliate_id === a.id);
    const earned = ac.filter(c => c.status === 'earned').reduce((s, c) => s + Number(c.commission_amount), 0);
    const reversed = ac.filter(c => c.status === 'reversed').reduce((s, c) => s + Number(c.commission_amount), 0);
    return { name: a.name, earned, reversed, net: earned };
  }).filter(r => r.earned > 0 || r.reversed > 0).sort((a, b) => b.net - a.net);

  // Top products (by qty sold across paid invoices)
  const paidIds = new Set(paid.map(i => i.id));
  const prodAgg: Record<string, { qty: number; revenue: number }> = {};
  items.filter(it => paidIds.has(it.invoice_id)).forEach(it => {
    (prodAgg[it.product_id] ??= { qty: 0, revenue: 0 });
    prodAgg[it.product_id].qty += it.quantity;
    prodAgg[it.product_id].revenue += Number(it.line_total);
  });
  const topProducts = Object.entries(prodAgg).map(([id, v]) => ({ name: pName(id), ...v })).sort((a, b) => b.qty - a.qty);

  // Customers report
  const custRows = customers.map(c => {
    const cInv = paid.filter(i => i.customer_id === c.id);
    return { name: c.full_name, phone: c.phone, count: cInv.length, total: cInv.reduce((s, i) => s + Number(i.total_amount), 0) };
  }).filter(r => r.count > 0).sort((a, b) => b.total - a.total);

  const totalRevenue = paid.reduce((s, i) => s + Number(i.total_amount), 0);

  const TABS: { id: Tab; label: string; icon: React.ReactNode }[] = [
    { id: 'sales_store', label: 'Sales by Store', icon: <TrendingUp size={15} /> },
    { id: 'top_products', label: 'Top Products', icon: <Package size={15} /> },
    { id: 'sales_affiliate', label: 'Sales by Affiliate', icon: <Star size={15} /> },
    { id: 'commission', label: 'Commission', icon: <BarChart3 size={15} /> },
    { id: 'customers', label: 'Customers', icon: <Users size={15} /> },
    { id: 'stock', label: 'Stock Balance', icon: <Package size={15} /> },
  ];

  return (
    <div>
      <div className="page-header">
        <div><h2>Reports</h2><p>Overview across sales, stock, affiliates, and customers. Total paid revenue: <strong style={{ color: 'var(--primary)' }}>{money(totalRevenue)}</strong></p></div>
        <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
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
                  <thead><tr><th>Affiliate</th><th style={{ textAlign: 'right' }}>Referred Paid</th><th style={{ textAlign: 'right' }}>Sales Value</th></tr></thead>
                  <tbody>{salesByAffiliate.length === 0 ? <tr><td colSpan={3} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No affiliate sales yet</td></tr>
                    : salesByAffiliate.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right' }}>{r.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.total)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'commission' && (
                <table>
                  <thead><tr><th>Affiliate</th><th style={{ textAlign: 'right' }}>Earned</th><th style={{ textAlign: 'right' }}>Reversed</th><th style={{ textAlign: 'right' }}>Net</th></tr></thead>
                  <tbody>{commissionRows.length === 0 ? <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No commissions yet</td></tr>
                    : commissionRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ textAlign: 'right', color: 'var(--success)' }}>{money(r.earned)}</td><td style={{ textAlign: 'right', color: 'var(--danger)' }}>{r.reversed > 0 ? `−${money(r.reversed)}` : '—'}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.net)}</td></tr>)}</tbody>
                </table>
              )}
              {tab === 'customers' && (
                <table>
                  <thead><tr><th>Customer</th><th>Phone</th><th style={{ textAlign: 'right' }}>Purchases</th><th style={{ textAlign: 'right' }}>Total Spent</th></tr></thead>
                  <tbody>{custRows.length === 0 ? <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 30 }}>No customer purchases yet</td></tr>
                    : custRows.map((r, i) => <tr key={i}><td><strong>{r.name}</strong></td><td style={{ fontSize: 12.5 }}>{r.phone}</td><td style={{ textAlign: 'right' }}>{r.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{money(r.total)}</td></tr>)}</tbody>
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
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default ReportsPage;
