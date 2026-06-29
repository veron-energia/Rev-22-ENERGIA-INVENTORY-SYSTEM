import React from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { ROLE_LABELS, isManagerOrAbove, isOwnerOrManager, isOwnerOrAdmin, canManageWarehouseStock } from '../types';
import {
  LayoutDashboard, Package, Warehouse, Store, Users2, CreditCard,
  LogOut, Leaf, ShieldCheck, Boxes, ArrowLeftRight, History, PackageOpen,
  Users, Star, Tag, FileText, ClipboardCheck, SlidersHorizontal, ScrollText, BarChart3,
} from 'lucide-react';

interface NavItem {
  to: string;
  label: string;
  icon: React.ReactNode;
  show: boolean;
}

const AppLayout: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { profile, signOut } = useAuth();
  const navigate = useNavigate();
  const role = profile?.role;

  const handleSignOut = async () => {
    await signOut();
    navigate('/login');
  };

  // Phase 1 navigation. Later phases add Inventory, Transfers, Invoices, etc.
  const mainNav: NavItem[] = [
    { to: '/', label: 'Dashboard', icon: <LayoutDashboard size={17} />, show: true },
    { to: '/products', label: 'Products', icon: <Package size={17} />, show: true },
  ];

  const inventoryNav: NavItem[] = [
    { to: '/warehouse-inventory', label: 'Warehouse Stock', icon: <Boxes size={17} />, show: isManagerOrAbove(role) || role === 'inventory_manager' },
    { to: '/store-inventory', label: 'Store Stock', icon: <PackageOpen size={17} />, show: true },
    { to: '/transfers', label: 'Transfers', icon: <ArrowLeftRight size={17} />, show: true },
    { to: '/stock-movements', label: 'Stock History', icon: <History size={17} />, show: isManagerOrAbove(role) || role === 'inventory_manager' },
  ];

  const salesNav: NavItem[] = [
    { to: '/invoices', label: 'Invoices', icon: <FileText size={17} />, show: true },
    { to: '/customers', label: 'Customers', icon: <Users size={17} />, show: true },
    { to: '/affiliates', label: 'Affiliates', icon: <Star size={17} />, show: isManagerOrAbove(role) },
    { to: '/price-list', label: 'Price List', icon: <Tag size={17} />, show: isOwnerOrManager(role) },
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

  return (
    <div style={{ display: 'flex', minHeight: '100vh' }}>
      {/* Sidebar */}
      <aside style={{ width: 240, background: 'var(--surface)', borderRight: '1px solid var(--border)', display: 'flex', flexDirection: 'column', position: 'sticky', top: 0, height: '100vh' }}>
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
        <div style={{ maxWidth: 1200, margin: '0 auto', padding: '32px 36px' }}>
          {children}
        </div>
      </main>
    </div>
  );
};

export default AppLayout;
