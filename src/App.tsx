import React, { Suspense } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import AppLayout from './components/AppLayout';
import AffiliateAuthShell from './components/AffiliateAuthShell';

/**
 * Pages are fetched when they are first opened, not when the application
 * starts. Before this, one bundle held every screen — the invoice editor,
 * the TikTok importer with its CSV parser, the spreadsheet writer, the PDF
 * builder — and a staff member waited for all of it to open the dashboard.
 * The shell below (layout, auth, the loader) stays in the first bundle so
 * there is something on screen while a page arrives.
 */
const LoginPage = React.lazy(() => import('./pages/LoginPage'));
const DashboardPage = React.lazy(() => import('./pages/DashboardPage'));
const ProductsPage = React.lazy(() => import('./pages/ProductsPage'));
const WarehousesPage = React.lazy(() => import('./pages/WarehousesPage'));
const StoresPage = React.lazy(() => import('./pages/StoresPage'));
const PaymentMethodsPage = React.lazy(() => import('./pages/PaymentMethodsPage'));
const UsersPage = React.lazy(() => import('./pages/UsersPage'));
const WarehouseInventoryPage = React.lazy(() => import('./pages/WarehouseInventoryPage'));
const StoreInventoryPage = React.lazy(() => import('./pages/StoreInventoryPage'));
const TransfersPage = React.lazy(() => import('./pages/TransfersPage'));
const StockMovementsPage = React.lazy(() => import('./pages/StockMovementsPage'));
const CustomersPage = React.lazy(() => import('./pages/CustomersPage'));
const PriceListPage = React.lazy(() => import('./pages/PriceListPage'));
const CommissionsPage = React.lazy(() => import('./pages/CommissionsPage'));
const VouchersPage = React.lazy(() => import('./pages/VouchersPage'));
const PromotionsPage = React.lazy(() => import('./pages/PromotionsPage'));
const SpecialPage = React.lazy(() => import('./pages/SpecialPage'));
const StaffCommissionsPage = React.lazy(() => import('./pages/StaffCommissionsPage'));
const NotFoundPage = React.lazy(() => import('./pages/NotFoundPage'));
const ExchangesPage = React.lazy(() => import('./pages/ExchangesPage'));
const TherapyPage = React.lazy(() => import('./pages/TherapyPage'));
const TherapyServicesPage = React.lazy(() => import('./pages/TherapyServicesPage'));
const PublicSurveyPage = React.lazy(() => import('./pages/PublicSurveyPage'));
const SurveysPage = React.lazy(() => import('./pages/SurveysPage'));
const TikTokImportPage = React.lazy(() => import('./pages/TikTokImportPage'));
const AffiliatesPage = React.lazy(() => import('./pages/AffiliatesPage'));
const InvoicesPage = React.lazy(() => import('./pages/InvoicesPage'));
const ApprovalsPage = React.lazy(() => import('./pages/ApprovalsPage'));
const AdjustmentsPage = React.lazy(() => import('./pages/AdjustmentsPage'));
const AuditLogPage = React.lazy(() => import('./pages/AuditLogPage'));
const ReportsPage = React.lazy(() => import('./pages/ReportsPage'));
const AffiliateJoinPage = React.lazy(() => import('./pages/AffiliateJoinPage'));
const AffiliateLoginPage = React.lazy(() => import('./pages/AffiliateLoginPage'));
const AffiliateVerifyPage = React.lazy(() => import('./pages/AffiliateVerifyPage'));
const AffiliateForgotPasswordPage = React.lazy(() => import('./pages/AffiliateForgotPasswordPage'));
const AffiliateResetPasswordPage = React.lazy(() => import('./pages/AffiliateResetPasswordPage'));
const AffiliateDashboardPage = React.lazy(() => import('./pages/AffiliateDashboardPage'));
const AffiliateNetworkPage = React.lazy(() => import('./pages/AffiliateNetworkPage'));
const AffiliateEarningsPage = React.lazy(() => import('./pages/AffiliateEarningsPage'));
const AffiliatePayoutsPage = React.lazy(() => import('./pages/AffiliatePayoutsPage'));
const AffiliateReferralPage = React.lazy(() => import('./pages/AffiliateReferralPage'));
const AffiliateAccountPage = React.lazy(() => import('./pages/AffiliateAccountPage'));
const ReferralSignupPage = React.lazy(() => import('./pages/ReferralSignupPage'));
const ForgotPasswordPage = React.lazy(() => import('./pages/ForgotPasswordPage'));
const ResetPasswordPage = React.lazy(() => import('./pages/ResetPasswordPage'));
const AcceptInvitationPage = React.lazy(() => import('./pages/AcceptInvitationPage'));
import { Leaf } from 'lucide-react';
import { ErrorBoundary } from './components/ErrorBoundary';

const FullScreenLoader: React.FC<{ message?: string }> = ({ message }) => (
  <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 16, background: 'var(--bg)' }}>
    <div style={{ display: 'inline-flex', width: 48, height: 48, borderRadius: 13, background: 'var(--primary)', alignItems: 'center', justifyContent: 'center' }} className="spin">
      <Leaf size={24} color="#fff" />
    </div>
    <p style={{ color: 'var(--text-muted)', fontSize: 14 }}>{message ?? 'Loading…'}</p>
  </div>
);

