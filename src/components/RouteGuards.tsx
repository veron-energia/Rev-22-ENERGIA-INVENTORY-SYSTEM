import React, { useState } from 'react';
import { Navigate } from 'react-router-dom';
import { Leaf } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import AppLayout from './AppLayout';
import AffiliateAuthShell from './AffiliateAuthShell';

/** The loader shown while the app or a signed-in account is being read. */
export const FullScreenLoader: React.FC<{ message?: string }> = ({ message }) => (
  <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 16, background: 'var(--bg)' }}>
    <div style={{ display: 'inline-flex', width: 48, height: 48, borderRadius: 13, background: 'var(--primary)', alignItems: 'center', justifyContent: 'center' }} className="spin">
      <Leaf size={24} color="#fff" />
    </div>
    <p style={{ color: 'var(--text-muted)', fontSize: 14 }} role="status">{message ?? 'Loading…'}</p>
  </div>
);

// Staff-only guard. Affiliates are redirected to their portal; a session with
// neither identity gets a friendly setup state (never the staff "profile" error).
export const Protected: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { session, actorType, profile, loading, resolving, error, signOut, refreshProfile } = useAuth();
  const [retrying, setRetrying] = useState(false);

  // ADMIN-AUTH-14: while a new sign-in's account is read, the loader shows.
  // Before, every staff sign-in flashed "Account setup needed".
  if (loading || resolving) return <FullScreenLoader />;
  if (!session) return <Navigate to="/login" replace />;
  if (actorType === 'affiliate') return <Navigate to="/affiliate/dashboard" replace />;

  if (!profile) {
    const retry = async () => {
      setRetrying(true);
      try { await refreshProfile(); } finally { setRetrying(false); }
    };
    return (
      <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
        <div className="card" style={{ padding: 32, maxWidth: 440, textAlign: 'center' }}>
          <h3 style={{ marginBottom: 10 }}>Account setup needed</h3>
          <p role="alert" style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 18 }}>
            {error ?? 'Your login works, but it is not yet linked to a Staff or Affiliate account. Please contact Energia.'}
          </p>
          <div style={{ display: 'flex', gap: 8, justifyContent: 'center', flexWrap: 'wrap' }}>
            {/* A connection blip is the commonest cause; trying again is better than signing out. */}
            <button className="btn btn-primary" onClick={() => void retry()} disabled={retrying}>
              {retrying ? 'Trying…' : 'Try again'}
            </button>
            <button className="btn btn-secondary" onClick={() => signOut()}>Sign out</button>
          </div>
        </div>
      </div>
    );
  }
  return <AppLayout>{children}</AppLayout>;
};

// Affiliate-only guard. Staff are sent to the staff app; unauthenticated to the
// affiliate login. Not-yet-onboarded sessions go to the verify/onboarding flow.
export const AffiliateProtected: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { session, actorType, loading, resolving, error, refreshProfile } = useAuth();
  if (loading || resolving) return <FullScreenLoader />;
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
