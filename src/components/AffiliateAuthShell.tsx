import React from 'react';
import { Leaf } from 'lucide-react';

// Centered card used by all affiliate auth pages (no staff chrome).
const AffiliateAuthShell: React.FC<{ title: string; subtitle?: string; children: React.ReactNode; footer?: React.ReactNode }>
  = ({ title, subtitle, children, footer }) => (
  <div className="portal-auth" style={{ minHeight: '100vh', background: 'var(--bg)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16 }}>
    <div style={{ width: '100%', maxWidth: 420 }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: 18 }}>
        <div style={{ width: 46, height: 46, borderRadius: 13, background: 'var(--primary)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 10 }}>
          <Leaf size={24} color="#fff" />
        </div>
        <h2 style={{ fontSize: 20, fontWeight: 700, textAlign: 'center' }}>{title}</h2>
        {subtitle && <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginTop: 4, textAlign: 'center' }}>{subtitle}</p>}
      </div>
      <div className="card portal-auth-card">{children}</div>
      {footer && <div style={{ textAlign: 'center', marginTop: 16, fontSize: 13.5, color: 'var(--text-secondary)' }}>{footer}</div>}
    </div>
  </div>
);

// The label names its field (ADMIN-AUTH-18): the one element inside gets an
// id (its own, if it has one) and the label points at it, so a screen reader
// reads the label and a tap on it moves to the field.
export const Field: React.FC<{ label: string; children: React.ReactNode }> = ({ label, children }) => {
  const generated = React.useId();
  const only = React.Children.count(children) === 1 && React.isValidElement(children) ? children : null;
  const id = (only?.props as { id?: string } | undefined)?.id ?? generated;
  return (
    <div style={{ marginBottom: 14 }}>
      <label htmlFor={only ? id : undefined} style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>{label}</label>
      {only ? React.cloneElement(only as React.ReactElement<{ id?: string }>, { id }) : children}
    </div>
  );
};

export default AffiliateAuthShell;
