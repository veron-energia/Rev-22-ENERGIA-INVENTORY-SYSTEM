import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { CustomerSearchSelect, SearchSelect } from '../SearchSelect';
import { Product } from '../../types';
import {
  BorrowerMode, LineDraft, LocationType, blankLine, checkLend, formatDay, loanItemsSummary, mayHaveSaved,
  newRequestId, saveFailure, sgToday,
} from '../../lib/stock-loans/stockLoans';

/**
 * Lend stock out of a store or a warehouse (lend_stock, 401). The borrower is
 * a customer or affiliate from the system (the loan then shows on their
 * profile) or a typed name; the expected return date is required. The stock
 * leaves this location at once, so it cannot be sold, and comes back through
 * Take back on the On loan list. After a failure that may have saved, the
 * form is locked, so pressing again sends the same loan (the server refuses
 * the same request with changed details).
 */
const LendModal: React.FC<{
  locationType: LocationType;
  locationId: string;
  locationName: string;
  products: Product[];
  /** On-hand stock here, per product. */
  available: Record<string, number>;
  onClose: () => void;
  onDone: (message: string) => void;
}> = ({ locationType, locationId, locationName, products, available, onClose, onDone }) => {
  const today = sgToday();
  const [requestId] = useState(newRequestId);
  const [lines, setLines] = useState<LineDraft[]>([blankLine()]);
  const [borrowerMode, setBorrowerMode] = useState<BorrowerMode>('customer');
  const [customerId, setCustomerId] = useState('');
  const [borrowerName, setBorrowerName] = useState('');
  const [expectedReturn, setExpectedReturn] = useState('');
  const [purpose, setPurpose] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [locked, setLocked] = useState(false);

  const nameOf = (id: string) => products.find(p => p.id === id)?.name ?? 'this product';
  const options = products.map(p => {
    const have = available[p.id] ?? 0;
    return { value: p.id, label: `${p.name} (${p.sku})`, search: `${p.name} ${p.sku}`,
      sublabel: have > 0 ? `${have} in stock here` : 'None in stock here', disabled: have <= 0 };
  });

  const submit = async () => {
    // A locked form is a retry of what may already be lent: the stock it took
    // and the date it passed when first sent are not checked again here (the
    // server answers the same form with the loan it made, or checks afresh).
    const checked = checkLend({ lines, borrowerMode, customerId, borrowerName, expectedReturn, purpose },
      locked ? '' : today, locked ? undefined : available, nameOf);
    if (!checked.ok) { setErr(checked.error); return; }
    setBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('lend_stock', {
      p_location_type: locationType, p_location_id: locationId, ...checked.value, p_request_id: requestId,
    });
    setBusy(false);
    if (error) {
      // Refused (nothing saved): open to correct. No answer: kept as sent.
      setLocked(mayHaveSaved(error));
      setErr(saveFailure(error, 'The form is locked as it was sent: press Lend again to finish, and it will not be lent twice.'));
      return;
    }
    onDone(`${data?.replayed ? 'Already lent' : 'Lent'}: ${data?.loan_no} (${loanItemsSummary(data?.loan)}) to ${data?.loan?.borrower}, due back ${formatDay(data?.loan?.expected_return_date)}.`);
  };

  return (
    <Modal title={`Lend stock — ${locationName}`} maxWidth={560} confirmClose onClose={onClose}
      footer={<><button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={submit} disabled={busy}>{busy ? 'Lending…' : locked ? 'Lend again' : 'Lend'}</button></>}>
      <div className="form-grid">
        <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
          For stock that is coming back — a demo set for a roadshow, a unit a customer tries at home.
          It leaves this {locationType === 'store' ? 'store' : 'warehouse'}’s stock now, so it cannot be sold, and shows under On loan until it is taken back.
        </div>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label>Borrower *</label>
          <div style={{ display: 'flex', gap: 6, marginBottom: 6, flexWrap: 'wrap' }} role="radiogroup" aria-label="Borrower">
            {([['customer', 'Customer or affiliate'], ['name', 'Someone else (type a name)']] as const).map(([v, l]) => (
              <button key={v} type="button" role="radio" aria-checked={borrowerMode === v}
                className={`btn btn-sm ${borrowerMode === v ? 'btn-primary' : 'btn-secondary'}`} disabled={locked}
                onClick={() => setBorrowerMode(v)}>{l}</button>
            ))}
          </div>
          {borrowerMode === 'customer'
            ? <CustomerSearchSelect value={customerId} onChange={setCustomerId} disabled={locked} />
            : <input value={borrowerName} onChange={e => setBorrowerName(e.target.value)} maxLength={120} disabled={locked}
                placeholder="e.g. Roadshow at the mall, a walk-in visitor" />}
          {borrowerMode === 'customer' && <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4 }}>
            The loan also shows on this customer’s profile on the Customers page.</span>}
        </div>
        <div className="form-grid-2">
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Expected return date *</label>
            <input type="date" min={today} value={expectedReturn} disabled={locked} onChange={e => setExpectedReturn(e.target.value)} />
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label>Purpose / note</label>
            <input value={purpose} onChange={e => setPurpose(e.target.value)} maxLength={500} disabled={locked} placeholder="Optional, e.g. Home trial" />
          </div>
        </div>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label>Products *</label>
          {lines.map((l, i) => (
            <div key={i} style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 6 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <SearchSelect options={options} value={l.product_id} disabled={locked}
                  exclude={lines.filter((_, j) => j !== i).map(x => x.product_id).filter(Boolean)}
                  onChange={v => setLines(ls => ls.map((x, j) => j === i ? { ...x, product_id: v } : x))}
                  placeholder="Search product name or SKU…" />
              </div>
              <input type="number" min={1} step={1} value={l.quantity || ''} placeholder="Qty" style={{ width: 90 }} aria-label="Quantity"
                disabled={locked} onChange={e => setLines(ls => ls.map((x, j) => j === i ? { ...x, quantity: +e.target.value } : x))} />
              <button className="btn btn-secondary btn-sm btn-icon" disabled={locked || lines.length === 1}
                onClick={() => setLines(ls => ls.filter((_, j) => j !== i))} title="Remove" aria-label="Remove line">×</button>
            </div>
          ))}
          <button className="btn btn-secondary btn-sm" style={{ marginTop: 2 }} disabled={locked}
            onClick={() => setLines(ls => [...ls, blankLine()])}>+ Add another product</button>
        </div>
        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
      </div>
    </Modal>
  );
};

export default LendModal;
