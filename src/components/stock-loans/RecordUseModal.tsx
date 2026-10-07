import React, { useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import { SearchSelect } from '../SearchSelect';
import { Product } from '../../types';
import {
  LineDraft, LocationType, blankLine, checkRecordUse, mayHaveSaved, newRequestId, saveFailure, usesSummary,
} from '../../lib/stock-loans/stockLoans';

/**
 * Record use at a store or a warehouse (401): every line in one call
 * (record_stock_uses), so a refused line records nothing, and one request id
 * per form, so pressing again after a lost answer records nothing twice.
 * After a failure that may have saved, the form is locked: pressing again
 * sends the same details (the server refuses the same request with changed
 * ones), and anything else is a new Record use.
 */
const RecordUseModal: React.FC<{
  locationType: LocationType;
  locationId: string;
  locationName: string;
  products: Product[];
  onClose: () => void;
  onDone: (message: string) => void;
}> = ({ locationType, locationId, locationName, products, onClose, onDone }) => {
  const [requestId] = useState(newRequestId);
  const [lines, setLines] = useState<LineDraft[]>([blankLine()]);
  const [reason, setReason] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [locked, setLocked] = useState(false);
  const nameOf = (id: string) => products.find(p => p.id === id)?.name ?? 'a product';

  const submit = async () => {
    const checked = checkRecordUse(lines, reason, note);
    if (!checked.ok) { setErr(checked.error); return; }
    setBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('record_stock_uses', {
      p_location_type: locationType, p_location_id: locationId, ...checked.value, p_request_id: requestId,
    });
    setBusy(false);
    if (error) {
      // Refused (nothing saved): the form opens again to be corrected. No
      // answer (it may have saved): it stays as sent, so a retry is the same form.
      setLocked(mayHaveSaved(error));
      setErr(saveFailure(error, 'The form is locked as it was sent: press Record Use again to finish, and it will not be recorded twice.'));
      return;
    }
    const saved = usesSummary(data?.uses ?? [], nameOf);
    onDone(data?.replayed ? `Already recorded: ${saved}.` : `Recorded ${saved}.`);
  };

  return (
    <Modal title={`Record stock used — ${locationName}`} maxWidth={520} confirmClose onClose={onClose}
      footer={<><button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={submit} disabled={busy}>{busy ? 'Recording…' : locked ? 'Record Use again' : 'Record Use'}</button></>}>
      <div className="form-grid">
        <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
          For stock genuinely consumed here — demo units, testers, samples, internal use.
          The stock reduces immediately and is logged against you. Every line is recorded together, or none is.
          Use an Adjustment instead if you are correcting a miscount, and Lend for stock that will come back.
        </div>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label>Products *</label>
          {lines.map((l, i) => (
            <div key={i} style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 6 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <SearchSelect
                  options={products.map(p => ({ value: p.id, label: `${p.name} (${p.sku})`, search: `${p.name} ${p.sku}` }))}
                  value={l.product_id} disabled={locked}
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
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label>Reason *</label>
          <input value={reason} disabled={locked} onChange={e => setReason(e.target.value)} placeholder="e.g. Demo unit opened for a customer" />
        </div>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label>Note</label>
          <textarea rows={2} value={note} disabled={locked} onChange={e => setNote(e.target.value)} placeholder="Optional" />
        </div>
        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
      </div>
    </Modal>
  );
};

export default RecordUseModal;
