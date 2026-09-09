import React, { useState } from 'react';
import { AlertTriangle, ChevronDown, ChevronRight } from 'lucide-react';
import './therapy.css';

/**
 * How an unlimited-therapy expiry was arrived at.
 *
 * Shown as the arithmetic it is — base, plus replacement days, equals adjusted —
 * because a customer asking "why does mine end on the 6th" deserves the four
 * dates that answer it rather than a single number.
 *
 * The remaining figure is labelled "calendar days" everywhere. It is a period of
 * access, not a number of visits, and calling it anything else would invite the
 * reading that a customer is owed that many appointments.
 */

export interface CoverageInfo {
  verified: boolean;
  country: string | null;
  region?: string | null;
  requires_region?: boolean;
  missing_years?: number[];
  reasons?: string[];
}

export interface ExpiryExplanationData {
  activation_date: string | null;
  months: number | null;
  convention?: string;
  country: string | null;
  region?: string | null;
  base_expiry: string | null;
  adjusted_expiry: string | null;
  added_days: number;
  expiry_is_inclusive?: boolean;
  applied: { date: string; weekday?: string; names: string[]; kinds: string[];
             observed_for?: string | null; scope?: string }[];
  skipped_sundays: { date: string; names: string[]; why: string }[];
}

const fmt = (d: string | null | undefined) =>
  !d ? '—' : new Date(`${d}T12:00:00Z`).toLocaleDateString('en-GB',
    { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' });

export const CoverageNotice: React.FC<{ coverage?: CoverageInfo | null }> = ({ coverage }) => {
  if (!coverage || coverage.verified) return null;
  return (
    <div className="alert alert-warning" role="status" style={{ marginTop: 8, fontSize: 12 }}>
      <AlertTriangle size={14} aria-hidden="true" />
      <div>
        <strong>This expiry is not fully verified.</strong>{' '}
        {(coverage.reasons ?? ['The holiday calendar for this period is incomplete.']).join(' ')}{' '}
        It is shown so it can be corrected, not because it has been confirmed.
      </div>
    </div>
  );
};

export const ExpiryExplanation: React.FC<{
  data: ExpiryExplanationData | null;
  coverage?: CoverageInfo | null;
  daysRemaining?: number | null;
  defaultOpen?: boolean;
}> = ({ data, coverage, daysRemaining, defaultOpen = false }) => {
  const [open, setOpen] = useState(defaultOpen);
  if (!data) return <span className="therapy-remaining-hint">Not yet activated.</span>;

  const added = data.added_days ?? 0;
  const detailId = `expiry-detail-${data.activation_date ?? 'x'}-${data.base_expiry ?? 'y'}`;

  return (
    <div>
      <div className="therapy-expiry-math">
        <span>{fmt(data.base_expiry)}</span>
        <span className="op">+</span>
        <span>{added} closure day{added === 1 ? '' : 's'}</span>
        <span className="op">=</span>
        <span className="result">{fmt(data.adjusted_expiry)}</span>
        {data.country && <span className="therapy-chip">{data.country}{data.region ? ` · ${data.region}` : ''}</span>}
        {!data.country && <span className="therapy-chip therapy-chip-warn">No holiday country</span>}
      </div>

      <div className="therapy-remaining-hint" style={{ marginTop: 4 }}>
        Last usable day is {fmt(data.adjusted_expiry)}, inclusive
        {typeof daysRemaining === 'number' && <> · {daysRemaining} calendar day{daysRemaining === 1 ? '' : 's'} remaining</>}
      </div>

      <CoverageNotice coverage={coverage} />

      {(data.applied.length > 0 || data.skipped_sundays.length > 0) && (
        <>
          <button type="button" className="therapy-row-button" style={{ marginTop: 8, fontSize: 12 }}
                  aria-expanded={open} aria-controls={detailId} onClick={() => setOpen(o => !o)}>
            {open ? <ChevronDown size={14} aria-hidden="true" /> : <ChevronRight size={14} aria-hidden="true" />}
            {open ? 'Hide' : 'Show'} the dates behind this
          </button>
          {open && (
            <div id={detailId} style={{ marginTop: 6 }}>
              {data.applied.length > 0 && (
                <ul style={{ margin: '4px 0 0 18px', fontSize: 12, lineHeight: 1.65 }}>
                  {data.applied.map(a => (
                    <li key={a.date}>
                      <strong>{fmt(a.date)}</strong>{a.weekday ? ` (${a.weekday})` : ''} — {a.names.join(', ')}
                      {a.observed_for && <> · observed for {fmt(a.observed_for)}</>}
                      {a.scope && <> · {a.scope}</>}
                      {' '}<span className="therapy-chip">+1 day</span>
                    </li>
                  ))}
                </ul>
              )}
              {data.skipped_sundays.length > 0 && (
                <ul style={{ margin: '6px 0 0 18px', fontSize: 12, lineHeight: 1.65, color: 'var(--text-muted)' }}>
                  {data.skipped_sundays.map(s => (
                    <li key={s.date}>
                      {fmt(s.date)} — {s.names.join(', ')} · <em>{s.why}</em>, so no day is added
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
};
