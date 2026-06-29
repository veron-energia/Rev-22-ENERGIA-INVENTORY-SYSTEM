import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import AppLayout from './components/AppLayout';
import LoginPage from './pages/LoginPage';
import DashboardPage from './pages/DashboardPage';
import ProductsPage from './pages/ProductsPage';
import WarehousesPage from './pages/WarehousesPage';
import StoresPage from './pages/StoresPage';
import PaymentMethodsPage from './pages/PaymentMethodsPage';
import UsersPage from './pages/UsersPage';
import WarehouseInventoryPage from './pages/WarehouseInventoryPage';
import StoreInventoryPage from './pages/StoreInventoryPage';
import TransfersPage from './pages/TransfersPage';
import StockMovementsPage from './pages/StockMovementsPage';
import CustomersPage from './pages/CustomersPage';
import AffiliatesPage from './pages/AffiliatesPage';
import PriceListPage from './pages/PriceListPage';
import InvoicesPage from './pages/InvoicesPage';
import ApprovalsPage from './pages/ApprovalsPage';
import AdjustmentsPage from './pages/AdjustmentsPage';
import AuditLogPage from './pages/AuditLogPage';
import ReportsPage from './pages/ReportsPage';
import { Leaf } from 'lucide-react';

const FullScreenLoader: React.FC<{ message?: string }> = ({ message }) => (
  <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 16, background: 'var(--bg)' }}>
    <div style={{ display: 'inline-flex', width: 48, height: 48, borderRadius: 13, background: 'var(--primary)', alignItems: 'center', justifyContent: 'center' }} className="spin">
      <Leaf size={24} color="#fff" />
    </div>
    <p style={{ color: 'var(--text-muted)', fontSize: 14 }}>{message ?? 'Loading…'}</p>
  </div>
);

// Wraps protected routes — requires a session AND a valid profile.
const Protected: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { session, profile, loading, error, signOut } = useAuth();

  if (loading) return <FullScreenLoader />;
  if (!session) return <Navigate to="/login" replace />;

  // Session exists but no profile (e.g. profile row not created yet).
  if (!profile) {
    return (
      <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
        <div className="card" style={{ padding: 32, maxWidth: 440, textAlign: 'center' }}>
          <h3 style={{ marginBottom: 10 }}>Profile not found</h3>
          <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 18 }}>
            {error ?? 'Your login works, but no profile record is linked to it yet.'}
          </p>
          <button className="btn btn-secondary" onClick={() => signOut()}>Sign out</button>
        </div>
      </div>
    );
  }

  return <AppLayout>{children}</AppLayout>;
};

const AppRoutes: React.FC = () => {
  const { session, loading } = useAuth();
  if (loading) return <FullScreenLoader />;

  return (
    <Routes>
      <Route path="/login" element={session ? <Navigate to="/" replace /> : <LoginPage />} />
      <Route path="/" element={<Protected><DashboardPage /></Protected>} />
      <Route path="/products" element={<Protected><ProductsPage /></Protected>} />
      <Route path="/warehouses" element={<Protected><WarehousesPage /></Protected>} />
      <Route path="/stores" element={<Protected><StoresPage /></Protected>} />
      <Route path="/warehouse-inventory" element={<Protected><WarehouseInventoryPage /></Protected>} />
      <Route path="/store-inventory" element={<Protected><StoreInventoryPage /></Protected>} />
      <Route path="/transfers" element={<Protected><TransfersPage /></Protected>} />
      <Route path="/stock-movements" element={<Protected><StockMovementsPage /></Protected>} />
      <Route path="/customers" element={<Protected><CustomersPage /></Protected>} />
      <Route path="/affiliates" element={<Protected><AffiliatesPage /></Protected>} />
      <Route path="/price-list" element={<Protected><PriceListPage /></Protected>} />
      <Route path="/invoices" element={<Protected><InvoicesPage /></Protected>} />
      <Route path="/approvals" element={<Protected><ApprovalsPage /></Protected>} />
      <Route path="/adjustments" element={<Protected><AdjustmentsPage /></Protected>} />
      <Route path="/audit-log" element={<Protected><AuditLogPage /></Protected>} />
      <Route path="/reports" element={<Protected><ReportsPage /></Protected>} />
      <Route path="/payment-methods" element={<Protected><PaymentMethodsPage /></Protected>} />
      <Route path="/users" element={<Protected><UsersPage /></Protected>} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
};

const App: React.FC = () => (
  <AuthProvider>
    <BrowserRouter>
      <AppRoutes />
    </BrowserRouter>
  </AuthProvider>
);

export default App;
