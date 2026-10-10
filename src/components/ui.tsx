import React from 'react';
import { useAuth } from '../context/AuthContext';
import { UserRole } from '../types';
import { Lock } from 'lucide-react';

// ── RoleGate: hide/replace content based on role ─────────────────────────────
export const RoleGate: React.FC<{
  allow: (role?: UserRole) => boolean;
  children: React.ReactNode;
  fallback?: React.ReactNode;
}> = ({ allow, children, fallback = null }) => {
  const { profile } = useAuth();
  if (!allow(profile?.role)) return <>{fallback}</>;
  return <>{children}</>;
};

// ── A full-page "no access" panel for route-level gating ─────────────────────
export const NoAccess: React.FC<{ message?: string }> = ({ message }) => (
  <div className="card" style={{ padding: 48, textAlign: 'center', maxWidth: 460, margin: '40px auto' }}>
    <div style={{ display: 'inline-flex', width: 48, height: 48, borderRadius: 12, background: 'var(--surface-2)', alignItems: 'center', justifyContent: 'center', marginBottom: 14 }}>
      <Lock size={22} color="var(--text-muted)" />
    </div>
    <h3 style={{ fontSize: 17, marginBottom: 6 }}>Access restricted</h3>
    <p style={{ color: 'var(--text-muted)', fontSize: 13.5 }}>
      {message ?? "You don't have permission to view this page. Contact an Owner or Manager if you think this is a mistake."}
    </p>
  </div>
);

// ── Simple modal wrapper ─────────────────────────────────────────────────────
/**
 * Whether this overlay is the window on top: the last open window in the
 * page. Windows share one z-index, so the last one in the page is the one
 * drawn on top, whichever opened first or sits inside which.
 */
function isTopModal(overlay: HTMLElement | null): boolean {
  if (!overlay || !overlay.isConnected) return false;
  const open = overlay.ownerDocument.querySelectorAll('[data-modal-overlay]');
  return open.length > 0 && open[open.length - 1] === overlay;
}

export const Modal: React.FC<{
  title: string;
  onClose: () => void;
  children: React.ReactNode;
  footer?: React.ReactNode;
  maxWidth?: number;
  /** Fill the working area, leaving only the sidebar visible. */
  wide?: boolean;
  /**
   * Set on any modal holding a form. A backdrop click or Escape then asks
   * before discarding, instead of throwing away work silently — a clerk two
   * minutes into a New Invoice used to lose all of it to one stray click.
   * Read-only modals leave this off and keep click-outside-to-close.
   */
  confirmClose?: boolean;
}> = ({ title, onClose, children, footer, maxWidth = 480, wide = false, confirmClose = false }) => {
  const titleId = React.useId();
  const panelRef = React.useRef<HTMLDivElement | null>(null);
  const overlayRef = React.useRef<HTMLDivElement | null>(null);

  const requestClose = React.useCallback(() => {
    if (confirmClose && !window.confirm('Discard what you have entered? It will not be saved.')) return;
    onClose();
  }, [confirmClose, onClose]);

  // Escape closes, through the same confirmation. Only the window on top
  // answers it: every open window listens on the document, so with one window
  // over another (Confirm Exchange over the exchange being entered) Escape
  // used to close both, and asked to discard the one below first.
  // The window that answers marks the key as used (preventDefault), and a
  // window below skips a used key. Checking "on top" alone is not enough: a
  // browser may finish closing the top window between two listeners, and the
  // window below would then find itself on top and answer the same key.
  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape' || e.defaultPrevented || !isTopModal(overlayRef.current)) return;
      e.preventDefault();
      e.stopPropagation();
      requestClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [requestClose]);

  // Focus moves into the dialog so the keyboard follows the eye.
  React.useEffect(() => { panelRef.current?.focus(); }, []);

  return (
  <div className={`modal-overlay${wide ? ' wide' : ''}`} ref={overlayRef} data-modal-overlay=""
       onClick={e => { if (e.target === e.currentTarget) requestClose(); }}>
    <div className="modal" ref={panelRef} tabIndex={-1}
      role="dialog" aria-modal="true" aria-labelledby={titleId}
      style={wide
      ? { maxWidth: 'none', width: '100%', height: '100%', maxHeight: 'none', display: 'flex', flexDirection: 'column', overflow: 'hidden' }
      : { maxWidth }}>
      <div className="modal-header">
        <h3 id={titleId}>{title}</h3>
        <button className="btn btn-secondary btn-sm btn-icon" aria-label="Close" onClick={requestClose}>✕</button>
      </div>
      <div className="modal-body" style={wide ? { flex: 1, overflowY: 'auto' } : undefined}>{children}</div>
      {footer && <div className="modal-footer">{footer}</div>}
    </div>
  </div>
  );
};

