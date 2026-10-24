import React, { useId, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { Modal } from '../ui';

/**
 * Delete a customer: the Customers page's own window, shared with Health
 * Surveys → To match (468), so both delete the same way.
 *
 * It goes through delete_customer(), which checks the role (Owner or
 * Manager), matches the typed name, refuses to strand credit or entitlements,
 * and records who did it. Writing to the table directly was blocked by RLS
 * and, worse, threw away the error — the click simply did nothing. The
 * customer is only taken off the list: an Owner or Manager can restore them.
 */
const DeleteCustomerModal: React.FC<{
  customer: { id: string; full_name: string | null };
  /** Said above the usual words, e.g. why it is offered here. */
  intro?: React.ReactNode;
  onClose: () => void;
  /** Called once the server has deleted the customer. */
  onDeleted: () => void;
}> = ({ customer, intro, onClose, onDeleted }) => {
  const [name, setName] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // Each box is tied to its label, so a screen reader names it by the label.
  const nameId = useId();
  const reasonId = useId();

  // Compared the same way the database does: case-insensitive, with runs
  // of whitespace collapsed. The point is to make someone read the name,
  // not to test their typing.
  const norm = (v: string) => v.trim().toLowerCase().replace(/\s+/g, ' ');
  const matches = norm(name) === norm(customer.full_name ?? '');

  const confirm = async () => {
    setBusy(true); setErr(null);
    const { error } = await supabase.rpc('delete_customer', {
      p_customer_id: customer.id,
      p_confirm_name: name,
      p_reason: reason.trim() || null,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    onDeleted();
  };

  return (
    <Modal title="Delete customer" maxWidth={460} onClose={onClose}
      footer={<>
        <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-danger" data-confirm-delete onClick={confirm}
          disabled={busy || !matches}>
          {busy ? 'Deleting…' : 'Delete customer'}
        </button>
      </>}>
      <div className="form-grid">
        {intro}
        <div style={{ fontSize: 13 }}>
          This removes <strong>{customer.full_name}</strong> from the customer list.
          Their invoices and history are kept, and an Owner or Manager can restore them.
        </div>

        {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}>
          <span>⚠</span><div>{err}</div></div>}

        <div className="form-group" style={{ marginBottom: 0 }}>
          <label htmlFor={nameId}>Type <strong>{customer.full_name}</strong> to confirm *</label>
          <input id={nameId} value={name} autoFocus data-delete-name
            placeholder={customer.full_name ?? ''}
            onChange={e => setName(e.target.value)} />
          {name.length > 0 && !matches && (
            <div style={{ fontSize: 11.5, color: 'var(--danger)', marginTop: 3 }}>
              That does not match the customer's name.
            </div>
          )}
        </div>

        <div className="form-group" style={{ marginBottom: 0 }}>
          <label htmlFor={reasonId}>Reason</label>
          <input id={reasonId} value={reason} data-delete-reason onChange={e => setReason(e.target.value)}
            placeholder="Duplicate record, created in error…" />
          <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3 }}>
            Recorded against the deletion, alongside who performed it.
          </div>
        </div>
      </div>
    </Modal>
  );
};

export default DeleteCustomerModal;
