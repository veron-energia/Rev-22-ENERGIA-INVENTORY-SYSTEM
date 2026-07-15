import React, { useEffect, useState, useCallback } from 'react';
import { supabase } from '../lib/supabase';
import { Store, Customer, TherapyPackageRule } from '../types';
import { Modal } from './ui';
import CustomerPicker from './CustomerPicker';
import { Wand2, Hand } from 'lucide-react';

const money = (n: number) => `S$${Number(n).toFixed(2)}`;
export const sgTodayStr = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Singapore' });

// How close (below the smallest package) still triggers an auto-prompt so
// staff can offer a top-up.
export const TOPUP_GAP = 50;

export interface QualifyPrefill {
  storeId?: string;
  customerId?: string;
  sgDate?: string;
  autoFind?: boolean;   // immediately run eligibility search on open
}

const TherapyQualifyModal: React.FC<{
  stores: Store[];
  customers: Customer[];
  rules: TherapyPackageRule[];
  prefill?: QualifyPrefill;
  onClose: () => void;
  onCreated: (result: any) => void;
}> = ({ stores, customers, rules, prefill, onClose, onCreated }) => {
  const [qStore, setQStore] = useState(prefill?.storeId ?? '');
  const [qCustomer, setQCustomer] = useState(prefill?.customerId ?? '');
  const [qDate, setQDate] = useState(prefill?.sgDate ?? sgTodayStr());
  const [eligible, setEligible] = useState<{ invoice_id: string; invoice_no: string; total_amount: number }[]>([]);
  const [picked, setPicked] = useState<string[]>([]);
  const [topup, setTopup] = useState(0);
  const [combo, setCombo] = useState<{ rule_id: string; qty: number }[]>([]);
  const [suggestion, setSuggestion] = useState<any>(null);
  const [flow, setFlow] = useState<'manual' | 'auto'>('auto');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [searched, setSearched] = useState(false);

  const cName = (id: string) => customers.find(c => c.id === id)?.full_name ?? '—';

  const findEligible = useCallback(async (storeId: string, customerId: string, date: string) => {
    setErr(null); setEligible([]); setPicked([]); setSearched(false);
    if (!storeId || !customerId) { setErr('Select store and customer.'); return; }
    const { data, error } = await supabase.rpc('therapy_eligible_invoices', { p_customer_id: customerId, p_store_id: storeId, p_sg_date: date });
    if (error) { setErr(error.message); return; }
    const rows = (data as any[]) ?? [];
    setEligible(rows);
    setPicked(rows.map(r => r.invoice_id)); // default: all same-day ticked
    setSearched(true);
  }, []);

  // Auto-find on open when prefill asks for it.
  useEffect(() => {
    if (prefill?.autoFind && prefill.storeId && prefill.customerId) {
      findEligible(prefill.storeId, prefill.customerId, prefill.sgDate ?? sgTodayStr());
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const pickedTotal = eligible.filter(e => picked.includes(e.invoice_id)).reduce((s, e) => s + Number(e.total_amount), 0) + (Number(topup) || 0);

  const computeSuggestion = useCallback(async () => {
    if (!qStore || pickedTotal <= 0) { setSuggestion(null); return; }
    const { data } = await supabase.rpc('therapy_combinations', { p_store_id: qStore, p_amount: pickedTotal });
    setSuggestion(data);
    if (flow === 'auto' && data) {
      const s = (data as any).suggestion ?? [];
      setCombo(s.map((x: any) => ({ rule_id: x.rule_id, qty: x.qty })));
    }
  }, [qStore, pickedTotal, flow]);

  useEffect(() => { computeSuggestion(); }, [computeSuggestion]);

  const affordable = suggestion?.affordable ?? [];
  const addCombo = (rule_id: string) => setCombo(prev => {
    const ex = prev.find(x => x.rule_id === rule_id);
    return ex ? prev.map(x => x.rule_id === rule_id ? { ...x, qty: x.qty + 1 } : x) : [...prev, { rule_id, qty: 1 }];
  });
  const decCombo = (rule_id: string) => setCombo(prev => prev.flatMap(x => x.rule_id === rule_id ? (x.qty > 1 ? [{ ...x, qty: x.qty - 1 }] : []) : [x]));

  const comboNeed = combo.reduce((s, c) => { const r = rules.find(x => x.id === c.rule_id); return s + (r ? Number(r.qualifying_amount) * c.qty : 0); }, 0);
  const forfeited = Math.max(0, +(pickedTotal - comboNeed).toFixed(2));
  const smallest = rules.length ? Math.min(...rules.map(r => Number(r.qualifying_amount))) : 0;
  const gapToSmallest = +(smallest - (pickedTotal - (Number(topup) || 0))).toFixed(2);

  const submit = async () => {
    setErr(null);
    if (picked.length === 0) { setErr('Select at least one eligible invoice.'); return; }
    if (combo.length === 0) { setErr('Choose at least one package (or add a top-up to reach one).'); return; }
    if (comboNeed > pickedTotal + 0.001) { setErr('Selected packages exceed the eligible amount.'); return; }
    setBusy(true);
    const { data, error } = await supabase.rpc('create_therapy_entitlements', {
      p_customer_id: qCustomer, p_store_id: qStore, p_invoice_ids: picked,
      p_combination: combo, p_topup_amount: Number(topup) || 0, p_topup_payments: [],
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    onCreated(data);
  };

  return (
    <Modal title="Qualify Customer for Therapy" maxWidth={620} onClose={onClose}
      footer={<><button className="btn btn-secondary" onClick={onClose}>Cancel</button><button className="btn btn-primary" onClick={submit} disabled={busy}>{busy ? 'Creating…' : 'Create Entitlements'}</button></>}>
      <div className="form-grid">
        {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        <div className="form-grid-2">
          <div className="form-group"><label>Store *</label><select value={qStore} onChange={e => setQStore(e.target.value)}><option value="">— Select —</option>{stores.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}</select></div>
          <div className="form-group"><label>Customer *</label><CustomerPicker customers={customers} value={qCustomer} onChange={setQCustomer} /></div>
        </div>
        <div className="form-grid-2">
          <div className="form-group"><label>Payment date (SG)</label><input type="date" value={qDate} onChange={e => setQDate(e.target.value)} /></div>
          <div className="form-group" style={{ display: 'flex', alignItems: 'flex-end' }}><button className="btn btn-secondary" type="button" onClick={() => findEligible(qStore, qCustomer, qDate)}>Find eligible invoices</button></div>
        </div>

        {searched && eligible.length === 0 && <div className="alert alert-info" style={{ marginBottom: 0 }}><span>ℹ️</span><div>No eligible same-day paid invoices for that customer/store/date.</div></div>}

        {eligible.length > 0 && (
          <>
            <div className="form-group">
              <label>Eligible same-day paid invoices</label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {eligible.map(e => {
                  const on = picked.includes(e.invoice_id);
                  return <label key={e.invoice_id} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13 }}>
                    <input type="checkbox" checked={on} style={{ width: 'auto' }} onChange={() => setPicked(p => on ? p.filter(x => x !== e.invoice_id) : [...p, e.invoice_id])} />
                    <span>{e.invoice_no} — {money(e.total_amount)}</span></label>;
                })}
              </div>
            </div>

            {gapToSmallest > 0 && gapToSmallest <= TOPUP_GAP && (Number(topup) || 0) === 0 && (
              <div className="alert alert-info" style={{ marginBottom: 0 }}><span>💡</span><div>This customer is only <strong>{money(gapToSmallest)}</strong> away from the {money(smallest)} package. Offer a top-up below to qualify.</div></div>
            )}

            <div className="form-grid-2">
              <div className="form-group"><label>Qualification top-up (optional)</label><input type="number" min={0} step="0.01" value={topup || ''} onChange={e => setTopup(+e.target.value)} placeholder={gapToSmallest > 0 && gapToSmallest <= TOPUP_GAP ? gapToSmallest.toFixed(2) : 'e.g. 4.00'} /></div>
              <div className="form-group" style={{ display: 'flex', alignItems: 'flex-end' }}><div style={{ fontSize: 14 }}>Eligible amount: <strong>{money(pickedTotal)}</strong></div></div>
            </div>

            <div style={{ display: 'flex', gap: 6 }}>
              <button type="button" className={`btn btn-sm ${flow === 'auto' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setFlow('auto')}><Wand2 size={13} /> Automatic</button>
              <button type="button" className={`btn btn-sm ${flow === 'manual' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setFlow('manual')}><Hand size={13} /> Manual</button>
            </div>

            {flow === 'auto' && suggestion && (
              <div style={{ background: 'var(--surface-2)', borderRadius: 'var(--radius-sm)', padding: 12, fontSize: 13 }}>
                <div style={{ fontWeight: 700, marginBottom: 4 }}>Suggested combination</div>
                {(suggestion.suggestion ?? []).length === 0 ? <div style={{ color: 'var(--text-muted)' }}>Not enough for any package. Add a top-up.</div>
                  : (suggestion.suggestion ?? []).map((s: any, i: number) => <div key={i}>{s.qty}× {s.name} ({money(s.qualifying_amount)})</div>)}
                <div style={{ borderTop: '1px solid var(--border)', marginTop: 6, paddingTop: 6, display: 'flex', justifyContent: 'space-between' }}><span>Forfeited</span><strong>{money(forfeited)}</strong></div>
              </div>
            )}

            {flow === 'manual' && (
              <div className="form-group">
                <label>Choose packages (must not exceed the eligible amount)</label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  {affordable.length === 0 && <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>No packages affordable with the current amount.</span>}
                  {affordable.map((a: any) => {
                    const sel = combo.find(x => x.rule_id === a.rule_id);
                    return <div key={a.rule_id} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, fontSize: 13 }}>
                      <span>{a.name} — {money(a.qualifying_amount)} <span style={{ color: 'var(--text-muted)' }}>({a.entitlement_kind === 'unlimited' ? `${a.duration_months}mo` : `${a.voucher_qty} vouchers`})</span></span>
                      <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                        <button type="button" className="btn btn-secondary btn-sm" onClick={() => decCombo(a.rule_id)}>−</button>
                        <strong style={{ minWidth: 16, textAlign: 'center' }}>{sel?.qty ?? 0}</strong>
                        <button type="button" className="btn btn-secondary btn-sm" onClick={() => addCombo(a.rule_id)}>+</button>
                      </span>
                    </div>;
                  })}
                </div>
                <div style={{ marginTop: 8, display: 'flex', justifyContent: 'space-between', fontSize: 13 }}>
                  <span>Uses {money(comboNeed)} of {money(pickedTotal)}</span>
                  <span>Forfeited <strong>{money(forfeited)}</strong></span>
                </div>
                {comboNeed > pickedTotal + 0.001 && <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>Selection exceeds the eligible amount.</div>}
              </div>
            )}
          </>
        )}
      </div>
    </Modal>
  );
};

export default TherapyQualifyModal;
