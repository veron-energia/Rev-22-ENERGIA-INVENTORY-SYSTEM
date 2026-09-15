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

  const requestClose = React.useCallback(() => {
    if (confirmClose && !window.confirm('Discard what you have entered? It will not be saved.')) return;
    onClose();
  }, [confirmClose, onClose]);

  // Escape closes, through the same confirmation. The component had no keyboard
  // route out at all before this.
  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); requestClose(); } };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [requestClose]);

  // Focus moves into the dialog so the keyboard follows the eye.
  React.useEffect(() => { panelRef.current?.focus(); }, []);

  return (
  <div className={`modal-overlay${wide ? ' wide' : ''}`}
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
  onSubmit: (reason: string) => void;
  onClose: () => void;
  required?: boolean;
}> = ({ title, label = 'Reason', placeholder = 'Enter a reason…', confirmLabel = 'Confirm', onSubmit, onClose, required = true }) => {
  const [val, setVal] = React.useState('');
  const [err, setErr] = React.useState<string | null>(null);
  const submit = () => {
    if (required && !val.trim()) { setErr('This field is required.'); return; }
    onSubmit(val.trim());
  };
  return (
    <Modal title={title} maxWidth={440} onClose={onClose}
      footer={<><button className="btn btn-secondary" onClick={onClose}>Cancel</button>
        <button className="btn btn-primary" onClick={submit}>{confirmLabel}</button></>}>
      <div className="form-group" style={{ marginBottom: 0 }}>
        <label>{label}{required ? ' *' : ''}</label>
        <textarea rows={3} value={val} autoFocus placeholder={placeholder}
          onChange={e => { setVal(e.target.value); setErr(null); }}
          onKeyDown={e => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) submit(); }} />
        {err && <div style={{ fontSize: 12, color: 'var(--danger)', marginTop: 4 }}>{err}</div>}
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
