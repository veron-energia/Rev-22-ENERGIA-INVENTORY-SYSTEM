// A stand-in for src/context/AuthContext: ?role=staff|manager|owner (default owner).
import React from 'react';
const role = new URLSearchParams(location.search).get('role') ?? 'owner';
export const useAuth = () => ({
  profile: { id: `u-${role}`, full_name: `Preview ${role}`, role, is_active: true },
  session: { user: { id: `u-${role}` } }, actorType: 'staff', assignments: [{ user_id: `u-${role}`, store_id: 'st-main' }],
  user: null, loading: false, error: null,
  signIn: async () => {}, signOut: async () => {}, refreshProfile: async () => {},
}) as any;
export const AuthProvider = ({ children }: { children: React.ReactNode }) => <>{children}</>;
