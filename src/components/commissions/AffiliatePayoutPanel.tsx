import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { ExcelExportButton } from '../ExcelExport';
import { InvoiceSearchSelect } from '../invoices/InvoiceSearchSelect';
import { singaporeToday } from '../../lib/invoices/business';
import { priceCents } from '../../lib/cataloguePriceSearch';
import '../invoices/invoice-controls.css';

import { Balance, Payout, ReferrerBalance, payoutMoney as money, unavailableName, payoutInRange, payoutExportColumns, referrerBalances, monthPayable, monthKey, remainingPayable, deductionsOutstanding,
  Settlement, SettlementForm, SETTLEMENT_METHODS, SETTLEMENT_EARLIEST, settlementMethodLabel, settlementFormError, settlementInRange, settlementExportColumns,
  firstPaidPayoutDate, sgDate } from '../../lib/affiliatePayoutPresentation';
type Method = { id: string; name: string; is_active: boolean; deleted_at: string | null; is_wallet_credit: boolean };
type Form = { referrer: string; month: string; payout?: Payout; amount: string; method: string; date: string; reference: string; notes: string; reason: string; request: string };
// 414: Mark as settled (a deduction settled some other way) and its Void.
type SettleForm = SettlementForm & { referrer: string; request: string };
type VoidForm = { settlement: Settlement; reason: string; request: string };
// A Mark as settled or Void sent and not yet answered, kept across a reload.
type PendingAct = { kind: 'settle'; form: SettleForm } | { kind: 'void'; form: VoidForm };
// 414: which months a settlement is shown against is worked out each time.
const SETTLED_MONTHS_NOTE = 'A settlement is shown against the oldest months still owed back; the months it covers can change when later corrections arrive. What the affiliate owes in all does not.';
// A long note wraps by words and the table scrolls sideways on a phone,
// rather than squeezing the column to a few letters a line.
const noteCell: React.CSSProperties = { maxWidth: 300, minWidth: 180, whiteSpace: 'pre-wrap', overflowWrap: 'break-word' };

