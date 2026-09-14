import React from 'react';
import { AlertTriangle, ArrowRight, Check } from 'lucide-react';
import './invoice-controls.css';

type Effect = { area: string; change: string; from?: string | null; to?: string | null;
                detail: string; items?: Array<{ kind: string; what: string; why?: string }> };
type Review = { area: string; detail: string; action?: string;
                items?: Array<{ kind: string; what: string; why?: string }> };
type Preview = {
  invoice_no: string; status: string; effects: Effect[];
  needs_review: Review[]; blocking: boolean;
  affiliate?: { explanation?: string };
};

const AREA: Record<string, string> = {
  affiliate: 'Affiliate commission', affiliate_payout: 'Affiliate payout',
  customer: 'Customer', benefits: 'Customer benefits', store: 'Store',
  voucher_ownership: 'Voucher ownership',
};

/**
 * What a correction will do, before it does it.
 *
 * The effect worth reading carefully is "unchanged": a field the operator
 * believes they changed which is not in the payload saves successfully and
 * alters nothing. Stating it here is the only place that distinction is
 * visible, so it is shown rather than filtered out as uninteresting.
 */
export const CorrectionPreview: React.FC<{
  preview: Preview;
  saving: boolean;
  onConfirm: () => void;
  onBack: () => void;
}> = ({ preview, saving, onConfirm, onBack }) => (
  <div className="correction-preview">
    <h4>Before saving — {preview.invoice_no}</h4>

    {preview.effects.length === 0 && (
      <p className="correction-none">Nothing in this save changes the invoice.</p>
    )}

    <ul className="correction-effects">
      {preview.effects.map((e, i) => (
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
