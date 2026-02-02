import { createClient } from '@supabase/supabase-js';

import { env } from '@/lib/env';

export const supabase = createClient(
  env.EXPO_PUBLIC_SUPABASE_URL,
  env.EXPO_PUBLIC_SUPABASE_ANON_KEY
);
