import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';

type Benefit = {
  lot_id?: string;
  reward_voucher_id?: string;
  customer_name: string;
  kind: string;
  granted_value: number;
};
type OriginalSource = {
  sale_id: string;
  customer_name: string;
  paid_lot_id?: string;
  bonus_lot_id?: string;
  verified: boolean;
  candidates: { lot_id: string; granted_value: number; purchase_date?: string }[];
};
type ReviewLine = {
  invoice_item_id: string;
  name: string;
  external_paid: number;
  review_note: string;
  blocked_reason?: string;
  benefits: Benefit[];
  sources?: OriginalSource[];
};
type Draft = { amounts: Record<string, string>; evidence: string; confirmed: boolean };
type SourceDraft = { choice: string; evidence: string };
const emptyDraft = (): Draft => ({ amounts: {}, evidence: '', confirmed: false });
const money = (value: number) => `S$${Number(value).toFixed(2)}`;
const benefitKey = (benefit: Benefit) => benefit.lot_id ? `lot:${benefit.lot_id}` : `voucher:${benefit.reward_voucher_id}`;
const cents = (value: string) => {
  if (!/^(?:\d+(?:\.\d{1,2})?|\.\d{1,2})$/.test(value.trim())) return null;
  const result = Math.round(Number(value) * 100);
  return Number.isSafeInteger(result) && result >= 0 ? result : null;
};
const message = (error: unknown, fallback: string) => error && typeof error === 'object' && 'message' in error && typeof error.message === 'string'
  ? error.message : fallback;

