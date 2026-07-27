import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Commission, CommissionPayout, Customer, PaymentMethod, isManagerOrAbove, isOwnerOrManager } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { exportCsv } from '../lib/csv';
import { RefreshCw, Coins, Wallet, Network, ChevronRight, ChevronDown, Download, Settings } from 'lucide-react';

const money = (n: number) => `S$${n.toFixed(2)}`;
const monthKey = (d: string) => (d || '').slice(0, 7); // YYYY-MM

const CommissionsPage: React.FC = () => {
  const { profile } = useAuth();
  if (!isManagerOrAbove(profile?.role)) return <NoAccess message="Only Owners, Admins, and Managers can view commissions." />;
  const canPay = isOwnerOrManager(profile?.role);

  const [commissions, setCommissions] = useState<Commission[]>([]);
  const [payouts, setPayouts] = useState<CommissionPayout[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'earned' | 'payouts' | 'referrers'>('earned');

  // Editable commission rates.
  const [rates, setRates] = useState({ t1_own: 15, t1_third: 4.5, t2_own: 5, t2_third: 5 });
  const [ratesOpen, setRatesOpen] = useState(false);
  const [ratesDraft, setRatesDraft] = useState({ t1_own: 15, t1_third: 4.5, t2_own: 5, t2_third: 5 });
  const [ratesBusy, setRatesBusy] = useState(false);
  const [ratesErr, setRatesErr] = useState<string | null>(null);

  // Referrers tab
  const [referrers, setReferrers] = useState<any[]>([]);
  const [refLoading, setRefLoading] = useState(false);
  const [detailFor, setDetailFor] = useState<any | null>(null);
  const [detail, setDetail] = useState<any>(null);
  const [downline, setDownline] = useState<any[]>([]);
  const [expandedBuyers, setExpandedBuyers] = useState<Set<string>>(new Set());

  const [payFor, setPayFor] = useState<{ referrer: string; month: string; t1: number; t2: number } | null>(null);
  const [payMethod, setPayMethod] = useState('');
  const [payRef, setPayRef] = useState('');
  const [payNote, setPayNote] = useState('');
  const [payBusy, setPayBusy] = useState(false);
  const [payErr, setPayErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const [co, po, cu, pm, st] = await Promise.all([
      supabase.from('commissions').select('*').order('invoice_paid_date', { ascending: false }),
      supabase.from('commission_payouts').select('*').order('payout_month', { ascending: false }),
      supabase.from('customers').select('id,full_name,phone').is('deleted_at', null),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true),
      supabase.from('app_settings').select('commission_tier1_own_rate,commission_tier1_third_rate,commission_tier2_own_rate,commission_tier2_third_rate').eq('id', true).single(),
    ]);
    setCommissions((co.data as Commission[]) ?? []);
    setPayouts((po.data as CommissionPayout[]) ?? []);
    setCustomers((cu.data as Customer[]) ?? []);
    setMethods((pm.data as PaymentMethod[]) ?? []);
    if (st.data) {
      const d = st.data as any;
      setRates({
        t1_own: Number(d.commission_tier1_own_rate), t1_third: Number(d.commission_tier1_third_rate),
        t2_own: Number(d.commission_tier2_own_rate), t2_third: Number(d.commission_tier2_third_rate),
      });
    }
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const loadReferrers = useCallback(async () => {
    setRefLoading(true);
    const { data } = await supabase.rpc('referrer_list');
    setReferrers((data as any[]) ?? []);
    setRefLoading(false);
  }, []);
  useEffect(() => { if (tab === 'referrers' && referrers.length === 0) loadReferrers(); }, [tab, referrers.length, loadReferrers]);

  const openDetail = async (r: any) => {
    setDetailFor(r); setDetail(null); setDownline([]); setExpandedBuyers(new Set());
    const [earn, dl] = await Promise.all([
      supabase.rpc('referrer_earnings', { p_customer_id: r.customer_id }),
      supabase.rpc('referrer_downline', { p_customer_id: r.customer_id }),
    ]);
    setDetail(earn.data ?? {});
    setDownline((dl.data as any[]) ?? []);
  };

  const toggleBuyer = (id: string) => {
    setExpandedBuyers(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n; });
  };

  const cName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';
  const mName = (id: string | null) => id ? (methods.find(m => m.id === id)?.name ?? '—') : '—';

  // Group EARNED (unpaid) commissions by referrer + month.
  const earnedGroups = useMemo(() => {
    const map = new Map<string, { referrer: string; month: string; t1: number; t2: number; count: number }>();
    commissions.filter(c => c.status === 'earned').forEach(c => {
      const m = monthKey(c.invoice_paid_date ?? '');
      const key = `${c.referrer_customer_id}|${m}`;
      const g = map.get(key) ?? { referrer: c.referrer_customer_id, month: m, t1: 0, t2: 0, count: 0 };
      if (c.tier === 'tier1') g.t1 += Number(c.commission_amount); else g.t2 += Number(c.commission_amount);
      g.count += 1;
      map.set(key, g);
    });
    return Array.from(map.values()).sort((a, b) => b.month.localeCompare(a.month));
  }, [commissions]);

  const totalEarned = earnedGroups.reduce((s, g) => s + g.t1 + g.t2, 0);

  const openPay = (g: { referrer: string; month: string; t1: number; t2: number }) => {
    setPayFor(g); setPayMethod(methods[0]?.id ?? ''); setPayRef(''); setPayNote(''); setPayErr(null);
  };

  const submitPay = async () => {
    if (!payFor) return;
    setPayBusy(true); setPayErr(null);
    const { error } = await supabase.rpc('create_commission_payout', {
      p_referrer_customer_id: payFor.referrer,
      p_month: payFor.month + '-01',
      p_payment_method_id: payMethod || null,
      p_reference: payRef.trim() || null,
      p_notes: payNote.trim() || null,
    });
    setPayBusy(false);
    if (error) { setPayErr(error.message); return; }
    setPayFor(null); load();
  };

  const doExport = () => {
    if (tab === 'earned') exportCsv('commission-unpaid.csv', earnedGroups.map(g => ({
      month: g.month, referrer: cName(g.referrer), tier1: g.t1.toFixed(2), tier2: g.t2.toFixed(2), total: (g.t1 + g.t2).toFixed(2),
    })));
    else if (tab === 'payouts') exportCsv('commission-payouts.csv', payouts.map(p => ({
      month: monthKey(p.payout_month), referrer: cName(p.referrer_customer_id),
      tier1: Number(p.total_tier1).toFixed(2), tier2: Number(p.total_tier2).toFixed(2),
      total: Number(p.total_amount).toFixed(2), method: mName(p.payment_method_id),
      reference: p.reference ?? '', paid_at: new Date(p.paid_at).toLocaleDateString(),
    })));
    else exportCsv('referrers.csv', referrers.map(r => ({
      referrer: r.full_name, phone: r.phone ?? '', direct: r.direct_referrals, downline: r.total_downline,
      lifetime_earned: Number(r.lifetime_earned).toFixed(2), unpaid: Number(r.unpaid_earned).toFixed(2),
    })));
  };

  const saveRates = async () => {
    setRatesBusy(true); setRatesErr(null);
    const { error } = await supabase.rpc('set_commission_rates', {
      p_tier1_own: ratesDraft.t1_own, p_tier1_third: ratesDraft.t1_third,
      p_tier2_own: ratesDraft.t2_own, p_tier2_third: ratesDraft.t2_third,
    });
    setRatesBusy(false);
    if (error) { setRatesErr(error.message); return; }
    setRatesOpen(false); load();
  };

  return (
    <div>
      <div className="page-header">
        <div><h2>Commissions</h2><p>Two-tier referral commission. Tier 1 earns on each paid invoice; Tier 2 earns a share of Tier 1. Unpaid total: <strong style={{ color: 'var(--primary)' }}>{money(totalEarned)}</strong></p></div>
        <div style={{ display: 'flex', gap: 10 }}>{canPay && <button className="btn btn-secondary" onClick={() => { setRatesDraft(rates); setRatesErr(null); setRatesOpen(true); }}><Settings size={15} /> Rates</button>}<button className="btn btn-secondary" onClick={doExport}><Download size={15} /> Export CSV</button><button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button></div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 16 }}>
        <button className={`btn btn-sm ${tab === 'earned' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('earned')}><Coins size={14} /> Unpaid (by referrer / month)</button>
        <button className={`btn btn-sm ${tab === 'payouts' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('payouts')}><Wallet size={14} /> Payout History</button>
        <button className={`btn btn-sm ${tab === 'referrers' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('referrers')}><Network size={14} /> Referrers</button>
      </div>

      <div className="card">
        <div className="table-wrap">
          {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
          : tab === 'earned' ? (
            earnedGroups.length === 0 ? <div className="empty-state"><Coins size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No unpaid commission</p></div>
            : (
              <table>
                <thead><tr><th>Month</th><th>Referrer</th><th style={{ textAlign: 'right' }}>Tier 1</th><th style={{ textAlign: 'right' }}>Tier 2</th><th style={{ textAlign: 'right' }}>Total</th><th></th></tr></thead>
                <tbody>
                  {earnedGroups.map((g, i) => (
                    <tr key={i}>
                      <td style={{ fontFamily: 'var(--font-display)' }}>{g.month}</td>
                      <td><strong>{cName(g.referrer)}</strong></td>
                      <td style={{ textAlign: 'right' }}>{money(g.t1)}</td>
                      <td style={{ textAlign: 'right' }}>{money(g.t2)}</td>
                      <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(g.t1 + g.t2)}</td>
                      <td style={{ textAlign: 'right' }}>{canPay && <button className="btn btn-primary btn-sm" onClick={() => openPay(g)}><Wallet size={13} /> Mark Paid</button>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )
          ) : tab === 'payouts' ? (
            payouts.length === 0 ? <div className="empty-state"><Wallet size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No payouts yet</p></div>
            : (
              <table>
                <thead><tr><th>Month</th><th>Referrer</th><th style={{ textAlign: 'right' }}>Tier 1</th><th style={{ textAlign: 'right' }}>Tier 2</th><th style={{ textAlign: 'right' }}>Total</th><th>Method</th><th>Paid</th></tr></thead>
                <tbody>
                  {payouts.map(p => (
                    <tr key={p.id}>
                      <td style={{ fontFamily: 'var(--font-display)' }}>{monthKey(p.payout_month)}</td>
                      <td><strong>{cName(p.referrer_customer_id)}</strong></td>
                      <td style={{ textAlign: 'right' }}>{money(Number(p.total_tier1))}</td>
                      <td style={{ textAlign: 'right' }}>{money(Number(p.total_tier2))}</td>
                      <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(p.total_amount))}</td>
                      <td style={{ fontSize: 12.5 }}>{mName(p.payment_method_id)}{p.reference ? ` · ${p.reference}` : ''}</td>
                      <td style={{ fontSize: 12 }}>{new Date(p.paid_at).toLocaleDateString()}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )
          ) : (
            refLoading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
            : referrers.length === 0 ? <div className="empty-state"><Network size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No referrers yet</p><p style={{ fontSize: 13 }}>Set a customer's "Referred by" on the Customers page.</p></div>
            : (
              <table>
                <thead><tr><th>Referrer</th><th>Phone</th><th style={{ textAlign: 'right' }}>Direct</th><th style={{ textAlign: 'right' }}>Downline</th><th style={{ textAlign: 'right' }}>Lifetime Earned</th><th style={{ textAlign: 'right' }}>Unpaid</th><th></th></tr></thead>
                <tbody>
                  {referrers.map(r => (
                    <tr key={r.customer_id}>
                      <td><strong>{r.full_name}</strong></td>
                      <td style={{ fontSize: 12.5 }}>{r.phone}</td>
                      <td style={{ textAlign: 'right' }}>{r.direct_referrals}</td>
                      <td style={{ textAlign: 'right' }}>{r.total_downline}</td>
                      <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(r.lifetime_earned))}</td>
                      <td style={{ textAlign: 'right', color: Number(r.unpaid_earned) > 0 ? 'var(--primary)' : 'var(--text-muted)' }}>{money(Number(r.unpaid_earned))}</td>
                      <td style={{ textAlign: 'right' }}><button className="btn btn-secondary btn-sm" onClick={() => openDetail(r)}><Network size={13} /> View</button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )
          )}
        </div>
      </div>

      {payFor && (
        <Modal title="Mark Commission Paid" maxWidth={420} onClose={() => setPayFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setPayFor(null)}>Cancel</button><button className="btn btn-primary" onClick={submitPay} disabled={payBusy}>{payBusy ? 'Processing…' : 'Confirm Payout'}</button></>}>
          <div className="form-grid">
            {payErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{payErr}</div></div>}
            <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
              <div style={{ fontSize: 13 }}><strong>{cName(payFor.referrer)}</strong> · {payFor.month}</div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6, fontSize: 13 }}><span>Tier 1</span><span>{money(payFor.t1)}</span></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13 }}><span>Tier 2</span><span>{money(payFor.t2)}</span></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700, marginTop: 4, paddingTop: 4, borderTop: '1px solid var(--border)' }}><span>Total</span><span>{money(payFor.t1 + payFor.t2)}</span></div>
            </div>
            <div className="form-group">
              <label>Payment Method</label>
              <select value={payMethod} onChange={e => setPayMethod(e.target.value)}>
                <option value="">— None —</option>
                {methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
              </select>
            </div>
            <div className="form-group"><label>Reference</label><input value={payRef} onChange={e => setPayRef(e.target.value)} placeholder="Optional — e.g. PayNow ref" /></div>
            <div className="form-group"><label>Notes</label><textarea rows={2} value={payNote} onChange={e => setPayNote(e.target.value)} placeholder="Optional" /></div>
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>This groups all unpaid commissions for this referrer in {payFor.month} into one payout and marks them paid.</div></div>
          </div>
        </Modal>
      )}

      {detailFor && (
        <Modal title={`Referrer — ${detailFor.full_name}`} maxWidth={680} onClose={() => setDetailFor(null)}
          footer={<button className="btn btn-secondary" onClick={() => setDetailFor(null)}>Close</button>}>
          {!detail ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div> : (
            <div className="form-grid">
              {/* Lifetime totals */}
              <div>
                <label>Lifetime earnings</label>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8, marginTop: 6 }}>
                  <div style={{ padding: 10, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Tier 1 (unpaid)</div>
                    <div style={{ fontSize: 15, fontWeight: 700 }}>{money(Number(detail.lifetime?.tier1_earned ?? 0))}</div>
                  </div>
                  <div style={{ padding: 10, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Tier 2 (unpaid)</div>
                    <div style={{ fontSize: 15, fontWeight: 700 }}>{money(Number(detail.lifetime?.tier2_earned ?? 0))}</div>
                  </div>
                  <div style={{ padding: 10, background: 'var(--success-light)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Paid out</div>
                    <div style={{ fontSize: 15, fontWeight: 700 }}>{money(Number(detail.lifetime?.total_paid ?? 0))}</div>
                  </div>
                  <div style={{ padding: 10, background: 'var(--primary-light)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Unpaid total</div>
                    <div style={{ fontSize: 15, fontWeight: 700 }}>{money(Number(detail.lifetime?.total_earned ?? 0))}</div>
                  </div>
                </div>
                {Number(detail.lifetime?.reversed ?? 0) > 0 && <div style={{ fontSize: 11.5, color: 'var(--danger)', marginTop: 4 }}>Reversed: {money(Number(detail.lifetime.reversed))}</div>}
              </div>

              {/* Per-month */}
              {(detail.monthly ?? []).length > 0 && (
                <div>
                  <label>By month (invoice paid date)</label>
                  <table style={{ marginTop: 4 }}>
                    <thead><tr><th>Month</th><th style={{ textAlign: 'right' }}>Tier 1</th><th style={{ textAlign: 'right' }}>Tier 2</th><th style={{ textAlign: 'right' }}>Unpaid</th><th style={{ textAlign: 'right' }}>Paid</th><th style={{ textAlign: 'right' }}>Total</th></tr></thead>
                    <tbody>
                      {detail.monthly.map((m: any, i: number) => (
                        <tr key={i}>
                          <td style={{ fontFamily: 'var(--font-display)' }}>{m.month}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(m.tier1))}</td>
                          <td style={{ textAlign: 'right' }}>{money(Number(m.tier2))}</td>
                          <td style={{ textAlign: 'right', color: 'var(--primary)' }}>{money(Number(m.unpaid))}</td>
                          <td style={{ textAlign: 'right', color: 'var(--success)' }}>{money(Number(m.paid))}</td>
                          <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(m.total))}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              {/* Per-buyer (Tier 2 traceback), expandable to lines */}
              {(detail.by_buyer ?? []).length > 0 && (
                <div>
                  <label>Earnings by referred customer <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— click to see each commission line</span></label>
                  <div style={{ marginTop: 4, border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', overflow: 'hidden' }}>
                    {detail.by_buyer.map((b: any) => {
                      const open = expandedBuyers.has(b.buyer_customer_id);
                      const lines = (detail.lines ?? []).filter((l: any) => l.buyer_customer_id === b.buyer_customer_id);
                      return (
                        <div key={b.buyer_customer_id} style={{ borderBottom: '1px solid var(--border)' }}>
                          <div onClick={() => toggleBuyer(b.buyer_customer_id)} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 10px', cursor: 'pointer', background: open ? 'var(--surface-2)' : 'transparent' }}>
                            {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                            <strong style={{ flex: 1, fontSize: 13 }}>{b.buyer_name}</strong>
                            <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>T1 {money(Number(b.tier1))} · T2 {money(Number(b.tier2))}</span>
                            <span style={{ fontSize: 13, fontWeight: 700, minWidth: 70, textAlign: 'right' }}>{money(Number(b.total))}</span>
                          </div>
                          {open && (
                            <table style={{ background: 'var(--surface)' }}>
                              <thead><tr><th>Invoice</th><th>Product</th><th>Tier</th><th>Type</th><th style={{ textAlign: 'right' }}>Basis</th><th style={{ textAlign: 'right' }}>Rate</th><th style={{ textAlign: 'right' }}>Amount</th><th>Status</th></tr></thead>
                              <tbody>
                                {lines.map((l: any) => (
                                  <tr key={l.id}>
                                    <td style={{ fontFamily: 'var(--font-display)', fontSize: 11.5 }}>{l.invoice_no}</td>
                                    <td style={{ fontSize: 12 }}>{l.product_name ?? '—'}</td>
                                    <td><span className={`badge ${l.tier === 'tier1' ? 'badge-primary' : 'badge-accent'}`}>{l.tier === 'tier1' ? 'T1' : 'T2'}</span></td>
                                    <td style={{ fontSize: 11.5 }}>{l.product_type === 'third_party' ? '3rd party' : 'Own'}</td>
                                    <td style={{ textAlign: 'right', fontSize: 12 }}>{money(Number(l.line_amount))}</td>
                                    <td style={{ textAlign: 'right', fontSize: 12 }}>{Number(l.rate)}%</td>
                                    <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(Number(l.commission_amount))}</td>
                                    <td><span className={`badge ${l.status === 'paid' ? 'badge-success' : l.status === 'reversed' ? 'badge-danger' : 'badge-muted'}`}>{l.status}</span></td>
                                  </tr>
                                ))}
                              </tbody>
                            </table>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Downline tree */}
              <div>
                <label>Downline ({downline.length}) <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— full referral chain, indented by depth</span></label>
                {downline.length === 0 ? <div style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 4 }}>No one referred yet.</div> : (
                  <div style={{ marginTop: 4 }}>
                    {downline.map((d: any) => (
                      <div key={d.customer_id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0', paddingLeft: (d.depth - 1) * 22, fontSize: 13 }}>
                        <span style={{ color: 'var(--text-muted)' }}>{d.depth === 1 ? '•' : '└'}</span>
                        <span style={{ flex: 1 }}>{d.full_name} <span style={{ color: 'var(--text-muted)', fontSize: 11.5 }}>({d.phone})</span></span>
                        <span style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Tier {d.depth} · {d.paid_purchases} paid · {money(Number(d.total_spend))}</span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}
        </Modal>
      )}

      {ratesOpen && (
        <Modal title="Commission Rates" maxWidth={460} onClose={() => setRatesOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setRatesOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={saveRates} disabled={ratesBusy}>{ratesBusy ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              Set the two-tier referral commission rates. Tier 1 is a percentage of the line value; Tier 2 is a percentage of the Tier 1 amount. Own and Third-party products can differ.
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Tier 1 — Own (%)</label>
                <input type="number" min={0} max={100} step={0.1} value={ratesDraft.t1_own || ''} onChange={e => setRatesDraft(d => ({ ...d, t1_own: +e.target.value }))} autoFocus />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Tier 1 — Third-party (%)</label>
                <input type="number" min={0} max={100} step={0.1} value={ratesDraft.t1_third || ''} onChange={e => setRatesDraft(d => ({ ...d, t1_third: +e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Tier 2 — Own (%)</label>
                <input type="number" min={0} max={100} step={0.1} value={ratesDraft.t2_own || ''} onChange={e => setRatesDraft(d => ({ ...d, t2_own: +e.target.value }))} />
              </div>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Tier 2 — Third-party (%)</label>
                <input type="number" min={0} max={100} step={0.1} value={ratesDraft.t2_third || ''} onChange={e => setRatesDraft(d => ({ ...d, t2_third: +e.target.value }))} />
              </div>
            </div>
            {ratesErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{ratesErr}</div></div>}
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Applies to invoices paid from now on. Already-earned commissions keep the rate they were calculated at.</div></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default CommissionsPage;
