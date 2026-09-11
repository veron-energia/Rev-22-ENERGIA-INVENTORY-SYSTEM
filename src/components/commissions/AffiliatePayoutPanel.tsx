import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { ExcelExportButton } from '../ExcelExport';
import { InvoiceSearchSelect } from '../invoices/InvoiceSearchSelect';
import { singaporeToday } from '../../lib/invoices/business';
import { priceCents } from '../../lib/cataloguePriceSearch';
import '../invoices/invoice-controls.css';

import { Balance, Payout, payoutMoney as money, unavailableName, payoutInRange, payoutExportColumns } from '../../lib/affiliatePayoutPresentation';
type Method = { id: string; name: string; is_active: boolean; deleted_at: string | null; is_wallet_credit: boolean };
type Form = { referrer: string; month: string; payout?: Payout; amount: string; method: string; date: string; reference: string; notes: string; reason: string; request: string };

export function AffiliatePayoutPanel({ mode, canPay, userId, onSaved }: { mode: 'earned' | 'payouts'; canPay: boolean; userId: string; onSaved: () => void }) {
  const [groups, setGroups] = useState<Balance[]>([]), [payouts, setPayouts] = useState<Payout[]>([]), [methods, setMethods] = useState<Method[]>([]);
  const [names, setNames] = useState<Record<string, string>>({}), [nameError, setNameError] = useState('');
  const [namesLoaded, setNamesLoaded] = useState(false);
  const [loading, setLoading] = useState(true), [loadError, setLoadError] = useState(''), [success, setSuccess] = useState('');
  const [form, setForm] = useState<Form | null>(null), [busy, setBusy] = useState(false), [error, setError] = useState(''), [uncertain, setUncertain] = useState(false);
  const [from, setFrom] = useState(''), [to, setTo] = useState('');
  const [historyFor, setHistoryFor] = useState<Payout | null>(null), [history, setHistory] = useState<any>(null), [historyError, setHistoryError] = useState('');
  const sequence = useRef(0), saveLock = useRef(false);
  const pendingKey = `energia-affiliate-payout-pending:${userId}`;
  const ids = useMemo(() => [...new Set([...groups.map(g => g.referrer), ...payouts.map(p => p.referrer_customer_id)])], [groups, payouts]);
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
      setGroups(data.groups); setPayouts(data.payouts); setMethods(data.methods || []); setLoadError('');
    } catch (e: any) { if (seq === sequence.current) setLoadError(`Balances could not be refreshed: ${e.message}. Refresh before recording or editing a payout.`); }
    finally { if (seq === sequence.current) setLoading(false); }
  }, []);
  useEffect(() => { void load(); return () => { sequence.current++; }; }, [load]);
  useEffect(() => { void lookupNames(ids); }, [ids, lookupNames]);
  useEffect(() => {
    try { const saved = sessionStorage.getItem(pendingKey); if (saved) { setForm(JSON.parse(saved)); setUncertain(true); setError('A previous save has an unconfirmed result. Retry the same save to recover its result safely.'); } } catch { /* Storage may be disabled. The in-memory request still prevents duplicate retries. */ }
  }, [pendingKey]);
  const name = (id: string) => names[id] || unavailableName(id);
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
  const visiblePayouts = payouts.filter(p => payoutInRange(p, from, to));
  const frozen = loading || !!loadError || uncertain;
  const field = (label: string, key: 'amount' | 'date' | 'reference' | 'notes' | 'reason', type = 'text') => <label className="form-group">{label}<input type={type} step={key === 'amount' ? '0.01' : undefined} min={key === 'amount' ? '0.01' : undefined} max={key === 'date' ? singaporeToday() : undefined} value={form?.[key] || ''} onChange={e => update(key, e.target.value)} /></label>;
  const recordValues = (r: any) => r ? <dl><dt>Amount</dt><dd>{money(r.total_amount)}</dd><dt>Payment date / method</dt><dd>{r.payment_date || r.paid_at?.slice(0, 10)} · {r.payment_method_name || methods.find(m => m.id === r.payment_method_id)?.name || 'Historical method unavailable'}</dd><dt>Reference / notes</dt><dd style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{r.reference || '—'} / {r.notes || '—'}</dd></dl> : null;
  return <div>
    {success && <div className="alert alert-success" role="status">{success}</div>}
    {loadError && <div className="alert alert-danger" role="alert">{loadError}</div>}
    {nameError && <div className="alert alert-danger" role="alert"><div>{nameError}<button className="btn btn-secondary btn-sm" onClick={() => lookupNames(ids)}>Retry names</button></div></div>}
    {namesLoaded && !nameError && ids.some(id => !names[id]) && <div className="alert alert-info">No readable customer name was returned for the rows marked “Name unavailable”. Their full customer IDs are in the row tooltips and export; review the corresponding customer records to resolve their names.</div>}
    <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', alignItems: 'center', marginBottom: 16 }}>
      <strong>Remaining payable: {money(groups.reduce((s, g) => s + (g.review_reason ? 0 : Math.max(Number(g.balance), 0)), 0))}</strong>
      <button className="btn btn-secondary" onClick={load} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh payouts'}</button>
      {mode === 'payouts' ? <ExcelExportButton rows={visiblePayouts} filename="affiliate-payouts" sheetName="Commissions" dateOf={(p: Payout) => p.payment_date} dateLabel="Payment date" columns={payoutExportColumns(name)} /> : <ExcelExportButton rows={groups} filename="affiliate-balances" sheetName="Commissions" columns={[
          { header: 'Affiliate', value: (g: Balance) => name(g.referrer) }, { header: 'Affiliate ID', value: (g: Balance) => g.referrer },
          { header: 'Month', value: (g: Balance) => g.month || 'Date needs review' },
          ...(['earned', 'adjustments', 'paid', 'balance'] as const).map(key => ({ header: key, value: (g: Balance) => Number(g[key]) })),
          { header: 'Review', value: (g: Balance) => g.review_reason || '' },
        ]} />}
    </div>
    {mode === 'payouts' && <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, marginBottom: 12 }}>
      <label>Payment date from <input type="date" value={from} onChange={e => setFrom(e.target.value)} /></label>
      <label>Payment date to <input type="date" value={to} onChange={e => setTo(e.target.value)} /></label>
    </div>}
    <div className="card table-wrap">
      {mode === 'earned' ? <table><thead><tr><th>Commission month</th><th>Affiliate</th><th>Earned</th><th>Adjustments</th><th>Paid</th><th>Remaining</th><th>Action</th></tr></thead><tbody>
        {groups.map(g => <tr key={`${g.referrer}/${g.month}`}><td>{g.month?.slice(0, 7) || 'Date needs review'}</td><td title={g.referrer}>{name(g.referrer)}</td>
          <td>{money(g.earned)}</td><td>{money(g.adjustments)}</td><td>{money(g.paid)}</td><td>{money(Math.max(Number(g.balance), 0))}{Number(g.balance) < 0 && <div>Overpaid adjustment: {money(-Number(g.balance))}</div>}</td>
          <td>{g.review_reason && <p role="status">{g.review_reason}</p>}{canPay && <button className="btn btn-primary btn-sm" disabled={frozen || !g.month || !!g.review_reason || Number(g.balance) <= 0} onClick={() => open(g.referrer, g.month!, g.balance)}>Record payout</button>}</td></tr>)}
        {!groups.length && <tr><td colSpan={7}>{loading ? 'Loading balances…' : 'No commission balances.'}</td></tr>}
      </tbody></table> : <table><thead><tr><th>Payment date / month</th><th>Affiliate</th><th>Amount</th><th>Tier 1 / Tier 2</th><th>Method / reference / notes</th><th>Actions</th></tr></thead><tbody>
        {visiblePayouts.map(p => <tr key={p.id}><td>{p.payment_date}<div>{p.payout_month.slice(0, 7)} · {p.status}</div></td><td title={p.referrer_customer_id}>{name(p.referrer_customer_id)}</td><td>{money(p.total_amount)}</td><td>{money(p.total_tier1)} / {money(p.total_tier2)}</td>
          <td style={{ maxWidth: 300, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{p.payment_method_name || 'Historical method unavailable'}<div>{p.reference}</div><div>{p.notes}</div>{p.allocation_review_reason && <p>{p.allocation_review_reason}</p>}</td>
          <td><div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}><button className="btn btn-secondary btn-sm" onClick={() => loadHistory(p)}>History & allocations</button>{canPay && <button className="btn btn-secondary btn-sm" disabled={frozen || p.status !== 'paid'} onClick={() => open(p.referrer_customer_id, p.payout_month, 0, p)}>Edit payout</button>}</div></td></tr>)}
        {!visiblePayouts.length && <tr><td colSpan={6}>{loading ? 'Loading payouts…' : 'No payouts in this date range.'}</td></tr>}
      </tbody></table>}
    </div>
    {form && <Modal title={form.payout ? 'Edit payout' : 'Record payout'} maxWidth={600} onClose={() => { if (!busy && !uncertain) setForm(null); }} footer={<>
      <button className="btn btn-secondary" disabled={busy || uncertain} onClick={() => setForm(null)}>Cancel</button>
      <button className="btn btn-primary" disabled={busy} onClick={save}>{busy ? 'Saving…' : uncertain ? 'Retry same save' : form.payout ? 'Save correction' : 'Record payout'}</button></>}>
      <p><strong>{name(form.referrer)}</strong> · Commission month {form.month.slice(0, 7)}</p>
      {!names[form.referrer] && <p style={{ overflowWrap: 'anywhere' }}>Customer ID: {form.referrer}</p>}
      <p>{form.payout ? 'Correct a mistaken payment record. To record another actual payment, use Record payout. This correction does not transfer or recover money.' : 'Record a payment already made. This does not initiate a bank transfer.'}</p>
      <p>Current remaining balance: {money(groups.find(g => g.referrer === form.referrer && g.month === form.month)?.balance || 0)}</p>
      {form.payout?.allocation_review_reason && <div className="alert alert-warning">{form.payout.allocation_review_reason} You may correct metadata while the amount stays unchanged.</div>}
      {error && <div className="alert alert-danger" role="alert">{error}</div>}
      <fieldset disabled={busy || uncertain} style={{ border: 0, padding: 0, minWidth: 0 }} className="form-grid">
        {field('Amount (S$)', 'amount', 'number')}
        <div className="form-group"><label>Payment method (required)</label><InvoiceSearchSelect value={form.method} onChange={v => update('method', v)} options={methods.filter(m => (m.is_active && !m.deleted_at && !m.is_wallet_credit) || m.id === form.payout?.payment_method_id).map(m => ({ value: m.id, label: m.name + (!m.is_active || m.deleted_at ? ' (historical, inactive)' : '') }))} /></div>
        {field('Payment date (Singapore)', 'date', 'date')}{field('Reference (optional)', 'reference')}{field('Notes (optional)', 'notes')}{form.payout && field('Correction reason (required)', 'reason')}
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
