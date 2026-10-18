import { useNavigate } from 'react-router-dom';
import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { fetchAllFrom } from '../lib/supabasePaging';
import { useAuth } from '../context/AuthContext';
import { ROLE_LABELS, isManagerOrAbove } from '../types';
import { singaporeToday } from '../lib/invoices/business';
import { focSnapshot, focWindowStart, type FocSnapshot } from '../lib/dashboard/focSnapshot.mjs';
import { dashboardCommissionFigures } from '../lib/affiliatePayoutPresentation';
import { Package, Warehouse, Store, CreditCard, AlertTriangle, ArrowLeftRight, Star, Ticket, KeyRound, CalendarClock, Clock, Ban, Sparkles, Users } from 'lucide-react';

// null: the count could not be read (the tile shows "—", 427).
interface Counts {
  products: number | null;
  warehouses: number | null;
  stores: number | null;
}

const StatCard: React.FC<{ icon: React.ReactNode; label: string; value: number | string; tint: string; sub?: string }> = ({ icon, label, value, tint, sub }) => (
  <div className="card" style={{ padding: 20, display: 'flex', alignItems: 'center', gap: 16 }}>
    <div style={{ width: 46, height: 46, borderRadius: 11, background: tint, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      {icon}
    </div>
    <div style={{ minWidth: 0 }}>
      <div style={{ fontSize: 26, fontWeight: 700, fontFamily: 'var(--font-display)', lineHeight: 1 }}>{value}</div>
      <div style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 3 }}>{label}</div>
      {sub && <div style={{ fontSize: 11.5, color: 'var(--danger)', marginTop: 2 }}>{sub}</div>}
    </div>
  </div>
);

