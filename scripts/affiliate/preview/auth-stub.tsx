// Stand-in for src/context/AuthContext, used only by the preview harness so the
// real AffiliateLayout can be rendered at real widths without a login. The
// session is an invented affiliate's, for the email warning above the page;
// ?signed=0 is someone not signed in (the public Rules page, 490).
import React from 'react';
const signedOut = new URLSearchParams(window.location.search).get('signed') === '0';
const session = signedOut ? null : { user: { id: '00000000-0000-4000-8000-0000000000aa', email: 'ada.preview@example.com' } };
export const useAuth = () => ({ session, actorType: signedOut ? null : 'affiliate', loading: false, signOut: async () => {} });
export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => <>{children}</>;
