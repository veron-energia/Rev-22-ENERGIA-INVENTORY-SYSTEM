import React, { useEffect, useRef } from 'react';

/**
 * The one footer action that used to be two buttons at the top of the invoice.
 *
 * It asks which of the two very different things the person means, and does
 * nothing else: opening it changes no state on the server and starts no
 * workflow. Choosing an option hands over to the existing refund or
 * cancellation workflow unchanged, with its own reason, preview and approvals.
 */
export function InvoiceRefundCancelChooser({ open, onClose, onChoose, canRefund, canCancel, refundBlockedReason, cancelBlockedReason, invoiceNo, status, netReceived, refundedAmount }: {
  open: boolean;
  onClose: () => void;
  onChoose: (choice: 'refund' | 'cancel') => void;
  canRefund: boolean;
  canCancel: boolean;
  refundBlockedReason?: string;
  cancelBlockedReason?: string;
  invoiceNo?: string;
  status?: string;
  netReceived?: number;
  refundedAmount?: number;
}) {
  const dialog = useRef<HTMLDivElement>(null);
  const first = useRef<HTMLButtonElement>(null);
  const opener = useRef<Element | null>(null);
  const closeCallback = useRef(onClose); closeCallback.current = onClose;

  useEffect(() => {
    if (!open) return;
    // Remember where focus came from so closing can put it back, which is what
    // makes this usable with a keyboard or a screen reader.
    opener.current = document.activeElement;
    dialog.current?.querySelector<HTMLElement>('button:not([disabled])')?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeCallback.current(); return; }
      if (e.key !== 'Tab') return;
      const focusable = dialog.current?.querySelectorAll<HTMLElement>(
        'button:not([disabled]), [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
      if (!focusable?.length) return;
      const list = Array.from(focusable);
      const firstEl = list[0], lastEl = list[list.length - 1];
      if (e.shiftKey && document.activeElement === firstEl) { e.preventDefault(); lastEl.focus(); }
      else if (!e.shiftKey && document.activeElement === lastEl) { e.preventDefault(); firstEl.focus(); }
    };
    document.addEventListener('keydown', onKey, true);
    return () => {
      document.removeEventListener('keydown', onKey, true);
      (opener.current as HTMLElement | null)?.focus?.();
    };
  }, [open]);

  if (!open) return null;
  return (
    <div className="invoice-chooser-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="invoice-chooser" role="dialog" aria-modal="true"
        aria-labelledby="invoice-chooser-title" aria-describedby="invoice-chooser-help" ref={dialog}>
        <h3 id="invoice-chooser-title">Refund or cancel this invoice</h3>
        <div className="invoice-chooser-context"><strong>{invoiceNo}</strong> · {status?.replace(/_/g, ' ')}
          <div>Payment still held: S${Number(netReceived ?? 0).toFixed(2)}</div>
          <div>Refunds recorded: S${Number(refundedAmount ?? 0).toFixed(2)}</div>
        </div>
        <p id="invoice-chooser-help">
          Choose an action to review its details. No financial change is made until you complete the existing confirmation steps.
        </p>
        <div className="invoice-chooser-options">
          <button ref={first} className="btn btn-secondary invoice-chooser-option"
            onClick={() => onChoose('cancel')} disabled={!canCancel}
            title={canCancel ? undefined : cancelBlockedReason}>
            <strong>Cancel invoice</strong>
            <span>{canCancel
              ? 'Releases outstanding stock and unused benefits. Payments and consumed benefits stay in history.'
              : (cancelBlockedReason ?? 'Cancellation is not available for this invoice.')}</span>
          </button>
          <button className="btn btn-secondary invoice-chooser-option"
            onClick={() => onChoose('refund')} disabled={!canRefund}
            title={canRefund ? undefined : refundBlockedReason}>
            <strong>Full or partial refund</strong>
            <span>{canRefund
              ? 'Records money or credit actually returned, allocated to its original sources.'
              : (refundBlockedReason ?? 'No refundable payment. No money or credit remains available to return.')}</span>
          </button>
        </div>
        <div className="invoice-chooser-footer">
          <button className="btn btn-secondary" onClick={onClose}>Back</button>
        </div>
      </div>
    </div>
  );
}
