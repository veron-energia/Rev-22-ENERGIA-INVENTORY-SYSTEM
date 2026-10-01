// A stand-in for src/context/AuthContext, used only by the preview harness.
// Add ?role=staff (or manager) to the URL to see the page as that role.
const role = new URLSearchParams(location.search).get('role') ?? 'owner';
export const useAuth = () => ({
  profile: { id: 'u-preview', full_name: 'Preview User', role, is_active: true },
  user: null, session: null, loading: false,
  signIn: async () => {}, signOut: async () => {}, refresh: async () => {},
}) as any;
export const AuthProvider = ({ children }: { children: React.ReactNode }) => <>{children}</>;