/** Historical paid values must come from reviewed evidence, never current prices. */
export function InvoiceBenefitEvidenceReview({ invoiceId, onChanged }: {
  invoiceId: string;
  onChanged: () => Promise<void>;
}) {
  const [lines, setLines] = useState<ReviewLine[]>([]);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [sourceDrafts, setSourceDrafts] = useState<Record<string, SourceDraft>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const generation = useRef(0);

  useEffect(() => {
    const current = ++generation.current;
    setLines([]); setDrafts({}); setSourceDrafts({}); setLoading(true); setSaving(''); setError(''); setSuccess('');
    const load = async () => {
      try {
        const { data, error } = await supabase.rpc('invoice_benefit_review_options', { p_invoice_id: invoiceId });
        if (error) throw error;
        if (!data || !Array.isArray(data.lines)) throw new Error('The historical benefit review could not be loaded. Reopen this invoice to try again.');
        if (generation.current === current) setLines(data.lines);
      } catch (error) {
        if (generation.current === current) setError(message(error, 'The historical benefit review could not be loaded. Reopen this invoice to try again.'));
      } finally {
        if (generation.current === current) setLoading(false);
      }
    };
    void load();
    return () => { generation.current++; };
  }, [invoiceId]);

  const change = (lineId: string, patch: Partial<Draft>) => {
    setDrafts(previous => ({ ...previous, [lineId]: { ...(previous[lineId] || emptyDraft()), ...patch } }));
    setSuccess('');
  };
  const refresh = async (current: number) => {
    const [refreshed] = await Promise.all([
      supabase.rpc('invoice_benefit_review_options', { p_invoice_id: invoiceId }),
      onChanged(),
    ]);
    if (refreshed.error) throw refreshed.error;
    if (!refreshed.data || !Array.isArray(refreshed.data.lines)) throw new Error('The updated review list could not be loaded.');
    if (generation.current === current) setLines(refreshed.data.lines);
  };
  const verifySource = async (line: ReviewLine, source: OriginalSource) => {
    if (saving) return;
    const draft = sourceDrafts[source.sale_id] || { choice: '', evidence: '' };
    if (!draft.choice || draft.evidence.trim().length < 10) {
      setError('Choose the original bonus grant, or confirm that no bonus was issued, and describe the supporting evidence (at least 10 characters).');
      return;
    }
    if (draft.choice !== 'none' && !source.candidates.some(candidate => candidate.lot_id === draft.choice)) {
      setError('Choose one of the original grant records shown for this sale.');
      return;
    }
    const current = generation.current;
    setSaving(`source:${source.sale_id}`); setError(''); setSuccess('');
    let recorded = false;
    try {
      const { error } = await supabase.rpc('verify_invoice_credit_sale_sources', {
        p_sale_id: source.sale_id,
        p_bonus_lot_id: draft.choice === 'none' ? null : draft.choice,
        p_no_bonus: draft.choice === 'none',
        p_evidence: draft.evidence.trim(),
      });
      if (error) throw error;
      recorded = true;
      if (generation.current !== current) return;
      // Keep allocations blocked until the refreshed list contains every verified grant.
      setLines(previous => previous.map(item => item.invoice_item_id === line.invoice_item_id
        ? { ...item, sources: item.sources?.map(s => s.sale_id === source.sale_id ? { ...s, verified: true } : s), blocked_reason: 'Refreshing the verified original grant records…' }
        : item));
      setDrafts(previous => ({ ...previous, [line.invoice_item_id]: emptyDraft() }));
      setSuccess('The original bonus source review was saved to the audit history.');
      await refresh(current);
    } catch (error) {
      if (generation.current === current) setError(recorded
        ? 'The source review was saved, but the updated grant list could not be fully refreshed. Reopen the invoice before allocating paid values.'
        : message(error, 'The source review could not be saved. Your selection and evidence have been kept.'));
    } finally {
      if (generation.current === current) setSaving('');
    }
  };
  const validation = (line: ReviewLine, draft: Draft) => {
    const paid = Number(line.external_paid);
    const keys = line.benefits.map(benefitKey);
    if (line.blocked_reason) return line.blocked_reason;
    if (line.sources?.some(source => !source.verified)) return 'Verify every original bonus source before allocating paid values.';
    if (!line.benefits.length || new Set(keys).size !== keys.length || line.benefits.some(benefit =>
      Boolean(benefit.lot_id) === Boolean(benefit.reward_voucher_id) || !Number.isFinite(Number(benefit.granted_value)) || Number(benefit.granted_value) <= 0)
      || !Number.isFinite(paid) || paid < 0 || !Number.isSafeInteger(Math.round(paid * 100))) {
      return 'The original grant records are incomplete. Their source records need review before paid values can be recorded.';
    }
    const amounts = keys.map(key => cents(draft.amounts[key] || ''));
    if (amounts.some(amount => amount === null)) return 'Enter a paid value for every grant, including 0 where no payment was allocated. Use no more than two decimal places.';
    if (amounts.reduce<number>((sum, amount) => sum + (amount || 0), 0) !== Math.round(paid * 100)) return 'The allocation total must equal the original external payment.';
    if (draft.evidence.trim().length < 10) return 'Describe the original records supporting these values (at least 10 characters).';
    if (!draft.confirmed) return 'Confirm that the evidence includes every original paid, bonus and voucher grant.';
    return '';
  };
  const save = async (line: ReviewLine) => {
    if (saving) return;
    const draft = drafts[line.invoice_item_id] || emptyDraft();
    const invalid = validation(line, draft);
    if (invalid) { setError(invalid); return; }
    const current = generation.current;
    setSaving(line.invoice_item_id); setError(''); setSuccess('');
    let recorded = false;
    try {
      const { error } = await supabase.rpc('record_invoice_benefit_values', {
        p_item_id: line.invoice_item_id,
        p_allocations: line.benefits.map(benefit => ({
          ...(benefit.lot_id ? { lot_id: benefit.lot_id } : { reward_voucher_id: benefit.reward_voucher_id }),
          paid_value: cents(draft.amounts[benefitKey(benefit)])! / 100,
          granted_value: Number(benefit.granted_value),
        })),
        p_evidence: draft.evidence.trim(),
      });
      if (error) throw error;
      recorded = true;
      if (generation.current !== current) return;
      // Do not offer another save if the follow-up refresh fails after recording.
      setLines(previous => previous.filter(item => item.invoice_item_id !== line.invoice_item_id));
      setSuccess(`The reviewed values for ${line.name} were saved to the audit history.`);
      await refresh(current);
    } catch (error) {
      if (generation.current === current) setError(recorded
        ? 'The reviewed values were saved, but the updated invoice could not be fully refreshed. Reopen the invoice to see the latest information.'
        : message(error, 'The reviewed values could not be saved. Your entered values and evidence have been kept.'));
    } finally {
      if (generation.current === current) setSaving('');
    }
  };

  if (!loading && !lines.length && !error && !success) return null;
  return <section className="invoice-finance" aria-label="Review historical benefit values" style={{ maxWidth: '100%', overflowWrap: 'anywhere' }}>
    <strong>Review historical benefit values</strong>
    {loading && <p role="status">Loading original benefit records…</p>}
    {error && <p role="alert" className="alert alert-danger">{error}</p>}
    {success && <p role="status">{success}</p>}
    {!!lines.length && <p>Use the original sale and grant records to enter how much was paid for each benefit. Current prices cannot establish historical values. Leave unresolved records pending review.</p>}
    {lines.map(line => {
      const draft = drafts[line.invoice_item_id] || emptyDraft();
      const invalid = validation(line, draft);
      const enteredCents = line.benefits.reduce((sum, benefit) => sum + (cents(draft.amounts[benefitKey(benefit)] || '') || 0), 0);
      return <fieldset key={line.invoice_item_id} disabled={Boolean(saving)} className="form-grid" style={{ marginTop: 12, maxWidth: '100%' }}>
        <legend>{line.name}</legend>
        {line.review_note && <p>{line.review_note}</p>}
        {line.blocked_reason && <p role="alert">{line.blocked_reason}</p>}
        {line.sources?.filter(source => !source.verified).map(source => {
          const sourceDraft = sourceDrafts[source.sale_id] || { choice: '', evidence: '' };
          const selected = source.candidates.find(candidate => candidate.lot_id === sourceDraft.choice);
          const updateSource = (patch: Partial<SourceDraft>) => {
            setSourceDrafts(previous => ({ ...previous, [source.sale_id]: { ...sourceDraft, ...patch } }));
            setSuccess('');
          };
          return <fieldset key={source.sale_id} className="form-grid" style={{ maxWidth: '100%' }}>
            <legend>Verify original bonus: {source.customer_name || 'Original recipient'}</legend>
            <small>Original sale: {source.sale_id}<br />Original paid grant: {source.paid_lot_id || 'Pending source review'}</small>
            <p>Check the original purchase records to establish whether a bonus was issued and which grant belongs to this sale. A similar amount or date alone does not establish a match.</p>
            <label>Original bonus grant for {source.customer_name || 'Original recipient'}
              <select value={sourceDraft.choice} onChange={event => updateSource({ choice: event.target.value })}
                style={{ width: '100%', maxWidth: '100%', minWidth: 0, minHeight: 44 }}>
                <option value="">Choose after checking the original records…</option>
                <option value="none">No bonus was originally issued</option>
                {source.candidates.map(candidate => <option key={candidate.lot_id} value={candidate.lot_id}>
                  {candidate.lot_id} · {money(candidate.granted_value)} · {candidate.purchase_date || 'Date unavailable'}
                </option>)}
              </select>
            </label>
            {selected && <small>Selected original grant: {selected.lot_id}<br />Originally granted: {money(selected.granted_value)} · Purchase date: {selected.purchase_date || 'Unavailable'}</small>}
            <label>Source evidence for {source.customer_name || 'Original recipient'}
              <textarea value={sourceDraft.evidence} rows={3} minLength={10}
                placeholder="Identify the original records proving this bonus grant belongs to the sale, or proving no bonus was issued."
                onChange={event => updateSource({ evidence: event.target.value })} />
            </label>
            <div className="invoice-finance-actions">
              <button type="button" className="btn btn-secondary" disabled={Boolean(saving) || !sourceDraft.choice || sourceDraft.evidence.trim().length < 10}
                onClick={() => void verifySource(line, source)}>
                {saving === `source:${source.sale_id}` ? 'Saving source review…' : 'Save original source review'}
              </button>
            </div>
          </fieldset>;
        })}
        <p>Original external payment: <strong>{money(line.external_paid)}</strong></p>
        {line.benefits.map((benefit, index) => {
          const key = benefitKey(benefit);
          const label = `Paid value for grant ${index + 1}: ${benefit.customer_name || 'Original recipient'} · ${(benefit.kind || 'benefit').replace(/_/g, ' ')}`;
          return <div key={`${key}:${index}`} style={{ minWidth: 0 }}>
            <label className="invoice-finance-amount">{label}
              <input aria-label={label} type="number" inputMode="decimal" min="0" max={Number(line.external_paid)} step="0.01"
                disabled={Boolean(line.blocked_reason)} value={draft.amounts[key] ?? ''} placeholder="Enter paid value"
                onChange={event => change(line.invoice_item_id, { amounts: { ...draft.amounts, [key]: event.target.value }, confirmed: false })} />
            </label>
            <small>Originally granted: {benefit.reward_voucher_id ? `${benefit.granted_value} voucher(s)` : money(benefit.granted_value)} · Record: {benefit.lot_id || benefit.reward_voucher_id}</small>
          </div>;
        })}
        <p aria-live="polite">Allocated: <strong>{money(enteredCents / 100)}</strong> of {money(line.external_paid)}</p>
        <label>Evidence for {line.name}
          <textarea value={draft.evidence} rows={3} minLength={10} disabled={Boolean(line.blocked_reason)}
            placeholder="Describe the original payment, grant and voucher records supporting each value."
            onChange={event => change(line.invoice_item_id, { evidence: event.target.value, confirmed: false })} />
        </label>
        <label><input type="checkbox" checked={draft.confirmed} disabled={Boolean(line.blocked_reason)}
          onChange={event => change(line.invoice_item_id, { confirmed: event.target.checked })} /> I confirm that this evidence includes every original paid-credit, bonus-credit and voucher grant for this invoice line.</label>
        {invalid && !line.blocked_reason && <small>{invalid}</small>}
        <div className="invoice-finance-actions">
          <button type="button" className="btn btn-primary" disabled={Boolean(saving) || Boolean(invalid)} onClick={() => void save(line)}>
            {saving === line.invoice_item_id ? 'Saving reviewed values…' : 'Save reviewed benefit values'}
          </button>
        </div>
      </fieldset>;
    })}
  </section>;
}
