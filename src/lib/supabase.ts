import { createClient } from '@supabase/supabase-js';
import type { Database } from './database.types';

// These values need to be replaced with the actual Supabase project URL and anon key
// Either set up environment variables or connect to Supabase through the StackBlitz UI
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey);