import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL =
  (import.meta.env.VITE_SUPABASE_URL as string | undefined) ||
  'https://qnhyiszgiymsypcwnntu.supabase.co';

const SUPABASE_ANON_KEY =
  (import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined) ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFuaHlpc3pnaXltc3lwY3dubnR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MjM2NjYsImV4cCI6MjEwNTQ5OTY2Nn0.bOazpdgpRKOB2n60ZgGL3Vgjd4oPp5yxZ0VqpeyLz_U';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
