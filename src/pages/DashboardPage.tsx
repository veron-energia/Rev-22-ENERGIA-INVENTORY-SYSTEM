import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { ROLE_LABELS, isManagerOrAbove } from '../types';
import { Package, Warehouse, Store, CreditCard, AlertTriangle, ArrowLeftRight, Star, Ticket, KeyRound, CalendarClock, TrendingUp, Clock, Ban, Sparkles } from 'lucide-react';

interface Counts {
  products: number;
  warehouses: number;
  stores: number;
  paymentMethods: number;
}

const StatCard: React.FC<{ icon: React.ReactNode; label: string; value: number | string; tint: string }> = ({ icon, label, value, tint }) => (
  <div className="card" style={{ padding: 20, display: 'flex', alignItems: 'center', gap: 16 }}>
    <div style={{ width: 46, height: 46, borderRadius: 11, background: tint, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      {icon}
    </div>
    <div>
      <div style={{ fontSize: 26, fontWeight: 700, fontFamily: 'var(--font-display)', lineHeight: 1 }}>{value}</div>
      <div style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 3 }}>{label}</div>
    </div>
  </div>
);

const DashboardPage: React.FC = () => {
  const { profile } = useAuth();
  const [counts, setCounts] = useState<Counts>({ products: 0, warehouses: 0, stores: 0, paymentMethods: 0 });
  const [loading, setLoading] = useState(true);

  // ── Phase 2: low stock alerts + pending approvals ──
  const [lowStock, setLowStock] = useState<{ name: string; sku: string; loc: string; qty: number; threshold: number }[]>([]);
  const [pendingApprovals, setPendingApprovals] = useState(0);
  const [todaySales, setTodaySales] = useState(0);
  const [todayCount, setTodayCount] = useState(0);
  // 5G-2 additions (Manager+ only — the underlying tables are RLS-gated)
  const [unpaidCommission, setUnpaidCommission] = useState(0);
  const [redemptionCount, setRedemptionCount] = useState(0);
  const [activeRentals, setActiveRentals] = useState(0);
  const [overdueRentals, setOverdueRentals] = useState(0);
  const [summary, setSummary] = useState<any>(null);
  // Phase 11: transfer receipt alerts (awaiting receipt / overdue / open discrepancies)
  const [transferAlerts, setTransferAlerts] = useState<{ awaiting_receipt: number; overdue: number; open_discrepancies: number } | null>(null);

  useEffect(() => {
    (async () => {
      // Pending transfer approvals (RLS shows only what the user can see).
      // Pending transfer approvals + invoice actions + adjustments.
      const [transferPending, otherPending] = await Promise.all([
        supabase.from('transfer_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
        supabase.from('approval_requests').select('id', { count: 'exact', head: true })
          .in('request_type', ['invoice_refund', 'invoice_cancel', 'adjustment']).eq('status', 'pending'),
      ]);
      setPendingApprovals((transferPending.count ?? 0) + (otherPending.count ?? 0));

      // Phase 8: role-scoped dashboard summary (Owner/Manager get the full set).
      const { data: sum } = await supabase.rpc('dashboard_summary');
      setSummary(sum ?? null);

      // Phase 11: transfer receipt / overdue / discrepancy alerts.
      const { data: ta } = await supabase.rpc('transfer_receipt_alerts');
      setTransferAlerts((ta as any) ?? null);

      // Today's paid sales.
      const startOfDay = new Date(); startOfDay.setHours(0, 0, 0, 0);
      const { data: paidToday } = await supabase.from('invoices')
        .select('total_amount')
        .eq('status', 'paid')
        .gte('paid_at', startOfDay.toISOString());
      const sales = (paidToday ?? []).reduce((s: number, i: any) => s + Number(i.total_amount), 0);
      setTodaySales(sales);
      setTodayCount((paidToday ?? []).length);

      // 5G-2 stats: unpaid commission, voucher redemptions, rentals.
      if (isManagerOrAbove(profile?.role)) {
        const [comm, redemp, rent] = await Promise.all([
          supabase.from('commissions').select('commission_amount').eq('status', 'earned'),
          supabase.from('voucher_redemptions').select('id', { count: 'exact', head: true }),
          supabase.from('rentals').select('status,expected_return_date').in('status', ['paid', 'active']),
        ]);
        setUnpaidCommission(((comm.data as any[]) ?? []).reduce((s, x) => s + Number(x.commission_amount), 0));
        setRedemptionCount(redemp.count ?? 0);
        const rents = (rent.data as any[]) ?? [];
        setActiveRentals(rents.length);
        const today = new Date().toISOString().slice(0, 10);
        setOverdueRentals(rents.filter(r => r.expected_return_date < today).length);
      }

      // Low stock across warehouse + store inventory.
      const [wh, st, prods, whs, sts] = await Promise.all([
        supabase.from('warehouse_inventory').select('*'),
        supabase.from('store_inventory').select('*'),
        supabase.from('products').select('id,name,sku'),
        supabase.from('warehouses').select('id,name'),
        supabase.from('stores').select('id,name'),
      ]);
      const pMap = new Map((prods.data ?? []).map((p: any) => [p.id, p]));
      const whMap = new Map((whs.data ?? []).map((w: any) => [w.id, w.name]));
      const stMap = new Map((sts.data ?? []).map((s: any) => [s.id, s.name]));
      const alerts: typeof lowStock = [];
      (wh.data ?? []).forEach((i: any) => {
        if (i.low_stock_threshold > 0 && i.current_qty <= i.low_stock_threshold) {
          const p = pMap.get(i.product_id);
          if (p) alerts.push({ name: p.name, sku: p.sku, loc: `🏭 ${whMap.get(i.warehouse_id) ?? ''}`, qty: i.current_qty, threshold: i.low_stock_threshold });
        }
      });
      (st.data ?? []).forEach((i: any) => {
        if (i.low_stock_threshold > 0 && i.current_qty <= i.low_stock_threshold) {
          const p = pMap.get(i.product_id);
          if (p) alerts.push({ name: p.name, sku: p.sku, loc: `🏪 ${stMap.get(i.store_id) ?? ''}`, qty: i.current_qty, threshold: i.low_stock_threshold });
        }
      });
      setLowStock(alerts);
    })();
  }, [profile?.role]);


  useEffect(() => {
    (async () => {
      const [p, w, s, pm] = await Promise.all([
        supabase.from('products').select('id', { count: 'exact', head: true }).is('deleted_at', null),
        supabase.from('warehouses').select('id', { count: 'exact', head: true }).is('deleted_at', null),
        supabase.from('stores').select('id', { count: 'exact', head: true }).is('deleted_at', null),
        supabase.from('payment_methods').select('id', { count: 'exact', head: true }).is('deleted_at', null),
      ]);
      setCounts({
        products: p.count ?? 0,
        warehouses: w.count ?? 0,
        stores: s.count ?? 0,
        paymentMethods: pm.count ?? 0,
      });
      setLoading(false);
    })();
  }, []);

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Welcome back, {profile?.full_name?.split(' ')[0]}</h2>
          <p>You're signed in as {profile ? ROLE_LABELS[profile.role] : ''}. Here's the current setup at a glance.</p>
        </div>
      </div>

      {isManagerOrAbove(profile?.role) && summary && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 12, marginBottom: 20 }}>
          <StatCard icon={<CreditCard size={20} color="var(--primary)" />} label="Membership sales today" value={`S$${Number(summary.membership_sales).toFixed(0)}`} tint="var(--primary-light)" />
          <StatCard icon={<TrendingUp size={20} color="var(--success)" />} label="Member sales today" value={`S$${Number(summary.member_sales).toFixed(0)}`} tint="var(--success-light)" />
          <StatCard icon={<TrendingUp size={20} color="var(--text-muted)" />} label="Non-member sales today" value={`S$${Number(summary.non_member_sales).toFixed(0)}`} tint="var(--surface-2)" />
          <StatCard icon={<Clock size={20} color="var(--accent)" />} label="Expiring memberships (90d)" value={summary.expiring_memberships} tint="var(--accent-light)" />
          <StatCard icon={<AlertTriangle size={20} color="var(--danger)" />} label="Missing Member IDs" value={summary.missing_member_ids} tint="var(--danger-light)" />
          <StatCard icon={<AlertTriangle size={20} color="var(--danger)" />} label="Missing membership stores" value={summary.missing_stores} tint="var(--danger-light)" />
          <StatCard icon={<Ban size={20} color="var(--danger)" />} label="Blocked commission" value={`S$${Number(summary.blocked_commission).toFixed(0)}`} tint="var(--danger-light)" />
          <StatCard icon={<Sparkles size={20} color="var(--accent)" />} label="Therapy awaiting activation" value={summary.therapy_awaiting} tint="var(--accent-light)" />
          <StatCard icon={<Clock size={20} color="var(--danger)" />} label="Therapy deadline warnings (30d)" value={summary.therapy_deadline_warn} tint="var(--danger-light)" />
          <StatCard icon={<Ticket size={20} color="var(--text-muted)" />} label="Discounts given today" value={`S$${Number(summary.discount_today).toFixed(0)}`} tint="var(--surface-2)" />
        </div>
      )}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 16, marginBottom: 28 }}>
        <StatCard icon={<CreditCard size={22} color="var(--success)" />} label={`Today's sales (${todayCount} paid)`} value={loading ? '—' : `S$${todaySales.toFixed(0)}`} tint="var(--success-light)" />
        <StatCard icon={<Package size={22} color="var(--primary)" />} label="Active products" value={loading ? '—' : counts.products} tint="var(--primary-light)" />
        <StatCard icon={<Warehouse size={22} color="#b45309" />} label="Warehouses" value={loading ? '—' : counts.warehouses} tint="var(--accent-light)" />
        <StatCard icon={<Store size={22} color="var(--primary)" />} label="Stores" value={loading ? '—' : counts.stores} tint="var(--primary-light)" />
      </div>

      {isManagerOrAbove(profile?.role) && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 16, marginBottom: 28 }}>
          <StatCard icon={<Star size={22} color="var(--primary)" />} label="Unpaid commission" value={loading ? '—' : `S$${unpaidCommission.toFixed(2)}`} tint="var(--primary-light)" />
          <StatCard icon={<Ticket size={22} color="var(--success)" />} label="Voucher redemptions" value={loading ? '—' : redemptionCount} tint="var(--success-light)" />
          <StatCard icon={<KeyRound size={22} color="#b45309" />} label="Rentals out (paid/active)" value={loading ? '—' : activeRentals} tint="var(--accent-light)" />
          <StatCard icon={<CalendarClock size={22} color="var(--danger)" />} label="Overdue rentals" value={loading ? '—' : overdueRentals} tint="var(--danger-light)" />
        </div>
      )}

      {/* Phase 2 + Phase 11 alerts */}
      {(pendingApprovals > 0 || lowStock.length > 0 ||
        (transferAlerts && (transferAlerts.awaiting_receipt > 0 || transferAlerts.open_discrepancies > 0))) && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 16, marginBottom: 28 }}>
          {transferAlerts && (transferAlerts.awaiting_receipt > 0 || transferAlerts.open_discrepancies > 0) && (
            <div className="card" style={{ padding: 20 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
                <ArrowLeftRight size={18} color="var(--primary)" />
                <h3 style={{ fontSize: 15 }}>Transfers</h3>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontSize: 13, color: 'var(--text-secondary)' }}>
                <div>Awaiting receipt: <strong>{transferAlerts.awaiting_receipt}</strong></div>
                {transferAlerts.overdue > 0 && <div style={{ color: 'var(--danger)' }}>Overdue &gt; 7 days: <strong>{transferAlerts.overdue}</strong></div>}
                {transferAlerts.open_discrepancies > 0 && <div style={{ color: 'var(--danger)' }}>Open discrepancies: <strong>{transferAlerts.open_discrepancies}</strong></div>}
                <div><a href="/transfers">Go to Transfers →</a></div>
              </div>
            </div>
          )}
          {pendingApprovals > 0 && (
            <div className="card" style={{ padding: 20 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
                <ArrowLeftRight size={18} color="var(--primary)" />
                <h3 style={{ fontSize: 15 }}>Pending Approvals</h3>
              </div>
              <p style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
                <strong style={{ fontSize: 22, fontFamily: 'var(--font-display)' }}>{pendingApprovals}</strong> request{pendingApprovals !== 1 ? 's' : ''} waiting for review.{' '}
                <a href="/transfers">Transfers →</a> · <a href="/approvals">Approvals →</a>
              </p>
            </div>
          )}
          {lowStock.length > 0 && (
            <div className="card" style={{ padding: 20 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
                <AlertTriangle size={18} color="var(--accent)" />
                <h3 style={{ fontSize: 15 }}>Low Stock Alerts</h3>
                <span className="badge badge-accent" style={{ marginLeft: 'auto' }}>{lowStock.length}</span>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 180, overflowY: 'auto' }}>
                {lowStock.slice(0, 8).map((a, i) => (
                  <div key={i} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 12.5, padding: '6px 10px', background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div><strong>{a.name}</strong> <span style={{ color: 'var(--text-muted)' }}>{a.loc}</span></div>
                    <div style={{ color: 'var(--accent)', fontWeight: 700 }}>{a.qty} / {a.threshold}</div>
                  </div>
                ))}
                {lowStock.length > 8 && <p style={{ fontSize: 11.5, color: 'var(--text-muted)', textAlign: 'center' }}>+ {lowStock.length - 8} more</p>}
              </div>
            </div>
          )}
        </div>
      )}

      <div className="card" style={{ padding: 24 }}>
        <h3 style={{ fontSize: 16, marginBottom: 10 }}>System Complete — All Phases Live</h3>
        <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 16, maxWidth: 640 }}>
          The full inventory and sales platform is in place: authentication and roles, warehouse
          and store inventory with approval-driven transfers, the sales engine with split payments
          and affiliate commission, and the controls layer — refunds, cancellations, inventory
          adjustments, audit log, and reports.
        </p>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 12 }}>
          {[
            { phase: 'Phase 1', title: 'Foundation', detail: 'Auth · Roles · Products · Warehouses · Stores · Payment methods' },
            { phase: 'Phase 2', title: 'Inventory', detail: 'Warehouse & store stock · Stock-in · Transfers · Approvals' },
            { phase: 'Phase 3', title: 'Sales', detail: 'Customers · Affiliates · Price lists · Invoices · Payments' },
            { phase: 'Phase 4', title: 'Controls', detail: 'Refunds · Adjustments · Audit log · Reports' },
          ].map(p => (
            <div key={p.phase} style={{ padding: 14, borderRadius: 'var(--radius-sm)', border: '1px solid var(--border)', background: 'var(--primary-light)' }}>
              <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--primary)', letterSpacing: '0.05em' }}>{p.phase} · LIVE</div>
              <div style={{ fontWeight: 600, fontSize: 14, margin: '4px 0 5px' }}>{p.title}</div>
              <div style={{ fontSize: 11.5, color: 'var(--text-muted)', lineHeight: 1.45 }}>{p.detail}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default DashboardPage;
