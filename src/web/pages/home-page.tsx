import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';

import {
  useEventAttendance,
  useEventChecklist,
  useEventRealtime,
  useUpcomingEvents,
  useUpdateChecklistItem,
  useUpdateRsvp,
} from '@/features/events/events-queries';
import {
  useNotifications,
  useNotificationsRealtime,
} from '@/features/notifications/notifications-queries';
import { usePodsByUser } from '@/features/pods/pods-queries';
import { useProfilesByIds } from '@/features/profiles/profiles-queries';
import { useSession } from '@/web/session-context';
import { formatEventTime } from '@/web/utils/date';
import { formatMemberName } from '@/web/utils/profile';

const arrivalLabels = {
  not_sure: 'Not sure',
  on_the_way: 'On the way',
  arrived: 'Arrived',
  late: 'Running late',
} as const;

const checklistNextState = {
  open: 'done',
  done: 'blocked',
  blocked: 'open',
} as const;

export function HomePage() {
  const { user, isLoading: authLoading } = useSession();
  const podsQuery = usePodsByUser(user?.id);
  const podIds = useMemo(() => podsQuery.data?.map((pod) => pod.id) ?? [], [podsQuery.data]);
  const podNameById = useMemo(
    () => new Map((podsQuery.data ?? []).map((pod) => [pod.id, pod.name])),
    [podsQuery.data]
  );
  const eventsQuery = useUpcomingEvents(podIds);
  const nextEvent = eventsQuery.data?.[0];
  const attendanceQuery = useEventAttendance(nextEvent?.id);
  const checklistQuery = useEventChecklist(nextEvent?.id);
  useEventRealtime(nextEvent?.id);

  const notificationsQuery = useNotifications(user?.id);
  useNotificationsRealtime(user?.id);
  const unreadCount =
    notificationsQuery.data?.filter((notification) => !notification.read_at).length ?? 0;

  const updateRsvp = useUpdateRsvp();
  const updateChecklistItem = useUpdateChecklistItem();
  const [actionMessage, setActionMessage] = useState<string | null>(null);

  const attendanceUserIds = useMemo(
    () => (attendanceQuery.data ?? []).map((member) => member.user_id),
    [attendanceQuery.data]
  );
  const profilesQuery = useProfilesByIds(attendanceUserIds);
  const profileById = useMemo(
    () => new Map((profilesQuery.data ?? []).map((profile) => [profile.id, profile])),
    [profilesQuery.data]
  );

  const isLoading = authLoading || podsQuery.isLoading || eventsQuery.isLoading;
  const canInteract = Boolean(user && nextEvent);

  const handleRsvp = (rsvp: 'yes' | 'no' | 'maybe') => {
    if (!user || !nextEvent) return;

    setActionMessage(null);
    updateRsvp.mutate(
      { eventId: nextEvent.id, userId: user.id, rsvp },
      {
        onSuccess: () => setActionMessage(`RSVP saved as "${rsvp}".`),
        onError: (error) =>
          setActionMessage(error instanceof Error ? error.message : 'Unable to update RSVP.'),
      }
    );
  };

  return (
    <div className="stack">
      <section className="panel hero">
        <div>
          <p className="eyebrow">Dashboard</p>
          <h2>{nextEvent?.title ?? 'No upcoming event yet'}</h2>
          <p className="muted">
            {nextEvent
              ? `${podNameById.get(nextEvent.pod_id) ?? 'Your pod'} · ${formatEventTime(nextEvent.starts_at, nextEvent.ends_at)}`
              : 'Create a pod event to start coordinating your next session.'}
          </p>
          <div className="actions">
            <Link className="btn btn-primary" to="/create-event">
              Create event
            </Link>
            <Link className="btn btn-outline" to="/notifications">
              Notifications {unreadCount > 0 ? `(${unreadCount})` : ''}
            </Link>
          </div>
        </div>
      </section>

      <section className="panel">
        <h3>RSVP</h3>
        {isLoading ? (
          <p className="muted">Loading your events...</p>
        ) : !user ? (
          <p className="muted">Sign in to respond to your pod events.</p>
        ) : !nextEvent ? (
          <p className="muted">No upcoming events.</p>
        ) : (
          <div className="actions">
            <button className="btn btn-primary" onClick={() => handleRsvp('yes')} type="button">
              I am in
            </button>
            <button className="btn btn-outline" onClick={() => handleRsvp('maybe')} type="button">
              Maybe
            </button>
            <button className="btn btn-outline" onClick={() => handleRsvp('no')} type="button">
              Cannot make it
            </button>
            <Link className="btn btn-outline" to={`/event/${nextEvent.id}`}>
              Event details
            </Link>
          </div>
        )}
        {actionMessage ? <p className="muted">{actionMessage}</p> : null}
      </section>

      <section className="panel">
        <h3>Arrival board</h3>
        {attendanceQuery.isLoading ? (
          <p className="muted">Loading arrivals...</p>
        ) : (attendanceQuery.data?.length ?? 0) === 0 ? (
          <p className="muted">No arrival updates yet.</p>
        ) : (
          <ul className="list">
            {(attendanceQuery.data ?? []).map((member) => (
              <li key={member.id} className="list-row">
                <div>
                  <p>{formatMemberName(member.user_id, profileById.get(member.user_id))}</p>
                  <p className="muted">{arrivalLabels[member.arrival] ?? 'Not sure'}</p>
                </div>
                <span className="pill">
                  {member.arrival === 'arrived'
                    ? 'Here'
                    : member.eta_minutes !== null
                      ? `${member.eta_minutes} min`
                      : '-'}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="panel">
        <h3>Checklist</h3>
        {checklistQuery.isLoading ? (
          <p className="muted">Loading checklist...</p>
        ) : (checklistQuery.data?.length ?? 0) === 0 ? (
          <p className="muted">Checklist is empty.</p>
        ) : (
          <ul className="list">
            {(checklistQuery.data ?? []).map((item) => (
              <li key={item.id} className="list-row">
                <div>
                  <p>{item.label}</p>
                  <p className="muted">{item.note ?? item.state}</p>
                </div>
                <button
                  className="btn btn-outline"
                  disabled={!canInteract || updateChecklistItem.isPending}
                  onClick={() =>
                    nextEvent &&
                    updateChecklistItem.mutate({
                      eventId: nextEvent.id,
                      itemId: item.id,
                      state: checklistNextState[item.state],
                    })
                  }
                  type="button">
                  Cycle state
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
