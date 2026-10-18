import React, { Suspense } from 'react';
import { NavLink, useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { ROLE_LABELS, isManagerOrAbove, isOwnerOrManager } from '../types';
import { ErrorBoundary } from './ErrorBoundary';
import {
  LayoutDashboard, Package, Warehouse, Store, Users2, CreditCard,
  LogOut, Leaf, ShieldCheck, Boxes, ArrowLeftRight, History, PackageOpen,
  Users, Star, Tag, FileText, ClipboardCheck, SlidersHorizontal, ScrollText, BarChart3, Ticket, Package2, KeyRound, Repeat, Sparkles, ClipboardList, UserPlus, Menu, X , Upload, PartyPopper, RefreshCw } from 'lucide-react';

// Below this width the menu is a drawer that slides in (globals.css).
const DRAWER_QUERY = '(max-width: 900px)';

function useIsDrawer(): boolean {
  const query = () => typeof window !== 'undefined' && typeof window.matchMedia === 'function'
    && window.matchMedia(DRAWER_QUERY).matches;
  const [drawer, setDrawer] = React.useState(query);
  React.useEffect(() => {
    if (typeof window.matchMedia !== 'function') return;
    const list = window.matchMedia(DRAWER_QUERY);
    const onChange = () => setDrawer(list.matches);
    list.addEventListener?.('change', onChange);
    return () => list.removeEventListener?.('change', onChange);
  }, []);
  return drawer;
}

interface NavItem {
  to: string;
  label: string;
  icon: React.ReactNode;
  show: boolean;
}

const AppLayout: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { profile, signOut } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const role = profile?.role;
  const isDrawer = useIsDrawer();
  const sidebarRef = React.useRef<HTMLElement | null>(null);

  const handleSignOut = async () => {
    await signOut();
    navigate('/login');
  };

  const mainNav: NavItem[] = [
    { to: '/', label: 'Dashboard', icon: <LayoutDashboard size={17} />, show: true },
    { to: '/products', label: 'Products', icon: <Package size={17} />, show: true },
  ];

  const inventoryNav: NavItem[] = [
    { to: '/warehouse-inventory', label: 'Warehouse Stock', icon: <Boxes size={17} />, show: isManagerOrAbove(role) || role === 'inventory_manager' },
    { to: '/store-inventory', label: 'Store Stock', icon: <PackageOpen size={17} />, show: true },
    { to: '/transfers', label: 'Transfers', icon: <ArrowLeftRight size={17} />, show: true },
    { to: '/stock-movements', label: 'Stock History', icon: <History size={17} />, show: isManagerOrAbove(role) || role === 'inventory_manager' || role === 'staff' },
    { to: '/special', label: 'Special & Rentals', icon: <KeyRound size={17} />, show: isOwnerOrManager(role) },
  ];

  const salesNav: NavItem[] = [
    { to: '/invoices', label: 'Invoices', icon: <FileText size={17} />, show: true },
    { to: '/tiktok-import', label: 'TikTok Sales Import', icon: <Upload size={17} />, show: true },
    { to: '/exchanges', label: 'Exchanges', icon: <Repeat size={17} />, show: true },
    { to: '/events', label: 'Events', icon: <PartyPopper size={17} />, show: isManagerOrAbove(role) || role === 'staff' },
    { to: '/therapy', label: 'Therapy', icon: <Sparkles size={17} />, show: true },
    { to: '/therapy-services', label: 'Therapy Services', icon: <Sparkles size={17} />, show: isManagerOrAbove(role) },
    // Health data is not for Inventory Managers, as the server already rules
    // for the survey detail and consultant notes (CUSTOMERS-M2).
    { to: '/surveys', label: 'Health Surveys', icon: <ClipboardList size={17} />, show: role !== 'inventory_manager' },
    { to: '/customers', label: 'Customers', icon: <Users size={17} />, show: true },
    { to: '/affiliates', label: 'Affiliates', icon: <UserPlus size={17} />, show: true },
    { to: '/commissions', label: 'Commissions', icon: <Star size={17} />, show: isManagerOrAbove(role) },
    { to: '/price-list', label: 'Price List', icon: <Tag size={17} />, show: isOwnerOrManager(role) },
    { to: '/vouchers', label: 'Vouchers', icon: <Ticket size={17} />, show: isOwnerOrManager(role) },
    { to: '/promotions', label: 'Promotions', icon: <Package2 size={17} />, show: isOwnerOrManager(role) },
  ];

  const controlsNav: NavItem[] = [
    { to: '/approvals', label: 'Approvals', icon: <ClipboardCheck size={17} />, show: isOwnerOrManager(role) },
    { to: '/adjustments', label: 'Adjustments', icon: <SlidersHorizontal size={17} />, show: true },
    { to: '/reports', label: 'Reports', icon: <BarChart3 size={17} />, show: isManagerOrAbove(role) },
    { to: '/audit-log', label: 'Audit Log', icon: <ScrollText size={17} />, show: isManagerOrAbove(role) },
  ];

  const setupNav: NavItem[] = [
    { to: '/warehouses', label: 'Warehouses', icon: <Warehouse size={17} />, show: isManagerOrAbove(role) },
    { to: '/stores', label: 'Stores', icon: <Store size={17} />, show: true },
    { to: '/payment-methods', label: 'Payment Methods', icon: <CreditCard size={17} />, show: isOwnerOrManager(role) },
  ];

  const adminNav: NavItem[] = [
    { to: '/users', label: 'Users & Roles', icon: <Users2 size={17} />, show: isOwnerOrManager(role) },
  ];

  const linkStyle = ({ isActive }: { isActive: boolean }): React.CSSProperties => ({
    display: 'flex', alignItems: 'center', gap: 11, padding: '9px 12px',
    borderRadius: 'var(--radius-sm)', fontSize: 13.5, fontWeight: 500,
    color: isActive ? 'var(--primary)' : 'var(--text-secondary)',
    background: isActive ? 'var(--primary-light)' : 'transparent',
    marginBottom: 2,
  });

  const renderSection = (label: string, items: NavItem[]) => {
    const visible = items.filter(i => i.show);
    if (visible.length === 0) return null;
    return (
      <div style={{ marginBottom: 18 }}>
        <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: 'var(--text-muted)', padding: '0 12px', marginBottom: 7 }}>
          {label}
        </div>
        {visible.map(i => (
          <NavLink key={i.to} to={i.to} style={linkStyle} end={i.to === '/'}>
            {i.icon} {i.label}
          </NavLink>
        ))}
      </div>
    );
  };

  const [mobileOpen, setMobileOpen] = React.useState(false);

  // A closed drawer is off screen, but its links could still be reached with
  // the keyboard or a screen reader. inert takes it out of both until it opens
  // (ADMIN-AUTH-18). Set on the element, as React 18 does not know the
  // attribute. On a wide screen the menu is always shown and never inert.
  const hidden = isDrawer && !mobileOpen;
  React.useEffect(() => {
    const el = sidebarRef.current;
    if (!el) return;
    if (hidden) el.setAttribute('inert', ''); else el.removeAttribute('inert');
  }, [hidden]);

  return (
    <div className="app-shell">
      {/* Mobile top bar */}
      <div className="mobile-topbar">
        <button className="btn btn-secondary btn-sm btn-icon" onClick={() => setMobileOpen(o => !o)}
                aria-label="Menu" aria-expanded={mobileOpen} aria-controls="app-sidebar">
          {mobileOpen ? <X size={18} /> : <Menu size={18} />}
        </button>
        <strong style={{ fontSize: 15 }}>Energia</strong>
      </div>
      {mobileOpen && <div className="sidebar-backdrop" onClick={() => setMobileOpen(false)} />}
      {/* Sidebar */}
      <aside id="app-sidebar" ref={sidebarRef} aria-label="Main menu"
             className={`sidebar ${mobileOpen ? 'open' : ''}`} onClick={() => setMobileOpen(false)}>
        <div style={{ padding: '20px 18px', borderBottom: '1px solid var(--border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 34, height: 34, borderRadius: 9, background: 'var(--primary)' }}>
              <Leaf size={18} color="#fff" />
            </div>
            <div>
              <div style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 16, color: 'var(--primary)' }}>Energia</div>
              <div style={{ fontSize: 10.5, color: 'var(--text-muted)' }}>Inventory &amp; Sales</div>
            </div>
          </div>
        </div>

        <nav style={{ flex: 1, padding: '18px 12px', overflowY: 'auto' }}>
          {renderSection('Main', mainNav)}
          {renderSection('Inventory', inventoryNav)}
          {renderSection('Sales', salesNav)}
          {renderSection('Controls', controlsNav)}
          {renderSection('Setup', setupNav)}
          {renderSection('Administration', adminNav)}
        </nav>

        {/* User footer */}
        <div style={{ padding: 14, borderTop: '1px solid var(--border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10, padding: '0 4px' }}>
            <div style={{ width: 34, height: 34, borderRadius: '50%', background: 'var(--primary-light)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--primary)', fontWeight: 700, fontSize: 14, flexShrink: 0 }}>
              {profile?.full_name?.[0]?.toUpperCase() ?? '?'}
            </div>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{profile?.full_name}</div>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}>
                <ShieldCheck size={11} /> {role ? ROLE_LABELS[role] : ''}
              </div>
            </div>
          </div>
          <button className="btn btn-secondary btn-sm" onClick={handleSignOut} style={{ width: '100%' }}>
            <LogOut size={14} /> Sign out
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main style={{ flex: 1, minWidth: 0 }}>
        <div className="app-main" style={{ maxWidth: 1200, margin: '0 auto' }}>
          {/* ADMIN-AUTH-8: a page that fails (a file gone after a deploy, a
              render fault) is replaced on its own; the menu stays, and going
              to another page starts afresh. A page still loading shows here
              too, under the menu. */}
          <ErrorBoundary key={location.pathname} label="this page">
            <Suspense fallback={
              <div className="empty-state" role="status">
                <RefreshCw size={24} className="spin" style={{ opacity: 0.4 }} aria-hidden="true" />
                <p style={{ marginTop: 8 }}>Loading…</p>
              </div>}>
              {children}
            </Suspense>
          </ErrorBoundary>
        </div>
      </main>
    </div>
  );
};

export default AppLayout;
