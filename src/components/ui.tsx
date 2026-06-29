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
}> = ({ title, onClose, children, footer, maxWidth = 480 }) => (
  <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
    <div className="modal" style={{ maxWidth }}>
      <div className="modal-header">
        <h3>{title}</h3>
        <button className="btn btn-secondary btn-sm btn-icon" onClick={onClose}>✕</button>
      </div>
      <div className="modal-body">{children}</div>
      {footer && <div className="modal-footer">{footer}</div>}
    </div>
  </div>
);
