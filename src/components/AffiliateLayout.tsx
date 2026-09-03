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
const AffiliateLayout: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { signOut } = useAuth();
  const nav = useNavigate();
  const [open, setOpen] = useState(false);

  const doSignOut = async () => { await signOut(); nav('/affiliate/login', { replace: true }); };

  const links = (
    <>
      {NAV.map(({ to, label, icon: Icon }) => (
        <NavLink key={to} to={to} onClick={() => setOpen(false)}
          className={({ isActive }) => 'aff-navlink' + (isActive ? ' active' : '')}
          style={({ isActive }) => ({
            display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', borderRadius: 10,
            color: isActive ? '#fff' : 'var(--text-secondary)', background: isActive ? 'var(--primary)' : 'transparent',
            fontSize: 14, fontWeight: 500, textDecoration: 'none',
          })}>
          <Icon size={18} /> {label}
        </NavLink>
      ))}
      <button className="aff-navlink" onClick={doSignOut}
        style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', borderRadius: 10,
          color: 'var(--danger)', background: 'transparent', fontSize: 14, fontWeight: 500, border: 'none', cursor: 'pointer', width: '100%' }}>
        <LogOut size={18} /> Sign Out
      </button>
    </>
  );

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg)', display: 'flex' }}>
      {/* Sidebar (desktop) */}
      <aside style={{ width: 240, borderRight: '1px solid var(--border)', background: 'var(--surface)', padding: 16,
        position: 'sticky', top: 0, height: '100vh', display: 'flex', flexDirection: 'column', gap: 6 }}
        className="aff-sidebar">
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

      {/* Mobile top bar */}
      <div className="aff-topbar" style={{ display: 'none' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 16px',
          borderBottom: '1px solid var(--border)', background: 'var(--surface)', position: 'sticky', top: 0, zIndex: 20 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ width: 30, height: 30, borderRadius: 8, background: 'var(--primary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Leaf size={17} color="#fff" />
            </div>
            <span style={{ fontWeight: 700 }}>Energia Affiliate</span>
          </div>
          <button className="btn btn-secondary" onClick={() => setOpen(v => !v)} style={{ padding: 8 }}>
            {open ? <X size={18} /> : <Menu size={18} />}
          </button>
        </div>
        {open && (
          <div style={{ padding: 12, background: 'var(--surface)', borderBottom: '1px solid var(--border)', display: 'flex', flexDirection: 'column', gap: 6 }}>
            {links}
          </div>
        )}
      </div>

      <main style={{ flex: 1, minWidth: 0 }}>
        <div style={{ maxWidth: 960, margin: '0 auto', padding: '24px 20px 64px' }}>{children}</div>
      </main>

      <style>{`
        @media (max-width: 820px) {
          .aff-sidebar { display: none !important; }
          .aff-topbar { display: block !important; width: 100%; }
          main { width: 100%; }
        }
      `}</style>
    </div>
  );
};

export default AffiliateLayout;
