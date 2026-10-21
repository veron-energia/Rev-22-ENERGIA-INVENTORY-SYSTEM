import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { isManagerOrAbove, isOwnerOrManager } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { RefreshCw, Coins, Wallet, Network, ChevronRight, ChevronDown, Settings } from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';
import { AffiliatePayoutPanel } from '../components/commissions/AffiliatePayoutPanel';
import { owedSplit } from '../lib/affiliatePayoutPresentation';
import { type Rates, type RatesDraft, type RateKey, RATE_KEYS, RATE_LABELS, ratesFromSettings, draftFromRates, checkRatesDraft, changeLine, sameRates, rebaseDraft } from '../lib/commissionRates';

const money = (n: number) => `S$${n.toFixed(2)}`;

// The four saved rates, read now. The page reads them on load, again when the
// Rates window opens, and again just before a save, so the window never shows
// or writes back rates that are out of date (AFFILIATES-M2).
async function readSavedRates(): Promise<{ rates: Rates | null; error: string | null }> {
  const { data, error } = await supabase.from('app_settings')
    .select('commission_tier1_own_rate,commission_tier1_third_rate,commission_tier2_own_rate,commission_tier2_third_rate')
    .eq('id', true).single();
  const rates = error ? null : ratesFromSettings(data as Record<string, unknown> | null);
  return { rates, error: rates ? null : (error?.message ?? 'The saved rates could not be read.') };
}

const CommissionsPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isManagerOrAbove(profile?.role);
  const canPay = isOwnerOrManager(profile?.role);

  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'earned' | 'payouts' | 'referrers'>('earned');

  // Commission rates (AFFILIATES-M2). There is no built-in rate: until the
  // saved rates have loaded the Rates window stays closed, so a Save can
  // never write a made-up rate over a real one. A failed read turns Rates
  // off again until Retry works.
  const [rates, setRates] = useState<Rates | null>(null);
  const [ratesOpening, setRatesOpening] = useState(false);
  const [ratesLoadErr, setRatesLoadErr] = useState<string | null>(null);
  // Part payments earn only once the owner has registered earlier ones (357).
  const [partPaymentsEarn, setPartPaymentsEarn] = useState(false);
  const [ratesOpen, setRatesOpen] = useState(false);
  const [ratesDraft, setRatesDraft] = useState<RatesDraft>({ t1_own: '', t1_third: '', t2_own: '', t2_third: '' });
  // Save first shows the old → new list; a second click saves.
  const [ratesConfirm, setRatesConfirm] = useState(false);
  const [ratesBusy, setRatesBusy] = useState(false);
  const [ratesErr, setRatesErr] = useState<string | null>(null);

  // Referrers tab
  const [referrers, setReferrers] = useState<any[]>([]);
  const [refLoading, setRefLoading] = useState(false);
  const [refLoaded, setRefLoaded] = useState(false);
  const [refErr, setRefErr] = useState<string | null>(null);
  const [detailFor, setDetailFor] = useState<any | null>(null);
  const [detail, setDetail] = useState<any>(null);
  const [detailErr, setDetailErr] = useState<string | null>(null);
  const [downline, setDownline] = useState<any[]>([]);
  const [expandedBuyers, setExpandedBuyers] = useState<Set<string>>(new Set());
  // Only the answer for the referrer open now is shown: a late answer for one
  // closed or replaced is dropped.
  const detailTicket = React.useRef(0);
  const refTicket = React.useRef(0);

  const load = useCallback(async () => {
    setLoading(true); setRatesLoadErr(null);
    // The switch is read on its own: a database without it (before 357) must not
    // cost the page its real rates.
    const [read, { data: sw }] = await Promise.all([
      readSavedRates(),
      supabase.from('app_settings').select('instalment_commission_from').eq('id', true).maybeSingle(),
    ]);
    setRates(read.rates);
    setRatesLoadErr(read.error);
    setPartPaymentsEarn(!!(sw as any)?.instalment_commission_from);
    setLoading(false);
  }, []);
  useEffect(() => { if (hasAccess) void load(); }, [load, hasAccess]);

  const loadReferrers = useCallback(async () => {
    const ticket = ++refTicket.current;
    setRefLoading(true); setRefErr(null);
    const { data, error } = await supabase.rpc('referrer_list');
    if (ticket !== refTicket.current) return;   // a newer load won
    setRefLoading(false); setRefLoaded(true);
    if (error) { setRefErr(error.message); return; }
    setReferrers((data as any[]) ?? []);
  }, []);
  useEffect(() => { if (tab === 'referrers' && !refLoaded && !refLoading) void loadReferrers(); }, [tab, refLoaded, refLoading, loadReferrers]);

  const openDetail = async (r: any) => {
    const ticket = ++detailTicket.current;
    setDetailFor(r); setDetail(null); setDetailErr(null); setDownline([]); setExpandedBuyers(new Set());
    const [earn, dl] = await Promise.all([
      supabase.rpc('referrer_earnings', { p_customer_id: r.customer_id }),
      supabase.rpc('referrer_downline', { p_customer_id: r.customer_id }),
    ]);
    if (ticket !== detailTicket.current) return;   // another referrer was opened, or this one closed
    if (earn.error || dl.error) { setDetailErr((earn.error ?? dl.error)!.message); return; }
    setDetail(earn.data ?? {});
    // Tier 1 and Tier 2, the levels that earn commission (425 stops there; an
    // older server may send more levels, which are not shown).
    setDownline(((dl.data as any[]) ?? []).filter(d => Number(d.depth) <= 2));
  };
  const closeDetail = () => { detailTicket.current++; setDetailFor(null); setDetail(null); setDetailErr(null); };

  const toggleBuyer = (id: string) => {
    setExpandedBuyers(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n; });
  };

  const ratesCheck = rates ? checkRatesDraft(rates, ratesDraft) : null;
  // The window opens on the rates saved now, not on what the page read
  // earlier (another Owner or Manager may have changed them since).
  const openRates = async () => {
    if (!rates || ratesOpening) return;
    setRatesOpening(true);
    const read = await readSavedRates();
    setRatesOpening(false);
    setRates(read.rates); setRatesLoadErr(read.error);
    if (!read.rates) return;   // the banner says why, with Retry
    setRatesDraft(draftFromRates(read.rates)); setRatesErr(null); setRatesConfirm(false); setRatesOpen(true);
  };
  const editRate = (k: RateKey, v: string) => { setRatesDraft(d => ({ ...d, [k]: v })); setRatesConfirm(false); setRatesErr(null); };
  const saveRates = async () => {
    if (!ratesCheck?.rates || ratesCheck.changes.length === 0) return;
    // The first click shows what changes; the second saves it.
    if (!ratesConfirm) { setRatesConfirm(true); return; }
    const next = ratesCheck.rates;
    setRatesBusy(true); setRatesErr(null);
    // Read the saved rates once more. If they changed since the window
    // opened, show the list against them instead of saving over the change.
    const read = await readSavedRates();
    if (!read.rates) { setRatesBusy(false); setRatesErr(read.error); setRatesConfirm(false); return; }
    if (rates && !sameRates(read.rates, rates)) {
      setRatesDraft(rebaseDraft(rates, read.rates, ratesDraft));
      setRates(read.rates);
      setRatesBusy(false); setRatesConfirm(false);
      setRatesErr('The rates changed since you opened this window. The boxes you did not change now show the new rates. Check them, then save again.');
      return;
    }
    const { error } = await supabase.rpc('set_commission_rates', {
      p_tier1_own: next.t1_own, p_tier1_third: next.t1_third,
      p_tier2_own: next.t2_own, p_tier2_third: next.t2_third,
    });
    setRatesBusy(false);
    if (error) { setRatesErr(error.message); setRatesConfirm(false); return; }
    setRates(next);   // what was saved, even if the reload below fails
    setRatesOpen(false); setRatesConfirm(false); void load();
  };

  if (!hasAccess) return <NoAccess message="Only Owners, Admins, and Managers can view commissions." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Commissions</h2><p>Two-tier referral commission. Tier 1 earns {partPaymentsEarn ? "on each payment a referred customer makes, part payments included" : "when a referred customer's invoice is fully paid"}; Tier 2 earns a share of Tier 1.</p></div>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          {tab === 'referrers' && <ExcelExportButton rows={referrers} filename="commission-referrers" sheetName="Referrers" columns={[
            { header: 'Referrer', value: (r: any) => r.full_name || '' }, { header: 'Phone', value: (r: any) => r.phone || '' },
            { header: 'Lifetime earned', value: (r: any) => Number(r.lifetime_earned) }, { header: 'Unpaid', value: (r: any) => owedSplit(r.unpaid_earned).unpaid },
            { header: 'Deduction to recover', value: (r: any) => owedSplit(r.unpaid_earned).deduction },
          ]} />}{canPay && <button className="btn btn-secondary" disabled={!rates || ratesOpening} title={rates ? 'Commission rates' : 'The rates have not loaded yet'} onClick={() => void openRates()}><Settings size={15} /> Rates</button>}{tab === 'referrers' && <button className="btn btn-secondary" onClick={() => { void load(); void loadReferrers(); }}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>}</div>
      </div>

      {canPay && ratesLoadErr && (
        <div className="alert alert-danger" data-error="rates" style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
          <span>The commission rates could not be loaded: {ratesLoadErr}</span>
          <button className="btn btn-secondary btn-sm" onClick={() => void load()}>Retry</button>
        </div>
      )}

      <div style={{ display: 'flex', gap: 6, marginBottom: 16, flexWrap: 'wrap' }}>
        <button className={`btn btn-sm ${tab === 'earned' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('earned')} title="Balances by affiliate and month"><Coins size={14} /> Balances</button>
        <button className={`btn btn-sm ${tab === 'payouts' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('payouts')}><Wallet size={14} /> Payout History</button>
        <button className={`btn btn-sm ${tab === 'referrers' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('referrers')}><Network size={14} /> Referrers</button>
      </div>

      {tab !== 'referrers' ? <AffiliatePayoutPanel mode={tab} canPay={canPay} userId={profile?.id || ''} onSaved={() => { void loadReferrers(); }} /> : <div className="card">
        <div className="table-wrap">
          {
            refLoading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
            : refErr ? <div className="empty-state" data-error="referrers"><p style={{ fontWeight: 600, color: 'var(--danger)' }}>The referrers could not be loaded</p><p style={{ fontSize: 13 }}>{refErr}</p><button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => void loadReferrers()}>Retry</button></div>
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
                      {/* The affiliate's months netted (410): never a negative Unpaid; what
                          they owe back is recovered from their later commission. */}
                      <td style={{ textAlign: 'right', color: Number(r.unpaid_earned) > 0 ? 'var(--primary)' : 'var(--text-muted)' }}>{money(owedSplit(r.unpaid_earned).unpaid)}
                        {owedSplit(r.unpaid_earned).deduction > 0 && <div style={{ fontSize: 11.5, color: 'var(--danger)' }}>Owes {money(owedSplit(r.unpaid_earned).deduction)} back</div>}</td>
                      <td style={{ textAlign: 'right' }}><button className="btn btn-secondary btn-sm" onClick={() => openDetail(r)}><Network size={13} /> View</button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )
          }
        </div>
      </div>}

      {detailFor && (
        <Modal title={`Referrer — ${detailFor.full_name}`} maxWidth={680} onClose={closeDetail}
          footer={<button className="btn btn-secondary" onClick={closeDetail}>Close</button>}>
          {detailErr ? <div className="empty-state" data-error="referrer-detail"><p style={{ fontWeight: 600, color: 'var(--danger)' }}>This referrer's earnings could not be loaded</p><p style={{ fontSize: 13 }}>{detailErr}</p><button className="btn btn-secondary btn-sm" style={{ marginTop: 8 }} onClick={() => void openDetail(detailFor)}>Retry</button></div>
          : !detail ? <div className="empty-state"><RefreshCw size={22} className="spin" style={{ opacity: 0.4 }} /></div> : (
            <div className="form-grid">
              {/* Lifetime totals */}
              <div>
                <label>Lifetime earnings</label>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8, marginTop: 6 }}>
                  <div style={{ padding: 10, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Tier 1 (not yet in a payout)</div>
                    <div style={{ fontSize: 15, fontWeight: 700 }}>{money(Number(detail.lifetime?.tier1_earned ?? 0))}</div>
                  </div>
                  <div style={{ padding: 10, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Tier 2 (not yet in a payout)</div>
                    <div style={{ fontSize: 15, fontWeight: 700 }}>{money(Number(detail.lifetime?.tier2_earned ?? 0))}</div>
                  </div>
                  <div style={{ padding: 10, background: 'var(--success-light)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Paid out</div>
                    <div style={{ fontSize: 15, fontWeight: 700 }}>{money(Number(detail.lifetime?.total_paid ?? 0))}</div>
                  </div>
                  <div style={{ padding: 10, background: 'var(--primary-light)', borderRadius: 'var(--radius-sm)' }}>
                    <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Unpaid total</div>
                    <div style={{ fontSize: 15, fontWeight: 700 }}>{money(owedSplit(detail.lifetime?.total_earned).unpaid)}</div>
                  </div>
                </div>
                {/* The tier boxes are the commission rows not yet in a payout, take-backs
                    included; Unpaid total nets the affiliate's months, so a deduction owed
                    back (never a negative Unpaid) and a settlement make them differ (414). */}
                {Math.round((Number(detail.lifetime?.tier1_earned ?? 0) + Number(detail.lifetime?.tier2_earned ?? 0)) * 100)
                  !== Math.round(owedSplit(detail.lifetime?.total_earned).unpaid * 100)
                  && <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4 }}>Deductions and settlements are netted in Unpaid total.</div>}
                {owedSplit(detail.lifetime?.total_earned).deduction > 0 && <div style={{ fontSize: 11.5, color: 'var(--danger)', marginTop: 4 }}>Deduction to be recovered: {money(owedSplit(detail.lifetime?.total_earned).deduction)}. Commission already paid out was taken back (a refund, a cancellation or a change of affiliate); it comes off this affiliate's later commission before anything more is paid.</div>}
                {/* 414: a deduction marked as settled (paid back, written off, or paid off outside the app) counts as recovered. */}
                {Number(detail.lifetime?.settled ?? 0) > 0 && <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4 }}>Deduction settled: {money(Number(detail.lifetime.settled))} (paid back, written off, or paid off outside the app; listed under Payout History). Counted as recovered. In the months below it is shown against the oldest months still owed back; the months it covers can change when later corrections arrive.</div>}
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
                          <td style={{ textAlign: 'right', color: 'var(--primary)' }}>{money(owedSplit(m.unpaid).unpaid)}{owedSplit(m.unpaid).deduction > 0 && <div style={{ fontSize: 11, color: 'var(--danger)' }}>owed back {money(owedSplit(m.unpaid).deduction)}</div>}{Number(m.settled ?? 0) > 0 && <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>settled {money(Number(m.settled))}</div>}</td>
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
                                    <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(Number(l.commission_amount))}<div style={{ fontSize: 11, fontWeight: 400 }}>Allocated: {money(Number(l.allocated_amount ?? 0))}</div></td>
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
                <label>Downline ({downline.length}) <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>— Tier 1 and Tier 2, the levels that earn commission</span></label>
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
        <Modal title="Commission Rates" maxWidth={460} onClose={() => setRatesOpen(false)} confirmClose={!!ratesCheck && ratesCheck.changes.length > 0}
          footer={<><button className="btn btn-secondary" onClick={() => ratesConfirm ? setRatesConfirm(false) : setRatesOpen(false)}>{ratesConfirm ? 'Back' : 'Cancel'}</button><button className="btn btn-primary" onClick={() => void saveRates()} disabled={ratesBusy || !ratesCheck?.rates || ratesCheck.changes.length === 0}>{ratesBusy ? 'Saving…' : ratesConfirm ? 'Confirm and save' : 'Save'}</button></>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
              Set the two-tier referral commission rates. Tier 1 is a percentage of the line value; Tier 2 is a percentage of the Tier 1 amount. Own and Third-party products can differ.
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              {RATE_KEYS.map((k, i) => (
                <div className="form-group" style={{ marginBottom: 0 }} key={k}>
                  <label htmlFor={`rate-${k}`}>{RATE_LABELS[k]} (%)</label>
                  <input id={`rate-${k}`} name={k} type="text" inputMode="decimal" value={ratesDraft[k]} autoFocus={i === 0}
                    aria-invalid={!!ratesCheck?.errors[k]} onChange={e => editRate(k, e.target.value)} />
                  {ratesCheck?.errors[k] && <div role="alert" data-rate-error={k} style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>{ratesCheck.errors[k]}</div>}
                </div>
              ))}
            </div>
            {ratesCheck?.rates && ratesCheck.changes.length === 0 && <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }} data-note="no-change">Nothing has changed yet.</div>}
            {ratesConfirm && ratesCheck?.rates && ratesCheck.changes.length > 0 && (
              <div className="alert alert-warning" data-confirm="rates" style={{ marginBottom: 0 }}>
                <span>⚠</span>
                <div>
                  <div style={{ fontWeight: 600 }}>Check the change before you save it:</div>
                  <ul style={{ margin: '4px 0 0 18px' }}>{ratesCheck.changes.map(c => <li key={c.key}>{changeLine(c)}</li>)}</ul>
                </div>
              </div>
            )}
            {ratesErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{ratesErr}</div></div>}
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Applies to invoices paid from now on. Already-earned commissions keep the rate they were calculated at.</div></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default CommissionsPage;
