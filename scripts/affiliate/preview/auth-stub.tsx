// Stand-in for src/context/AuthContext, used only by the preview harness so the
// real AffiliateLayout can be rendered at real widths without a login.
import React from 'react';
export const useAuth = () => ({ signOut: async () => {} });
export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => <>{children}</>;
