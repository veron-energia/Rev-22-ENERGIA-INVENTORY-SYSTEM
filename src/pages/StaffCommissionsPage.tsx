import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { StaffCommission, StaffCommissionPayout, Profile, PaymentMethod, InstalmentBackfillRow, isOwnerOrManager, isManagerOrAbove } from '../types';
import { Modal, NoAccess } from '../components/ui';
import { RefreshCw, Coins, Wallet, Settings, Download } from 'lucide-react';
import { ExcelExportButton } from '../components/ExcelExport';

const money = (n: number) => `S$${n.toFixed(2)}`;
const monthKey = (d: string) => new Date(d).toLocaleDateString(undefined, { year: 'numeric', month: 'short' });

const StaffCommissionsPage: React.FC = () => {
  const { profile } = useAuth();
  // Access is checked AFTER the hooks below. Returning early here would call
  // no hooks on the first render and every hook on the next, which React
  // treats as a fatal error and blanks the whole app.
  const hasAccess = isManagerOrAbove(profile?.role);
  const canPay = isOwnerOrManager(profile?.role);

  const [tab, setTab] = useState<'earned' | 'payouts'>('earned');
  const [commissions, setCommissions] = useState<StaffCommission[]>([]);
  const [payouts, setPayouts] = useState<StaffCommissionPayout[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [rate, setRate] = useState<number>(3);
  // When part payments started earning commission (357). Null: not yet — the
  // owner first reviews and registers the part payments made before then.
  const [instalmentFrom, setInstalmentFrom] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // PostgREST caps a response at 1000 rows. staff_commissions was read in one
  // unpaginated call, and the table GROWS with every rebase: each press reverses
  // the existing rows (which stay) and inserts new ones. Once past 1000 rows the
  // page could see only a fraction of the earned ones, so the total fell with
  // each press — while the server-side preview, which aggregates in SQL, stayed
  // correct. The stored commission was never changing; only how much of it the
  // page could see.
  const fetchAllRows = async <T,>(build: (from: number, to: number) => any): Promise<T[]> => {
    const PAGE = 1000;
    const out: T[] = [];
    for (let from = 0; ; from += PAGE) {
      const { data, error } = await build(from, from + PAGE - 1);
      if (error) throw new Error(error.message);
      const batch = (data as T[]) ?? [];
      out.push(...batch);
      if (batch.length < PAGE) break;
    }
    return out;
  };

  const load = useCallback(async () => {
    setLoading(true);
    const [sc, pay, prof, pm, st, sw] = await Promise.all([
      fetchAllRows<StaffCommission>((f, t) => supabase.from('staff_commissions')
        .select('*').order('invoice_paid_date', { ascending: false }).range(f, t)),
      fetchAllRows<StaffCommissionPayout>((f, t) => supabase.from('staff_commission_payouts')
        .select('*').order('paid_at', { ascending: false }).range(f, t)),
      supabase.from('profiles').select('id,full_name,role,work_phone,is_active').is('deleted_at', null),
      supabase.from('payment_methods').select('*').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('app_settings').select('staff_commission_rate').eq('id', true).single(),
      // Read on its own: a database without the switch (before 357) must not cost
      // the page its real rate.
      supabase.from('app_settings').select('instalment_commission_from').eq('id', true).maybeSingle(),
    ]);
    setCommissions(sc ?? []);
    setPayouts(pay ?? []);
    setProfiles((prof.data as Profile[]) ?? []);
    setMethods((pm.data as PaymentMethod[]) ?? []);
    if (st.data) setRate(Number((st.data as any).staff_commission_rate));
    setInstalmentFrom((sw.data as any)?.instalment_commission_from ?? null);
    setLoading(false);
  }, []);
  useEffect(() => { load(); }, [load]);

  const sName = (id: string) => profiles.find(p => p.id === id)?.full_name ?? '—';
  const mName = (id: string | null) => id ? (methods.find(m => m.id === id)?.name ?? '—') : '—';

  // Unpaid grouped by staff + month.
  const earnedGroups = useMemo(() => {
    // "Invoices" counts invoices, not rows: an invoice paid in parts has a row
    // for each payment, and one more when it settles.
    const map = new Map<string, { staff_id: string; month: string; total: number; count: number; invoices: Set<string> }>();
    commissions.filter(c => c.status === 'earned' && !c.payout_id && c.invoice_paid_date).forEach(c => {
      const mk = (c.invoice_paid_date as string).slice(0, 7);
      const key = `${c.staff_id}|${mk}`;
      const g = map.get(key) ?? { staff_id: c.staff_id, month: mk, total: 0, count: 0, invoices: new Set<string>() };
      g.total += Number(c.commission_amount); g.invoices.add(c.invoice_id); g.count = g.invoices.size; map.set(key, g);
    });
    return Array.from(map.values()).sort((a, b) => b.month.localeCompare(a.month) || b.total - a.total);
  }, [commissions]);

  const unpaidTotal = earnedGroups.reduce((s, g) => s + g.total, 0);
  // Part-payment shares (357) stay with whoever shared each payment; the rebase never touches them.
  const partShareUnpaid = commissions
    .filter(c => c.status === 'earned' && !c.payout_id && c.earning_basis === 'instalment')
    .reduce((s, c) => s + Number(c.commission_amount), 0);

  // Pay modal
  const [payFor, setPayFor] = useState<{ staff_id: string; month: string; total: number } | null>(null);
  const [payMethod, setPayMethod] = useState(''); const [payRef, setPayRef] = useState('');
  const [payBusy, setPayBusy] = useState(false); const [payErr, setPayErr] = useState<string | null>(null);
  const submitPay = async () => {
    if (!payFor) return;
    setPayBusy(true); setPayErr(null);
    const { error } = await supabase.rpc('create_staff_commission_payout', {
      p_staff_id: payFor.staff_id, p_month: `${payFor.month}-01`,
      p_payment_method_id: payMethod || null, p_reference: payRef.trim() || null, p_notes: null,
    });
    setPayBusy(false);
    if (error) { setPayErr(error.message); return; }
    setPayFor(null); load();
  };

  // Rate settings
  const [rateOpen, setRateOpen] = useState(false);
  const [rateDraft, setRateDraft] = useState(3);
  const [rateBusy, setRateBusy] = useState(false);
  // Moving outstanding commission onto the store-staff basis. Previewed first:
  // this changes what people are owed, so it must be readable before it is done.
  const [rebaseOpen, setRebaseOpen] = useState(false);
  const [rebasePreview, setRebasePreview] = useState<any[]>([]);
  // The preview only covers invoices the rebase can act on. Anything outside
  // that — refunded, cancelled, deleted, part-paid — still shows on this page,
  // which is why the two totals never matched.
  const [rebaseScope, setRebaseScope] = useState<any>(null);
  const [outOfScope, setOutOfScope] = useState<any[]>([]);
  const [rebaseBusy, setRebaseBusy] = useState(false);
  const [rebaseDone, setRebaseDone] = useState<string | null>(null);

  const openRebase = async () => {
    setRebaseDone(null); setRebaseOpen(true); setRebasePreview([]);
    const [{ data }, { data: rec }, { data: out }] = await Promise.all([
      supabase.rpc('preview_commission_rebase_effect'),
      supabase.rpc('commission_totals_reconciliation'),
      supabase.rpc('commission_outside_rebase_scope'),
    ]);
    setRebasePreview((data as any[]) ?? []);
    setRebaseScope(rec ?? null);
    setOutOfScope((out as any[]) ?? []);
  };
  const applyRebase = async () => {
    setRebaseBusy(true);
    const { data, error } = await supabase.rpc('apply_commission_rebase_all');
    setRebaseBusy(false);
    if (error) { setRebaseDone(`Could not rebase: ${error.message}`); return; }
    const d = data as any;
    setRebaseDone(`${d?.invoices_affected ?? 0} invoice(s) rebased.`
      + (d?.invoices_with_no_commission_before
          ? ` ${d.invoices_with_no_commission_before} had no commission recorded before and now do.` : '')
      + (d?.invoices_skipped_already_paid
          ? ` ${d.invoices_skipped_already_paid} skipped — already paid out.` : ''));
    setRebasePreview([]);
    load();
  };
  // Registering part payments made before part-payment commission was on.
  // Always reviewed first: it adds to what people are owed, so the owner reads
  // every figure, and registering sends the commission and sales totals back —
  // the server refuses it if either total has moved since. It does not recheck
  // who each share goes to: a roster or 'Served by' change between review and
  // Register moves shares without changing the totals.
  const [partOpen, setPartOpen] = useState(false);
  const [partRows, setPartRows] = useState<InstalmentBackfillRow[] | null>(null);
  const [partBusy, setPartBusy] = useState(false);
  const [partErr, setPartErr] = useState<string | null>(null);
  const [partDone, setPartDone] = useState<string | null>(null);
  const [partCreditDate, setPartCreditDate] = useState<string | null>(null);
  const reviewPartPayments = async () => {
    setPartErr(null); setPartDone(null); setPartRows(null); setPartOpen(true);
    // Read in pages: the totals sent back on Register are added up from these
    // rows, and a response is capped at 1,000 rows.
    let rows: InstalmentBackfillRow[];
    try {
      rows = await fetchAllRows<InstalmentBackfillRow>((f, t) =>
        supabase.rpc('commission_instalment_backfill', { p_apply: false }).range(f, t));
    } catch (e: any) { setPartErr(e?.message ?? String(e)); return; }
    setPartRows(rows);
    setPartCreditDate(rows[0]?.credit_date ?? null);
  };
  // Commission owed, and separately the earlier receipts whose staff-sales credit moves to this month.
  const partTotal = (partRows ?? []).filter(r => r.ledger !== 'sales').reduce((t, r) => t + Number(r.earned_amount), 0);
  const partBlocked = (partRows ?? []).reduce((t, r) => t + Number(r.blocked_amount), 0);
  const partSales = (partRows ?? []).filter(r => r.ledger === 'sales').reduce((t, r) => t + Number(r.earned_amount), 0);
  const partByPerson = useMemo(() => {
    const map = new Map<string, { ledger: string; name: string; earned: number; blocked: number; invoices: { no: string; earned: number; blocked: number }[] }>();
    (partRows ?? []).filter(r => r.ledger !== 'sales').forEach(r => {
      const key = `${r.ledger}|${r.beneficiary_id}`;
      const g = map.get(key) ?? { ledger: r.ledger, name: r.beneficiary_name ?? '—', earned: 0, blocked: 0, invoices: [] };
      g.earned += Number(r.earned_amount); g.blocked += Number(r.blocked_amount);
      g.invoices.push({ no: r.invoice_no, earned: Number(r.earned_amount), blocked: Number(r.blocked_amount) });
      map.set(key, g);
    });
    // Staff first: this is the staff page.
    return Array.from(map.values()).sort((a, b) => (a.ledger === 'staff' ? 0 : 1) - (b.ledger === 'staff' ? 0 : 1) || b.earned - a.earned);
  }, [partRows]);
  const partSalesByPerson = useMemo(() => {
    const map = new Map<string, { name: string; total: number; invoices: string[] }>();
    (partRows ?? []).filter(r => r.ledger === 'sales').forEach(r => {
      const g = map.get(r.beneficiary_id) ?? { name: r.beneficiary_name ?? '—', total: 0, invoices: [] };
      g.total += Number(r.earned_amount); if (!g.invoices.includes(r.invoice_no)) g.invoices.push(r.invoice_no);
      map.set(r.beneficiary_id, g);
    });
    return Array.from(map.values()).sort((a, b) => b.total - a.total);
  }, [partRows]);
  const registerPartPayments = async () => {
    setPartBusy(true); setPartErr(null);
    const { error } = await supabase.rpc('commission_instalment_backfill', {
      p_apply: true, p_credit_date: partCreditDate, p_expected_total: Math.round(partTotal * 100) / 100,
      p_expected_sales: Math.round(partSales * 100) / 100,
    });
    setPartBusy(false);
    if (error) { setPartErr(error.message); return; }
    setPartDone(partTotal !== 0
      ? `${money(partTotal)} registered, dated ${partCreditDate ? new Date(partCreditDate).toLocaleDateString('en-GB') : 'today'}. Part payments now earn as they arrive.`
      : 'Part payments now earn commission as they arrive.');
    setPartRows([]);
    load();
  };

  const saveRate = async () => {
    setRateBusy(true);
    const { error } = await supabase.rpc('set_staff_commission_rate', { p_rate: rateDraft });
    setRateBusy(false);
    if (error) { alert(error.message); return; }
    setRateOpen(false); load();
  };


  if (!hasAccess) return <NoAccess message="Only Owners, Admins, and Managers can view staff commissions." />;


  return (
    <div>
      <div className="page-header">
        <div><h2>Staff Commissions</h2><p>{instalmentFrom
            ? <>Each payment received on an invoice, part payments included, pays {rate}% of it</>
            : <>Each paid invoice pays {rate}% of its total</>}, shared equally between the
          <strong> active staff assigned to that store</strong>{instalmentFrom ? ' on the day the payment is recorded' : ''} — Owners and Managers are excluded,
          and "Served by" does not affect it. Unpaid total: <strong>{money(unpaidTotal)}</strong></p></div>
        <div style={{ display: 'flex', gap: 10 }}>
          <ExcelExportButton
            rows={tab === 'earned' ? earnedGroups : payouts}
            filename={`staff-commissions-${tab}`} sheetName="Staff Commissions"
            dateOf={tab === 'payouts' ? ((p: any) => p.created_at) : undefined}
            dateLabel="Payout date"
            columns={tab === 'earned' ? [
              { header: 'Month', value: (g: any) => monthKey(`${g.month}-01`) },
              { header: 'Staff', value: (g: any) => sName(g.staff_id) },
              { header: 'Invoices', value: (g: any) => Number(g.count ?? 0) },
              { header: 'Unpaid', value: (g: any) => Number(g.total ?? 0) },
            ] : [
              { header: 'Paid on', value: (p: any) => new Date(p.paid_at ?? p.created_at).toLocaleDateString('en-GB') },
              { header: 'Month', value: (p: any) => monthKey(p.payout_month) },
              { header: 'Staff', value: (p: any) => sName(p.staff_id) },
              { header: 'Amount', value: (p: any) => Number(p.total_amount ?? 0) },
            ]} />
          {canPay && <button className="btn btn-secondary" onClick={() => { setRateDraft(rate); setRateOpen(true); }}><Settings size={15} /> Rate</button>}
          {canPay && <button className="btn btn-secondary" onClick={openRebase}><RefreshCw size={15} /> Rebase unpaid</button>}
          {!instalmentFrom && <button className="btn btn-secondary" onClick={reviewPartPayments}><Coins size={15} /> Part payments</button>}
          <button className="btn btn-secondary" onClick={load}><RefreshCw size={15} className={loading ? 'spin' : ''} /> Refresh</button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 6, marginBottom: 16 }}>
        <button className={`btn btn-sm ${tab === 'earned' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('earned')}><Coins size={14} /> Unpaid (by staff / month)</button>
        <button className={`btn btn-sm ${tab === 'payouts' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setTab('payouts')}><Wallet size={14} /> Payout History</button>
      </div>

      <div className="card"><div className="table-wrap">
        {loading ? <div className="empty-state"><RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} /></div>
        : tab === 'earned' ? (
          earnedGroups.length === 0 ? <div className="empty-state"><Coins size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No unpaid staff commission</p></div>
          : <table>
              <thead><tr><th>Month</th><th>Staff</th><th style={{ textAlign: 'right' }}>Invoices</th><th style={{ textAlign: 'right' }}>Unpaid</th>{canPay && <th></th>}</tr></thead>
              <tbody>{earnedGroups.map((g, i) => (
                <tr key={i}>
                  <td>{monthKey(`${g.month}-01`)}</td>
                  <td><strong>{sName(g.staff_id)}</strong></td>
                  <td style={{ textAlign: 'right' }}>{g.count}</td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(g.total)}</td>
                  {canPay && <td>{g.total > 0.004
                    ? <button className="btn btn-primary btn-sm" onClick={() => { setPayFor(g); setPayMethod(methods[0]?.id ?? ''); setPayRef(''); setPayErr(null); }}>Mark Paid</button>
                    : <span style={{ fontSize: 12, color: 'var(--text-muted)' }} title="Commission taken back after it was paid out. There is nothing to pay for this month, and it is not deducted from other months automatically: settle it with the staff member directly.">Nothing to pay</span>}</td>}
                </tr>))}
              </tbody>
            </table>
        ) : (
          payouts.length === 0 ? <div className="empty-state"><Wallet size={32} style={{ opacity: 0.3 }} /><p style={{ fontWeight: 600, marginTop: 8 }}>No payouts yet</p></div>
          : <table>
              <thead><tr><th>Paid On</th><th>Month</th><th>Staff</th><th style={{ textAlign: 'right' }}>Amount</th><th>Method</th><th>Reference</th></tr></thead>
              <tbody>{payouts.map(p => (
                <tr key={p.id}>
                  <td style={{ fontSize: 12.5 }}>{new Date(p.paid_at).toLocaleDateString()}</td>
                  <td>{monthKey(p.payout_month)}</td>
                  <td><strong>{sName(p.staff_id)}</strong></td>
                  <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(Number(p.total_amount))}</td>
                  <td style={{ fontSize: 12.5 }}>{mName(p.payment_method_id)}</td>
                  <td style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{p.reference || '—'}</td>
                </tr>))}
              </tbody>
            </table>
        )}
      </div></div>

      {payFor && (
        <Modal title="Mark Staff Commission Paid" maxWidth={420} onClose={() => setPayFor(null)}
          footer={<><button className="btn btn-secondary" onClick={() => setPayFor(null)}>Cancel</button><button className="btn btn-primary" onClick={submitPay} disabled={payBusy}>{payBusy ? 'Processing…' : `Pay ${money(payFor.total)}`}</button></>}>
          <div className="form-grid">
            {payErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{payErr}</div></div>}
            <div style={{ padding: 12, background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', fontSize: 13 }}>
              <strong>{sName(payFor.staff_id)}</strong> · {monthKey(`${payFor.month}-01`)}<br />
              Total unpaid: <strong>{money(payFor.total)}</strong>
            </div>
            <div className="form-group"><label>Payment Method</label>
              <select value={payMethod} onChange={e => setPayMethod(e.target.value)}>{methods.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}</select>
            </div>
            <div className="form-group"><label>Reference</label><input value={payRef} onChange={e => setPayRef(e.target.value)} placeholder="Optional" /></div>
          </div>
        </Modal>
      )}

      {rebaseOpen && (
        <Modal title="Rebase unpaid commission" maxWidth={640} onClose={() => setRebaseOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setRebaseOpen(false)}>Close</button>
            {rebasePreview.length > 0 && (
              <button className="btn btn-primary" onClick={applyRebase} disabled={rebaseBusy}>
                {rebaseBusy ? 'Rebasing…' : 'Apply to all unpaid'}</button>
            )}</>}>
          <div className="form-grid">
            {/* Why this dialog's figures differ from the page. Stated plainly,
                because unpaid commission on a refunded or cancelled invoice is a
                question about the money, not a display quirk. */}
            {rebaseScope && Number(rebaseScope.outside_rebase_scope ?? 0) !== 0 && (
              <div className="alert alert-warning" style={{ marginBottom: 0, display: 'block' }}>
                <div style={{ fontWeight: 600, marginBottom: 4 }}>
                  These figures cover part of the unpaid total
                </div>
                <div style={{ fontSize: 12.5 }}>
                  The page shows <strong>{money(Number(rebaseScope.page_total ?? 0))}</strong> unpaid.
                  Of that, <strong>{money(Number(rebaseScope.in_rebase_scope ?? 0))}</strong> is on
                  invoices this rebase can act on, and{' '}
                  <strong>{money(Number(rebaseScope.outside_rebase_scope ?? 0))}</strong> is not —
                  so it will be left exactly as it is.
                </div>
                {outOfScope.length > 0 && (
                  <table style={{ marginTop: 8, fontSize: 12 }}>
                    <tbody>
                      {outOfScope.map((r: any, i: number) => (
                        <tr key={i}>
                          <td style={{ paddingRight: 12 }}>{r.reason}</td>
                          <td style={{ paddingRight: 12, color: 'var(--text-muted)' }}>
                            {r.invoices} invoice{r.invoices === 1 ? '' : 's'}
                          </td>
                          <td style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
                            {money(Number(r.amount))}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
                <div style={{ fontSize: 11.5, marginTop: 6, color: 'var(--text-muted)' }}>
                  Commission still owed on a refunded or cancelled invoice is worth looking at —
                  the sale was undone but the commission was not.
                </div>
              </div>
            )}

            {Math.abs(partShareUnpaid) >= 0.005 && (
              <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
                {money(partShareUnpaid)} of the unpaid total is part-payment shares. The rebase never
                changes those — they stay with the staff who shared each payment — so "Rebasable now"
                below leaves them out, even where the figures above count them as on invoices it can act on.
              </div>
            )}

            {rebaseScope && Number(rebaseScope.no_paid_date ?? 0) !== 0 && (
              <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                A further {money(Number(rebaseScope.no_paid_date))} has no paid date recorded and
                is not counted on this page at all.
              </div>
            )}

            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              This recalculates commission that has <strong>not yet been paid out</strong> onto the
              current rule: <strong>every paid invoice divided equally between the active staff
              assigned to that store</strong>, whoever served the customer. Owners, Managers,
              Admins and Inventory Managers receive nothing. Anything already paid out is left
              exactly as it is.
            </div>

            {rebaseDone && (
              <div className="alert alert-info" style={{ marginBottom: 0 }}>
                <span>ℹ</span><div>{rebaseDone}</div>
              </div>
            )}

            {!rebaseDone && rebasePreview.length === 0 && (
              <div style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>
                Nothing outstanding to rebase.
              </div>
            )}

            {rebasePreview.length > 0 && (
              <div className="table-wrap">
                <table>
                  <thead><tr>
                    <th>Staff</th>
                    <th style={{ textAlign: 'right' }}>Rebasable now</th>
                    <th style={{ textAlign: 'right' }}>After</th>
                    <th style={{ textAlign: 'right' }}>Change</th>
                  </tr></thead>
                  <tbody>
                    {rebasePreview.map((r: any) => (
                      <tr key={r.staff_name}>
                        <td><strong>{r.staff_name}</strong></td>
                        <td style={{ textAlign: 'right' }}>{money(Number(r.current_unpaid))}</td>
                        <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(Number(r.projected_unpaid))}</td>
                        <td style={{ textAlign: 'right', fontWeight: 600,
                                     color: Number(r.difference) >= 0 ? 'var(--success)' : 'var(--danger)' }}>
                          {Number(r.difference) >= 0 ? '+' : ''}{money(Number(r.difference))}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {rebasePreview.length > 0 && (
              <div className="alert alert-warning" style={{ marginBottom: 0 }}>
                <span>⚠</span>
                <div>
                  The total paid out does not change — only how it is divided. The original rows are
                  kept and marked reversed, so the history stays intact.
                </div>
              </div>
            )}
          </div>
        </Modal>
      )}

      {partOpen && (
        <Modal title="Commission on part payments" maxWidth={680} onClose={() => setPartOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setPartOpen(false)}>Close</button>
            {canPay && partRows !== null && !partDone && (
              <button className="btn btn-primary" onClick={registerPartPayments} disabled={partBusy}>
                {partBusy ? 'Registering…' : partTotal !== 0 ? `Register ${money(partTotal)}` : 'Turn on'}</button>
            )}</>}>
          <div className="form-grid">
            <div style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>
              Invoices still being paid have earned nothing on the money already received. Registering
              credits it now, in one go, dated <strong>{partCreditDate ? new Date(partCreditDate).toLocaleDateString('en-GB') : 'today'}</strong>:
              staff share it with the store's active staff today, affiliates on the same rules as a fully paid
              invoice. From then on each part payment earns as it arrives. When an invoice is finally paid,
              the total is exactly what paying it in one go would have earned — nothing is paid twice.
              Wallet credit never earns.
            </div>
            {partErr && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{partErr}</div></div>}
            {partDone && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ</span><div>{partDone}</div></div>}
            {partRows === null && !partErr && (
              <div style={{ textAlign: 'center', padding: 20 }}><RefreshCw size={20} className="spin" style={{ opacity: 0.4 }} /></div>
            )}
            {partRows !== null && !partDone && partByPerson.length === 0 && partSalesByPerson.length === 0 && (
              <div style={{ textAlign: 'center', padding: 20, color: 'var(--text-muted)' }}>
                No earlier part payments to register.{canPay ? ' Turning it on only affects payments from now on.' : ''}
              </div>
            )}
            {partByPerson.length > 0 && (
              <div className="table-wrap">
                <table>
                  <thead><tr><th>Earns</th><th>Invoices</th><th style={{ textAlign: 'right' }}>Registered</th></tr></thead>
                  <tbody>
                    {partByPerson.map((g, i) => (
                      <tr key={i}>
                        <td><strong>{g.name}</strong><div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>{g.ledger === 'staff' ? 'Staff' : 'Affiliate'}</div></td>
                        <td style={{ fontSize: 12 }}>
                          {g.invoices.map(v => (
                            <div key={v.no} style={{ whiteSpace: 'nowrap' }}>{v.no}: {money(v.earned)}{v.blocked ? <span style={{ color: 'var(--text-muted)' }}> · {money(v.blocked)} not payable</span> : null}</div>
                          ))}
                        </td>
                        <td style={{ textAlign: 'right', fontWeight: 700 }}>{money(g.earned)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            {partByPerson.length > 0 && (
              <div style={{ fontSize: 12.5 }}>
                Total to register: <strong>{money(partTotal)}</strong>
                {partBlocked !== 0 && <span style={{ color: 'var(--text-muted)' }}> · a further {money(partBlocked)} is
                  recorded but not payable, because the referrer is not an activated affiliate</span>}
              </div>
            )}
            {partSalesByPerson.length > 0 && (
              <div style={{ fontSize: 12.5 }}>
                <div style={{ fontWeight: 600, marginBottom: 4 }}>Sales by Service Staff</div>
                <div style={{ color: 'var(--text-muted)', marginBottom: 6 }}>
                  {money(partSales)} of money on these invoices (payments less any refunds) arrived before this month.
                  Registering also credits it to this month in the Sales by Service Staff report, the same month as its
                  commission; the months it arrived in drop by the same amount. Revenue itself does not move.
                </div>
                {partSalesByPerson.map((g, i) => (
                  <div key={i} style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                    <span><strong>{g.name}</strong> <span style={{ color: 'var(--text-muted)' }}>{g.invoices.join(', ')}</span></span>
                    <span style={{ fontWeight: 600, whiteSpace: 'nowrap' }}>{money(g.total)}</span>
                  </div>
                ))}
              </div>
            )}
            {!canPay && partRows !== null && !partDone && (
              <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Only an Owner or Manager can register it.</div>
            )}
          </div>
        </Modal>
      )}

      {rateOpen && (
        <Modal title="Staff Commission Rate" maxWidth={380} onClose={() => setRateOpen(false)}
          footer={<><button className="btn btn-secondary" onClick={() => setRateOpen(false)}>Cancel</button><button className="btn btn-primary" onClick={saveRate} disabled={rateBusy}>{rateBusy ? 'Saving…' : 'Save'}</button></>}>
          <div className="form-grid">
            <div className="form-group"><label>Rate (% of each paid invoice, shared between the store's active staff)</label>
              <input type="number" min={0} step={0.1} value={rateDraft || ''} onChange={e => setRateDraft(+e.target.value)} autoFocus />
            </div>
            <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>Applies to invoices paid from now on. Already-earned commissions keep the rate they were calculated at.</div></div>
          </div>
        </Modal>
      )}
    </div>
  );
};

export default StaffCommissionsPage;
