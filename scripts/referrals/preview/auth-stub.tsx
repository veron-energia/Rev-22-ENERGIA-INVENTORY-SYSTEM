// Stand-in for src/context/AuthContext, used only by the 398 preview: the
// signed-in role comes from ?role= (owner, manager, staff).
import React from 'react';

const role = new URLSearchParams(window.location.search).get('role') ?? 'owner';
const profile = { id: `u-${role}`, full_name: `Preview ${role}`, role, is_active: true };
export const useAuth = () => ({ profile, signOut: async () => {} });
export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => <>{children}</>;
