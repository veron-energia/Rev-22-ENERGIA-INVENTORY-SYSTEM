// Stand-in for src/context/AuthContext, used only by the preview harness so the
// real Therapy page renders without a login: as an Owner, or as the role a
// page test sets in globalThis.__THERAPY_PREVIEW_ROLE (422: staff hand reward
// vouchers over too).
import React from 'react';
export const useAuth = () => ({
  profile: { id: 'me', role: ((globalThis as any).__THERAPY_PREVIEW_ROLE ?? 'owner'), full_name: 'Preview User' },
  signOut: async () => {},
});
export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => <>{children}</>;
