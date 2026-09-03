import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';
import { CustomerSearchSelect } from './SearchSelect';

// A Premium Bundle purchase divided between several customers, each of whom
// gets their own normal invoice. Paid/Bonus credit are derived from payment
// (read-only); the bundle's free vouchers are allocated per customer across
// the bundle's allowed voucher types and must total the bundle's free quantity.
// The RPC is authoritative — this panel is a live preview.

interface AllowedVoucher { voucher_id: string; name: string; unlimited: boolean; stock: number; }
interface BundlePreview {
  found: boolean; bundle_name: string; customer_price: number;
  paid_credit_total: number; bonus_total: number; free_voucher_total: number;
  allowed_vouchers: AllowedVoucher[];
}
// vouchers[voucher_id] = quantity string
interface Row { customer_id: string; payment: string; vouchers: Record<string, string>; }

interface Props {
  storeId: string;
  bundleId: string;
  serviceStaff: string[];
  affiliateId: string | null;
  notes: string | null;
  onCreated: (result: any) => void;
  onCancel: () => void;
}

const money = (n: number) => 'S$' + n.toLocaleString('en-SG', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

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
  const short = centsTotal - assigned;
  frac.sort((a, b) => b.f - a.f || a.i - b.i);
  for (let k = 0; k < short; k++) base[frac[k].i] += 1;
  return base.map(c => round2(c / 100));
}

const emptyVouchers = (): Record<string, string> => ({});

