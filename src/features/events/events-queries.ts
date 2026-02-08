import { useEffect } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { supabase } from '@/lib/supabase';

export type EventSummary = {
  id: string;
  pod_id: string;
  title: string;
  starts_at: string;
  ends_at: string | null;
  location_text: string | null;
};

export type EventDetail = EventSummary & {
  created_by: string;
  description: string | null;
  canceled_at: string | null;
  canceled_by: string | null;
  cancel_reason: string | null;
  pod?: {
    id: string;
    name: string;
  } | null;
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
  byId: (eventId: string) => [...eventKeys.all, 'by-id', eventId] as const,
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
    .is('canceled_at', null)
    .gte('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true })
    .limit(10);

  if (error) {
    throw error;
  }

  return (data ?? []) as EventSummary[];
}

async function fetchEventById(eventId: string): Promise<EventDetail | null> {
  const { data, error } = await supabase
    .from('events')
    .select(
      'id,pod_id,created_by,title,description,starts_at,ends_at,location_text,canceled_at,canceled_by,cancel_reason,pod:pods(id,name)'
    )
    .eq('id', eventId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return (data ?? null) as EventDetail | null;
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

type CreateEventInput = {
  userId: string;
  podId: string;
  title: string;
  description?: string | null;
  startsAt: string;
  endsAt?: string | null;
  locationText?: string | null;
};

type UpdateEventInput = {
  eventId: string;
  userId: string;
  title?: string;
  description?: string | null;
  startsAt?: string;
  endsAt?: string | null;
  locationText?: string | null;
};

type UpdateRsvpInput = {
  eventId: string;
  userId: string;
  rsvp: EventAttendanceRow['rsvp'];
};

type UpdateArrivalInput = {
  eventId: string;
  userId: string;
  arrival: EventAttendanceRow['arrival'];
  etaMinutes?: number | null;
};

type UpdateChecklistItemInput = {
  eventId: string;
  itemId: string;
  state: ChecklistItem['state'];
  note?: string | null;
};

type CreateChecklistItemInput = {
  eventId: string;
  userId: string;
  label: string;
  note?: string | null;
};

type NotifyEventInput = {
  eventId: string;
  actorId: string;
  type: 'event_created' | 'schedule_changed' | 'arrival_update' | 'eta_update' | 'event_cancelled';
  arrival?: EventAttendanceRow['arrival'];
  etaMinutes?: number | null;
  changedFields?: string[];
  cancelReason?: string | null;
};

async function notifyEvent(payload: NotifyEventInput) {
  try {
    const { error } = await supabase.functions.invoke('notify-event', {
      body: payload,
    });

    if (error) {
      throw error;
    }
  } catch (error) {
    console.warn('Failed to notify event:', error);
  }
}

async function updateRsvp({ eventId, userId, rsvp }: UpdateRsvpInput) {
  const { error } = await supabase
    .from('event_attendance')
    .upsert(
      {
        event_id: eventId,
        user_id: userId,
        rsvp,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'event_id,user_id' }
    );

  if (error) {
    throw error;
  }
}

async function updateArrival({ eventId, userId, arrival, etaMinutes }: UpdateArrivalInput) {
  const { error } = await supabase
    .from('event_attendance')
    .upsert(
      {
        event_id: eventId,
        user_id: userId,
        arrival,
        eta_minutes: etaMinutes ?? null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'event_id,user_id' }
    );

  if (error) {
    throw error;
  }
}

async function updateChecklistItem({ itemId, state, note }: UpdateChecklistItemInput) {
  const { error } = await supabase
    .from('event_checklist_items')
    .update({
      state,
      note: note ?? null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', itemId);

  if (error) {
    throw error;
  }
}

async function createChecklistItem({ eventId, userId, label, note }: CreateChecklistItemInput) {
  const { error } = await supabase.from('event_checklist_items').insert({
    event_id: eventId,
    label,
    note: note ?? null,
    state: 'open',
    created_by: userId,
  });

  if (error) {
    throw error;
  }
}

async function updateEvent({
  eventId,
  title,
  description,
  startsAt,
  endsAt,
  locationText,
}: UpdateEventInput) {
  const updates: Record<string, string | null> = {};

  if (typeof title !== 'undefined') updates.title = title;
  if (typeof description !== 'undefined') updates.description = description ?? null;
  if (typeof startsAt !== 'undefined') updates.starts_at = startsAt;
  if (typeof endsAt !== 'undefined') updates.ends_at = endsAt ?? null;
  if (typeof locationText !== 'undefined') updates.location_text = locationText ?? null;

  if (Object.keys(updates).length === 0) {
    return;
  }

  const { data, error } = await supabase
    .from('events')
    .update(updates)
    .eq('id', eventId)
    .is('canceled_at', null)
    .select('id')
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error('Event is already canceled or unavailable.');
  }
}

async function createEvent({
  userId,
  podId,
  title,
  description,
  startsAt,
  endsAt,
  locationText,
}: CreateEventInput) {
  const { data, error } = await supabase
    .from('events')
    .insert({
      pod_id: podId,
      title,
      description: description ?? null,
      starts_at: startsAt,
      ends_at: endsAt ?? null,
      location_text: locationText ?? null,
      created_by: userId,
    })
    .select('id')
    .single();

  if (error) {
    throw error;
  }

  return data.id;
}

type CancelEventInput = {
  eventId: string;
  userId: string;
  reason?: string | null;
};

async function cancelEvent({ eventId, userId, reason }: CancelEventInput) {
  const { data, error } = await supabase
    .from('events')
    .update({
      canceled_at: new Date().toISOString(),
      canceled_by: userId,
      cancel_reason: reason ?? null,
    })
    .eq('id', eventId)
    .is('canceled_at', null)
    .select('id')
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error('Event is already canceled or unavailable.');
  }
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

export function useEventById(eventId?: string) {
  return useQuery({
    queryKey: eventKeys.byId(eventId ?? 'unknown'),
    queryFn: () => fetchEventById(eventId ?? ''),
    enabled: Boolean(eventId),
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

export function useEventRealtime(eventId?: string) {
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!eventId) return;

    const attendanceChannel = supabase
      .channel(`event-${eventId}-attendance`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'event_attendance',
          filter: `event_id=eq.${eventId}`,
        },
        () => {
          queryClient.invalidateQueries({ queryKey: eventKeys.attendance(eventId) });
        }
      )
      .subscribe();

    const checklistChannel = supabase
      .channel(`event-${eventId}-checklist`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'event_checklist_items',
          filter: `event_id=eq.${eventId}`,
        },
        () => {
          queryClient.invalidateQueries({ queryKey: eventKeys.checklist(eventId) });
        }
      )
      .subscribe();

    const eventChannel = supabase
      .channel(`event-${eventId}-details`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'events',
          filter: `id=eq.${eventId}`,
        },
        () => {
          queryClient.invalidateQueries({ queryKey: eventKeys.byId(eventId) });
          queryClient.invalidateQueries({ queryKey: eventKeys.all });
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(attendanceChannel);
      supabase.removeChannel(checklistChannel);
      supabase.removeChannel(eventChannel);
    };
  }, [eventId, queryClient]);
}

export function useUpdateRsvp() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: updateRsvp,
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: eventKeys.attendance(variables.eventId) });
    },
  });
}