const sgd = (n: unknown) => `S$${Number(n ?? 0).toLocaleString('en-SG', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
// A failed read is shown, never mistaken for "nothing there" (427, REPORTS-5).
const failure = (label: string, error: any) => `${label}: ${error?.message || 'could not be loaded'}`;
// A day the server sends as YYYY-MM-DD (already Singapore's), as "1 Aug 2026".
// Read as text, never through Date, so no time zone can move it.
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const dayLabel = (d: unknown): string | null => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(d ?? ''));
  return m && Number(m[2]) >= 1 && Number(m[2]) <= 12 ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : null;
};

const DashboardPage: React.FC = () => {
  const { profile } = useAuth();
  const [counts, setCounts] = useState<Counts>({ products: null, warehouses: null, stores: null });
  const [loading, setLoading] = useState(true);
  // What could not be counted for the tiles (427). Kept apart from
  // alertsError, which the alerts effect sets on its own.
  const [countsError, setCountsError] = useState('');

  // ── Phase 2: low stock alerts + pending approvals ──
  const [lowStock, setLowStock] = useState<{ name: string; sku: string; loc: string; qty: number; threshold: number }[]>([]);
  const [pendingApprovals, setPendingApprovals] = useState(0);
  const [todaySales, setTodaySales] = useState(0);
  // Sales period selector: day / week / month / year / all, plus a custom range.
  const [period, setPeriod] = useState<'day' | 'week' | 'month' | 'year' | 'all' | 'custom'>('day');
  const [rangeFrom, setRangeFrom] = useState('');
  const [rangeTo, setRangeTo] = useState('');
  const [periodStore, setPeriodStore] = useState('');
  const [sales, setSales] = useState<any>(null);
  // Credit settled in the same period. Reported separately because sales
  // deliberately exclude it: the money arrived when the credit was bought.
  const [credit, setCredit] = useState<any>(null);
  const [creditByStore, setCreditByStore] = useState<any[]>([]);
  const [salesBusy, setSalesBusy] = useState(false);
  const [byStore, setByStore] = useState<any[]>([]);
  // Why the Sales card has no figures (the sales read failed, or a custom
  // range the server refuses), and what else in it could not be read.
  const [salesError, setSalesError] = useState('');
  const [salesNote, setSalesNote] = useState('');

  useEffect(() => {
    // A custom range is only queried once both ends are set, so the panel does
    // not flicker an error while the dates are being typed.
    if (period === 'custom' && !rangeFrom) {
      // Otherwise the previous period's figures stay on screen under the new
      // heading, which reads as though they belong to the custom range.
      setSales(null);
      setCredit(null);
      setCreditByStore([]);
      setSalesError('');
      setSalesNote('');
      setSalesBusy(false);
      return;
    }
    let cancelled = false;
    setSalesBusy(true);
    (async () => {
      try {
        const args = {
          p_period: period,
          p_from: period === 'custom' ? rangeFrom : null,
          p_to: period === 'custom' ? (rangeTo || rangeFrom) : null,
          p_store_id: periodStore || null,
        };
        const [s1, s2, c1, c2] = await Promise.all([
          supabase.rpc('dashboard_sales', args),
          supabase.rpc('dashboard_sales_by_store', {
            p_period: args.p_period, p_from: args.p_from, p_to: args.p_to }),
          supabase.rpc('dashboard_credit_spend', args),
          supabase.rpc('dashboard_credit_by_store', {
            p_period: args.p_period, p_from: args.p_from, p_to: args.p_to }),
        ]);
        if (cancelled) return;
        // The sales figure itself failed (a custom range ending before it
        // starts, say): say so in the card, never an empty card.
        setSalesError(s1.error ? s1.error.message || 'The sales figures could not be loaded.' : '');
        setSales(s1.error ? null : s1.data ?? null);
        setByStore(s2.error ? [] : (s2.data as any[]) ?? []);
        setCredit(c1.error ? null : c1.data ?? null);
        setCreditByStore(c2.error ? [] : (c2.data as any[]) ?? []);
        setSalesNote(s1.error ? '' : [s2.error && failure('Sales by store', s2.error),
          c1.error && failure('Settled from credit', c1.error), c2.error && failure('Credit by store', c2.error)]
          .filter(Boolean).join(' · '));
      } catch (error: any) {
        if (cancelled) return;
        setSales(null); setCredit(null); setCreditByStore([]); setByStore([]); setSalesNote('');
        setSalesError(error?.message || 'The sales figures could not be loaded.');
      } finally {
        if (!cancelled) setSalesBusy(false);
      }
    })();
    return () => { cancelled = true; };
  }, [period, rangeFrom, rangeTo, periodStore]);
  const [todayCount, setTodayCount] = useState(0);
  // 5G-2 additions (Manager+ only — the underlying tables are RLS-gated)
  const [activeRentals, setActiveRentals] = useState(0);
  const [overdueRentals, setOverdueRentals] = useState(0);
  const [summary, setSummary] = useState<any>(null);
  // Phase 11: transfer receipt alerts (awaiting receipt / overdue / open discrepancies)
  const [transferAlerts, setTransferAlerts] = useState<{ awaiting_receipt: number; overdue: number; open_discrepancies: number } | null>(null);
  // Phase 14 — top customer sources.
  const [topSources, setTopSources] = useState<{ source_label: string; customers_count: number; surveys_count: number }[]>([]);
  // Phase 16 — negative TikTok stock alerts.
  const navigate = useNavigate();
  const [negStock, setNegStock] = useState<{ store_name: string; kind: string; item_name: string; current_qty: number }[]>([]);
  // Phase 18 — operations alerts + FOC snapshot.
  const [alerts, setAlerts] = useState<any>(null);
  const [foc, setFoc] = useState<FocSnapshot | null>(null);
  // What could not be read for the cards below the Sales panel (427).
  const [alertsError, setAlertsError] = useState('');

  useEffect(() => {
    let cancelled = false;
    // Each part loads on its own: one failing never stops the others, and
    // every failure is listed in one notice above the cards.
    const problems: string[] = [];
    const part = async (label: string, run: () => Promise<void>) => {
      try { await run(); } catch (error: any) { problems.push(failure(label, error)); }
    };
    const must = <T,>(r: { data: T; error: any }) => { if (r.error) throw r.error; return r.data; };
    const manager = isManagerOrAbove(profile?.role);
    (async () => {
      await Promise.all([
        // Pending transfer approvals + invoice actions + adjustments (RLS shows
        // only what the user can see).
        part('Pending approvals', async () => {
          const [transferPending, otherPending] = await Promise.all([
            supabase.from('transfer_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
            supabase.from('approval_requests').select('id', { count: 'exact', head: true })
              .in('request_type', ['invoice_refund', 'invoice_cancel', 'adjustment']).eq('status', 'pending'),
          ]);
          if (transferPending.error) throw transferPending.error;
          if (otherPending.error) throw otherPending.error;
          if (!cancelled) setPendingApprovals((transferPending.count ?? 0) + (otherPending.count ?? 0));
        }),
        // Phase 8: the summary cards, for the roles that see them (406 answers
        // Owners, Admins and Managers only).
        part('Summary cards', async () => {
          const sum = manager ? must(await supabase.rpc('dashboard_summary')) : null;
          if (!cancelled) setSummary(sum ?? null);
        }),
        // Phase 11: transfer receipt / overdue / discrepancy alerts.
        part('Transfers', async () => {
          const ta = must(await supabase.rpc('transfer_receipt_alerts'));
          if (!cancelled) setTransferAlerts((ta as any) ?? null);
        }),
        part('Customer sources', async () => {
          const srcs = must(await supabase.rpc('report_customer_sources', { p_from: null, p_to: null }));
          if (!cancelled) setTopSources((((srcs as any[]) ?? []).filter(r => Number(r.customers_count) > 0 || Number(r.surveys_count) > 0)
            .sort((a, b) => Number(b.customers_count) - Number(a.customers_count)).slice(0, 5)));
        }),
        part('Negative TikTok stock', async () => {
          const neg = must(await supabase.rpc('tiktok_negative_stock_alerts'));
          if (!cancelled) setNegStock(((neg as any[]) ?? []).filter(n => Number(n.current_qty) < 0));
        }),
        part('Operations alerts', async () => {
          const al = must(await supabase.rpc('dashboard_alerts_summary'));
          if (!cancelled) setAlerts(al ?? null);
        }),
        // The FOC card: the last 30 days of the FOC report (the stores this login
        // may see, settled invoices, by invoice date), its total and breakdown
        // read from the same rows. The report returns store_id and foc_value.
        part('FOC', async () => {
          const focToday = singaporeToday();
          const [lines, focStores] = await Promise.all([
            supabase.rpc('report_foc_lines', { p_from: focWindowStart(focToday), p_to: focToday, p_store_id: null }),
            supabase.from('stores').select('id,name'),
          ]);
          const fl = must(lines), st = must(focStores);
          if (!cancelled) setFoc(focSnapshot((fl as any[]) ?? [], new Map(((st as any[]) ?? []).map(s => [s.id, s.name]))));
        }),
        // Same eligible-receipt basis as the period charts and sales reports.
        part("Today's sales", async () => {
          const todaySummary: any = must(await supabase.rpc('dashboard_sales', { p_period: 'day' }));
          if (!cancelled) { setTodaySales(Number(todaySummary?.sales ?? 0)); setTodayCount(Number(todaySummary?.invoice_count ?? 0)); }
        }),
        // Rentals out and overdue (Managers and above). Overdue is against
        // today in Singapore (427): before 8 am the UTC date is still yesterday.
        part('Rentals', async () => {
          if (!manager) return;
          const rents = await fetchAllFrom<any>('rentals', 'id,status,expected_return_date', q => q.in('status', ['paid', 'active']));
          const today = singaporeToday();
          if (!cancelled) {
            setActiveRentals(rents.length);
            setOverdueRentals(rents.filter(r => r.expected_return_date && r.expected_return_date < today).length);
          }
        }),
        // Low stock across warehouse + store inventory. Inventory and products
        // are joined in the browser, so a truncated read would silently drop
        // products out of the low-stock list instead of erroring: paged.
        part('Low stock', async () => {
          const [wh, st, prods, whs, sts] = await Promise.all([
            fetchAllFrom<any>('warehouse_inventory'),
            fetchAllFrom<any>('store_inventory'),
            fetchAllFrom<any>('products', 'id,name,sku'),
            fetchAllFrom<any>('warehouses', 'id,name'),
            fetchAllFrom<any>('stores', 'id,name'),
          ]);
          const pMap = new Map(prods.map((p: any) => [p.id, p]));
          const whMap = new Map(whs.map((w: any) => [w.id, w.name]));
          const stMap = new Map(sts.map((s: any) => [s.id, s.name]));
          const low: typeof lowStock = [];
          wh.forEach((i: any) => {
            if (i.low_stock_threshold > 0 && i.current_qty <= i.low_stock_threshold) {
              const p = pMap.get(i.product_id);
              if (p) low.push({ name: p.name, sku: p.sku, loc: `🏭 ${whMap.get(i.warehouse_id) ?? ''}`, qty: i.current_qty, threshold: i.low_stock_threshold });
            }
          });
          st.forEach((i: any) => {
            if (i.low_stock_threshold > 0 && i.current_qty <= i.low_stock_threshold) {
              const p = pMap.get(i.product_id);
              if (p) low.push({ name: p.name, sku: p.sku, loc: `🏪 ${stMap.get(i.store_id) ?? ''}`, qty: i.current_qty, threshold: i.low_stock_threshold });
            }
          });
          if (!cancelled) setLowStock(low);
        }),
      ]);
      if (!cancelled) setAlertsError(problems.join(' · '));
    })();
    return () => { cancelled = true; };
  }, [profile?.role]);


  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [p, w, s] = await Promise.all([
          supabase.from('products').select('id', { count: 'exact', head: true }).is('deleted_at', null),
          supabase.from('warehouses').select('id', { count: 'exact', head: true }).is('deleted_at', null),
          supabase.from('stores').select('id', { count: 'exact', head: true }).is('deleted_at', null),
        ]);
        // A count that could not be read shows "—" and is named in the
        // notice, never 0 (427, REPORTS-5).
        const reads = [['Active products', p], ['Warehouses', w], ['Stores', s]] as const;
        if (!cancelled) {
          setCounts({
            products: p.error ? null : p.count ?? 0,
            warehouses: w.error ? null : w.count ?? 0,
            stores: s.error ? null : s.count ?? 0,
          });
          setCountsError(reads.filter(([, r]) => r.error).map(([label, r]) => failure(label, r.error)).join(' · '));
        }
      } catch (error: any) {
        if (!cancelled) setCountsError(failure('Counts', error));
      } finally {
        // The tiles stop showing "—" whatever happened (427).
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  // "Unpaid commission": what affiliates are still owed, as the Commissions
  // page nets it (414); what is still to be recovered from them beside it.
  const unpaidTile = dashboardCommissionFigures(summary, 0);
  // The Transfers card shows when there is something to receive or resolve.
  const transferCard = !!transferAlerts && (transferAlerts.awaiting_receipt > 0 || transferAlerts.open_discrepancies > 0);
  // The alert cards show whenever any of them has something to show (427:
  // they showed only beside a pending approval, low stock or a transfer).
  const showAlerts = pendingApprovals > 0 || lowStock.length > 0 || transferCard || !!alerts
    || negStock.length > 0 || topSources.length > 0;
  const heldSales: string[] = alerts?.sales?.invoice_nos ?? [];
  // 427 (the Owner, 18 Oct 2026): the server counts only the customers added
  // since this day, and the tile says so.
  const noSourceSince = dayLabel(alerts?.surveys?.customers_without_source_since);

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Welcome back, {profile?.full_name?.split(' ')[0]}</h2>
          <p>You're signed in as {profile ? ROLE_LABELS[profile.role] : ''}. Here's the current setup at a glance.</p>
        </div>
      </div>

      {/* ---- Sales for a chosen period ---- */}
      <div className="card" data-testid="sales-card" style={{ marginBottom: 20, padding: 20 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                      flexWrap: 'wrap', gap: 12,
                      paddingBottom: 14, marginBottom: 18,
                      borderBottom: '1px solid var(--border)' }}>
          <div style={{ fontWeight: 700, fontSize: 15 }}>Sales</div>
          <div style={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center',
                        background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 2 }}>
            {([['day','Today'],['week','This week'],['month','This month'],
               ['year','This year'],['all','All time'],['custom','Custom']] as const).map(([k, lbl]) => (
              <button key={k} className={`btn btn-sm ${period === k ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setPeriod(k)}>{lbl}</button>
            ))}
          </div>
        </div>

        {period === 'custom' && (
          <div style={{
            display: 'flex', gap: 14, alignItems: 'flex-end', flexWrap: 'wrap',
            background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)',
            padding: '12px 14px', marginBottom: 18,
          }}>
            <div style={{ flex: '1 1 150px', maxWidth: 200, minWidth: 0 }}>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 4,
                            textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600 }}>From</div>
              <input type="date" value={rangeFrom} onChange={e => setRangeFrom(e.target.value)} />
            </div>
            <div style={{ flex: '1 1 150px', maxWidth: 200, minWidth: 0 }}>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 4,
                            textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600 }}>To</div>
              <input type="date" value={rangeTo} min={rangeFrom}
                onChange={e => setRangeTo(e.target.value)} />
            </div>
            {!rangeFrom && (
              <div style={{ fontSize: 12, color: 'var(--text-muted)', paddingBottom: 9 }}>
                Choose a start date to see the range.
              </div>
            )}
          </div>
        )}

        {byStore.length > 1 && (
          <div style={{ marginBottom: 12 }}>
            <select value={periodStore} onChange={e => setPeriodStore(e.target.value)} style={{ maxWidth: 320 }}>
              <option value="">All stores</option>
              {byStore.map(b => <option key={b.store_id} value={b.store_id}>{b.store_name}</option>)}
            </select>
          </div>
        )}

        {salesBusy && <div style={{ fontSize: 13, color: 'var(--text-muted)' }}>Loading…</div>}

        {!salesBusy && salesError && (
          <div role="alert" className="alert alert-danger" style={{ marginBottom: 0 }}>
            The sales figures could not be loaded: {salesError}
          </div>
        )}

        {!salesBusy && !salesError && !sales && period === 'custom' && (
          <div style={{ fontSize: 13, color: 'var(--text-muted)', padding: '10px 0' }}>
            Pick a start date above to see the figures for that range.
          </div>
        )}

        {!salesBusy && sales && (
          <>
            {/* The headline figure, then the supporting numbers as a divided
                row — a strip of equal-weight labels reads as a list rather
                than as one figure with context. */}
            <div style={{ display: 'flex', alignItems: 'stretch',
                          gap: 0, flexWrap: 'wrap' }}>
              <div style={{ minWidth: 0, paddingRight: 32 }}>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', textTransform: 'uppercase',
                              letterSpacing: '0.06em', fontWeight: 600 }}>{sales.label}</div>
                <div style={{ fontSize: 38, fontWeight: 700, lineHeight: 1.05,
                              letterSpacing: '-0.02em', fontVariantNumeric: 'tabular-nums' }}>
                  {sgd(sales.sales)}
                </div>
                {sales.change_percent != null ? (
                  <div style={{ fontSize: 12, marginTop: 2 }}>
                    <span style={{
                      fontWeight: 700,
                      color: Number(sales.change_percent) >= 0 ? 'var(--success)' : 'var(--danger)',
                    }}>
                      {Number(sales.change_percent) >= 0 ? '↑' : '↓'} {Math.abs(Number(sales.change_percent)).toFixed(1)}%
                    </span>
                    <span style={{ color: 'var(--text-muted)' }}>
                      {' '}on S${Number(sales.previous_sales).toLocaleString('en-SG', { maximumFractionDigits: 0 })} before
                    </span>
                  </div>
                ) : (
                  <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2 }}>
                    No earlier period to compare
                  </div>
                )}
              </div>

              {/* Supporting figures, separated so they read as a set */}
              <div style={{ display: 'flex', gap: 34, flexWrap: 'wrap', minWidth: 0,
                            alignItems: 'flex-end', paddingBottom: 4,
                            borderLeft: '1px solid var(--border)', paddingLeft: 32 }}>
                {([
                  ['Invoices', String(sales.invoice_count)],
                  ['Average', sgd(sales.average_invoice)],
                  ['Items sold', String(sales.items_sold)],
                  ['Discounts', sgd(sales.discount_total)],
                ] as [string, string][]).map(([label, value]) => (
                  <div key={label}>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)', textTransform: 'uppercase',
                                  letterSpacing: '0.05em', fontWeight: 600 }}>{label}</div>
                    <div style={{ fontSize: 19, fontWeight: 600, marginTop: 1,
                                  fontVariantNumeric: 'tabular-nums' }}>{value}</div>
                  </div>
                ))}
              </div>
            </div>

            {salesNote && (
              <div role="alert" className="alert alert-warning" style={{ marginTop: 12, marginBottom: 0 }}>
                Not all of this period could be loaded: {salesNote}
              </div>
            )}

            {/* Credit settled in this period. Kept apart from the sales figure
                above, which deliberately excludes it — the money arrived when
                the credit was bought, not when it was spent. */}
            {credit && Number(credit.credit_spent) > 0 && (
              <div style={{ marginTop: 14, paddingTop: 12, borderTop: '1px dashed var(--border)' }}>
                <div style={{ display: 'flex', gap: 28, alignItems: 'flex-end', flexWrap: 'wrap' }}>
                  <div>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)', textTransform: 'uppercase',
                                  letterSpacing: '0.05em', fontWeight: 600 }}>
                      Settled from credit
                    </div>
                    <div style={{ fontSize: 22, fontWeight: 700, lineHeight: 1.15,
                                  fontVariantNumeric: 'tabular-nums', color: 'var(--warning)' }}>
                      {sgd(credit.credit_spent)}
                    </div>
                  </div>
                  <div>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)', textTransform: 'uppercase',
                                  letterSpacing: '0.05em', fontWeight: 600 }}>Invoices</div>
                    <div style={{ fontSize: 17, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
                      {credit.invoices}
                    </div>
                  </div>
                  <div style={{ fontSize: 11.5, color: 'var(--text-muted)', paddingBottom: 3, flex: '1 1 200px', minWidth: 0 }}>
                    Not counted in sales above — it was counted when the credit was purchased.
                    Invoices totalled{' '}
                    <strong>{sgd(Number(sales?.sales ?? 0) + Number(credit.credit_spent))}</strong>{' '}
                    including it.
                  </div>
                </div>

                {creditByStore.length > 1 && !periodStore && (
                  <div style={{ marginTop: 10 }}>
                    {creditByStore.map((r: any) => (
                      <div key={r.store_id} data-testid="credit-store-row" style={{ display: 'flex', gap: 10, alignItems: 'center',
                                                     fontSize: 12.5, marginBottom: 3 }}>
                        <span style={{ flex: '1 1 120px', minWidth: 0, overflow: 'hidden',
                                       textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{r.store_name}</span>
                        <span style={{ flex: '0 0 auto', fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
                          {sgd(r.credit_spent)}
                        </span>
                        <span style={{ flex: '0 0 auto', color: 'var(--text-muted)', fontSize: 11.5 }}>
                          {r.invoices} invoice{r.invoices === 1 ? '' : 's'}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {byStore.length > 1 && !periodStore && (
              <div style={{ marginTop: 14 }}>
                <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginBottom: 6 }}>By store</div>
                {byStore.map(b => {
                  const top = Math.max(...byStore.map(x => Number(x.sales)), 1);
                  return (
                    <div key={b.store_id} data-testid="store-row" style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                      <div style={{ flex: '1 1 120px', minWidth: 0, fontSize: 12.5, overflow: 'hidden',
                                    textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{b.store_name}</div>
                      <div style={{ flex: '1 1 40px', minWidth: 40, background: 'var(--surface-2)', borderRadius: 3, height: 8 }}>
                        <div style={{ width: `${Number(b.sales) / top * 100}%`, background: 'var(--primary)',
                                      height: 8, borderRadius: 3 }} />
                      </div>
                      <div style={{ flex: '0 0 auto', textAlign: 'right', fontSize: 12.5, fontWeight: 600 }}>
                        S${Number(b.sales).toFixed(2)}
                      </div>
                      <div style={{ flex: '0 0 auto', textAlign: 'right', fontSize: 11.5, color: 'var(--text-muted)' }}>
                        {b.invoice_count} inv
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </>
        )}
      </div>

      {(alertsError || countsError) && (
        <div role="alert" className="alert alert-danger" data-testid="alerts-error" style={{ marginBottom: 20 }}>
          Some of the Dashboard could not be loaded, so it may show less than there is. {[alertsError, countsError].filter(Boolean).join(' · ')}. Refresh the page to try again.
        </div>
      )}

      {isManagerOrAbove(profile?.role) && summary && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 12, marginBottom: 20 }}>
          <StatCard icon={<Ban size={20} color="var(--danger)" />} label="Blocked commission" value={`S$${Number(summary.blocked_commission).toFixed(0)}`} tint="var(--danger-light)" />
          <StatCard icon={<Sparkles size={20} color="var(--accent)" />} label="Therapy awaiting activation" value={summary.therapy_awaiting} tint="var(--accent-light)" />
          <StatCard icon={<Clock size={20} color="var(--danger)" />} label="Therapy deadline warnings (30d)" value={summary.therapy_deadline_warn} tint="var(--danger-light)" />
          <StatCard icon={<Ticket size={20} color="var(--text-muted)" />} label="Discounts given today" value={`S$${Number(summary.discount_today).toFixed(0)}`} tint="var(--surface-2)" />
        </div>
      )}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 16, marginBottom: 28 }}>
        <StatCard icon={<CreditCard size={22} color="var(--success)" />} label={`Today's sales (${todayCount} paid)`} value={loading ? '—' : `S$${todaySales.toFixed(0)}`} tint="var(--success-light)" />
        <StatCard icon={<Package size={22} color="var(--primary)" />} label="Active products" value={loading || counts.products == null ? '—' : counts.products} tint="var(--primary-light)" />
        <StatCard icon={<Warehouse size={22} color="#b45309" />} label="Warehouses" value={loading || counts.warehouses == null ? '—' : counts.warehouses} tint="var(--accent-light)" />
        <StatCard icon={<Store size={22} color="var(--primary)" />} label="Stores" value={loading || counts.stores == null ? '—' : counts.stores} tint="var(--primary-light)" />
      </div>

      {isManagerOrAbove(profile?.role) && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 16, marginBottom: 28 }}>
          {/* What affiliates are still owed and, under it, what is still to
              be recovered from them, as the Commissions page shows both. */}
          <StatCard icon={<Star size={22} color="var(--primary)" />} label="Unpaid commission"
            value={!summary ? '—' : sgd(unpaidTile.unpaid)}
            sub={summary && unpaidTile.deductions > 0 ? `To recover ${sgd(unpaidTile.deductions)}` : undefined}
            tint="var(--primary-light)" />
          {/* Counted as the Reports page's Vouchers tab counts uses (427). */}
          <StatCard icon={<Ticket size={22} color="var(--success)" />} label="Voucher uses this month"
            value={!summary || summary.voucher_uses_month == null ? '—' : Number(summary.voucher_uses_month)} tint="var(--success-light)" />
          <StatCard icon={<KeyRound size={22} color="#b45309" />} label="Rentals out (paid/active)" value={loading ? '—' : activeRentals} tint="var(--accent-light)" />
          <StatCard icon={<CalendarClock size={22} color="var(--danger)" />} label="Overdue rentals" value={loading ? '—' : overdueRentals} tint="var(--danger-light)" />
        </div>
      )}

      {/* Phase 2 + Phase 11 alerts */}
      {showAlerts && (
        <div data-testid="alerts-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(min(300px, 100%), 1fr))', gap: 16, marginBottom: 28 }}>
          {transferCard && transferAlerts && (
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
          {alerts && (
            <div className="card" data-testid="operations-alerts" style={{ padding: 20 }}>
              <h3 style={{ fontSize: 15, marginBottom: 10 }}>Operations Alerts</h3>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 10 }}>
                {/* Transfers are counted once, on the Transfers card (427). */}
                {([
                  ['TikTok imported orders', alerts.tiktok?.imported_orders, '/tiktok-import'],
                  ['TikTok unmatched SKUs', alerts.tiktok?.unmatched_skus, '/tiktok-import'],
                  ['TikTok awaiting confirmation', alerts.tiktok?.staged_batches, '/tiktok-import'],
                  ['Orders awaiting settlement', alerts.tiktok?.orders_awaiting_settlement, '/tiktok-import'],
                  // 427: paid out by TikTok, but no order file took their stock off.
                  ['Settled with no imported order', alerts.tiktok?.settled_without_order, '/tiktok-import'],
                  ['Settlement mismatches', alerts.tiktok?.settlement_mismatches, '/tiktok-import'],
                  ['Awaiting physical return', alerts.tiktok?.awaiting_physical_return, '/tiktok-import'],
                  ['Negative stock alerts', alerts.tiktok?.negative_stock, '/tiktok-import'],
                  [noSourceSince ? `Customers without source (added since ${noSourceSince})` : 'Customers without source',
                    alerts.surveys?.customers_without_source, '/customers'],
                ] as [string, number, string][]).map(([label, v, to]) => (
                  <div key={label} data-testid="alert-tile" onClick={() => navigate(to)} style={{ cursor: 'pointer', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '10px 12px', borderLeft: Number(v) > 0 && !label.includes('imported orders') ? '3px solid var(--warning, #d97706)' : undefined }}>
                    <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>{label}</div>
                    <div style={{ fontSize: 18, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{v ?? 0}</div>
                  </div>
                ))}
                {/* 427 (the Owner, 9 Oct 2026): refunded or cancelled sales that
                    still hold credit that can be spent, or rewards and
                    vouchers still to be claimed. */}
                <div data-testid="alert-tile" onClick={() => navigate('/invoices')} style={{ cursor: 'pointer', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '10px 12px', borderLeft: Number(alerts.sales?.holding_benefits) > 0 ? '3px solid var(--danger)' : undefined }}>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Refunded or cancelled sales still holding credit or rewards</div>
                  <div style={{ fontSize: 18, fontWeight: 700, fontFamily: 'var(--font-display)' }}>{alerts.sales?.holding_benefits ?? 0}</div>
                  {heldSales.length > 0 && (
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)', marginTop: 4, overflowWrap: 'anywhere' }}>
                      {heldSales.join(', ')}{Number(alerts.sales?.holding_benefits) > heldSales.length ? ' and more' : ''}
                    </div>
                  )}
                </div>
                <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '10px 12px' }}>
                  <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>FOC value (30 days)</div>
                  <div style={{ fontSize: 18, fontWeight: 700, fontFamily: 'var(--font-display)' }}>S${(foc?.total ?? 0).toFixed(2)}</div>
                  {foc && foc.lineCount > 0 && (
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)', marginTop: 4 }}>
                      {foc.stores.map(s => <div key={s.name}>{s.name}: S${s.value.toFixed(2)}</div>)}
                      {foc.reasons.map(r => <div key={r.label}>{r.label}: {r.count}×</div>)}
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}
          {negStock.length > 0 && (
            <div className="card" style={{ padding: 20, borderLeft: '3px solid var(--danger)' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
                <AlertTriangle size={18} color="var(--danger)" />
                <h3 style={{ fontSize: 15 }}>Negative TikTok Stock</h3>
              </div>
              <p style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 6 }}>Confirmed TikTok sales exceeded recorded stock — replenish or adjust.</p>
              {negStock.slice(0, 6).map((n, i) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, padding: '3px 0' }}>
                  <span>{n.item_name} <span style={{ color: 'var(--text-muted)' }}>({n.kind}, {n.store_name})</span></span>
                  <strong style={{ color: 'var(--danger)' }}>{n.current_qty}</strong>
                </div>
              ))}
            </div>
          )}
          {topSources.length > 0 && (
            <div className="card" style={{ padding: 20 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
                <Users size={18} color="var(--primary)" />
                <h3 style={{ fontSize: 15 }}>Customer Sources</h3>
              </div>
              {topSources.map((r, i) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, padding: '3px 0' }}>
                  <span>{r.source_label}</span>
                  <span style={{ color: 'var(--text-muted)' }}><strong style={{ color: 'var(--text)' }}>{r.customers_count}</strong> customers · {r.surveys_count} surveys</span>
                </div>
              ))}
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
    </div>
  );
};

export default DashboardPage;
