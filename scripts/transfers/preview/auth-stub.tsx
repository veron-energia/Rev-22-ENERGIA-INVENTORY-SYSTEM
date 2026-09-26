// A stand-in for src/context/AuthContext, used only by the preview harness.
export const useAuth = () => ({
  profile: { id: 'u-owner', full_name: 'Preview Owner', role: 'owner', is_active: true },
  user: null, session: null, loading: false,
  signIn: async () => {}, signOut: async () => {}, refresh: async () => {},
}) as any;
export const AuthProvider = ({ children }: { children: React.ReactNode }) => <>{children}</>;