export function PremiumBundleSplitPanel(props: Props) {
  const { storeId, bundleId, serviceStaff, affiliateId, notes, onCreated, onCancel } = props;
  const [pv, setPv] = useState<BundlePreview | null>(null);
  const [rows, setRows] = useState<Row[]>([
    { customer_id: '', payment: '', vouchers: emptyVouchers() },
    { customer_id: '', payment: '', vouchers: emptyVouchers() },
  ]);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    (async () => {
      const { data, error } = await supabase.rpc('premium_bundle_benefit_preview', { p_bundle_id: bundleId, p_store_id: storeId });
      if (!live) return;
      if (error) { setErr(error.message); return; }
      setPv(data as BundlePreview);
    })();
    return () => { live = false; };
  }, [bundleId, storeId]);

  const payments = rows.map(r => Number(r.payment) || 0);
  const price = pv?.customer_price ?? 0;
  const paidTotal = pv?.paid_credit_total ?? 0;
  const bonusTotal = pv?.bonus_total ?? 0;
  const freeTotal = pv?.free_voucher_total ?? 0;
  const allowed = pv?.allowed_vouchers ?? [];

  const paidParts = useMemo(() => splitAmount(paidTotal, payments), [paidTotal, JSON.stringify(payments)]);
  const bonusParts = useMemo(() => splitAmount(bonusTotal, payments), [bonusTotal, JSON.stringify(payments)]);

  const rowVoucherTotal = (r: Row) => allowed.reduce((a, v) => a + (Number(r.vouchers[v.voucher_id]) || 0), 0);
  const voucherGrandTotal = rows.reduce((a, r) => a + rowVoucherTotal(r), 0);
  const perTypeTotal = (vid: string) => rows.reduce((a, r) => a + (Number(r.vouchers[vid]) || 0), 0);

  const paySum = round2(payments.reduce((a, b) => a + b, 0));
  const payRemaining = round2(price - paySum);
  const payOk = Math.abs(payRemaining) < 0.005 && payments.every(p => p > 0);
  const vouOk = voucherGrandTotal === freeTotal;
  const dupCustomer = (() => { const ids = rows.map(r => r.customer_id).filter(Boolean); return new Set(ids).size !== ids.length; })();
  const allCustomers = rows.every(r => r.customer_id);
  // any limited voucher type over its store stock across the whole split
  const stockProblem = allowed.find(v => !v.unlimited && perTypeTotal(v.voucher_id) > v.stock);

  const canCreate = pv?.found && rows.length >= 2 && allCustomers && !dupCustomer && payOk && vouOk && !stockProblem && !saving;

  const setEqual = () => {
    const parts = splitAmount(price, new Array(rows.length).fill(1));
    setRows(rs => rs.map((r, i) => ({ ...r, payment: String(parts[i]) })));
  };
  const addRow = () => setRows(rs => [...rs, { customer_id: '', payment: '', vouchers: emptyVouchers() }]);
  const removeRow = (i: number) => setRows(rs => rs.length > 2 ? rs.filter((_, k) => k !== i) : rs);

  const create = async () => {
    setErr(null);
    if (dupCustomer) { setErr('The same customer cannot appear twice.'); return; }
    if (!payOk) { setErr(payRemaining > 0 ? `Allocate the remaining ${money(payRemaining)} before creating the invoices.` : `The allocation exceeds the bundle price by ${money(-payRemaining)}.`); return; }
    if (!vouOk) { setErr(`Reward vouchers allocated: ${voucherGrandTotal} / ${freeTotal}. Adjust before creating.`); return; }
    if (stockProblem) { setErr(`Not enough store stock of "${stockProblem.name}".`); return; }
    setSaving(true);
    const allocations = rows.map(r => ({
      customer_id: r.customer_id,
      payment_amount: Number(r.payment) || 0,
      voucher_selection: allowed
        .map(v => ({ voucher_id: v.voucher_id, quantity: Number(r.vouchers[v.voucher_id]) || 0 }))
        .filter(s => s.quantity > 0),
    }));
    const { data, error } = await supabase.rpc('create_split_premium_bundle_invoices', {
      p_store_id: storeId,
      p_premium_bundle_id: bundleId,
      p_allocations: allocations,
      p_service_staff: serviceStaff?.length ? serviceStaff : null,
      p_affiliate_id: affiliateId,
      p_notes: notes,
    });
    setSaving(false);
    if (error) { setErr(error.message); return; }
    onCreated(data);
  };

  if (!pv) return <div style={{ padding: 12, color: 'var(--text-muted)' }}>Loading bundle…</div>;
  if (!pv.found) return <div style={{ padding: 12, color: 'var(--danger)' }}>Bundle unavailable.</div>;

  const th: React.CSSProperties = { textAlign: 'right', padding: '4px 8px', fontSize: 12, color: 'var(--text-muted)' };
  const td: React.CSSProperties = { textAlign: 'right', padding: '4px 8px', fontVariantNumeric: 'tabular-nums' };

  return (
    <div style={{ border: '1px solid var(--border)', borderRadius: 8, padding: 12, marginTop: 8 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
        <strong>Customer Allocation — {pv.bundle_name}</strong>
        <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
          Bundle {money(price)} · Paid {money(paidTotal)} · Bonus {money(bonusTotal)} · {freeTotal} free vouchers
        </span>
      </div>

      <div style={{ display: 'flex', gap: 8, marginBottom: 8 }}>
        <button type="button" className="btn btn-secondary btn-sm" onClick={setEqual}>Split Equally</button>
        <button type="button" className="btn btn-secondary btn-sm" onClick={addRow}>+ Add Customer</button>
      </div>

      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={{ ...th, textAlign: 'left' }}>Customer</th>
              <th style={th}>Payment</th>
              <th style={th}>%</th>
              <th style={th}>Paid Credit</th>
              <th style={th}>Bonus</th>
              {allowed.map(v => <th key={v.voucher_id} style={th}>{v.name}{!v.unlimited ? ` (stock ${v.stock})` : ''}</th>)}
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => {
              const pct = price > 0 ? round2((payments[i] / price) * 100) : 0;
              return (
                <tr key={i}>
                  <td style={{ padding: '4px 8px', minWidth: 200 }}>
                    <CustomerSearchSelect value={r.customer_id} onChange={v => setRows(rs => rs.map((x, k) => k === i ? { ...x, customer_id: v } : x))} />
                  </td>
                  <td style={td}>
                    <input type="number" min={0} step="0.01" value={r.payment} style={{ width: 96, textAlign: 'right' }}
                      onChange={e => setRows(rs => rs.map((x, k) => k === i ? { ...x, payment: e.target.value } : x))} />
                  </td>
                  <td style={td}>{pct.toFixed(2)}%</td>
                  <td style={td}>{money(paidParts[i] ?? 0)}</td>
                  <td style={td}>{money(bonusParts[i] ?? 0)}</td>
                  {allowed.map(v => (
                    <td key={v.voucher_id} style={td}>
                      <input type="number" min={0} step={1} value={r.vouchers[v.voucher_id] ?? ''}
                        style={{ width: 56, textAlign: 'right' }}
                        onChange={e => setRows(rs => rs.map((x, k) => k === i ? { ...x, vouchers: { ...x.vouchers, [v.voucher_id]: e.target.value } } : x))} />
                    </td>
                  ))}
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
              {allowed.map(v => {
                const t = perTypeTotal(v.voucher_id);
                const over = !v.unlimited && t > v.stock;
                return <td key={v.voucher_id} style={{ ...td, color: over ? 'var(--danger)' : 'inherit' }}>{t}</td>;
              })}
              <td />
            </tr>
          </tfoot>
        </table>
      </div>

      <div style={{ marginTop: 8, fontSize: 12.5 }}>
        {!payOk && (payRemaining > 0
          ? <span style={{ color: 'var(--danger)' }}>Allocated: {money(paySum)} / {money(price)} — allocate the remaining {money(payRemaining)}.</span>
          : <span style={{ color: 'var(--danger)' }}>Allocated: {money(paySum)} / {money(price)} — exceeds the bundle price by {money(-payRemaining)}.</span>)}
        {payOk && !vouOk && <span style={{ color: 'var(--danger)' }}>Reward vouchers allocated: {voucherGrandTotal} / {freeTotal}.</span>}
        {stockProblem && <span style={{ color: 'var(--danger)' }}> Not enough store stock of “{stockProblem.name}”.</span>}
        {dupCustomer && <span style={{ color: 'var(--danger)' }}> The same customer is selected more than once.</span>}
        {payOk && vouOk && !stockProblem && allCustomers && !dupCustomer && <span style={{ color: 'var(--text-muted)' }}>Paid Credit and Bonus are derived from payment and issued only when each customer’s own invoice is paid.</span>}
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
