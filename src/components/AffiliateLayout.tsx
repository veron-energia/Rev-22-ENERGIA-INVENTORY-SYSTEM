import React, { useState } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Leaf, LayoutDashboard, Users, TrendingUp, Wallet, QrCode, UserCircle, ScrollText, LogOut, Menu, X } from 'lucide-react';
import VerifyEmailBanner from './VerifyEmailBanner';
import AffiliatePortalNotice from './AffiliatePortalNotice';
import { usePortalAccess } from '../lib/affiliatePortalAccess';

const NAV = [
  { to: '/affiliate/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/affiliate/network', label: 'My Network', icon: Users },
  { to: '/affiliate/earnings', label: 'Earnings', icon: TrendingUp },
  { to: '/affiliate/payouts', label: 'Payouts', icon: Wallet },
  { to: '/affiliate/referral', label: 'My Referral QR', icon: QrCode },
  { to: '/affiliate/account', label: 'Account', icon: UserCircle },
  { to: '/affiliate/rules', label: 'Rules', icon: ScrollText },
];

// Standalone portal shell — Energia styling, NO staff/POS navigation.
// Layout is CSS-driven (.affiliate-* in globals.css): a row on desktop with a
// sidebar, a stacked column on mobile with a sticky header above the content.
// Above each page, the warning while the email is not verified (3 Nov 2026);
// the Account page leaves it out, as it has its own Verify your email.
//
// What the page may show (the Owner, 17 Nov 2026; affiliatePortalAccess.ts):
//   shows 'record'  the record's referrals, earnings or payouts (Dashboard,
//                   My Network, Earnings, Payouts): a login whose link is not
//                   confirmed yet (508) sees the "checking" notice instead;
//   shows 'own'     the login's own details and referral link (Account, My
//                   Referral QR): the "checking" notice above the page;
//   shows 'public'  the Rules, which anyone may read.
// A suspended affiliate (509) sees the "suspended" notice and nothing else on
// every page but the Rules, and only Rules and Sign Out in the menu.
const AffiliateLayout: React.FC<{ children: React.ReactNode; verifyEmailBanner?: boolean; shows?: 'record' | 'own' | 'public' }> = ({ children, verifyEmailBanner = true, shows = 'record' }) => {
  const { signOut, session } = useAuth();
  const nav = useNavigate();
  const [open, setOpen] = useState(false);
  const access = usePortalAccess(session?.user?.id ?? null);
  const closed = access === 'suspended';

  const doSignOut = async () => { setOpen(false); await signOut(); nav('/affiliate/login', { replace: true }); };

  const links = (
    <>
      {(closed ? NAV.filter(n => n.to === '/affiliate/rules') : NAV).map(({ to, label, icon: Icon }) => (
        <NavLink key={to} to={to} onClick={() => setOpen(false)}
          className={({ isActive }) => 'portal-navlink' + (isActive ? ' active' : '')}>
          <Icon size={18} /> {label}
        </NavLink>
      ))}
      <button className="portal-navlink danger" onClick={doSignOut}>
        <LogOut size={18} /> Sign Out
      </button>
    </>
  );

  return (
    <div className="portal-shell">
      {/* Sidebar (desktop) */}
      <nav className="portal-sidebar" aria-label="Affiliate portal">
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
      </nav>

      {/* Mobile header (sticky, above content) */}
      <header className="portal-mobile-header">
        <div className="portal-mobile-bar">
          <div className="portal-brand">
            <div style={{ width: 30, height: 30, borderRadius: 8, background: 'var(--primary)', display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' }}>
              <Leaf size={17} color="#fff" />
            </div>
            <span>Energia Affiliate</span>
          </div>
          <button className="portal-hamburger" aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open} aria-controls="portal-mobile-nav" onClick={() => setOpen(v => !v)}>
            {open ? <X size={20} /> : <Menu size={20} />}
          </button>
        </div>
        {open && <nav id="portal-mobile-nav" className="portal-mobile-nav">{links}</nav>}
      </header>

      <main className="portal-main">
        <div className="portal-content">
          {verifyEmailBanner && !closed && <VerifyEmailBanner />}
          {shows === 'public' ? children
            // the first page opened: its own read waits for this one
            : access === null ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p>
            : closed ? <AffiliatePortalNotice kind="suspended" />
            : access === 'unproven' && shows === 'record' ? <AffiliatePortalNotice kind="checking" />
            : access === 'unproven' ? <><AffiliatePortalNotice kind="checking" />{children}</>
            : children}
        </div>
      </main>
    </div>
  );
};

export default AffiliateLayout;
