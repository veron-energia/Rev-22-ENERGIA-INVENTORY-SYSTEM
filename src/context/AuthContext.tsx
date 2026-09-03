import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { Profile, UserStoreAssignment } from '../types';

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
  error: string | null;
  signIn: (email: string, password: string) => Promise<{ error: string | null }>;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [session, setSession] = useState<Session | null>(null);
  const [actorType, setActorType] = useState<ActorType>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [affiliateAccount, setAffiliateAccount] = useState<AffiliateAccount | null>(null);
  const [assignments, setAssignments] = useState<UserStoreAssignment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const resolveActor = useCallback(async (userId: string) => {
    // 1) Staff? A profiles row keyed by auth.uid().
    const { data: profileData } = await supabase
      .from('profiles').select('*').eq('id', userId).maybeSingle();

    if (profileData) {
      if (!profileData.is_active) {
        setError('Your account has been deactivated. Contact an Owner or Manager.');
        setActorType(null); setProfile(null); setAffiliateAccount(null);
        return;
      }
      setError(null);
      setActorType('staff');
      setProfile(profileData as Profile);
      setAffiliateAccount(null);
      const { data: assignData } = await supabase
        .from('user_store_assignments').select('*').eq('user_id', userId);
      setAssignments((assignData as UserStoreAssignment[]) ?? []);
      return;
    }

    // 2) Affiliate? An affiliate_accounts row keyed by auth.uid().
    //    RLS on affiliate_accounts limits this to the user's own row.
    const { data: acct } = await supabase
      .from('affiliate_accounts')
      .select('id, auth_user_id, customer_id, affiliate_id, status')
      .eq('auth_user_id', userId).maybeSingle();

    if (acct) {
      setError(null);
      setActorType('affiliate');
      setAffiliateAccount(acct as AffiliateAccount);
      setProfile(null);
      setAssignments([]);
      return;
    }

    // 3) Neither yet (e.g. verified email but onboarding not completed).
    setActorType(null); setProfile(null); setAffiliateAccount(null);
    setAssignments([]); setError(null);
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      if (data.session?.user) {
        resolveActor(data.session.user.id).finally(() => setLoading(false));
      } else {
        setLoading(false);
      }
    });

    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
      if (newSession?.user) {
        resolveActor(newSession.user.id);
      } else {
        setActorType(null); setProfile(null); setAffiliateAccount(null); setAssignments([]);
      }
    });

    return () => sub.subscription.unsubscribe();
  }, [resolveActor]);

  const signIn = useCallback(async (email: string, password: string) => {
    setError(null);
    const { error: signInErr } = await supabase.auth.signInWithPassword({ email, password });
    if (signInErr) return { error: signInErr.message };
    return { error: null };
  }, []);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    setActorType(null); setProfile(null); setAffiliateAccount(null); setAssignments([]);
  }, []);

  const refreshProfile = useCallback(async () => {
    if (session?.user) await resolveActor(session.user.id);
  }, [session, resolveActor]);

  return (
    <AuthContext.Provider
      value={{ session, actorType, profile, affiliateAccount, assignments, loading, error, signIn, signOut, refreshProfile }}
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
