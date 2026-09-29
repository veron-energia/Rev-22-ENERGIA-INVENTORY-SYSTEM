// A stand-in for src/context/AuthContext, used only by the preview harness.
// ?role=staff|manager|owner picks who is signed in (default: manager). The
// supabase stub reads the same parameter, so the server's answers match.
import React from 'react';

export const PREVIEW_USERS = {
  owner: { id: 'u-owner', full_name: 'Preview Owner', role: 'owner' },
  manager: { id: 'u-manager', full_name: 'Preview Manager', role: 'manager' },
  staff: { id: 'u-staff', full_name: 'Staff One', role: 'staff' },
} as const;

export function previewRole(): keyof typeof PREVIEW_USERS {
  const r = new URLSearchParams(typeof location === 'undefined' ? '' : location.search).get('role');
  return r === 'owner' || r === 'staff' ? r : 'manager';
}

const profile = { ...PREVIEW_USERS[previewRole()], is_active: true, deleted_at: null };

export const useAuth = () => ({
  profile, session: null, actorType: 'staff', affiliateAccount: null, assignments: [], loading: false, error: null,
  signIn: async () => ({ error: null }), signOut: async () => {}, refreshProfile: async () => {},
}) as any;
export const AuthProvider = ({ children }: { children: React.ReactNode }) => <>{children}</>;
