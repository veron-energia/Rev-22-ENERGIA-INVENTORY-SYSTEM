import React, { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react';
import { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { Profile, UserStoreAssignment } from '../types';
import { signInErrorMessage } from '../lib/staffLogin';

// A logged-in Supabase Auth user resolves to EITHER a Staff member (has a
// profiles row) OR an Affiliate (has an affiliate_accounts row) — never both.
// Affiliates must never be treated as Staff.
export type ActorType = 'staff' | 'affiliate' | null;

export interface AffiliateAccount {
  id: string;
  auth_user_id: string;
  customer_id: string;
  affiliate_id: string | null;
  status: 'claimed' | 'disabled';
}

interface AuthContextValue {
  session: Session | null;
  actorType: ActorType;
  profile: Profile | null;
  affiliateAccount: AffiliateAccount | null;
  assignments: UserStoreAssignment[];
  loading: boolean;
  /**
   * A login has just signed in and its account is still being read. The
   * guards show the loader meanwhile, not "Account setup needed"
   * (ADMIN-AUTH-14). Never set for a re-read of an account already loaded.
   */
  resolving: boolean;
  error: string | null;
  signIn: (email: string, password: string) => Promise<{ error: string | null }>;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

const UNREACHABLE = 'We could not reach the server to load your account. Check your connection and try again.';

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [session, setSession] = useState<Session | null>(null);
  const [actorType, setActorType] = useState<ActorType>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [affiliateAccount, setAffiliateAccount] = useState<AffiliateAccount | null>(null);
  const [assignments, setAssignments] = useState<UserStoreAssignment[]>([]);
  const [loading, setLoading] = useState(true);
  const [resolving, setResolving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // The login whose account (staff, affiliate or neither) is loaded now.
  const loadedFor = useRef<string | null>(null);
  // What that login was loaded as. Null when it is neither, or its profile is
  // switched off: a failed re-read then shows the error, not the old page.
  const loadedActor = useRef<'staff' | 'affiliate' | null>(null);

  const clearActor = useCallback(() => {
    setActorType(null); setProfile(null); setAffiliateAccount(null); setAssignments([]);
  }, []);

  // 437: each read of the account is numbered, and an older read never
  // overwrites what a newer one already set. A sign-up signs in and creates
  // its affiliate account moments apart: the sign-in's read (no account yet)
  // could otherwise land after the read that found the new account, and send
  // the person back to "Finishing setup".
  const resolveSeq = useRef(0);
  const appliedSeq = useRef(0);

  const resolveActor = useCallback(async (userId: string) => {
    const mine = ++resolveSeq.current;
    const stale = () => {
      if (mine < appliedSeq.current) return true;
      appliedSeq.current = mine;
      return false;
    };
    // ADMIN-AUTH-14: a re-read of an account already loaded that fails (a
    // network blip) keeps what is there. Clearing it replaced the page staff
    // were working on, an unsaved invoice included, with "Account setup
    // needed" and only Sign out. Only a staff or affiliate account is kept.
    // A login loaded as neither (onboarding not finished) or as switched off
    // shows the connection error, so the guards do not send it elsewhere.
    const known = loadedFor.current === userId && loadedActor.current !== null;

    // 1) Staff? A profiles row keyed by auth.uid().
    const { data: profileData, error: profileError } = await supabase
      .from('profiles').select('*').eq('id', userId).maybeSingle();
    if (stale()) return;

    // A failed lookup is not the same as "no profile". Falling through would
    // send a perfectly valid owner to the "account setup needed" dead end,
    // whose only way out is Sign out, because a network blip looks exactly
    // like an absent row once the error is dropped.
    if (profileError) {
      if (known) return;
      setError(UNREACHABLE);
      clearActor();
      loadedActor.current = null;
      return;
    }

    if (profileData) {
      if (!profileData.is_active) {
        setError('Your account has been deactivated. Contact an Owner or Manager.');
        setActorType(null); setProfile(null); setAffiliateAccount(null);
        loadedFor.current = userId;
        loadedActor.current = null;
        return;
      }
      setError(null);
      setActorType('staff');
      setProfile(profileData as Profile);
      setAffiliateAccount(null);
      loadedFor.current = userId;
      loadedActor.current = 'staff';
      const { data: assignData, error: assignError } = await supabase
        .from('user_store_assignments').select('*').eq('user_id', userId);
      if (stale()) return;
      if (!assignError || !known) setAssignments((assignData as UserStoreAssignment[]) ?? []);
      return;
    }

    // 2) Affiliate? An affiliate_accounts row keyed by auth.uid().
    //    RLS on affiliate_accounts limits this to the user's own row.
    const { data: acct, error: acctError } = await supabase
      .from('affiliate_accounts')
      .select('id, auth_user_id, customer_id, affiliate_id, status')
      .eq('auth_user_id', userId).maybeSingle();
    if (stale()) return;

    if (acctError) {
      if (known) return;
      setError(UNREACHABLE);
      clearActor();
      loadedActor.current = null;
      return;
    }

    if (acct) {
      setError(null);
      setActorType('affiliate');
      setAffiliateAccount(acct as AffiliateAccount);
      setProfile(null);
      setAssignments([]);
      loadedFor.current = userId;
      loadedActor.current = 'affiliate';
      return;
    }

    // 3) Neither yet (e.g. verified email but onboarding not completed).
    clearActor(); setError(null);
    loadedFor.current = userId;
    loadedActor.current = null;
  }, [clearActor]);

  useEffect(() => {
    let live = true;
    supabase.auth.getSession().then(({ data }) => {
      if (!live) return;
      setSession(data.session);
      if (data.session?.user) {
        resolveActor(data.session.user.id).finally(() => { if (live) setLoading(false); });
      } else {
        setLoading(false);
      }
    });

    const { data: sub } = supabase.auth.onAuthStateChange((event, newSession) => {
      setSession(newSession);
      const userId = newSession?.user?.id;
      if (!userId) {
        loadedFor.current = null;
        loadedActor.current = null;
        clearActor();
        return;
      }
      // The hourly token refresh does not change who this is, so the account
      // is not read again. A login switched off is signed out by the
      // database (412), which arrives here as a sign-out.
      if (event === 'TOKEN_REFRESHED' && loadedFor.current === userId) return;
      // Already loaded (a tab coming back into view, an account update): read
      // it again in the background; the page stays as it is.
      if (loadedFor.current === userId) {
        void resolveActor(userId);
        return;
      }
      // A new sign-in: the loader shows until the account is read.
      setResolving(true);
      resolveActor(userId).finally(() => { if (live) setResolving(false); });
    });

    return () => { live = false; sub.subscription.unsubscribe(); };
  }, [resolveActor, clearActor]);

  const signIn = useCallback(async (email: string, password: string) => {
    setError(null);
    const { error: signInErr } = await supabase.auth.signInWithPassword({ email, password });
    // 412: a login whose staff profile is switched off is banned in Supabase
    // Auth; say so in plain words rather than "User is banned".
    if (signInErr) return { error: signInErrorMessage(signInErr) };
    return { error: null };
  }, []);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    loadedFor.current = null;
    loadedActor.current = null;
    clearActor();
  }, [clearActor]);

  // 437: read the session supabase-js holds now, not the one this render saw.
  // Right after a sign-up signs in, the page that finishes the sign-up can
  // run before React has stored the new session, and a refresh that read the
  // old (empty) one did nothing.
  const refreshProfile = useCallback(async () => {
    const { data } = await supabase.auth.getSession();
    const userId = data.session?.user?.id ?? session?.user?.id;
    if (userId) await resolveActor(userId);
  }, [session, resolveActor]);

  return (
    <AuthContext.Provider
      value={{ session, actorType, profile, affiliateAccount, assignments, loading, resolving, error, signIn, signOut, refreshProfile }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
};
