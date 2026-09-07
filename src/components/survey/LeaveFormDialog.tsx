import React, { useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { AlertTriangle } from 'lucide-react';

/**
 * Accessible confirmation shown when a customer tries to navigate away from an
 * unfinished survey. Escape or a click outside cancels (keeps them on the form);
 * only "Leave and discard" proceeds.
 */
const LeaveFormDialog: React.FC<{
  open: boolean;
  /** true while a submission is in flight — wording changes to match */
  submitting: boolean;
  onStay: () => void;
  onLeave: () => void;
}> = ({ open, submitting, onStay, onLeave }) => {
  const dialogRef = useRef<HTMLDivElement>(null);
  const stayBtnRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const previouslyFocused = document.activeElement as HTMLElement | null;
    stayBtnRef.current?.focus();

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onStay();
        return;
      }
      if (e.key === 'Tab') {
        // Minimal focus trap between the two actions.
        const focusables = dialogRef.current?.querySelectorAll<HTMLElement>('button');
        if (!focusables || focusables.length === 0) return;
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener('keydown', onKeyDown, true);
    return () => {
      document.removeEventListener('keydown', onKeyDown, true);
      previouslyFocused?.focus?.();
    };
  }, [open, onStay]);

  if (!open) return null;

  const title = submitting ? 'Your form is still being sent' : 'Leave this form?';
  const message = submitting
    ? 'Your form is being submitted right now. If you leave, we may not be able to '
      + 'tell you whether it went through. Please wait a moment.'
    : 'You have entered information that has not been submitted. If you leave, all '
      + 'the information you entered will be lost.';

  return createPortal(
    <div
      className="survey-dialog-overlay"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onStay();
      }}
    >
      <div
        ref={dialogRef}
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="survey-leave-title"
        aria-describedby="survey-leave-message"
        className="survey-dialog"
      >
        <div className="survey-dialog-head">
          <AlertTriangle size={20} aria-hidden="true" />
          <h2 id="survey-leave-title">{title}</h2>
        </div>
        <p id="survey-leave-message">{message}</p>
        <div className="survey-dialog-actions">
          <button ref={stayBtnRef} type="button" className="btn btn-secondary" onClick={onStay}>
            {submitting ? 'Keep waiting' : 'Continue filling form'}
          </button>
          <button type="button" className="btn btn-danger" onClick={onLeave}>
            {submitting ? 'Leave anyway' : 'Leave and discard'}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  );
};

export default LeaveFormDialog;
