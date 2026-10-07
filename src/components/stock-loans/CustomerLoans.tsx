import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { StockLoan, formatDay, sgToday } from '../../lib/stock-loans/stockLoans';
import { LoanHistory, LoanItems, LoanStatus } from './OnLoanPanel';

/**
 * A customer's (or affiliate's) loans on their profile (customer_stock_loans,
 * 401): those lent from the stores the viewer works in (Owners and Managers:
 * all), open first. Read only; a loan is taken back from the stock page it
 * was lent from.
 */
const CustomerLoans: React.FC<{ customerId: string }> = ({ customerId }) => {
  const [loans, setLoans] = useState<StockLoan[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const today = sgToday();

  useEffect(() => {
    let live = true;
    setLoans(null); setError(null);
    supabase.rpc('customer_stock_loans', { p_customer_id: customerId }).then(({ data, error: e }) => {
      if (!live) return;
      if (e) { setError(e.message); setLoans([]); return; }
      setLoans((data as StockLoan[]) ?? []);
    });
    return () => { live = false; };
  }, [customerId]);

  if (loans === null) return null;
  if (error) return <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Stock on loan could not be read: {error}</div>;
  if (loans.length === 0) return null;
  const open = loans.filter(l => l.status === 'open');
  return (
    <div>
      <label>Stock on loan{open.length > 0 ? ` (${open.length} open)` : ''}</label>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 6 }}>
        {loans.map(loan => (
          <div key={loan.id} style={{
            border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '8px 10px',
            ...(loan.overdue ? { background: 'var(--danger-light)', boxShadow: 'inset 3px 0 0 var(--danger)' } : {}),
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
              <span style={{ fontWeight: 600, fontSize: 13 }}>{loan.loan_no} · {loan.location_name}</span>
              <LoanStatus loan={loan} today={today} />
            </div>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)', margin: '2px 0 4px' }}>
              Lent {formatDay(loan.lent_at)} · due back {formatDay(loan.expected_return_date)}
            </div>
            <LoanItems loan={loan} />
            {loan.events.length > 0 && <div style={{ marginTop: 4 }}><LoanHistory loan={loan} /></div>}
          </div>
        ))}
      </div>
    </div>
  );
};

export default CustomerLoans;
