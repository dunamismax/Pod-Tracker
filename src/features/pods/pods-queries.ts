import { useQuery } from '@tanstack/react-query';

import { supabase } from '@/lib/supabase';

export type PodSummary = {
  id: string;
  name: string;
  description: string | null;
  location_text: string | null;
  role: 'owner' | 'admin' | 'member';
};

const podKeys = {
  all: ['pods'] as const,
  byUser: (userId: string) => [...podKeys.all, 'by-user', userId] as const,
};

type PodMembershipRow = {
  role: PodSummary['role'];
  pod: {
    id: string;
    name: string;
    description: string | null;
    location_text: string | null;
  } | null;
};

async function fetchPodsByUser(userId: string): Promise<PodSummary[]> {
  const { data, error } = await supabase
    .from('pod_memberships')
    .select('role, pod:pods(id,name,description,location_text)')
    .eq('user_id', userId)
    .eq('is_active', true)
    .order('joined_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data as PodMembershipRow[])
    .map((row) => (row.pod ? { ...row.pod, role: row.role } : null))
    .filter((row): row is PodSummary => Boolean(row));
}

export function usePodsByUser(userId?: string) {
  return useQuery({
    queryKey: podKeys.byUser(userId ?? 'anonymous'),
    queryFn: () => fetchPodsByUser(userId ?? ''),
    enabled: Boolean(userId),
    staleTime: 60_000,
  });
}
