import { useQuery } from '@tanstack/react-query';

import { supabase } from '@/lib/supabase';

export type EventSummary = {
  id: string;
  pod_id: string;
  title: string;
  starts_at: string;
  ends_at: string | null;
  location_text: string | null;
};

export type EventAttendanceRow = {
  id: string;
  user_id: string;
  rsvp: 'yes' | 'no' | 'maybe';
  arrival: 'not_sure' | 'on_the_way' | 'arrived' | 'late';
  eta_minutes: number | null;
  updated_at: string;
};

export type ChecklistItem = {
  id: string;
  label: string;
  state: 'open' | 'done' | 'blocked';
  note: string | null;
  created_by: string;
  updated_at: string;
};

const eventKeys = {
  all: ['events'] as const,
  upcoming: (podIds: string[]) => [...eventKeys.all, 'upcoming', podIds] as const,
  attendance: (eventId: string) => [...eventKeys.all, 'attendance', eventId] as const,
  checklist: (eventId: string) => [...eventKeys.all, 'checklist', eventId] as const,
};

function normalizeIds(ids: string[]) {
  return Array.from(new Set(ids)).sort();
}

async function fetchUpcomingEvents(podIds: string[]): Promise<EventSummary[]> {
  if (podIds.length === 0) return [];

  const { data, error } = await supabase
    .from('events')
    .select('id,pod_id,title,starts_at,ends_at,location_text')
    .in('pod_id', podIds)
    .gte('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true })
    .limit(10);

  if (error) {
    throw error;
  }

  return (data ?? []) as EventSummary[];
}

async function fetchAttendance(eventId: string): Promise<EventAttendanceRow[]> {
  const { data, error } = await supabase
    .from('event_attendance')
    .select('id,user_id,rsvp,arrival,eta_minutes,updated_at')
    .eq('event_id', eventId)
    .order('updated_at', { ascending: false });

  if (error) {
    throw error;
  }

  return (data ?? []) as EventAttendanceRow[];
}

async function fetchChecklist(eventId: string): Promise<ChecklistItem[]> {
  const { data, error } = await supabase
    .from('event_checklist_items')
    .select('id,label,state,note,created_by,updated_at')
    .eq('event_id', eventId)
    .order('created_at', { ascending: true });

  if (error) {
    throw error;
  }

  return (data ?? []) as ChecklistItem[];
}

export function useUpcomingEvents(podIds: string[]) {
  const normalized = normalizeIds(podIds);

  return useQuery({
    queryKey: eventKeys.upcoming(normalized),
    queryFn: () => fetchUpcomingEvents(normalized),
    enabled: normalized.length > 0,
    staleTime: 30_000,
  });
}

export function useEventAttendance(eventId?: string) {
  return useQuery({
    queryKey: eventKeys.attendance(eventId ?? 'unknown'),
    queryFn: () => fetchAttendance(eventId ?? ''),
    enabled: Boolean(eventId),
    staleTime: 10_000,
  });
}

export function useEventChecklist(eventId?: string) {
  return useQuery({
    queryKey: eventKeys.checklist(eventId ?? 'unknown'),
    queryFn: () => fetchChecklist(eventId ?? ''),
    enabled: Boolean(eventId),
    staleTime: 30_000,
  });
}
