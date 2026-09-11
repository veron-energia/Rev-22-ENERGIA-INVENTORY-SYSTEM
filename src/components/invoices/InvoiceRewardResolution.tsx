import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';

type Row = {
  sale_id: string; invoice_item_id: string; package_name: string; reward_units: number;
  entitlement_id: string | null; entitlement_no: string | null; status: string | null;
  activation_date: string | null; claimed_at: string | null;
  disposition: 'withdrawable' | 'consumed' | 'already_closed' | 'none_issued';
  resolved_at: string | null;
};

const LABEL: Record<string, string> = {
  withdrawable: 'Not claimed — can be taken back',
  consumed: 'Activated or claimed — stays',
  already_closed: 'Already closed',
  none_issued: 'Nothing was issued',
};

/**
 * What a credit package's qualification rewards actually became, and the
 * decision that lets the refund or cancellation proceed.
 *
 * Unclaimed entitlements are withdrawn. Anything the customer has activated or
 * claimed is listed and kept — this never edits it, and the person resolving has
 * to say they understand it stays.
 */
export function InvoiceRewardResolution({ invoiceId, onResolved, onCancel }: {
  invoiceId: string; onResolved: () => void; onCancel: () => void;
}) {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [reason, setReason] = useState('');
  const [acknowledge, setAcknowledge] = useState(false);
  const [error, setError] = useState('');
  const [notInstalled, setNotInstalled] = useState(false);
  const [busy, setBusy] = useState(false);
  const [requestId] = useState(() => crypto.randomUUID());
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let alive = true;
    root.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    supabase.rpc('invoice_credit_reward_entitlements', { p_invoice_id: invoiceId })
      .then(({ data, error }) => {
        if (!alive) return;
        if (error) {
          if ((error as any).code === '42883' || /does not exist/i.test(error.message)) setNotInstalled(true);
          else setError(error.message);
          setRows([]); return;
        }
        setRows((data as Row[]) ?? []);
      });
    return () => { alive = false; };
  }, [invoiceId]);

  const consumed = (rows ?? []).filter(r => r.disposition === 'consumed');
  const withdrawable = (rows ?? []).filter(r => r.disposition === 'withdrawable');

  const resolve = async () => {
    if (!reason.trim()) { setError('Enter a reason for the audit history.'); return; }
    setBusy(true); setError('');
    const { error } = await supabase.rpc('resolve_invoice_credit_rewards', {
      p_invoice_id: invoiceId, p_reason: reason.trim(),
      p_acknowledge_consumed: acknowledge, p_request_id: requestId,
    });
    setBusy(false);
    if (error) { setError(error.message); return; }
    onResolved();
  };

  return (
    <div className="invoice-evidence-review" role="group" aria-label="Qualification reward review" ref={root}>
      <strong>This package granted qualification rewards</strong>
      <p>
        Buying it created Legacy therapy entitlements. Decide what happens to them before
        the refund or cancellation. Nothing is changed until you confirm.
      </p>
      {notInstalled && (
        <div role="alert" className="alert alert-warning">
          <span>⚠</span>
          <div>
            This review is not available on this database yet. Apply migration
            <strong> 291_invoice_credit_reward_resolution.sql</strong>, then reopen this invoice.
          </div>
        </div>
      )}
      {error && <div role="alert" className="alert alert-danger">{error}</div>}
      {!rows && !notInstalled && <p role="status">Reading the reward entitlements…</p>}
      {rows?.filter(r => r.entitlement_id).map(r => (
        <div key={r.entitlement_id!} className="invoice-evidence-line">
          <div className="invoice-evidence-line-head">
            <span><strong>{r.entitlement_no}</strong> <span className="invoice-evidence-kind">{r.package_name}</span></span>
            <span className={`invoice-evidence-status invoice-evidence-${r.disposition === 'consumed' ? 'needs_confirmation' : r.disposition === 'withdrawable' ? 'reconstructable' : 'captured'}`}>
              {LABEL[r.disposition] ?? r.disposition}</span>
          </div>
          <p className="invoice-evidence-source">
            Status {r.status}{r.activation_date ? ` · activated ${r.activation_date}` : ''}
            {r.claimed_at ? ` · claimed ${new Date(r.claimed_at).toLocaleDateString('en-SG')}` : ''}
          </p>
        </div>
      ))}
      {rows && rows.filter(r => r.entitlement_id).length === 0 && !notInstalled && (
        <p role="status">This purchase left no reward entitlement outstanding.</p>
      )}
      {withdrawable.length > 0 && (
        <p className="invoice-evidence-source">
          {withdrawable.length} unclaimed entitlement{withdrawable.length === 1 ? '' : 's'} will be withdrawn,
          and any reward voucher stock they hold returned.
        </p>
      )}
      {consumed.length > 0 && (
        <label className="invoice-evidence-confirm">
          <input type="checkbox" checked={acknowledge} onChange={e => setAcknowledge(e.target.checked)} />
          I understand {consumed.length} entitlement{consumed.length === 1 ? ' has' : 's have'} already been
          activated or claimed. {consumed.length === 1 ? 'It stays' : 'They stay'} with the customer and
          {consumed.length === 1 ? ' its' : ' their'} history is kept.
        </label>
      )}
      <label>Reason (required)
        <input value={reason} onChange={e => setReason(e.target.value)}
          placeholder="e.g. Customer returned the package on 11 September" /></label>
      <div className="invoice-evidence-actions">
        <button className="btn btn-secondary" onClick={onCancel} disabled={busy}>Back</button>
        <button className="btn btn-primary" onClick={resolve}
          disabled={busy || !rows || notInstalled || (consumed.length > 0 && !acknowledge)}
          title={consumed.length > 0 && !acknowledge ? 'Confirm the claimed entitlements first.' : undefined}>
          {busy ? 'Recording…' : 'Record this decision and continue'}
        </button>
      </div>
    </div>
  );
}
