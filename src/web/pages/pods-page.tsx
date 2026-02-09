import { useMemo } from 'react';
import { Link } from 'react-router-dom';

import { useUpcomingEvents } from '@/features/events/events-queries';
import { usePodsByUser } from '@/features/pods/pods-queries';
import { useSession } from '@/web/session-context';
import { formatEventTime } from '@/web/utils/date';

const roleLabels = {
  owner: 'Owner',
  admin: 'Admin',
  member: 'Member',
} as const;

export function PodsPage() {
  const { user, isLoading: authLoading } = useSession();
  const podsQuery = usePodsByUser(user?.id);
  const podIds = useMemo(() => podsQuery.data?.map((pod) => pod.id) ?? [], [podsQuery.data]);
  const eventsQuery = useUpcomingEvents(podIds);
  const podNameById = useMemo(
    () => new Map((podsQuery.data ?? []).map((pod) => [pod.id, pod.name])),
    [podsQuery.data]
  );
  const isLoading = authLoading || podsQuery.isLoading || eventsQuery.isLoading;

  return (
    <div className="stack">
      <section className="panel">
        <h2>Pods</h2>
        <p className="muted">Your MTG pods and other tabletop play groups.</p>
        <div className="actions">
          <Link className="btn btn-primary" to="/create-pod">
            New pod
          </Link>
          <Link className="btn btn-outline" to="/invites">
            Pending invites
          </Link>
        </div>
      </section>

      <section className="panel">
        <h3>Your pods</h3>
        {isLoading ? (
          <p className="muted">Loading pods...</p>
        ) : !user ? (
          <p className="muted">Sign in to view your pods.</p>
        ) : (podsQuery.data?.length ?? 0) === 0 ? (
          <p className="muted">No pods yet. Create one to get started.</p>
        ) : (
          <ul className="list">
            {(podsQuery.data ?? []).map((pod) => (
              <li key={pod.id} className="list-row">
                <div>
                  <p>{pod.name}</p>
                  <p className="muted">
                    {[pod.location_text, roleLabels[pod.role] ?? 'Member'].filter(Boolean).join(' · ')}
                  </p>
                </div>
                <Link className="btn btn-outline" to={`/pod/${pod.id}`}>
                  Open
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="panel">
        <h3>Upcoming across pods</h3>
        {isLoading ? (
          <p className="muted">Loading events...</p>
        ) : (eventsQuery.data?.length ?? 0) === 0 ? (
          <p className="muted">No upcoming events yet.</p>
        ) : (
          <ul className="list">
            {(eventsQuery.data ?? []).map((event) => (
              <li key={event.id} className="list-row">
                <div>
                  <p>{event.title}</p>
                  <p className="muted">
                    {formatEventTime(event.starts_at)} · {podNameById.get(event.pod_id) ?? 'Your pod'}
                  </p>
                </div>
                <Link className="btn btn-outline" to={`/event/${event.id}`}>
                  View
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
