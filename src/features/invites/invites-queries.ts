import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { supabase } from '@/lib/supabase';

export type PodInvite = {
  id: string;
  pod_id: string;
  invited_email: string | null;
  invited_user_id: string | null;
  invited_by: string;
  status: 'pending' | 'accepted' | 'revoked' | 'expired';
  expires_at: string | null;
  created_at: string;
  pod?: {
    id: string;
    name: string;
    location_text: string | null;
  } | null;
};

type PodInviteRow = Omit<PodInvite, 'pod'> & {
  pod:
    | {
        id: string;
        name: string;
        location_text: string | null;
      }
    | {
        id: string;
        name: string;
        location_text: string | null;
      }[]
    | null;
};

const inviteKeys = {
  all: ['invites'] as const,
  byUser: (userId: string, email: string | null) =>
    [...inviteKeys.all, 'by-user', userId, email] as const,
  byPod: (podId: string) => [...inviteKeys.all, 'by-pod', podId] as const,
};

async function fetchInvitesForUser(userId: string, email: string | null): Promise<PodInvite[]> {
  if (!userId) return [];
  const normalizedEmail = email?.trim().toLowerCase() ?? null;

  const query = supabase
    .from('pod_invites')
    .select(
      'id,pod_id,invited_email,invited_user_id,invited_by,status,expires_at,created_at,pod:pods(id,name,location_text)'
    )
    .eq('status', 'pending');

  if (normalizedEmail) {
    query.or(`invited_user_id.eq.${userId},invited_email.eq.${normalizedEmail}`);
  } else {
    query.eq('invited_user_id', userId);
  }

  const { data, error } = await query.order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  return ((data ?? []) as PodInviteRow[]).map((row) => ({
    ...row,
    pod: Array.isArray(row.pod) ? row.pod[0] ?? null : row.pod,
  }));
}

async function fetchInvitesForPod(podId: string): Promise<PodInvite[]> {
  const { data, error } = await supabase
    .from('pod_invites')
    .select('id,pod_id,invited_email,invited_user_id,invited_by,status,token,expires_at,created_at')
    .eq('pod_id', podId)
    .eq('status', 'pending')
    .order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  return (data ?? []) as PodInvite[];
}

type CreateInviteInput = {
  podId: string;
  invitedEmail: string;
  invitedBy: string;
};

async function createInvite({ podId, invitedEmail, invitedBy }: CreateInviteInput) {
  const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString();
  const { error } = await supabase.from('pod_invites').insert({
    pod_id: podId,
    invited_email: invitedEmail.trim().toLowerCase(),
    invited_by: invitedBy,
    status: 'pending',
    expires_at: expiresAt,
  });

  if (error) {
    throw error;
  }
}

type AcceptInviteInput = {
  inviteId: string;
};

async function acceptInvite({ inviteId }: AcceptInviteInput) {
  const { data, error } = await supabase.rpc('accept_pod_invite', { invite_id: inviteId });

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error('Unable to accept invite.');
  }

  return data as string;
}

export function usePendingInvites(userId?: string, email?: string | null) {
  return useQuery({
    queryKey: inviteKeys.byUser(userId ?? 'anonymous', email ?? null),
    queryFn: () => fetchInvitesForUser(userId ?? '', email ?? null),
    enabled: Boolean(userId),
    staleTime: 15_000,
  });
}

export function usePodInvites(podId?: string) {
  return useQuery({
    queryKey: inviteKeys.byPod(podId ?? 'unknown'),
    queryFn: () => fetchInvitesForPod(podId ?? ''),
    enabled: Boolean(podId),
    staleTime: 15_000,
  });
}

export function useCreateInvite() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: createInvite,
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: inviteKeys.byPod(variables.podId) });
    },
  });
}

export function useAcceptInvite() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: acceptInvite,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: inviteKeys.all });
    },
  });
}
