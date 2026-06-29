import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { Profile, UserStoreAssignment } from '../types';

interface AuthContextValue {
  session: Session | null;
  profile: Profile | null;
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
  const [profile, setProfile] = useState<Profile | null>(null);
  const [assignments, setAssignments] = useState<UserStoreAssignment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadProfile = useCallback(async (userId: string) => {
    // Load the profile row that matches the authenticated user.
    const { data: profileData, error: profileErr } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single();

    if (profileErr) {
      // Most common cause: Auth user exists but no matching profiles row yet.
      setError(
        'Your login works, but no profile record was found. An Owner needs to ' +
        'create your profile row (see starter data SQL) before you can use the system.'
      );
      setProfile(null);
      setAssignments([]);
      return;
    }

    if (profileData && !profileData.is_active) {
      setError('Your account has been deactivated. Contact an Owner or Manager.');
      setProfile(null);
      return;
    }

    setError(null);
    setProfile(profileData as Profile);

    // Load store assignments (used by role-gated views later).
    const { data: assignData } = await supabase
      .from('user_store_assignments')
      .select('*')
      .eq('user_id', userId);
    setAssignments((assignData as UserStoreAssignment[]) ?? []);
  }, []);

  useEffect(() => {
    // Initial session check.
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      if (data.session?.user) {
        loadProfile(data.session.user.id).finally(() => setLoading(false));
      } else {
        setLoading(false);
      }
    });

    // Subscribe to auth changes.
    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
      if (newSession?.user) {
        loadProfile(newSession.user.id);
      } else {
        setProfile(null);
        setAssignments([]);
      }
    });

    return () => sub.subscription.unsubscribe();
  }, [loadProfile]);

  const signIn = useCallback(async (email: string, password: string) => {
    setError(null);
    const { error: signInErr } = await supabase.auth.signInWithPassword({ email, password });
    if (signInErr) return { error: signInErr.message };
    return { error: null };
  }, []);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    setProfile(null);
    setAssignments([]);
  }, []);

  const refreshProfile = useCallback(async () => {
    if (session?.user) await loadProfile(session.user.id);
  }, [session, loadProfile]);

  return (
    <AuthContext.Provider
      value={{ session, profile, assignments, loading, error, signIn, signOut, refreshProfile }}
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
