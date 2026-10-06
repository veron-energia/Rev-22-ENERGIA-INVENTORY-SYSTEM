import React, { useEffect, useId, useRef, useState } from 'react';
import { QrCode } from 'lucide-react';
import { paymentQrAmount, type PaymentQrChoice, type PaymentQrImage } from '../../lib/invoices/paymentQr.mjs';

/**
 * The store's QR for the customer to scan, shown the moment staff pick PayNow,
 * GrabPay or Atome on a payment line (Owner, 6 Oct 2026).
 *
 * It only shows the code. Closing it records nothing: staff press Record
 * Payment as before once the money is in.
 */
export function PaymentQrPopup({ qr, image, amount, reference, onClose, returnFocusTo }: {
  qr: Pick<PaymentQrChoice, 'label' | 'methodName'>;
  image: PaymentQrImage;
  /** The payment line's amount as it stands. */
  amount: number;
  /** The invoice number, for the customer to quote. */
  reference: string;
  onClose: () => void;
  /** Where focus goes when it closes: its line's Show QR button. Picking a
   *  method closes the picker, so whatever had focus is gone by the time this
   *  opens. Without it (or when it finds nothing), focus goes back to the opener. */
  returnFocusTo?: () => HTMLElement | null | undefined;
}) {
  const dialog = useRef<HTMLDivElement>(null);
  const opener = useRef<Element | null>(null);
  const closeCallback = useRef(onClose); closeCallback.current = onClose;
  const focusTarget = useRef(returnFocusTo); focusTarget.current = returnFocusTo;
  const titleId = useId();
  const [broken, setBroken] = useState(false);
  useEffect(() => { setBroken(false); }, [image.url]);

  useEffect(() => {
    opener.current = document.activeElement;
    dialog.current?.querySelector<HTMLElement>('.invoice-qr-paid')?.focus();
    // Captured on the document, so the invoice window's own Escape handler
    // never sees the key: Escape closes this and leaves the invoice open.
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeCallback.current(); return; }
      if (e.key !== 'Tab') return;
      const list = Array.from(dialog.current?.querySelectorAll<HTMLElement>('button:not([disabled])') ?? []);
      if (!list.length) return;
      const first = list[0], last = list[list.length - 1];
      if (!dialog.current?.contains(document.activeElement)) { e.preventDefault(); first.focus(); }
      else if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', onKey, true);
    return () => {
      document.removeEventListener('keydown', onKey, true);
      // Back to the line it belongs to, never to the page behind the invoice.
      const back = (focusTarget.current?.() ?? opener.current) as HTMLElement | null;
      if (back?.isConnected && back !== document.body) back.focus?.();
    };
  }, []);

  const pay = paymentQrAmount(amount);
  return (
    <div className="invoice-qr-backdrop" onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="invoice-qr" role="dialog" aria-modal="true" aria-labelledby={titleId} ref={dialog}>
        <h3 id={titleId}>Scan to pay with {qr.label}</h3>
        {qr.methodName && qr.methodName.toLowerCase() !== qr.label.toLowerCase() &&
          <div className="invoice-qr-method">{qr.methodName}</div>}
        {pay
          ? <div className="invoice-qr-amount">Pay {pay}</div>
          : <div className="invoice-qr-amount invoice-qr-no-amount">No amount entered on this line yet</div>}
        <div className="invoice-qr-ref">Reference: <strong>{reference}</strong></div>
        <div className="invoice-qr-image">
          {broken
            ? <p role="alert">The {qr.label} QR image could not be loaded. Check the store's image on the Stores page.</p>
            : <img src={image.url} alt={`${qr.label} QR code of ${image.storeName}`} onError={() => setBroken(true)} />}
        </div>
        {image.borrowed &&
          <p className="invoice-qr-borrowed">This store has no {qr.label} QR of its own, so this is <strong>{image.storeName}</strong>'s.</p>}
        <div className="invoice-qr-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Close</button>
          <button type="button" className="btn btn-primary invoice-qr-paid" onClick={onClose}>Customer has paid</button>
        </div>
        <p className="invoice-qr-note">This records nothing. Press Record Payment once the money is in.</p>
      </div>
    </div>
  );
}

/**
 * Beside a payment line whose method has a QR: a button to show it again, or a
 * quiet word when no store has uploaded one.
 */
export function PaymentQrLineAction({ qr, onShow, buttonRef }: {
  qr: PaymentQrChoice | null; onShow: () => void; buttonRef?: React.Ref<HTMLButtonElement>;
}) {
  if (!qr) return null;
  if (!qr.image) return <small className="invoice-qr-missing">No {qr.label} QR uploaded</small>;
  return (
    <button type="button" className="btn btn-secondary btn-sm invoice-qr-show" onClick={onShow} ref={buttonRef}
      title={qr.image.borrowed ? `Shows ${qr.image.storeName}'s ${qr.label} QR` : `Shows this store's ${qr.label} QR`}>
      <QrCode size={13} /> Show QR
    </button>
  );
}