export function AffiliatePayoutPanel({ mode, canPay, userId, onSaved }: { mode: 'earned' | 'payouts'; canPay: boolean; userId: string; onSaved: () => void }) {
  const [groups, setGroups] = useState<Balance[]>([]), [payouts, setPayouts] = useState<Payout[]>([]), [methods, setMethods] = useState<Method[]>([]);
  // 410: each affiliate's months netted. A database without 410 sends none;
  // they are then worked out from the months the same way.
  const [serverRefs, setServerRefs] = useState<ReferrerBalance[] | null>(null);
  const [names, setNames] = useState<Record<string, string>>({}), [nameError, setNameError] = useState('');
  const [namesLoaded, setNamesLoaded] = useState(false);
  const [loading, setLoading] = useState(true), [loadError, setLoadError] = useState(''), [success, setSuccess] = useState('');
  const [form, setForm] = useState<Form | null>(null), [busy, setBusy] = useState(false), [error, setError] = useState(''), [uncertain, setUncertain] = useState(false);
  const [from, setFrom] = useState(''), [to, setTo] = useState('');
  const [historyFor, setHistoryFor] = useState<Payout | null>(null), [history, setHistory] = useState<any>(null), [historyError, setHistoryError] = useState('');
  // 414: deductions marked as settled (voided ones too); none before 414.
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [settleForm, setSettleForm] = useState<SettleForm | null>(null), [voidForm, setVoidForm] = useState<VoidForm | null>(null);
  const [actBusy, setActBusy] = useState(false), [actError, setActError] = useState(''), [actUncertain, setActUncertain] = useState(false);
  const sequence = useRef(0), saveLock = useRef(false), actLock = useRef(false);
  const pendingKey = `energia-affiliate-payout-pending:${userId}`;
  const settlePendingKey = `energia-affiliate-settlement-pending:${userId}`;
  const ids = useMemo(() => [...new Set([...groups.map(g => g.referrer), ...payouts.map(p => p.referrer_customer_id),
    ...settlements.map(x => x.referrer_customer_id)])], [groups, payouts, settlements]);
  const lookupNames = useCallback(async (requested: string[]) => {
    const found: Record<string, string> = {}; setNamesLoaded(false);
    try {
      // Bounded API calls, only identities actually referenced by these records.
      for (let i = 0; i < requested.length; i += 200) {
        const response = await supabase.rpc('commission_referrer_names', { p_ids: requested.slice(i, i + 200) });
        if (response.error) throw response.error;
        for (const r of response.data || []) if (r.full_name?.trim()) found[r.id] = r.full_name + (r.deleted_at ? ' (deleted)' : '');
      }
      setNames(found); setNameError('');
    } catch (e: any) { setNameError(`Affiliate names could not be loaded: ${e.message}. Records and IDs are still shown. Retry the lookup; an administrator may need to apply migrations 280–282 and reload the API schema.`); }
    finally { setNamesLoaded(true); }
  }, []);
  const load = useCallback(async () => {
    const seq = ++sequence.current; setLoading(true);
    try {
      const { data, error } = await supabase.rpc('affiliate_payout_overview');
      if (error) throw error;
      if (!data || !Array.isArray(data.groups) || !Array.isArray(data.payouts)) throw new Error('The payout response is incomplete.');
      if (seq !== sequence.current) return;
      setGroups(data.groups); setPayouts(data.payouts); setMethods(data.methods || []); setServerRefs(Array.isArray(data.referrers) ? data.referrers : null);
      setSettlements(Array.isArray(data.settlements) ? data.settlements : []); setLoadError('');
    } catch (e: any) { if (seq === sequence.current) setLoadError(`Balances could not be refreshed: ${e.message}. Refresh before recording or editing a payout.`); }
    finally { if (seq === sequence.current) setLoading(false); }
  }, []);
  useEffect(() => { void load(); return () => { sequence.current++; }; }, [load]);
  useEffect(() => { void lookupNames(ids); }, [ids, lookupNames]);
  useEffect(() => {
    try { const saved = sessionStorage.getItem(pendingKey); if (saved) { setForm(JSON.parse(saved)); setUncertain(true); setError('A previous save has an unconfirmed result. Retry the same save to recover its result safely.'); } } catch { /* Storage may be disabled. The in-memory request still prevents duplicate retries. */ }
  }, [pendingKey]);
  // 414: a Mark as settled or Void whose answer was lost comes back after a
  // reload with the same request id, so retrying it cannot record it twice.
  useEffect(() => {
    try {
      const saved = sessionStorage.getItem(settlePendingKey);
      if (!saved) return;
      const pending = JSON.parse(saved) as PendingAct;
      if (pending?.kind === 'settle' && pending.form?.request) setSettleForm(pending.form);
      else if (pending?.kind === 'void' && pending.form?.request && pending.form.settlement?.id) setVoidForm(pending.form);
      else { sessionStorage.removeItem(settlePendingKey); return; }
      setActUncertain(true);
      setActError('A previous save has an unconfirmed result. Retry the same save to recover its result safely.');
    } catch { /* Storage may be disabled. The in-memory request still prevents duplicate retries. */ }
  }, [settlePendingKey]);
  const name = (id: string) => names[id] || unavailableName(id);
  // Commission already paid out and then taken back is recovered from the
  // affiliate's later commission (the Owner, 3 Oct 2026): what may be paid
  // for a month is netted across all of the affiliate's months.
  const refs = useMemo(() => referrerBalances(groups, serverRefs), [groups, serverRefs]);
  const payableBy = useMemo(() => monthPayable(groups, refs), [groups, refs]);
  const payableOf = (g: Balance) => payableBy.get(monthKey(g)) ?? 0;
  const owing = useMemo(() => deductionsOutstanding(refs), [refs]);
  const open = (referrer: string, month: string, balance: number, payout?: Payout) => {
    setError(''); setUncertain(false);
    setForm({ referrer, month, payout, amount: Number(payout?.total_amount ?? balance).toFixed(2), method: payout?.payment_method_id || '', date: payout?.payment_date || singaporeToday(), reference: payout?.reference || '', notes: payout?.notes || '', reason: '', request: crypto.randomUUID() });
  };
  const update = (key: keyof Form, value: string) => setForm(f => f ? { ...f, [key]: value } : f);
  const save = async () => {
    if (!form || saveLock.current) return;
    if (priceCents(form.amount) == null || Number(form.amount) <= 0 || !form.method || !form.date || (form.payout && !form.reason.trim())) {
      setError('Enter a positive amount with at most two decimal places, a payment method, payment date, and a reason for corrections.'); return;
    }
    saveLock.current = true; setBusy(true); setError('');
    // Keep the request key across a lost response and even a reload of this tab.
    try { sessionStorage.setItem(pendingKey, JSON.stringify(form)); } catch { /* best effort */ }
    const args = { p_amount: form.amount, p_payment_method_id: form.method, p_payment_date: form.date, p_reference: form.reference.trim() || null, p_notes: form.notes.trim() || null, p_request_id: form.request };
    try {
      const response = form.payout
        ? await supabase.rpc('correct_affiliate_payout', { ...args, p_payout_id: form.payout.id, p_expected_version: form.payout.version, p_reason: form.reason.trim() })
        : await supabase.rpc('record_affiliate_payout', { ...args, p_referrer_customer_id: form.referrer, p_month: form.month });
      if (response.error) throw response.error;
      if (!response.data?.id) throw new Error('The server response could not be confirmed.');
      try { sessionStorage.removeItem(pendingKey); } catch { /* best effort */ }
      setForm(null); setUncertain(false);
      setSuccess(`${form.payout ? 'Payout correction' : 'Payout'} saved: ${money(response.data.amount)} · ${response.data.id}. This payment record is saved even if the refresh fails.`);
      onSaved(); await load();
    } catch (e: any) {
      // A PostgreSQL validation error rolled back the transaction. Network/API
      // failures may have lost a committed response: retry exactly that request.
      const definite = /^[0-9A-Z]{5}$/.test(e.code || '') && !String(e.code).startsWith('PGRST');
      setUncertain(!definite);
      setError(definite ? e.message : `Save result is unconfirmed: ${e.message}. Retry the same save; it cannot record this payment twice.`);
      if (definite) { try { sessionStorage.removeItem(pendingKey); } catch { /* best effort */ } setForm(f => f ? { ...f, request: crypto.randomUUID() } : f); }
    } finally { saveLock.current = false; setBusy(false); }
  };
  const loadHistory = async (p: Payout) => {
    setHistoryFor(p); setHistory(null); setHistoryError('');
    try { const { data, error } = await supabase.rpc('affiliate_payout_history', { p_payout_id: p.id }); if (error) throw error; setHistory(data); }
    catch (e: any) { setHistoryError(e.message); }
  };
  // 414: Mark as settled and Void. A refusal from the database is definite and
  // gets a new request id; a lost answer keeps the same one, so a retry cannot
  // record it twice.
  const act = async (pending: PendingAct, call: () => PromiseLike<{ data: any; error: any }>, done: (data: any) => string) => {
    if (actLock.current) return;
    actLock.current = true; setActBusy(true); setActError('');
    // Keep the request id across a lost answer and even a reload of this tab.
    try { sessionStorage.setItem(settlePendingKey, JSON.stringify(pending)); } catch { /* best effort */ }
    try {
      const response = await call();
      if (response.error) throw response.error;
      if (!response.data?.id) throw new Error('The server response could not be confirmed.');
      try { sessionStorage.removeItem(settlePendingKey); } catch { /* best effort */ }
      setSettleForm(null); setVoidForm(null); setActUncertain(false);
      setSuccess(done(response.data));
      onSaved(); await load();
    } catch (e: any) {
      const definite = /^[0-9A-Z]{5}$/.test(e.code || '') && !String(e.code).startsWith('PGRST');
      setActUncertain(!definite);
      setActError(definite ? e.message : `The result is unconfirmed: ${e.message}. Retry; it cannot be recorded twice.`);
      if (definite) {
        try { sessionStorage.removeItem(settlePendingKey); } catch { /* best effort */ }
        setSettleForm(f => f ? { ...f, request: crypto.randomUUID() } : f);
        setVoidForm(f => f ? { ...f, request: crypto.randomUUID() } : f);
      }
    } finally { actLock.current = false; setActBusy(false); }
  };
  const openSettle = (referrer: string) => {
    setActError(''); setActUncertain(false); setSuccess('');
    setSettleForm({ referrer, method: '', amount: (refs.get(referrer)?.deduction ?? 0).toFixed(2), date: singaporeToday(), note: '', request: crypto.randomUUID() });
  };
  const updateSettle = (key: keyof SettlementForm, value: string) => setSettleForm(f => f ? { ...f, [key]: value } : f);
  const settleDeduction = settleForm ? refs.get(settleForm.referrer)?.deduction ?? 0 : 0;
  // A deduction cannot have been settled before the first payout that made it.
  const settleFirstPayout = settleForm ? firstPaidPayoutDate(payouts, settleForm.referrer) : null;
  const saveSettle = () => {
    if (!settleForm) return;
    const problem = actUncertain ? '' : settlementFormError(settleForm, settleDeduction, singaporeToday(), settleFirstPayout);
    if (problem) { setActError(problem); return; }
    const f = settleForm;
    void act({ kind: 'settle', form: f }, () => supabase.rpc('record_affiliate_deduction_settlement', {
      p_referrer_customer_id: f.referrer, p_amount: f.amount.trim(), p_settled_on: f.date, p_method: f.method, p_note: f.note.trim(), p_request_id: f.request,
    }), d => `Marked as settled: ${money(d.amount)} for ${name(f.referrer)} (${settlementMethodLabel(d.method)}, ${sgDate(d.settled_on)}). The commission records and payouts are unchanged.`);
  };
  const openVoid = (settlement: Settlement) => { setActError(''); setActUncertain(false); setSuccess(''); setVoidForm({ settlement, reason: '', request: crypto.randomUUID() }); };
  const saveVoid = () => {
    if (!voidForm) return;
    if (!voidForm.reason.trim()) { setActError('A reason is required to void a settlement.'); return; }
    const f = voidForm;
    void act({ kind: 'void', form: f }, () => supabase.rpc('void_affiliate_deduction_settlement', { p_settlement_id: f.settlement.id, p_reason: f.reason.trim(), p_request_id: f.request }),
      d => `Settlement voided: ${name(f.settlement.referrer_customer_id)} owes ${money(d.amount)} back again, recovered from their later commission.`);
  };
  const visiblePayouts = payouts.filter(p => payoutInRange(p, from, to));
  const visibleSettlements = settlements.filter(x => settlementInRange(x, from, to));
  // What the server accepts for a new payout: the month's balance, and no more
  // than the affiliate's months net to (410).
  const formGroup = form ? groups.find(g => g.referrer === form.referrer && g.month === form.month) : undefined;
  const formCap = Math.min(Math.max(Number(formGroup?.balance ?? 0), 0), form ? refs.get(form.referrer)?.payable ?? 0 : 0);
  const frozen = loading || !!loadError || uncertain;
  const field = (label: string, key: 'amount' | 'date' | 'reference' | 'notes' | 'reason', type = 'text') => <label className="form-group">{label}<input type={type} step={key === 'amount' ? '0.01' : undefined} min={key === 'amount' ? '0.01' : undefined} max={key === 'date' ? singaporeToday() : undefined} value={form?.[key] || ''} onChange={e => update(key, e.target.value)} /></label>;
  const recordValues = (r: any) => r ? <dl><dt>Amount</dt><dd>{money(r.total_amount)}</dd><dt>Payment date / method</dt><dd>{r.payment_date || r.paid_at?.slice(0, 10)} · {r.payment_method_name || methods.find(m => m.id === r.payment_method_id)?.name || 'Historical method unavailable'}</dd><dt>Reference / notes</dt><dd style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{r.reference || '—'} / {r.notes || '—'}</dd></dl> : null;
  return <div>
    {success && <div className="alert alert-success" role="status">{success}</div>}
    {loadError && <div className="alert alert-danger" role="alert">{loadError}</div>}
    {nameError && <div className="alert alert-danger" role="alert"><div>{nameError}<button className="btn btn-secondary btn-sm" onClick={() => lookupNames(ids)}>Retry names</button></div></div>}
    {namesLoaded && !nameError && ids.some(id => !names[id]) && <div className="alert alert-info">No readable customer name was returned for the rows marked “Name unavailable”. Their full customer IDs are in the row tooltips and export; review the corresponding customer records to resolve their names.</div>}
    <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', alignItems: 'center', marginBottom: 16 }}>
      <strong>Remaining payable: {money(remainingPayable(refs))}</strong>
      {owing.count > 0 && <span role="status">Deductions to recover: {money(owing.total)} ({owing.count} affiliate{owing.count === 1 ? '' : 's'}), taken from their later commission before anything more is paid.</span>}
      <button className="btn btn-secondary" onClick={load} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh payouts'}</button>
      {mode === 'payouts' ? <ExcelExportButton rows={visiblePayouts} filename="affiliate-payouts" sheetName="Commissions" dateOf={(p: Payout) => p.payment_date} dateLabel="Payment date" columns={payoutExportColumns(name)} /> : <ExcelExportButton rows={groups} filename="affiliate-balances" sheetName="Commissions" columns={[
          { header: 'Affiliate', value: (g: Balance) => name(g.referrer) }, { header: 'Affiliate ID', value: (g: Balance) => g.referrer },
          { header: 'Month', value: (g: Balance) => g.month || 'Date needs review' },
          ...(['earned', 'adjustments', 'paid'] as const).map(key => ({ header: key, value: (g: Balance) => Number(g[key]) })),
          // 414: balance = earned + adjustments - paid + settled, so the columns add up.
          { header: 'settled', value: (g: Balance) => Number(g.settled ?? 0) },
          { header: 'balance', value: (g: Balance) => Number(g.balance) },
          { header: 'payable now', value: (g: Balance) => payableOf(g) },
          { header: 'affiliate deduction to recover', value: (g: Balance) => refs.get(g.referrer)?.deduction ?? 0 },
          { header: 'Review', value: (g: Balance) => g.review_reason || '' },
        ]} />}
    </div>
    {mode === 'payouts' && <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginBottom: 12 }}>
      <label>Payment date from <input type="date" value={from} onChange={e => setFrom(e.target.value)} /></label>
      <label>Payment date to <input type="date" value={to} onChange={e => setTo(e.target.value)} /></label>
    </div>}
    <div className="card table-wrap">
      {mode === 'earned' ? <table><thead><tr><th>Commission month</th><th>Affiliate</th><th>Earned</th><th>Adjustments</th><th>Paid</th><th>Remaining</th><th>Payable now</th><th>Action</th></tr></thead><tbody>
        {groups.map(g => { const payable = payableOf(g), ref = refs.get(g.referrer); return <tr key={`${g.referrer}/${g.month}`}><td>{g.month?.slice(0, 7) || 'Date needs review'}</td><td title={g.referrer}>{name(g.referrer)}</td>
          <td>{money(g.earned)}</td><td>{money(g.adjustments)}</td><td>{money(g.paid)}</td><td>{money(Math.max(Number(g.balance), 0))}{Number(g.balance) < 0 && <div>Owed back: {money(-Number(g.balance))}</div>}{Number(g.settled ?? 0) > 0 && <div title={SETTLED_MONTHS_NOTE}>Settled: {money(Number(g.settled))}</div>}</td>
          <td>{money(payable)}{ref && ref.deduction > 0
            ? <div style={{ color: 'var(--danger)' }}>Affiliate owes {money(ref.deduction)} back; recovered from later commission first.{canPay && <div style={{ marginTop: 6 }}><button className="btn btn-secondary btn-sm" disabled={frozen} onClick={() => openSettle(g.referrer)}>Mark as settled</button></div>}</div>
            : !g.review_reason && payable < Math.max(Number(g.balance), 0) && <div>Limited by the affiliate's other months ({money(ref?.payable ?? 0)} payable in all).</div>}</td>
          <td>{g.review_reason && <p role="status">{g.review_reason}</p>}{canPay && <button className="btn btn-primary btn-sm" disabled={frozen || !g.month || !!g.review_reason || payable <= 0} onClick={() => open(g.referrer, g.month!, payable)}>Record payout</button>}</td></tr>; })}
        {!groups.length && <tr><td colSpan={8}>{loading ? 'Loading balances…' : 'No commission balances.'}</td></tr>}
      </tbody></table> : <table><thead><tr><th>Payment date / month</th><th>Affiliate</th><th>Amount</th><th>Tier 1 / Tier 2</th><th>Method / reference / notes</th><th>Actions</th></tr></thead><tbody>
        {visiblePayouts.map(p => <tr key={p.id}><td>{p.payment_date}<div>{p.payout_month.slice(0, 7)} · {p.status}</div></td><td title={p.referrer_customer_id}>{name(p.referrer_customer_id)}</td><td>{money(p.total_amount)}</td><td>{money(p.total_tier1)} / {money(p.total_tier2)}</td>
          <td style={noteCell}>{p.payment_method_name || 'Historical method unavailable'}<div>{p.reference}</div><div>{p.notes}</div>{p.allocation_review_reason && <p>{p.allocation_review_reason}</p>}</td>
          <td><div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}><button className="btn btn-secondary btn-sm" onClick={() => loadHistory(p)}>History & allocations</button>{canPay && <button className="btn btn-secondary btn-sm" disabled={frozen || p.status !== 'paid'} onClick={() => open(p.referrer_customer_id, p.payout_month, 0, p)}>Edit payout</button>}</div></td></tr>)}
        {!visiblePayouts.length && <tr><td colSpan={6}>{loading ? 'Loading payouts…' : 'No payouts in this date range.'}</td></tr>}
      </tbody></table>}
    </div>
    {mode === 'payouts' && <div className="card" style={{ marginTop: 16 }} data-testid="settlement-history">
      <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', padding: '12px 12px 0' }}>
        <h3 style={{ margin: 0, fontSize: 15 }}>Deductions marked as settled</h3>
        <ExcelExportButton rows={visibleSettlements} filename="affiliate-settlements" sheetName="Settlements" dateOf={(x: Settlement) => x.settled_on} dateLabel="Date settled" columns={settlementExportColumns(name)} />
      </div>
      <p style={{ padding: '0 12px', fontSize: 12.5, color: 'var(--text-muted)' }}>Commission paid out and then taken back that was settled another way: paid back, written off, or paid off outside the app. A voided settlement no longer counts; the affiliate owes that amount back again. {SETTLED_MONTHS_NOTE}</p>
      <p style={{ padding: '0 12px', fontSize: 12.5, color: 'var(--text-muted)' }}>Filtered by the date settled, using the payment date range above.</p>
      <div className="table-wrap"><table><thead><tr><th>Date settled</th><th>Affiliate</th><th>Amount</th><th>How</th><th>Note</th><th>Recorded</th><th>Actions</th></tr></thead><tbody>
        {visibleSettlements.map(x => <tr key={x.id}><td>{sgDate(x.settled_on)}{x.voided_at && <div><span className="badge badge-muted">Voided</span></div>}</td>
          <td title={x.referrer_customer_id}>{name(x.referrer_customer_id)}</td>
          <td>{x.voided_at ? <s>{money(x.amount)}</s> : money(x.amount)}</td><td>{settlementMethodLabel(x.method)}</td>
          <td style={noteCell}>{x.note}{x.voided_at && <div style={{ color: 'var(--danger)' }}>Voided {new Date(x.voided_at).toLocaleDateString('en-SG', { timeZone: 'Asia/Singapore' })} by {x.voided_by_name || 'Unavailable'}: {x.void_reason}</div>}</td>
          <td>{x.created_by_name || 'Unavailable'}<div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{new Date(x.created_at).toLocaleString('en-SG', { timeZone: 'Asia/Singapore' })} SGT</div></td>
          <td>{canPay && !x.voided_at && <button className="btn btn-secondary btn-sm" disabled={frozen} onClick={() => openVoid(x)}>Void</button>}</td></tr>)}
        {!visibleSettlements.length && <tr><td colSpan={7}>{loading ? 'Loading…' : 'No deductions marked as settled with a date settled in this range.'}</td></tr>}
      </tbody></table></div>
    </div>}
    {form && <Modal title={form.payout ? 'Edit payout' : 'Record payout'} maxWidth={600} onClose={() => { if (!busy && !uncertain) setForm(null); }} footer={<>
      <button className="btn btn-secondary" disabled={busy || uncertain} onClick={() => setForm(null)}>Cancel</button>
      <button className="btn btn-primary" disabled={busy} onClick={save}>{busy ? 'Saving…' : uncertain ? 'Retry same save' : form.payout ? 'Save correction' : 'Record payout'}</button></>}>
      <p><strong>{name(form.referrer)}</strong> · Commission month {form.month.slice(0, 7)}</p>
      {!names[form.referrer] && <p style={{ overflowWrap: 'anywhere' }}>Customer ID: {form.referrer}</p>}
      <p>{form.payout ? 'Correct a mistaken payment record. To record another actual payment, use Record payout. This correction does not transfer or recover money.' : 'Record a payment already made. This does not initiate a bank transfer.'}</p>
      <p>Current remaining balance: {money(groups.find(g => g.referrer === form.referrer && g.month === form.month)?.balance || 0)}</p>
      {!form.payout && <p>Can be paid now for this month, all of this affiliate's months counted: up to {money(formCap)}</p>}
      {(refs.get(form.referrer)?.deduction ?? 0) > 0 && <div className="alert alert-warning">This affiliate owes {money(refs.get(form.referrer)!.deduction)} back from commission already paid out and then taken back. It is recovered from their later commission first, so nothing more can be paid yet.</div>}
      {form.payout?.allocation_review_reason && <div className="alert alert-warning">{form.payout.allocation_review_reason} You may correct metadata while the amount stays unchanged.</div>}
      {error && <div className="alert alert-danger" role="alert">{error}</div>}
      <fieldset disabled={busy || uncertain} style={{ border: 0, padding: 0, minWidth: 0 }} className="form-grid">
        {field('Amount (S$)', 'amount', 'number')}
        <div className="form-group"><label>Payment method (required)</label><InvoiceSearchSelect value={form.method} onChange={v => update('method', v)} options={methods.filter(m => (m.is_active && !m.deleted_at && !m.is_wallet_credit) || m.id === form.payout?.payment_method_id).map(m => ({ value: m.id, label: m.name + (!m.is_active || m.deleted_at ? ' (historical, inactive)' : '') }))} /></div>
        {field('Payment date (Singapore)', 'date', 'date')}{field('Reference (optional)', 'reference')}{field('Notes (optional)', 'notes')}{form.payout && field('Correction reason (required)', 'reason')}
      </fieldset>
    </Modal>}
    {settleForm && <Modal title="Mark deduction as settled" maxWidth={560} onClose={() => { if (!actBusy && !actUncertain) setSettleForm(null); }} footer={<>
      <button className="btn btn-secondary" disabled={actBusy || actUncertain} onClick={() => setSettleForm(null)}>Cancel</button>
      <button className="btn btn-primary" disabled={actBusy} onClick={saveSettle}>{actBusy ? 'Saving…' : actUncertain ? 'Retry same save' : 'Mark as settled'}</button></>}>
      <p style={{ margin: '0 0 8px' }}><strong>{name(settleForm.referrer)}</strong> owes {money(settleDeduction)} back from commission already paid out and then taken back.</p>
      {!names[settleForm.referrer] && <p style={{ margin: '0 0 8px', overflowWrap: 'anywhere' }}>Customer ID: {settleForm.referrer}</p>}
      <p style={{ margin: '0 0 12px', fontSize: 12.5, color: 'var(--text-secondary)' }}>Record how it was settled. This does not pay or collect anything; it records what already happened. The commission records and payouts stay as they are, and a settlement recorded by mistake can be voided with a reason.</p>
      {actError && <div className="alert alert-danger" role="alert">{actError}</div>}
      <fieldset disabled={actBusy || actUncertain} style={{ border: 0, padding: 0, minWidth: 0 }} className="form-grid">
        <fieldset className="form-group" style={{ border: 0, padding: 0, margin: 0, minWidth: 0 }}>
          <legend style={{ fontSize: 12.5, fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 4 }}>How was it settled? (required)</legend>
          <div style={{ display: 'flex', gap: '0 16px', flexWrap: 'wrap' }}>
            {SETTLEMENT_METHODS.map(m => <label key={m.value} style={{ display: 'flex', alignItems: 'center', gap: 6, fontWeight: 400, minHeight: 40, marginBottom: 0 }}>
              <input type="radio" name="settlement-method" value={m.value} checked={settleForm.method === m.value} onChange={() => updateSettle('method', m.value)} style={{ width: 'auto' }} />{m.label}</label>)}
          </div>
        </fieldset>
        <label className="form-group">Amount (S$, at most {money(settleDeduction)})<input type="number" step="0.01" min="0.01" max={settleDeduction.toFixed(2)} value={settleForm.amount} onChange={e => updateSettle('amount', e.target.value)} /></label>
        <label className="form-group">Date it was settled (Singapore)<input type="date" min={settleFirstPayout && settleFirstPayout > SETTLEMENT_EARLIEST ? settleFirstPayout : SETTLEMENT_EARLIEST} max={singaporeToday()} value={settleForm.date} onChange={e => updateSettle('date', e.target.value)} /></label>
        <label className="form-group">Note (required)<textarea rows={3} maxLength={2000} placeholder="How and why it was settled" value={settleForm.note} onChange={e => updateSettle('note', e.target.value)} /></label>
      </fieldset>
    </Modal>}
    {voidForm && <Modal title="Void settlement" maxWidth={520} onClose={() => { if (!actBusy && !actUncertain) setVoidForm(null); }} footer={<>
      <button className="btn btn-secondary" disabled={actBusy || actUncertain} onClick={() => setVoidForm(null)}>Cancel</button>
      <button className="btn btn-danger" disabled={actBusy} onClick={saveVoid}>{actBusy ? 'Voiding…' : actUncertain ? 'Retry same void' : 'Void settlement'}</button></>}>
      <p style={{ margin: '0 0 8px' }}><strong>{name(voidForm.settlement.referrer_customer_id)}</strong> · {money(voidForm.settlement.amount)} · {settlementMethodLabel(voidForm.settlement.method)} · settled {sgDate(voidForm.settlement.settled_on)}</p>
      <p style={{ margin: '0 0 12px', fontSize: 12.5, color: 'var(--text-secondary)' }}>Void a settlement recorded by mistake. It stays in the history, marked void, and the affiliate owes {money(voidForm.settlement.amount)} back again, recovered from their later commission.</p>
      {actError && <div className="alert alert-danger" role="alert">{actError}</div>}
      <fieldset disabled={actBusy || actUncertain} style={{ border: 0, padding: 0, minWidth: 0 }}>
        <label className="form-group">Reason (required)<textarea rows={3} maxLength={2000} value={voidForm.reason} onChange={e => setVoidForm(f => f ? { ...f, reason: e.target.value } : f)} /></label>
      </fieldset>
    </Modal>}
    {historyFor && <Modal title="Payout history & allocations" maxWidth={780} onClose={() => setHistoryFor(null)}>
      <p>{name(historyFor.referrer_customer_id)} · {historyFor.payout_month.slice(0, 7)} · {historyFor.id}</p>
      {historyError && <div role="alert">{historyError} <button onClick={() => loadHistory(historyFor)}>Retry history</button></div>}
      {!history && !historyError && <p>Loading history…</p>}
      {history && <><details><summary>Original payment record</summary>{recordValues(history.original)}</details>
        <h3>Current allocations</h3><div className="table-wrap"><table><thead><tr><th>Invoice</th><th>Commission ID</th><th>Tier</th><th>Amount</th></tr></thead><tbody>{(history.allocations || []).map((a: any) => <tr key={a.commission_id}><td>{a.invoice_no}</td><td>{a.commission_id}</td><td>{a.tier}</td><td>{money(a.amount)}</td></tr>)}</tbody></table></div>
        {!history.allocations?.length && <p>No verified allocations are available. Check any historical review notice.</p>}
        {(history.changes || []).map((h: any) => <details key={h.id}><summary>Version {h.version} · {h.editor} · {new Date(h.created_at).toLocaleString('en-SG', { timeZone: 'Asia/Singapore' })} SGT</summary><p>Reason: {h.reason}</p>{h.old_record && <><strong>Previous</strong>{recordValues(h.old_record)}</>}<strong>Revised</strong>{recordValues(h.new_record)}<details><summary>Allocation audit</summary><pre style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{JSON.stringify({ before: h.old_allocations, after: h.new_allocations }, null, 2)}</pre></details></details>)}
      </>}
    </Modal>}
  </div>;
}