// Staff-only guard. Affiliates are redirected to their portal; a session with
// neither identity gets a friendly setup state (never the staff "profile" error).
const Protected: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { session, actorType, profile, loading, error, signOut } = useAuth();

  if (loading) return <FullScreenLoader />;
  if (!session) return <Navigate to="/login" replace />;
  if (actorType === 'affiliate') return <Navigate to="/affiliate/dashboard" replace />;

  if (!profile) {
    return (
      <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
        <div className="card" style={{ padding: 32, maxWidth: 440, textAlign: 'center' }}>
          <h3 style={{ marginBottom: 10 }}>Account setup needed</h3>
          <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 18 }}>
            {error ?? 'Your login works, but it is not yet linked to a Staff or Affiliate account. Please contact Energia.'}
          </p>
          <button className="btn btn-secondary" onClick={() => signOut()}>Sign out</button>
        </div>
      </div>
    );
  }
  return <AppLayout>{children}</AppLayout>;
};

// Affiliate-only guard. Staff are sent to the staff app; unauthenticated to the
// affiliate login. Not-yet-onboarded sessions go to the verify/onboarding flow.
const AffiliateProtected: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { session, actorType, loading, error, refreshProfile } = useAuth();
  if (loading) return <FullScreenLoader />;
  if (!session) return <Navigate to="/affiliate/login" replace />;
  if (actorType === 'staff') return <Navigate to="/" replace />;
  // A lookup that failed is not an account that does not exist. Sending the
  // person on to /affiliate/verify here is how an existing affiliate on a poor
  // phone connection was asked to "confirm their details" again.
  if (actorType !== 'affiliate' && error) return (
    <AffiliateAuthShell title="Could not load your account">
      <p role="alert" style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>{error}</p>
      <button type="button" className="btn btn-primary" style={{ width: '100%', marginTop: 14 }} onClick={() => void refreshProfile()}>Try again</button>
    </AffiliateAuthShell>
  );
  if (actorType !== 'affiliate') return <Navigate to="/affiliate/verify" replace />;
  return <>{children}</>;
};

const AppRoutes: React.FC = () => {
  const { session, loading } = useAuth();
  if (loading) return <FullScreenLoader />;

  return (
    <ErrorBoundary>
    <Suspense fallback={<FullScreenLoader />}>
    <Routes>
      {/* Public: no login required (QR survey) */}
      <Route path="/survey/:token" element={<PublicSurveyPage />} />
      {/* Public affiliate auth + referral signup */}
      <Route path="/affiliate/join" element={<AffiliateJoinPage />} />
      <Route path="/affiliate/login" element={<AffiliateLoginPage />} />
      <Route path="/affiliate/verify" element={<AffiliateVerifyPage />} />
      <Route path="/affiliate/forgot-password" element={<AffiliateForgotPasswordPage />} />
      <Route path="/affiliate/reset-password" element={<AffiliateResetPasswordPage />} />
      <Route path="/r/:referralCode" element={<ReferralSignupPage />} />
      {/* Public staff password recovery. The reset page needs no session of its
          own: Supabase turns the emailed link into a recovery session on arrival. */}
      <Route path="/forgot-password" element={<ForgotPasswordPage />} />
      <Route path="/reset-password" element={<ResetPasswordPage />} />
      {/* Where an internal user's invitation link lands. Public, because they
          have no account until they finish here. */}
      <Route path="/accept-invitation" element={<AcceptInvitationPage />} />
      {/* Authenticated affiliate portal */}
      <Route path="/affiliate/dashboard" element={<AffiliateProtected><AffiliateDashboardPage /></AffiliateProtected>} />
      <Route path="/affiliate/network" element={<AffiliateProtected><AffiliateNetworkPage /></AffiliateProtected>} />
      <Route path="/affiliate/earnings" element={<AffiliateProtected><AffiliateEarningsPage /></AffiliateProtected>} />
      <Route path="/affiliate/payouts" element={<AffiliateProtected><AffiliatePayoutsPage /></AffiliateProtected>} />
      <Route path="/affiliate/referral" element={<AffiliateProtected><AffiliateReferralPage /></AffiliateProtected>} />
      <Route path="/affiliate/account" element={<AffiliateProtected><AffiliateAccountPage /></AffiliateProtected>} />
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
      <Route path="/price-list" element={<Protected><PriceListPage /></Protected>} />
      <Route path="/invoices" element={<Protected><InvoicesPage /></Protected>} />
      <Route path="/commissions" element={<Protected><CommissionsPage /></Protected>} />
      <Route path="/vouchers" element={<Protected><VouchersPage /></Protected>} />
      <Route path="/promotions" element={<Protected><PromotionsPage /></Protected>} />
      <Route path="/special" element={<Protected><SpecialPage /></Protected>} />
      <Route path="/staff-commissions" element={<Protected><StaffCommissionsPage /></Protected>} />
      <Route path="/exchanges" element={<Protected><ExchangesPage /></Protected>} />
      <Route path="/therapy" element={<Protected><TherapyPage /></Protected>} />
      <Route path="/therapy-services" element={<Protected><TherapyServicesPage /></Protected>} />
      <Route path="/surveys" element={<Protected><SurveysPage /></Protected>} />
      <Route path="/tiktok-import" element={<Protected><TikTokImportPage /></Protected>} />
      <Route path="/affiliates" element={<Protected><AffiliatesPage /></Protected>} />
      <Route path="/approvals" element={<Protected><ApprovalsPage /></Protected>} />
      <Route path="/adjustments" element={<Protected><AdjustmentsPage /></Protected>} />
      <Route path="/audit-log" element={<Protected><AuditLogPage /></Protected>} />
      <Route path="/reports" element={<Protected><ReportsPage /></Protected>} />
      <Route path="/payment-methods" element={<Protected><PaymentMethodsPage /></Protected>} />
      <Route path="/users" element={<Protected><UsersPage /></Protected>} />
      <Route path="*" element={<NotFoundPage />} />
    </Routes>
    </Suspense>
    </ErrorBoundary>
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
