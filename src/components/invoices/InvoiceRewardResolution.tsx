import React, { useEffect, useRef, useState } from 'react';
import { supabase } from '../../lib/supabase';
import { displayDay } from '../../lib/calendarDates';

type Row = {
  sale_id: string; invoice_item_id: string; package_name: string; reward_units: number;
  entitlement_id: string | null; entitlement_no: string | null; status: string | null;
  activation_date: string | null; claimed_at: string | null;
  disposition: 'withdrawable' | 'consumed' | 'already_closed' | 'none_issued';
  resolved_at: string | null;
};

const LABEL: Record<string, string> = {
  withdrawable: 'Not handed over — will be withdrawn',
  consumed: 'Handed over (some or all) — stays with the customer',
  already_closed: 'Already closed',
  none_issued: 'Nothing was issued',
};
/** A reward's status, in the words of Therapy → Vouchers to hand over. */
const STATUS: Record<string, string> = {
  pending_activation: 'to hand over', active: 'handed over', cancelled: 'cancelled', expired: 'expired',
};

/**
 * The reward vouchers an older Credit Package sale came with, and the decision
 * that lets its refund or cancellation go ahead (291). New sales give credit
 * only since 502 (the user, 10 Nov 2026), so only older sales reach this.
 *
 * Rewards not handed over yet are withdrawn. A reward whose vouchers were
 * handed over (some or all) is listed and kept: this never edits it, and the
 * person deciding ticks that they understand it stays.
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
    <div className="invoice-evidence-review" role="group" aria-label="Reward voucher review" ref={root}>
      <strong>This Credit Package came with reward vouchers</strong>
      <p>
        When it was sold it came with free vouchers for the customer. Decide what happens to them
        before the refund or cancellation. Nothing is changed until you confirm.
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
      {!rows && !notInstalled && <p role="status">Reading the reward vouchers…</p>}
      {rows?.filter(r => r.entitlement_id).map(r => (
        <div key={r.entitlement_id!} className="invoice-evidence-line">
          <div className="invoice-evidence-line-head">
            <span><strong>{r.entitlement_no}</strong> <span className="invoice-evidence-kind">{r.package_name}</span></span>
            <span className={`invoice-evidence-status invoice-evidence-${r.disposition === 'consumed' ? 'needs_confirmation' : r.disposition === 'withdrawable' ? 'reconstructable' : 'captured'}`}>
              {LABEL[r.disposition] ?? r.disposition}</span>
          </div>
          {/* Every date is its Singapore day, whatever the device's time zone. */}
          <p className="invoice-evidence-source">
            Status: {STATUS[r.status ?? ''] ?? String(r.status ?? '—').replace(/_/g, ' ')}
            {r.activation_date ? ` · first handed over ${displayDay(r.activation_date)}` : ''}
            {r.claimed_at ? ` · last handed over ${displayDay(r.claimed_at)}` : ''}
          </p>
        </div>
      ))}
      {rows && rows.filter(r => r.entitlement_id).length === 0 && !notInstalled && (
        <p role="status">This sale has no reward vouchers left to settle.</p>
      )}
      {withdrawable.length > 0 && (
        <p className="invoice-evidence-source">
          {withdrawable.length} reward{withdrawable.length === 1 ? '' : 's'} not handed over yet will be withdrawn.
          Any vouchers already issued against them are revoked and their stock returned.
        </p>
      )}
      {consumed.length > 0 && (
        <label className="invoice-evidence-confirm">
          <input type="checkbox" checked={acknowledge} onChange={e => setAcknowledge(e.target.checked)} />
          I understand {consumed.length} reward{consumed.length === 1 ? ' has' : 's have'} already had vouchers
          handed over. Those vouchers stay with the customer, and the history is kept.
        </label>
      )}
      <label>Reason (required)
        <input value={reason} onChange={e => setReason(e.target.value)}
          placeholder="e.g. Customer returned the package on 11 September" /></label>
      <div className="invoice-evidence-actions">
        <button className="btn btn-secondary" onClick={onCancel} disabled={busy}>Back</button>
        <button className="btn btn-primary" onClick={resolve}
          disabled={busy || !rows || notInstalled || (consumed.length > 0 && !acknowledge)}
          title={consumed.length > 0 && !acknowledge ? 'Tick the box above first.' : undefined}>
          {busy ? 'Recording…' : 'Record this decision and continue'}
        </button>
      </div>
    </div>
  );
}
