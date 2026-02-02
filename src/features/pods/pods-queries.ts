import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

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

type CreatePodInput = {
  userId: string;
  name: string;
  description?: string | null;
  locationText?: string | null;
};

async function createPod({ userId, name, description, locationText }: CreatePodInput) {
  const { data: pod, error: podError } = await supabase
    .from('pods')
    .insert({
      name,
      description: description ?? null,
      location_text: locationText ?? null,
      created_by: userId,
    })
    .select('id')
    .single();

  if (podError) {
    throw podError;
  }

  const { error: membershipError } = await supabase.from('pod_memberships').insert({
    pod_id: pod.id,
    user_id: userId,
    role: 'owner',
    is_active: true,
  });

  if (membershipError) {
    throw membershipError;
  }

  return pod.id;
}

export function usePodsByUser(userId?: string) {
  return useQuery({
    queryKey: podKeys.byUser(userId ?? 'anonymous'),
    queryFn: () => fetchPodsByUser(userId ?? ''),
    enabled: Boolean(userId),
    staleTime: 60_000,
  });
}

export function useCreatePod() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: createPod,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: podKeys.all });
    },
  });
}
