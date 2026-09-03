import { useEffect, useMemo, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { CustomerSearchSelect } from './SearchSelect';

// A Credit Package purchase divided between several customers, each of whom
// gets their own normal invoice. Paid/Bonus credit are derived from payment
// (read-only); reward vouchers are staff-adjustable but must total the
// package's reward. The RPC is authoritative — this panel is a live preview.

export interface CreditSplitAllocation {
  customer_id: string;
  payment_amount: number;
  allocation_percent: number;
  paid_credit_amount: number;
  bonus_credit_amount: number;
  reward_voucher_qty: number;
}

interface BenefitPreview {
  found: boolean;
  package_name: string;
  customer_price: number;
  paid_credit_total: number;
  bonus_total: number;
  grants_reward: boolean;
  reward_voucher_total: number;
}

interface Row { customer_id: string; payment: string; vouchers: string; }

interface Props {
  storeId: string;
  creditPackageId: string;
  serviceStaff: string[];
  affiliateId: string | null;
  notes: string | null;
  onCreated: (result: any) => void;
  onCancel: () => void;
}

const money = (n: number) => 'S$' + n.toLocaleString('en-SG', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

// Cent-exact proportional split (mirrors split_amount_by_weights server-side).
function splitAmount(total: number, weights: number[]): number[] {
  const n = weights.length;
  const sumw = weights.reduce((a, b) => a + b, 0);
  const centsTotal = Math.round(total * 100);
  if (n === 0) return [];
  if (sumw <= 0) { const a = new Array(n).fill(0); a[0] = total; return a; }
  const base: number[] = []; const frac: { i: number; f: number }[] = [];
  let assigned = 0;
  for (let i = 0; i < n; i++) {
    const raw = (centsTotal * weights[i]) / sumw;
    const fl = Math.floor(raw);
    base.push(fl); frac.push({ i, f: raw - fl }); assigned += fl;
  }
  let short = centsTotal - assigned;
  frac.sort((a, b) => b.f - a.f || a.i - b.i);
  for (let k = 0; k < short; k++) base[frac[k].i] += 1;
  return base.map(c => round2(c / 100));
}

// Largest-remainder integer split (mirrors split_int_by_weights).
function splitInt(total: number, weights: number[]): number[] {
  const n = weights.length;
  if (total === 0 || n === 0) return new Array(n).fill(0);
  const sumw = weights.reduce((a, b) => a + b, 0);
  if (sumw <= 0) { const a = new Array(n).fill(0); a[0] = total; return a; }
  const base: number[] = []; const frac: { i: number; f: number }[] = [];
  let assigned = 0;
  for (let i = 0; i < n; i++) {
    const raw = (total * weights[i]) / sumw;
    const fl = Math.floor(raw);
    base.push(fl); frac.push({ i, f: raw - fl }); assigned += fl;
  }
  let short = total - assigned;
  frac.sort((a, b) => b.f - a.f || a.i - b.i);
  for (let k = 0; k < short; k++) base[frac[k].i] += 1;
  return base;
}

export function CreditPackageSplitPanel(props: Props) {
  const { storeId, creditPackageId, serviceStaff, affiliateId, notes, onCreated, onCancel } = props;
  const [pv, setPv] = useState<BenefitPreview | null>(null);
  const [rows, setRows] = useState<Row[]>([{ customer_id: '', payment: '', vouchers: '0' }, { customer_id: '', payment: '', vouchers: '0' }]);
  const [vouchersTouched, setVouchersTouched] = useState(false);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    (async () => {
      const { data, error } = await supabase.rpc('credit_package_benefit_preview', { p_package_id: creditPackageId, p_store_id: storeId });
      if (!live) return;
      if (error) { setErr(error.message); return; }
      setPv(data as BenefitPreview);
    })();
    return () => { live = false; };
  }, [creditPackageId, storeId]);

  const payments = rows.map(r => Number(r.payment) || 0);
  const paidTotal = pv?.paid_credit_total ?? 0;
  const bonusTotal = pv?.bonus_total ?? 0;
  const rewardTotal = pv?.reward_voucher_total ?? 0;
  const price = pv?.customer_price ?? 0;

  const paidParts = useMemo(() => splitAmount(paidTotal, payments), [paidTotal, JSON.stringify(payments)]);
  const bonusParts = useMemo(() => splitAmount(bonusTotal, payments), [bonusTotal, JSON.stringify(payments)]);
  const suggestedVouchers = useMemo(() => splitInt(rewardTotal, payments), [rewardTotal, JSON.stringify(payments)]);

  // Keep vouchers on the suggestion until staff edits them.
  const applySuggested = useCallback(() => {
    setRows(rs => rs.map((r, i) => ({ ...r, vouchers: String(suggestedVouchers[i] ?? 0) })));
    setVouchersTouched(false);
  }, [suggestedVouchers]);

  useEffect(() => {
    if (!vouchersTouched && rewardTotal >= 0) {
      setRows(rs => rs.map((r, i) => ({ ...r, vouchers: String(suggestedVouchers[i] ?? 0) })));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [JSON.stringify(suggestedVouchers), vouchersTouched]);

  const paySum = round2(payments.reduce((a, b) => a + b, 0));
  const vouSum = rows.reduce((a, r) => a + (Number(r.vouchers) || 0), 0);
  const dupCustomer = (() => {
    const ids = rows.map(r => r.customer_id).filter(Boolean);
    return new Set(ids).size !== ids.length;
  })();
  const allCustomers = rows.every(r => r.customer_id);

  const payRemaining = round2(price - paySum);
  const payOk = Math.abs(payRemaining) < 0.005 && payments.every(p => p > 0);
  const vouOk = rewardTotal === 0 ? vouSum === 0 : vouSum === rewardTotal;

  const canCreate = pv?.found && rows.length >= 2 && allCustomers && !dupCustomer && payOk && vouOk && !saving;

  const setEqual = () => {
    const parts = splitAmount(price, new Array(rows.length).fill(1));
    setRows(rs => rs.map((r, i) => ({ ...r, payment: String(parts[i]) })));
  };

  const addRow = () => setRows(rs => [...rs, { customer_id: '', payment: '', vouchers: '0' }]);
  const removeRow = (i: number) => setRows(rs => rs.length > 2 ? rs.filter((_, k) => k !== i) : rs);

  const create = async () => {
    setErr(null);
    if (dupCustomer) { setErr('The same customer cannot appear twice.'); return; }
    if (!payOk) { setErr(payRemaining > 0 ? `Allocate the remaining ${money(payRemaining)} before creating the invoices.` : `The allocation exceeds the package price by ${money(-payRemaining)}.`); return; }
    if (!vouOk) { setErr(`Reward vouchers allocated: ${vouSum} / ${rewardTotal}. Adjust before creating.`); return; }
    setSaving(true);
    const allocations = rows.map(r => ({
      customer_id: r.customer_id,
      payment_amount: Number(r.payment) || 0,
      reward_voucher_qty: Number(r.vouchers) || 0,
    }));
    const { data, error } = await supabase.rpc('create_split_credit_package_invoices', {
      p_store_id: storeId,
      p_credit_package_id: creditPackageId,
      p_allocations: allocations,
      p_service_staff: serviceStaff?.length ? serviceStaff : null,
      p_affiliate_id: affiliateId,
      p_notes: notes,
    });
    setSaving(false);
    if (error) { setErr(error.message); return; }
    onCreated(data);
  };

  if (!pv) return <div style={{ padding: 12, color: 'var(--text-muted)' }}>Loading package…</div>;
  if (!pv.found) return <div style={{ padding: 12, color: 'var(--danger)' }}>Package unavailable.</div>;

  const th: React.CSSProperties = { textAlign: 'right', padding: '4px 8px', fontSize: 12, color: 'var(--text-muted)' };
  const td: React.CSSProperties = { textAlign: 'right', padding: '4px 8px', fontVariantNumeric: 'tabular-nums' };

  return (
    <div style={{ border: '1px solid var(--border)', borderRadius: 8, padding: 12, marginTop: 8 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
        <strong>Customer Allocation — {pv.package_name}</strong>
        <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
          Package {money(price)} · Paid {money(paidTotal)} · Bonus {money(bonusTotal)} · Reward {rewardTotal} vouchers
        </span>
      </div>

      <div style={{ display: 'flex', gap: 8, marginBottom: 8 }}>
        <button type="button" className="btn btn-secondary btn-sm" onClick={setEqual}>Split Equally</button>
        {rewardTotal > 0 && <button type="button" className="btn btn-secondary btn-sm" onClick={applySuggested}>Reset to Suggested Split</button>}
        <button type="button" className="btn btn-secondary btn-sm" onClick={addRow}>+ Add Customer</button>
      </div>

      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
        <thead>
          <tr>
            <th style={{ ...th, textAlign: 'left' }}>Customer</th>
            <th style={th}>Payment</th>
            <th style={th}>%</th>
            <th style={th}>Paid Credit</th>
            <th style={th}>Bonus</th>
            {rewardTotal > 0 && <th style={th}>Vouchers</th>}
            <th />
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => {
            const pct = price > 0 ? round2((payments[i] / price) * 100) : 0;
            return (
              <tr key={i}>
                <td style={{ padding: '4px 8px', minWidth: 220 }}>
                  <CustomerSearchSelect value={r.customer_id} onChange={v => setRows(rs => rs.map((x, k) => k === i ? { ...x, customer_id: v } : x))} />
                </td>
                <td style={td}>
                  <input type="number" min={0} step="0.01" value={r.payment} style={{ width: 100, textAlign: 'right' }}
                    onChange={e => setRows(rs => rs.map((x, k) => k === i ? { ...x, payment: e.target.value } : x))} />
                </td>
                <td style={td}>{pct.toFixed(2)}%</td>
                <td style={td}>{money(paidParts[i] ?? 0)}</td>
                <td style={td}>{money(bonusParts[i] ?? 0)}</td>
                {rewardTotal > 0 && (
                  <td style={td}>
                    <input type="number" min={0} step={1} value={r.vouchers} style={{ width: 64, textAlign: 'right' }}
                      onChange={e => { setVouchersTouched(true); setRows(rs => rs.map((x, k) => k === i ? { ...x, vouchers: e.target.value } : x)); }} />
                  </td>
                )}
                <td style={{ padding: '4px 8px' }}>
                  {rows.length > 2 && <button type="button" className="btn btn-secondary btn-sm" onClick={() => removeRow(i)}>×</button>}
                </td>
              </tr>
            );
          })}
        </tbody>
        <tfoot>
          <tr style={{ fontWeight: 600, borderTop: '1px solid var(--border)' }}>
            <td style={{ padding: '4px 8px' }}>Total</td>
            <td style={{ ...td, color: payOk ? 'inherit' : 'var(--danger)' }}>{money(paySum)}</td>
            <td style={td}>{price > 0 ? round2((paySum / price) * 100).toFixed(0) : 0}%</td>
            <td style={td}>{money(round2(paidParts.reduce((a, b) => a + b, 0)))}</td>
            <td style={td}>{money(round2(bonusParts.reduce((a, b) => a + b, 0)))}</td>
            {rewardTotal > 0 && <td style={{ ...td, color: vouOk ? 'inherit' : 'var(--danger)' }}>{vouSum} / {rewardTotal}</td>}
            <td />
          </tr>
        </tfoot>
      </table>

      <div style={{ marginTop: 8, fontSize: 12.5 }}>
        {!payOk && (payRemaining > 0
          ? <span style={{ color: 'var(--danger)' }}>Allocated: {money(paySum)} / {money(price)} — allocate the remaining {money(payRemaining)}.</span>
          : <span style={{ color: 'var(--danger)' }}>Allocated: {money(paySum)} / {money(price)} — exceeds the package price by {money(-payRemaining)}.</span>)}
        {payOk && rewardTotal > 0 && !vouOk && <span style={{ color: 'var(--danger)' }}>Reward vouchers allocated: {vouSum} / {rewardTotal}.</span>}
        {dupCustomer && <span style={{ color: 'var(--danger)' }}> The same customer is selected more than once.</span>}
        {payOk && vouOk && allCustomers && !dupCustomer && <span style={{ color: 'var(--text-muted)' }}>Paid Credit and Bonus are derived from payment and issued only when each customer’s own invoice is paid.</span>}
      </div>

      {err && <div style={{ color: 'var(--danger)', marginTop: 8 }}>{err}</div>}

      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 12 }}>
        <button type="button" className="btn btn-secondary" onClick={onCancel}>Cancel</button>
        <button type="button" className="btn btn-primary" disabled={!canCreate} onClick={create}>
          {saving ? 'Creating…' : `Create ${rows.length} Invoices`}
        </button>
      </div>
    </div>
  );
}
