import React, { useEffect, useState, useCallback } from 'react';
import type { Session, User } from '@supabase/supabase-js';
import { supabase } from '../lib/supabaseClient';
import { AuthContext, type HouseholdInfo } from './AuthContextType';

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [household, setHousehold] = useState<HouseholdInfo | null>(null);

  const fetchHousehold = useCallback(async (userId: string) => {
    try {
      const { data: userData, error: userErr } = await supabase
        .from('users')
        .select('household_id')
        .eq('id', userId)
        .maybeSingle();

      if (userErr || !userData?.household_id) {
        setHousehold(null);
        return;
      }

      const { data: houseData, error: houseErr } = await supabase
        .from('households')
        .select('id, name, payday_day, type, currency')
        .eq('id', userData.household_id)
        .maybeSingle();

      if (!houseErr && houseData) {
        setHousehold({
          id: houseData.id,
          name: houseData.name || 'المنزل',
          paydayDay: houseData.payday_day || 27,
          type: (houseData.type as 'family' | 'shared') || 'family',
          currency: houseData.currency || 'SAR',
        });
      } else {
        setHousehold({
          id: userData.household_id,
          name: 'المنزل',
          paydayDay: 27,
          type: 'family',
          currency: 'SAR',
        });
      }
    } catch {
      setHousehold(null);
    }
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setUser(session?.user ?? null);
      if (session?.user) {
        fetchHousehold(session.user.id).finally(() => setLoading(false));
      } else {
        setLoading(false);
      }
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
      setUser(session?.user ?? null);
      if (session?.user) {
        fetchHousehold(session.user.id).finally(() => setLoading(false));
      } else {
        setHousehold(null);
        setLoading(false);
      }
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [fetchHousehold]);

  const refreshHousehold = useCallback(async () => {
    if (user) {
      await fetchHousehold(user.id);
    }
  }, [user, fetchHousehold]);

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return { error: error as Error | null };
  };

  const signUp = async (email: string, password: string, displayName?: string) => {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          display_name: displayName,
        },
      },
    });
    if (!error && data.user && displayName) {
      await supabase.from('users').upsert({
        id: data.user.id,
        display_name: displayName,
      }).select();
    }
    return { error: error as Error | null };
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    setSession(null);
    setUser(null);
    setHousehold(null);
  };

  return (
    <AuthContext.Provider
      value={{
        session,
        user,
        loading,
        household,
        householdId: household?.id ?? null,
        refreshHousehold,
        signIn,
        signUp,
        signOut,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};


