import React, { useEffect, useRef } from 'react';

/**
 * The one footer action that used to be two buttons at the top of the invoice.
 *
 * It asks which of the two very different things the person means, and does
 * nothing else: opening it changes no state on the server and starts no
 * workflow. Choosing an option hands over to the existing refund or
 * cancellation workflow unchanged, with its own reason, preview and approvals.
 */
export function InvoiceRefundCancelChooser({ open, onClose, onChoose, canRefund, canCancel, refundBlockedReason, cancelBlockedReason }: {
  open: boolean;
  onClose: () => void;
  onChoose: (choice: 'refund' | 'cancel') => void;
  canRefund: boolean;
  canCancel: boolean;
  refundBlockedReason?: string;
  cancelBlockedReason?: string;
}) {
  const dialog = useRef<HTMLDivElement>(null);
  const first = useRef<HTMLButtonElement>(null);
  const opener = useRef<Element | null>(null);

  useEffect(() => {
    if (!open) return;
    // Remember where focus came from so closing can put it back, which is what
    // makes this usable with a keyboard or a screen reader.
    opener.current = document.activeElement;
    first.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.stopPropagation(); onClose(); return; }
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
  }, [open, onClose]);

  if (!open) return null;
  return (
    <div className="invoice-chooser-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="invoice-chooser" role="dialog" aria-modal="true"
        aria-labelledby="invoice-chooser-title" aria-describedby="invoice-chooser-help" ref={dialog}>
        <h3 id="invoice-chooser-title">Refund or cancel this invoice</h3>
        <p id="invoice-chooser-help">
          These do different things. Cancelling reverses what the invoice still holds;
          a refund records money or credit actually returned. Choose one to continue —
          nothing changes until you complete that step.
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
            <strong>Full / partial refund</strong>
            <span>{canRefund
              ? 'Records money or credit actually returned, allocated to its original sources.'
              : (refundBlockedReason ?? 'No refundable payment.')}</span>
          </button>
        </div>
        <div className="invoice-chooser-footer">
          <button className="btn btn-secondary" onClick={onClose}>Back</button>
        </div>
      </div>
    </div>
  );
}
