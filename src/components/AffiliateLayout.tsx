import React, { useState } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Leaf, LayoutDashboard, Users, TrendingUp, Wallet, QrCode, UserCircle, LogOut, Menu, X } from 'lucide-react';

const NAV = [
  { to: '/affiliate/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/affiliate/network', label: 'My Network', icon: Users },
  { to: '/affiliate/earnings', label: 'Earnings', icon: TrendingUp },
  { to: '/affiliate/payouts', label: 'Payouts', icon: Wallet },
  { to: '/affiliate/referral', label: 'My Referral QR', icon: QrCode },
  { to: '/affiliate/account', label: 'Account', icon: UserCircle },
];

// Standalone portal shell — Energia styling, NO staff/POS navigation.
// Layout is CSS-driven (.affiliate-* in globals.css): a row on desktop with a
// sidebar, a stacked column on mobile with a sticky header above the content.
const AffiliateLayout: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { signOut } = useAuth();
  const nav = useNavigate();
  const [open, setOpen] = useState(false);

  const doSignOut = async () => { setOpen(false); await signOut(); nav('/affiliate/login', { replace: true }); };

  const links = (
    <>
      {NAV.map(({ to, label, icon: Icon }) => (
        <NavLink key={to} to={to} onClick={() => setOpen(false)}
          className={({ isActive }) => 'aff-navlink' + (isActive ? ' active' : '')}>
          <Icon size={18} /> {label}
        </NavLink>
      ))}
      <button className="aff-navlink danger" onClick={doSignOut}>
        <LogOut size={18} /> Sign Out
      </button>
    </>
  );

  return (
    <div className="affiliate-shell">
      {/* Sidebar (desktop) */}
      <aside className="affiliate-sidebar">
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 8px 16px' }}>
          <div style={{ width: 36, height: 36, borderRadius: 10, background: 'var(--primary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Leaf size={20} color="#fff" />
          </div>
          <div>
            <div style={{ fontWeight: 700, fontSize: 15 }}>Energia</div>
            <div style={{ fontSize: 11.5, color: 'var(--text-muted)' }}>Affiliate Portal</div>
          </div>
        </div>
        {links}
      </aside>

      {/* Mobile header (sticky, above content) */}
      <header className="affiliate-mobile-header">
        <div className="affiliate-mobile-bar">
          <div className="affiliate-brand">
            <div style={{ width: 30, height: 30, borderRadius: 8, background: 'var(--primary)', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' }}>
              <Leaf size={17} color="#fff" />
            </div>
            <span>Energia Affiliate</span>
          </div>
          <button className="affiliate-hamburger" aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open} aria-controls="affiliate-mobile-nav" onClick={() => setOpen(v => !v)}>
            {open ? <X size={20} /> : <Menu size={20} />}
          </button>
        </div>
        {open && <nav id="affiliate-mobile-nav" className="affiliate-mobile-nav">{links}</nav>}
      </header>

      <main className="affiliate-main">
        <div className="affiliate-content">{children}</div>
      </main>
    </div>
  );
};

export default AffiliateLayout;
