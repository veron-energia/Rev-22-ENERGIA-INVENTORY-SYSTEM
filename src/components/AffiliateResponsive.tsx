import React from 'react';

// Small shared building blocks for responsive Affiliate pages. Tables and mobile
// cards render from the SAME loaded data (CSS toggles which is visible at 640px);
// no duplicate API calls.

export const StatGrid: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div className="affiliate-stat-grid" style={{ marginBottom: 22 }}>{children}</div>
);

export const Stat: React.FC<{ label: string; value: string; icon?: React.ReactNode; accent?: string }> = ({ label, value, icon, accent }) => (
  <div className="card affiliate-stat-card">
    <div className="lbl">{icon}{label}</div>
    <div className="val" style={{ color: accent }}>{value}</div>
  </div>
);

// Desktop-only card wrapping a <table>; the wrapper scrolls horizontally, never the page.
export const DesktopTableCard: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div className="card affiliate-desktop-only" style={{ padding: 0 }}>
    <div className="affiliate-table-wrap">{children}</div>
  </div>
);

export const MobileCards: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div className="affiliate-mobile-only">{children}</div>
);

// One stacked record card. `rows` is a list of [label, value] pairs; value may be
// a node (e.g. a status badge).
export const MCard: React.FC<{ title?: React.ReactNode; rows: [React.ReactNode, React.ReactNode][] }> = ({ title, rows }) => (
  <div className="card affiliate-mobile-card">
    {title && <div className="title">{title}</div>}
    {rows.map(([k, v], i) => (
      <div className="row" key={i}><span className="k">{k}</span><span className="v">{v}</span></div>
    ))}
  </div>
);

export const EmptyNote: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <p style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 12 }}>{children}</p>
);
