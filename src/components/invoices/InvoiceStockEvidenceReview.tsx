import React, { useEffect, useState } from 'react';
import { supabase } from '../../lib/supabase';

type Evidence = {
  invoice_item_id: string; line_kind: string; description: string;
  evidence_status: 'captured' | 'reconstructable' | 'needs_confirmation' | 'not_applicable' | 'missing';
  evidence_source: string; proposed: { kind: string; item_id: string; quantity: number; component_source?: string }[];
  missing: string | null;
};

const STATUS_LABEL: Record<string, string> = {
  captured: 'Already recorded',
  reconstructable: 'On record',
  needs_confirmation: 'Needs your confirmation',
  not_applicable: 'No stock involved',
  missing: 'Not on record',
};

/**
 * The review an Owner or Manager works through when an invoice predates stock
 * snapshots and its store has to change.
 *
 * It shows the evidence the database found, line by line, and where it found
 * it. Nothing is rebuilt until someone reads that and says so, and the one case
 * the records cannot answer — what a promotion contained on the day — has to be
 * confirmed explicitly rather than taken from today's catalogue.
 */
export function InvoiceStockEvidenceReview({ invoiceId, onResolved, onCancel }: {
  invoiceId: string; onResolved: () => void; onCancel: () => void;
}) {
  const [rows, setRows] = useState<Evidence[] | null>(null);
  const [confirmed, setConfirmed] = useState<Record<string, boolean>>({});
  const [reason, setReason] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [requestId] = useState(() => crypto.randomUUID());

  useEffect(() => {
    let alive = true;
    supabase.rpc('invoice_stock_component_evidence', { p_invoice_id: invoiceId })
      .then(({ data, error }) => {
        if (!alive) return;
        if (error) { setError(error.message); setRows([]); return; }
        setRows((data as Evidence[]) ?? []);
      });
    return () => { alive = false; };
  }, [invoiceId]);

  const needing = (rows ?? []).filter(r => r.evidence_status === 'needs_confirmation');
  const blocked = (rows ?? []).filter(r => r.evidence_status === 'missing');
  const outstanding = needing.filter(r => !confirmed[r.invoice_item_id]);

  const rebuild = async () => {
    if (!reason.trim()) { setError('Enter a reason for the audit history.'); return; }
    setBusy(true); setError('');
    const { error } = await supabase.rpc('rebuild_invoice_stock_components', {
      p_invoice_id: invoiceId, p_reason: reason.trim(), p_request_id: requestId,
      p_confirmations: needing.filter(r => confirmed[r.invoice_item_id])
        .map(r => ({ invoice_item_id: r.invoice_item_id, confirmed: true })),
    });
    setBusy(false);
    if (error) { setError(error.message); return; }
    onResolved();
  };

  return (
    <div className="invoice-evidence-review" role="group" aria-label="Historical stock evidence review">
      <strong>This invoice predates stock records</strong>
      <p>
        Its store cannot change until what it consumed is on record. Below is what the
        original records actually say. Nothing is written until you confirm it.
      </p>
      {error && <div role="alert" className="alert alert-danger">{error}</div>}
      {!rows && <p role="status">Reading the original records…</p>}
      {rows?.map(r => (
        <div key={r.invoice_item_id} className="invoice-evidence-line">
          <div className="invoice-evidence-line-head">
            <span><strong>{r.description}</strong> <span className="invoice-evidence-kind">{r.line_kind}</span></span>
            <span className={`invoice-evidence-status invoice-evidence-${r.evidence_status}`}>
              {STATUS_LABEL[r.evidence_status] ?? r.evidence_status}</span>
          </div>
          <p className="invoice-evidence-source">{r.evidence_source}</p>
          {r.proposed?.length > 0 && (
            <ul className="invoice-evidence-components">
              {r.proposed.map((c, i) => <li key={i}>{c.quantity} × {c.kind}{c.component_source ? ` (${c.component_source})` : ''}</li>)}
            </ul>
          )}
          {r.missing && <p className="invoice-evidence-missing">{r.missing}</p>}
          {r.evidence_status === 'needs_confirmation' && (
            <label className="invoice-evidence-confirm">
              <input type="checkbox" checked={!!confirmed[r.invoice_item_id]}
                onChange={e => setConfirmed(c => ({ ...c, [r.invoice_item_id]: e.target.checked }))} />
              I confirm these contents match what was sold on this invoice.
            </label>
          )}
        </div>
      ))}
      {blocked.length > 0 && (
        <div role="alert" className="alert alert-warning">
          <span>⚠</span>
          <div>
            Nothing on record answers {blocked.length === 1 ? 'one line' : `${blocked.length} lines`}.
            The store cannot be corrected until that evidence is found. Nothing here will guess it.
          </div>
        </div>
      )}
      <label>Reason (required)
        <input value={reason} onChange={e => setReason(e.target.value)}
          placeholder="e.g. Checked against the original till record" /></label>
      <div className="invoice-evidence-actions">
        <button className="btn btn-secondary" onClick={onCancel} disabled={busy}>Back</button>
        <button className="btn btn-primary" onClick={rebuild}
          disabled={busy || !rows || blocked.length > 0 || outstanding.length > 0}
          title={blocked.length > 0 ? 'Some lines have no evidence on record.'
            : outstanding.length > 0 ? 'Confirm the promotion contents first.' : undefined}>
          {busy ? 'Recording…' : 'Record this evidence and continue'}
        </button>
      </div>
    </div>
  );
}
