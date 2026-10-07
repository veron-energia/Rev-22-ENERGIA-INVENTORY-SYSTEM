import React, { useEffect, useMemo, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';
import {
  StockLoan, TAKE_BACK_FIELDS, TakeBackDraft, blankTakeBack, borrowerLabel, formatDay, mayHaveSaved, newRequestId,
  outstanding, returnPlaces, saveFailure, takeBackAll, takeBackEntries,
} from '../../lib/stock-loans/stockLoans';

/**
 * Take a loan back, in part or in full (return_stock_loan, 401). For each
 * item staff enter what came back (into the place chosen below: any store, or
 * a warehouse for Owner/Manager), what came back damaged (back to stock, or
 * recorded as used), and what did not come back (used / given away, lost /
 * damaged). The loan closes when every item is accounted for. After a
 * failure that may have saved, the form is locked, so pressing again sends the
 * same entries (the server refuses the same request with changed ones).
 */
const TakeBackModal: React.FC<{
  loan: StockLoan;
  /** The warehouse stock permission (Owner, Manager, Inventory Manager). */
  canWarehouse: boolean;
  onClose: () => void;
  onDone: (message: string) => void;
}> = ({ loan, canWarehouse, onClose, onDone }) => {
  const [requestId] = useState(newRequestId);
  const [drafts, setDrafts] = useState<Record<string, TakeBackDraft>>(() =>
    Object.fromEntries(loan.lines.map(l => [l.line_id, blankTakeBack()])));
  const [places, setPlaces] = useState<ReturnType<typeof returnPlaces>>([]);
  const [place, setPlace] = useState(
    loan.location_type === 'store' || canWarehouse ? `${loan.location_type}:${loan.location_id}` : '');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [locked, setLocked] = useState(false);

  useEffect(() => {
    Promise.all([
      supabase.from('stores').select('id,name').is('deleted_at', null).eq('is_active', true).order('name'),
      supabase.from('warehouses').select('id,name').is('deleted_at', null).eq('is_active', true).order('name'),
    ]).then(([{ data: st }, { data: wh }]) => setPlaces(returnPlaces(st ?? [], wh ?? [], canWarehouse)));
  }, [canWarehouse]);

  const chosen = places.find(p => p.value === place) ?? null;
  const open = loan.lines.filter(l => outstanding(l) > 0);
  const preview = useMemo(() => takeBackEntries(loan, drafts, chosen ? { type: chosen.type, id: chosen.id } : null),
    [loan, drafts, chosen]);
  const set = (lineId: string, key: keyof TakeBackDraft, v: number) => {
    setErr(null);
    setDrafts(d => ({ ...d, [lineId]: { ...(d[lineId] ?? blankTakeBack()), [key]: Number.isFinite(v) ? v : 0 } }));
  };

  const submit = async () => {
    if (!preview.ok) { setErr(preview.error); return; }
    setBusy(true); setErr(null);
    const { data, error } = await supabase.rpc('return_stock_loan', {
      p_loan_id: loan.id, p_entries: preview.value.entries, p_note: note.trim() || null, p_request_id: requestId,
    });
    setBusy(false);
    if (error) {
      // Refused (nothing saved): open to correct. No answer: kept as sent.
      setLocked(mayHaveSaved(error));
      setErr(saveFailure(error, 'The form is locked as it was sent: press Save again to finish, and it will not be recorded twice.'));
      return;
    }
    const left = Number(data?.loan?.outstanding ?? 0);
    onDone(`${data?.replayed ? 'Already recorded' : 'Recorded'} for ${loan.loan_no}. ${data?.closed ? 'Everything is accounted for: the loan is closed.' : `${left} still out.`}`);
  };

  return (
    <Modal title={`Take back — ${loan.loan_no}`} maxWidth={640} confirmClose onClose={onClose}
      footer={<><button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={submit} disabled={busy}>{busy ? 'Saving…' : locked ? 'Save again' : 'Save'}</button></>}>
      <div className="form-grid">
        <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
          <strong>{borrowerLabel(loan)}</strong> · lent from {loan.location_name} on {formatDay(loan.lent_at)} ·
          due back {formatDay(loan.expected_return_date)}
          {loan.overdue && <span className="badge badge-danger" style={{ marginLeft: 6 }}>Overdue {loan.days_overdue} day{loan.days_overdue === 1 ? '' : 's'}</span>}
          {loan.purpose && <div style={{ marginTop: 2 }}>{loan.purpose}</div>}
        </div>
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label>Returned items go back to</label>
          <select value={place} disabled={locked} onChange={e => { setErr(null); setPlace(e.target.value); }}>
            <option value="">Choose a store{canWarehouse ? ' or warehouse' : ''}…</option>
            {places.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}
          </select>
          <span style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4 }}>
            Items back in different places? Save one take-back per place.
            {!canWarehouse && ' Only an Owner or Manager can take stock back into a warehouse.'}
          </span>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <label style={{ margin: 0 }}>Items still out</label>
          <button type="button" className="btn btn-secondary btn-sm" disabled={locked} onClick={() => { setErr(null); setDrafts(takeBackAll(loan)); }}>Everything came back</button>
        </div>
        {open.map(l => (
          <div key={l.line_id} style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: 10 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, marginBottom: 8, flexWrap: 'wrap' }}>
              <strong style={{ fontSize: 13 }}>{l.product_name}</strong>
              <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>{outstanding(l)} of {l.qty_out} still out</span>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(104px, 1fr))', gap: 8 }}>
              {TAKE_BACK_FIELDS.map(f => (
                <label key={f.key} style={{ display: 'flex', flexDirection: 'column', gap: 3, fontSize: 11.5, margin: 0 }} title={f.hint}>
                  <span>{f.label}</span>
                  <input type="number" min={0} step={1} max={outstanding(l)} value={drafts[l.line_id]?.[f.key] || ''} placeholder="0"
                    aria-label={`${l.product_name}: ${f.label}`} disabled={locked}
                    onChange={e => set(l.line_id, f.key, e.target.value === '' ? 0 : +e.target.value)} />
                </label>
              ))}
            </div>
          </div>
        ))}
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label>Note</label>
          <input value={note} disabled={locked} onChange={e => setNote(e.target.value)} placeholder="Optional, e.g. One box opened" />
        </div>
        {preview.ok && <div style={{ fontSize: 12.5, color: 'var(--text-secondary)' }}>
          {preview.value.closes ? `Everything is accounted for: ${loan.loan_no} will close.` : `${loan.loan_no} stays open for what is still out.`}
        </div>}
        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
      </div>
    </Modal>
  );
};

export default TakeBackModal;
