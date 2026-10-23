import { createContext } from 'react';
import type { Session, User } from '@supabase/supabase-js';

export interface HouseholdInfo {
  id: string;
  name: string;
  paydayDay: number;
  type: 'family' | 'shared';
  currency: string;
}

export interface AuthContextType {
  session: Session | null;
  user: User | null;
  loading: boolean;
  household: HouseholdInfo | null;
  householdId: string | null;
  refreshHousehold: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>;
  signUp: (email: string, password: string, displayName?: string) => Promise<{ error: Error | null }>;
  signOut: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextType | undefined>(undefined);
