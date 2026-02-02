import { useQuery } from '@tanstack/react-query';

import { supabase } from '@/lib/supabase';

export type Profile = {
  id: string;
  display_name: string | null;
  full_name: string | null;
  email: string | null;
  avatar_url: string | null;
};

const profileKeys = {
  all: ['profiles'] as const,
  byIds: (userIds: string[]) => [...profileKeys.all, 'by-ids', userIds] as const,
};

function normalizeIds(ids: string[]) {
  return Array.from(new Set(ids)).sort();
}

async function fetchProfiles(userIds: string[]): Promise<Profile[]> {
  if (userIds.length === 0) return [];

  const { data, error } = await supabase
    .from('profiles')
    .select('id,display_name,full_name,email,avatar_url')
    .in('id', userIds);

  if (error) {
    return [];
  }

  return (data ?? []) as Profile[];
}

export function useProfilesByIds(userIds: string[]) {
  const normalized = normalizeIds(userIds);

  return useQuery({
    queryKey: profileKeys.byIds(normalized),
    queryFn: () => fetchProfiles(normalized),
    enabled: normalized.length > 0,
    staleTime: 60_000,
  });
}
