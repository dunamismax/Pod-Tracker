import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { supabase } from '@/lib/supabase';

export type Profile = {
  id: string;
  display_name: string | null;
  email: string | null;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  contact_email: string | null;
  contact_handle: string | null;
  contact_notes: string | null;
  avatar_url: string | null;
};

const profileKeys = {
  all: ['profiles'] as const,
  byId: (userId: string) => [...profileKeys.all, 'by-id', userId] as const,
  byIds: (userIds: string[]) => [...profileKeys.all, 'by-ids', userIds] as const,
};

function normalizeIds(ids: string[]) {
  return Array.from(new Set(ids)).sort();
}

async function fetchProfiles(userIds: string[]): Promise<Profile[]> {
  if (userIds.length === 0) return [];

  const { data, error } = await supabase
    .from('profiles')
    .select(
      'id,display_name,first_name,last_name,email,phone,contact_email,contact_handle,contact_notes,avatar_url'
    )
    .in('id', userIds);

  if (error) {
    throw error;
  }

  return (data ?? []) as Profile[];
}

async function fetchProfile(userId: string): Promise<Profile | null> {
  const { data, error } = await supabase
    .from('profiles')
    .select(
      'id,display_name,first_name,last_name,email,phone,contact_email,contact_handle,contact_notes,avatar_url'
    )
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return (data ?? null) as Profile | null;
}

type UpsertProfileInput = {
  id: string;
  display_name?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  email?: string | null;
  phone?: string | null;
  contact_email?: string | null;
  contact_handle?: string | null;
  contact_notes?: string | null;
  avatar_url?: string | null;
};

async function upsertProfile(input: UpsertProfileInput) {
  const { error } = await supabase
    .from('profiles')
    .upsert(
      {
        id: input.id,
        display_name: input.display_name ?? null,
        first_name: input.first_name ?? null,
        last_name: input.last_name ?? null,
        email: input.email ?? null,
        phone: input.phone ?? null,
        contact_email: input.contact_email ?? null,
        contact_handle: input.contact_handle ?? null,
        contact_notes: input.contact_notes ?? null,
        avatar_url: input.avatar_url ?? null,
      },
      { onConflict: 'id' }
    );

  if (error) {
    throw error;
  }
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

export function useProfile(userId?: string) {
  return useQuery({
    queryKey: profileKeys.byId(userId ?? 'anonymous'),
    queryFn: () => fetchProfile(userId ?? ''),
    enabled: Boolean(userId),
    staleTime: 60_000,
  });
}

export function useUpsertProfile() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: upsertProfile,
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: profileKeys.byId(variables.id) });
      queryClient.invalidateQueries({ queryKey: profileKeys.all });
    },
  });
}