// Reusable input modals to replace browser prompt() calls.
export const ReasonModal: React.FC<{
  title: string;
  label?: string;
  placeholder?: string;
  confirmLabel?: string;
  /** Takes the reason; the caller closes the window. */
  onSubmit?: (reason: string) => void;
  /**
   * Saves the reason instead, and answers an error to show, or null once
   * saved. The window stays open, showing the error, until the save works;
   * then it closes through onClose.
   */
  onSubmitAsync?: (reason: string) => Promise<string | null>;
  onClose: () => void;
  required?: boolean;
  /** The fewest characters a reason may have, as the server checks it. */
  minLength?: number;
}> = ({ title, label = 'Reason', placeholder = 'Enter a reason…', confirmLabel = 'Confirm', onSubmit, onSubmitAsync,
  onClose, required = true, minLength }) => {
  const [val, setVal] = React.useState('');
  const [err, setErr] = React.useState<string | null>(null);
  const [busy, setBusy] = React.useState(false);
  // Set on every mount, not only at first: in development React mounts a
  // window, unmounts it and mounts it again (StrictMode), and a flag left
  // false kept the window on 'Saving…' for good.
  const mounted = React.useRef(true);
  React.useEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);
  const submit = async () => {
    if (busy) return;
    const reason = val.trim();
    if (required && !reason) { setErr('This field is required.'); return; }
    if (minLength && (required || reason) && reason.length < minLength) {
      setErr(`Give at least ${minLength} characters.`); return;
    }
    if (!onSubmitAsync) { onSubmit?.(reason); return; }
    setBusy(true); setErr(null);
    let failure: string | null;
    try { failure = await onSubmitAsync(reason); }
    catch (e) { failure = e instanceof Error ? e.message : String(e); }
    if (!mounted.current) return;
    setBusy(false);
    if (failure) { setErr(failure); return; }
    onClose();
  };
  return (
    <Modal title={title} maxWidth={440} onClose={onClose}
      footer={<><button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={() => void submit()} disabled={busy}>
          {busy ? 'Saving…' : confirmLabel}
        </button></>}>
      <div className="form-group" style={{ marginBottom: 0 }}>
        <label>{label}{required ? ' *' : ''}</label>
        <textarea rows={3} value={val} autoFocus placeholder={placeholder}
          onChange={e => { setVal(e.target.value); setErr(null); }}
          onKeyDown={e => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) void submit(); }} />
        {minLength ? (
          <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4 }}>At least {minLength} characters.</div>
        ) : null}
        {err && <div role="alert" style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>{err}</div>}
      </div>
    </Modal>
  );
};

export const DateModal: React.FC<{
  title: string;
  label?: string;
  initial?: string;
  min?: string;
  max?: string;
  confirmLabel?: string;
  helpText?: string;
  onSubmit: (date: string) => void;
  onClose: () => void;
}> = ({ title, label = 'Date', initial = '', min, max, confirmLabel = 'Confirm', helpText, onSubmit, onClose }) => {
  const [val, setVal] = React.useState(initial);
  const [err, setErr] = React.useState<string | null>(null);
  const submit = () => {
    if (!val) { setErr('Please choose a date.'); return; }
    if (min && val < min) { setErr(`Date can't be before ${min}.`); return; }
    if (max && val > max) { setErr(`Date can't be after ${max}.`); return; }
    onSubmit(val);
  };
  return (
    <Modal title={title} maxWidth={400} onClose={onClose}
      footer={<><button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={submit}>{confirmLabel}</button></>}>
      <div className="form-group" style={{ marginBottom: 0 }}>
        <label>{label}</label>
        <input type="date" value={val} min={min} max={max} autoFocus
          onChange={e => { setVal(e.target.value); setErr(null); }} />
        {helpText && <div style={{ fontSize: 11.5, color: 'var(--text-muted)', marginTop: 4 }}>{helpText}</div>}
        {err && <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>{err}</div>}
      </div>
    </Modal>
  );
};
