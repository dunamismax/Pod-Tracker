import type { User } from '@supabase/supabase-js';

import { supabase } from '@/lib/supabase';

type ProfileUpsert = {
  id: string;
  display_name?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  email?: string | null;
};

function pickDisplayName(user: User) {
  const displayName =
    (user.user_metadata?.display_name as string | undefined) ??
    (user.user_metadata?.full_name as string | undefined) ??
    null;

  if (displayName) return displayName;
  if (user.email) return user.email.split('@')[0];
  return null;
}

export async function ensureProfile(user: User | null) {
  if (!user?.id) return;

  const payload: ProfileUpsert = {
    id: user.id,
    email: user.email ?? null,
    display_name: pickDisplayName(user),
  };

  const { error } = await supabase.from('profiles').upsert(payload, { onConflict: 'id' });
  if (error) {
    throw error;
  }
}