export function useUpdateArrival() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: updateArrival,
    onSuccess: (_data, variables) => {
      const hasEta = typeof variables.etaMinutes === 'number';
      queryClient.invalidateQueries({ queryKey: eventKeys.attendance(variables.eventId) });
      void notifyEvent({
        eventId: variables.eventId,
        actorId: variables.userId,
        type: hasEta ? 'eta_update' : 'arrival_update',
        arrival: variables.arrival,
        etaMinutes: variables.etaMinutes ?? null,
      });
    },
  });
}

export function useUpdateChecklistItem() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: updateChecklistItem,
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: eventKeys.checklist(variables.eventId) });
    },
  });
}

export function useCreateChecklistItem() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: createChecklistItem,
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: eventKeys.checklist(variables.eventId) });
    },
  });
}

export function useCreateEvent() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: createEvent,
    onSuccess: (eventId, variables) => {
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
      void notifyEvent({
        eventId,
        actorId: variables.userId,
        type: 'event_created',
      });
    },
  });
}

export function useUpdateEvent() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: updateEvent,
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: eventKeys.byId(variables.eventId) });
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
      const changedFields = [
        typeof variables.startsAt !== 'undefined' ? 'starts_at' : null,
        typeof variables.endsAt !== 'undefined' ? 'ends_at' : null,
        typeof variables.locationText !== 'undefined' ? 'location_text' : null,
        typeof variables.title !== 'undefined' ? 'title' : null,
      ].filter(Boolean) as string[];

      if (changedFields.length > 0) {
        void notifyEvent({
          eventId: variables.eventId,
          actorId: variables.userId,
          type: 'schedule_changed',
          changedFields,
        });
      }
    },
  });
}

export function useCancelEvent() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: cancelEvent,
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: eventKeys.byId(variables.eventId) });
      queryClient.invalidateQueries({ queryKey: eventKeys.all });
      void notifyEvent({
        eventId: variables.eventId,
        actorId: variables.userId,
        type: 'event_cancelled',
        cancelReason: variables.reason ?? null,
      });
    },
  });
}
