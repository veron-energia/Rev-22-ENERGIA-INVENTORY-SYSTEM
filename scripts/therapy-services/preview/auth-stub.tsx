// A stand-in for src/context/AuthContext, used only by the preview harness.
//
// Aliased in rather than exporting the real context: AuthContext.tsx is shared,
// and widening its exports to suit a preview would change production code for a
// reason that has nothing to do with production.
export const useAuth = () => ({
  profile: { id: 'p1', full_name: 'Preview Manager', role: 'manager', is_active: true },
  user: null, session: null, loading: false,
  signIn: async () => {}, signOut: async () => {}, refresh: async () => {},
}) as any;
export const AuthProvider = ({ children }: { children: React.ReactNode }) => <>{children}</>;
