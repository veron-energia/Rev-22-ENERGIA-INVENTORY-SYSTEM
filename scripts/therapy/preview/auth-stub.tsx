// Stand-in for src/context/AuthContext, used only by the preview harness so the
// real Therapy page renders as an Owner without a login.
import React from 'react';
export const useAuth = () => ({ profile: { id: 'me', role: 'owner', full_name: 'Preview Owner' }, signOut: async () => {} });
export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => <>{children}</>;
