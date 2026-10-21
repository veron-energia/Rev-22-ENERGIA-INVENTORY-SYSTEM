import React from 'react';
import { AlertTriangle, ArrowRight, Check } from 'lucide-react';
import { outcomeLines, type CorrectionOutcome } from '../../lib/invoices/correctionReview';
import './invoice-controls.css';

type Effect = { area: string; change: string; from?: string | null; to?: string | null;
                detail: string; items?: Array<{ kind: string; what: string; why?: string }> };
type Review = { area: string; detail: string; action?: string;
                items?: Array<{ kind: string; what: string; why?: string }> };
type Preview = {
  invoice_no: string; status: string; effects: Effect[];
  needs_review: Review[]; blocking: boolean;
  affiliate?: { explanation?: string };
  /** 416 (rule 11): what the corrected lines make of the invoice, when they were sent. */
  outcome?: CorrectionOutcome | null;
};

const AREA: Record<string, string> = {
  affiliate: 'Affiliate commission', affiliate_payout: 'Affiliate payout',
  customer: 'Customer', benefits: 'Customer benefits', store: 'Store',
  voucher_ownership: 'Voucher ownership', payments: 'Payments',
  vouchers: 'Vouchers given free',
  // 416: the corrected total and status, and a save the lines would be refused for.
  total: 'Total and status', correction: 'The corrected lines',
};

/**
 * What a correction will do, before it does it.
 *
 * The effect worth reading carefully is "unchanged": a field the operator
 * believes they changed which is not in the payload saves successfully and
 * alters nothing. Stating it here is the only place that distinction is
 * visible, so it is shown rather than filtered out as uninteresting.
 *
 * B16: with the corrected lines sent (416, rule 11), the total, the status,
 * what is owing and any refund due come first, with what was checked and what
 * was not. `notice` says why a summary was asked for again.
 */
export const CorrectionPreview: React.FC<{
  preview: Preview;
  saving: boolean;
  onConfirm: () => void;
  onBack: () => void;
  notice?: string | null;
}> = ({ preview, saving, onConfirm, onBack, notice }) => {
  // The summary opens under the form, which is locked: bring it into view, so
  // on a phone it is not left below where the person was looking.
  const ref = React.useRef<HTMLDivElement | null>(null);
  React.useEffect(() => { ref.current?.scrollIntoView?.({ block: 'start' }); }, [preview]);
  const outcome = outcomeLines(preview.outcome);
  // The outcome block says what the 'total' entry says, so it is not said twice.
  const effects = outcome ? preview.effects.filter(e => e.area !== 'total') : preview.effects;
  return (
  <div className="correction-preview" data-testid="correction-preview" ref={ref}>
    <h4>Before saving — {preview.invoice_no}</h4>

    {notice && <p className="correction-notice" role="alert">{notice}</p>}

    {outcome && (
      <div className="correction-outcome" data-testid="correction-outcome">
        <div><strong>{outcome.total}</strong></div>
        <div>{outcome.status}{outcome.money.length ? ` · ${outcome.money.join(' · ')}` : ''}</div>
        {outcome.lines.length > 0 && (
          <ul className="correction-items">
            {outcome.lines.map((l, i) => <li key={i}>{l}</li>)}
          </ul>
        )}
        <p className="correction-hint" data-testid="correction-checked-note">{outcome.note}</p>
      </div>
    )}

    {effects.length === 0 && !outcome && (
      <p className="correction-none">Nothing in this save changes the invoice.</p>
    )}

    <ul className="correction-effects">
      {effects.map((e, i) => (
        <li key={i} className={e.change === 'unchanged' ? 'is-unchanged' : ''}>
          <span className="correction-area">{AREA[e.area] ?? e.area}</span>
          {e.change === 'unchanged'
            ? <span className="correction-tag">unchanged</span>
            : (e.from || e.to)
              ? <span className="correction-move">
                  {e.from ?? 'None'} <ArrowRight size={12} aria-hidden="true" /> {e.to ?? 'None'}
                </span>
              : <span className="correction-tag">{e.change}</span>}
          <span className="correction-detail">{e.detail}</span>
          {e.items && e.items.length > 0 && (
            <ul className="correction-items">
              {e.items.map((x, j) => <li key={j}>{x.what}{x.why ? ` — ${x.why}` : ''}</li>)}
            </ul>
          )}
        </li>
      ))}
    </ul>

    {preview.needs_review.length > 0 && (
      <div className="correction-review" role="alert">
        <AlertTriangle size={15} aria-hidden="true" />
        <div>
          <strong>Needs attention first</strong>
          {preview.needs_review.map((r, i) => (
            <div key={i} className="correction-review-item">
              <span className="correction-area">{AREA[r.area] ?? r.area}</span>
              <span className="correction-detail">{r.detail}</span>
              {r.items && r.items.length > 0 && (
                <ul className="correction-items">
                  {r.items.map((x, j) => <li key={j}>{x.what}{x.why ? ` — ${x.why}` : ''}</li>)}
                </ul>
              )}
            </div>
          ))}
        </div>
      </div>
    )}

    <div className="correction-actions">
      <button type="button" className="btn btn-secondary" onClick={onBack} disabled={saving}>
        Back to the form
      </button>
      <button type="button" className="btn btn-primary" onClick={onConfirm} disabled={saving}>
        <Check size={14} aria-hidden="true" /> {saving ? 'Saving…' : 'Save the correction'}
      </button>
    </div>
    {preview.blocking && (
      <p className="correction-hint">
        Saving will be refused until the items above are resolved. Nothing has been changed yet.
      </p>
    )}
  </div>
  );
};
