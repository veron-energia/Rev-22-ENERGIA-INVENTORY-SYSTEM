import React, { Suspense } from 'react';
import { BrowserRouter, Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import { FullScreenLoader, Protected, AffiliateProtected } from './components/RouteGuards';
import { ErrorBoundary } from './components/ErrorBoundary';
import { lazyPage } from './lib/staleChunks';
// Loaded with the app, not with the reset pages: it notes whether the app was
// opened from an email link before Supabase clears the address (ADMIN-AUTH-9).
import './lib/resetSession';

/**
 * Pages are fetched when they are first opened, not when the application
 * starts. Before this, one bundle held every screen — the invoice editor,
 * the TikTok importer with its CSV parser, the spreadsheet writer, the PDF
 * builder — and a staff member waited for all of it to open the dashboard.
 * The shell below (layout, auth, the loader) stays in the first bundle so
 * there is something on screen while a page arrives.
 *
 * lazyPage (ADMIN-AUTH-8): after a deploy a page file of the old build is
 * gone; the app reloads once to pick up the new build instead of failing.
 */
const LoginPage = lazyPage(() => import('./pages/LoginPage'));
const DashboardPage = lazyPage(() => import('./pages/DashboardPage'));
const ProductsPage = lazyPage(() => import('./pages/ProductsPage'));
const WarehousesPage = lazyPage(() => import('./pages/WarehousesPage'));
const StoresPage = lazyPage(() => import('./pages/StoresPage'));
const PaymentMethodsPage = lazyPage(() => import('./pages/PaymentMethodsPage'));
const UsersPage = lazyPage(() => import('./pages/UsersPage'));
const WarehouseInventoryPage = lazyPage(() => import('./pages/WarehouseInventoryPage'));
const StoreInventoryPage = lazyPage(() => import('./pages/StoreInventoryPage'));
const TransfersPage = lazyPage(() => import('./pages/TransfersPage'));
const StockMovementsPage = lazyPage(() => import('./pages/StockMovementsPage'));
const CustomersPage = lazyPage(() => import('./pages/CustomersPage'));
const PriceListPage = lazyPage(() => import('./pages/PriceListPage'));
const CommissionsPage = lazyPage(() => import('./pages/CommissionsPage'));
const VouchersPage = lazyPage(() => import('./pages/VouchersPage'));
const PromotionsPage = lazyPage(() => import('./pages/PromotionsPage'));
const SpecialPage = lazyPage(() => import('./pages/SpecialPage'));
const EventsPage = lazyPage(() => import('./pages/EventsPage'));
const NotFoundPage = lazyPage(() => import('./pages/NotFoundPage'));
const ExchangesPage = lazyPage(() => import('./pages/ExchangesPage'));
const TherapyPage = lazyPage(() => import('./pages/TherapyPage'));
const TherapyServicesPage = lazyPage(() => import('./pages/TherapyServicesPage'));
const PublicSurveyPage = lazyPage(() => import('./pages/PublicSurveyPage'));
const SurveysPage = lazyPage(() => import('./pages/SurveysPage'));
const TikTokImportPage = lazyPage(() => import('./pages/TikTokImportPage'));
const AffiliatesPage = lazyPage(() => import('./pages/AffiliatesPage'));
const InvoicesPage = lazyPage(() => import('./pages/InvoicesPage'));
const ApprovalsPage = lazyPage(() => import('./pages/ApprovalsPage'));
const AdjustmentsPage = lazyPage(() => import('./pages/AdjustmentsPage'));
const AuditLogPage = lazyPage(() => import('./pages/AuditLogPage'));
const ReportsPage = lazyPage(() => import('./pages/ReportsPage'));
const AffiliateJoinPage = lazyPage(() => import('./pages/AffiliateJoinPage'));
const AffiliateLoginPage = lazyPage(() => import('./pages/AffiliateLoginPage'));
const AffiliateVerifyPage = lazyPage(() => import('./pages/AffiliateVerifyPage'));
const AffiliateForgotPasswordPage = lazyPage(() => import('./pages/AffiliateForgotPasswordPage'));
const AffiliateResetPasswordPage = lazyPage(() => import('./pages/AffiliateResetPasswordPage'));
const AffiliateDashboardPage = lazyPage(() => import('./pages/AffiliateDashboardPage'));
const AffiliateNetworkPage = lazyPage(() => import('./pages/AffiliateNetworkPage'));
const AffiliateEarningsPage = lazyPage(() => import('./pages/AffiliateEarningsPage'));
const AffiliatePayoutsPage = lazyPage(() => import('./pages/AffiliatePayoutsPage'));
const AffiliateReferralPage = lazyPage(() => import('./pages/AffiliateReferralPage'));
const AffiliateAccountPage = lazyPage(() => import('./pages/AffiliateAccountPage'));
const ReferralSignupPage = lazyPage(() => import('./pages/ReferralSignupPage'));
const ForgotPasswordPage = lazyPage(() => import('./pages/ForgotPasswordPage'));
const ResetPasswordPage = lazyPage(() => import('./pages/ResetPasswordPage'));
const AcceptInvitationPage = lazyPage(() => import('./pages/AcceptInvitationPage'));

// The guards (Protected, AffiliateProtected) and the loader live in
// components/RouteGuards.tsx, so they can be tested on their own.

const AppRoutes: React.FC = () => {
  const { session, loading } = useAuth();
  const location = useLocation();
  if (loading) return <FullScreenLoader />;

  // Staff pages have their own error boundary inside the menu layout, so the
  // menu stays. This one covers the pages outside it, and clears itself when
  // the address changes (ADMIN-AUTH-8).
  return (
    <ErrorBoundary resetKey={location.pathname}>
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
      <Route path="/events" element={<Protected><EventsPage /></Protected>} />
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
