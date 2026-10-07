import React, { useState } from 'react';
import { ChevronDown, ChevronRight, RefreshCw, Undo2 } from 'lucide-react';
import { StockLoan, borrowerLabel, eventLabel, formatDay, outstanding } from '../../lib/stock-loans/stockLoans';

/** A loan's status as a badge: overdue (red, with days), due today, open, closed. */
export const LoanStatus: React.FC<{ loan: StockLoan; today: string }> = ({ loan, today }) => {
  if (loan.status === 'closed') return <span className="badge badge-muted">Closed {formatDay(loan.closed_at)}</span>;
  if (loan.overdue) return <span className="badge badge-danger">Overdue · {loan.days_overdue} day{loan.days_overdue === 1 ? '' : 's'}</span>;
  if (today && loan.expected_return_date === today) return <span className="badge badge-accent">Due today</span>;
  return <span className="badge badge-success">On loan</span>;
};

/** The items of a loan, one per line: "Mat ×2 (1 still out)". */
export const LoanItems: React.FC<{ loan: StockLoan }> = ({ loan }) => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
    {loan.lines.map(l => {
      const left = outstanding(l);
      return (
        <span key={l.line_id} style={{ fontSize: 12.5 }}>
          {l.product_name} ×{l.qty_out}
          {loan.status === 'open' && left !== l.qty_out && <span style={{ color: 'var(--text-muted)' }}> ({left} still out)</span>}
        </span>
      );
    })}
  </div>
);

/** What happened at each take-back, oldest first. */
export const LoanHistory: React.FC<{ loan: StockLoan }> = ({ loan }) => (
  <div style={{ fontSize: 12, color: 'var(--text-secondary)', display: 'flex', flexDirection: 'column', gap: 3 }}>
    <span>Lent {formatDay(loan.lent_at)} by {loan.lent_by_name ?? '—'} from {loan.location_name}{loan.purpose ? ` · ${loan.purpose}` : ''}</span>
    {loan.events.map(e => (
      <span key={e.id}>
        {formatDay(e.recorded_at)} · {e.product_name} ×{e.quantity}: {eventLabel(e)}
        {e.location_name ? ` → ${e.location_name}` : ''}{e.recorded_by_name ? ` · ${e.recorded_by_name}` : ''}{e.note ? ` · ${e.note}` : ''}
      </span>
    ))}
    {loan.events.length === 0 && <span>Nothing taken back yet.</span>}
  </div>
);

/**
 * The "On loan" list of a store or a warehouse (401): its open loans, oldest
 * due first, overdue ones highlighted, each with Take back; its closed ones
 * when asked.
 */
const OnLoanPanel: React.FC<{
  open: StockLoan[];
  closed: StockLoan[];
  today: string;
  loading: boolean;
  error: string | null;
  showClosed: boolean;
  onShowClosed: (v: boolean) => void;
  onReload: () => void;
  /** Whether this person may take back loans of this location. */
  canAct: boolean;
  onTakeBack: (loan: StockLoan) => void;
}> = ({ open, closed, today, loading, error, showClosed, onShowClosed, onReload, canAct, onTakeBack }) => {
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const rows = showClosed ? [...open, ...closed] : open;
  return (
    <div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 10, flexWrap: 'wrap' }}>
        <label style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 12.5, margin: 0 }}>
          <input type="checkbox" checked={showClosed} onChange={e => onShowClosed(e.target.checked)} style={{ width: 'auto' }} />
          Show closed loans (last 50)
        </label>
        <button className="btn btn-secondary btn-sm" onClick={onReload} disabled={loading}>
          <RefreshCw size={13} className={loading ? 'spin' : ''} /> Refresh
        </button>
      </div>
      {error && <div className="alert alert-danger" role="alert"><span>⚠</span><div>Couldn’t read the loans: {error}</div></div>}
      <div className="card">
        <div className="table-wrap">
          {rows.length === 0
            ? <div className="empty-state"><p style={{ fontWeight: 600 }}>{loading ? 'Loading…' : 'Nothing is out on loan.'}</p></div>
            : (
              <table>
                <thead><tr><th></th><th>Loan</th><th>Borrower</th><th>Items</th><th>Lent</th><th>Due back</th><th>Status</th>{canAct && <th></th>}</tr></thead>
                <tbody>
                  {rows.map(loan => (
                    <React.Fragment key={loan.id}>
                      <tr style={loan.overdue ? { background: 'var(--danger-light)', boxShadow: 'inset 3px 0 0 var(--danger)' } : undefined}>
                        <td>
                          <button className="btn btn-secondary btn-sm btn-icon" aria-expanded={!!expanded[loan.id]}
                            aria-label={`History of ${loan.loan_no}`}
                            onClick={() => setExpanded(s => ({ ...s, [loan.id]: !s[loan.id] }))}>
                            {expanded[loan.id] ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
                          </button>
                        </td>
                        <td style={{ fontFamily: 'var(--font-display)', fontSize: 12.5, whiteSpace: 'nowrap' }}>{loan.loan_no}</td>
                        <td>
                          <strong>{loan.borrower}</strong>
                          <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>
                            {loan.is_affiliate ? 'Affiliate' : loan.customer_id ? 'Customer' : 'Typed name'}
                            {loan.borrower_phone ? ` · ${loan.borrower_phone}` : ''}
                          </div>
                        </td>
                        <td><LoanItems loan={loan} /></td>
                        <td style={{ whiteSpace: 'nowrap' }}>{formatDay(loan.lent_at)}</td>
                        <td style={{ whiteSpace: 'nowrap', fontWeight: loan.overdue ? 700 : undefined }}>{formatDay(loan.expected_return_date)}</td>
                        <td><LoanStatus loan={loan} today={today} /></td>
                        {canAct && <td>{loan.status === 'open' &&
                          <button className="btn btn-primary btn-sm" onClick={() => onTakeBack(loan)}><Undo2 size={13} /> Take back</button>}</td>}
                      </tr>
                      {expanded[loan.id] && (
                        <tr><td></td><td colSpan={canAct ? 7 : 6}><LoanHistory loan={loan} /></td></tr>
                      )}
                    </React.Fragment>
                  ))}
                </tbody>
              </table>
            )}
        </div>
      </div>
    </div>
  );
};

export default OnLoanPanel;
