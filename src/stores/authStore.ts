import { create } from 'zustand';
import { supabase } from '../lib/supabase';
import type { Session, User } from '@supabase/supabase-js';
import type { Database } from '../lib/database.types';

type Profile = Database['public']['Tables']['profiles']['Row']; 

interface AuthState {
  session: Session | null;
  user: User | null;
  profile: Profile | null;
  isLoading: boolean;
  
  // Session management
  setSession: (session: Session | null) => void;
  clearSession: () => void;
  
  // Profile data
  setProfile: (profile: Profile | null) => void;
  fetchProfile: () => Promise<void>;
  
  // Auth methods
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>;
  signUp: (email: string, password: string, fullName: string, role: 'client' | 'mentor' | 'training_director') => Promise<{ error: Error | null }>;
  signOut: () => Promise<void>;
}

export const useAuthStore = create<AuthState>((set, get) => ({
  session: null,
  user: null,
  profile: null,
  isLoading: false,
  
  setSession: (session) => {
    set({ 
      session,
      user: session?.user || null,
    });
    
    // Fetch profile when session changes
    if (session?.user) {
      get().fetchProfile();
    } else {
      set({ profile: null });
    }
  },
  
  clearSession: () => {
    set({ session: null, user: null, profile: null });
  },
  
  setProfile: (profile) => {
    set({ profile });
  },
  
  fetchProfile: async () => {
    const { user } = get();
    if (!user) return;
    
    set({ isLoading: true });
    
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single();
    
    if (error) {
      console.error('Error fetching profile:', error);
    } else {
      set({ profile: data });
    }
    
    set({ isLoading: false });
  },
  
  signIn: async (email, password) => {
    set({ isLoading: true });
    
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password
    });
    
    set({ isLoading: false });
    return { error };
  },
  
  signUp: async (email, password, fullName, role) => {
    set({ isLoading: true });
    
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName,
          role
        }
      }
    });
    
    // If signup successful, create a profile
    if (data.user && !error) {
      const { error: profileError } = await supabase
        .from('profiles')
        .insert({
          id: data.user.id,
          full_name: fullName,
          role,
          mentor_id: null,
          director_id: null
        });
      
      if (profileError) {
        console.error('Error creating profile:', profileError);
        set({ isLoading: false });
        return { error: new Error('Failed to create profile') };
      }
    }
    
    set({ isLoading: false });
    return { error };
  },
  
  signOut: async () => {
    set({ isLoading: true });
    await supabase.auth.signOut();
    set({ isLoading: false });
    get().clearSession();
  }
}));