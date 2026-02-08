import { useEffect, useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';

import {
  useCreateChecklistItem,
  useEventAttendance,
  useEventById,
  useEventChecklist,
  useEventRealtime,
  useUpdateArrival,
  useUpdateChecklistItem,
  useUpdateRsvp,
} from '@/features/events/events-queries';
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

type ArrivalKey = keyof typeof arrivalLabels;

const checklistNextState = {
  open: 'done',
  done: 'blocked',
  blocked: 'open',
} as const;

export function EventDetailPage() {
  const { id } = useParams();
  const eventId = id ?? '';
  const { user, isLoading: authLoading } = useSession();

  const eventQuery = useEventById(eventId);
  const podsQuery = usePodsByUser(user?.id);
  const attendanceQuery = useEventAttendance(eventId);
  const checklistQuery = useEventChecklist(eventId);
  useEventRealtime(eventId);

  const updateRsvp = useUpdateRsvp();
  const updateArrival = useUpdateArrival();
  const updateChecklistItem = useUpdateChecklistItem();
  const createChecklistItem = useCreateChecklistItem();

  const attendanceUserIds = useMemo(
    () => (attendanceQuery.data ?? []).map((member) => member.user_id),
    [attendanceQuery.data]
  );
  const profilesQuery = useProfilesByIds(attendanceUserIds);
  const profileById = useMemo(
    () => new Map((profilesQuery.data ?? []).map((profile) => [profile.id, profile])),
    [profilesQuery.data]
  );

  const currentAttendance = (attendanceQuery.data ?? []).find((row) => row.user_id === user?.id);
  const [etaInput, setEtaInput] = useState('');
  const [newItemLabel, setNewItemLabel] = useState('');
  const [newItemNote, setNewItemNote] = useState('');
  const [status, setStatus] = useState<string | null>(null);

  useEffect(() => {
    if (!currentAttendance) return;
    setEtaInput(currentAttendance.eta_minutes !== null ? String(currentAttendance.eta_minutes) : '');
  }, [currentAttendance]);

  const parsedEta = Number(etaInput);
  const etaMinutes = etaInput.trim() ? parsedEta : null;
  const etaError =
    etaInput.trim().length > 0 && (!Number.isInteger(parsedEta) || parsedEta < 0);
  const podRole = useMemo(
    () => (eventQuery.data ? (podsQuery.data ?? []).find((pod) => pod.id === eventQuery.data?.pod_id)?.role : null),
    [eventQuery.data, podsQuery.data]
  );
  const isCanceled = Boolean(eventQuery.data?.canceled_at);
  const canManageEvent = Boolean(
    user &&
      eventQuery.data &&
      (eventQuery.data.created_by === user.id || podRole === 'owner' || podRole === 'admin')
  );

  const isLoading = authLoading || eventQuery.isLoading || podsQuery.isLoading;
  const canInteract = Boolean(user && eventQuery.data && !isCanceled);

  const handleRsvp = (rsvp: 'yes' | 'no' | 'maybe') => {
    if (!user || !eventQuery.data) return;
    setStatus(null);
    updateRsvp.mutate(
      { eventId: eventQuery.data.id, userId: user.id, rsvp },
      {
        onError: (error) => setStatus(error instanceof Error ? error.message : 'Unable to update RSVP.'),
      }
    );
  };

  const handleArrival = (arrival: ArrivalKey) => {
    if (!canInteract || !user || !eventQuery.data || etaError) return;
    setStatus(null);
    updateArrival.mutate(
      {
        eventId: eventQuery.data.id,
        userId: user.id,
        arrival,
        etaMinutes,
      },
      {
        onError: (error) => setStatus(error instanceof Error ? error.message : 'Unable to update arrival.'),
      }
    );
  };

  const handleAddChecklistItem = async () => {
    if (!user || !eventQuery.data || newItemLabel.trim().length === 0) return;
    setStatus(null);
    try {
      await createChecklistItem.mutateAsync({
        eventId: eventQuery.data.id,
        userId: user.id,
        label: newItemLabel.trim(),
        note: newItemNote.trim() ? newItemNote.trim() : null,
      });
      setNewItemLabel('');
      setNewItemNote('');
    } catch (error) {
      setStatus(error instanceof Error ? error.message : 'Unable to add checklist item.');
    }
  };

  return (
    <div className="stack">
      <section className="panel">
        <div className="section-header">
          <h2>{eventQuery.data?.title ?? 'Event'}</h2>
          {eventQuery.data && canManageEvent ? (
            <Link className="btn btn-outline" to={`/event/edit/${eventQuery.data.id}`}>
              Edit event
            </Link>
          ) : null}
        </div>
        {isLoading ? (
          <p className="muted">Loading event...</p>
        ) : eventQuery.data ? (
          <>
            <p className="muted">
              {eventQuery.data.pod?.name ?? 'Your pod'} ·{' '}
              {formatEventTime(eventQuery.data.starts_at, eventQuery.data.ends_at)}
            </p>
            <p className="muted">{eventQuery.data.location_text ?? 'Location TBD'}</p>
            {eventQuery.data.description ? <p>{eventQuery.data.description}</p> : null}
            {isCanceled ? (
              <p className="error">
                Canceled{eventQuery.data.cancel_reason ? `: ${eventQuery.data.cancel_reason}` : '.'}
              </p>
            ) : null}
          </>
        ) : (
          <p className="muted">You do not have access to this event.</p>
        )}
      </section>

      <section className="panel">
        <h3>RSVP</h3>
        <div className="actions">
          <button className="btn btn-primary" disabled={!canInteract} onClick={() => handleRsvp('yes')} type="button">
            I am in
          </button>
          <button className="btn btn-outline" disabled={!canInteract} onClick={() => handleRsvp('maybe')} type="button">
            Maybe
          </button>
          <button className="btn btn-outline" disabled={!canInteract} onClick={() => handleRsvp('no')} type="button">
            Cannot make it
          </button>
        </div>
      </section>

      <section className="panel">
        <h3>Arrival status</h3>
        <label className="field">
          ETA minutes
          <input
            className="input"
            inputMode="numeric"
            min={0}
            onChange={(event) => setEtaInput(event.target.value)}
            step={1}
            type="number"
            value={etaInput}
          />
        </label>
        {etaError ? <p className="error">Enter a valid number of minutes.</p> : null}
        <div className="actions">
          {Object.entries(arrivalLabels).map(([value, label]) => (
            <button
              className={`btn ${currentAttendance?.arrival === value ? 'btn-primary' : 'btn-outline'}`}
              disabled={!canInteract}
              key={value}
              onClick={() => handleArrival(value as ArrivalKey)}
              type="button">
              {label}
            </button>
          ))}
        </div>
        <ul className="list">
          {(attendanceQuery.data ?? []).map((member) => (
            <li className="list-row" key={member.id}>
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
      </section>

      <section className="panel">
        <h3>Checklist</h3>
        {(checklistQuery.data?.length ?? 0) === 0 ? (
          <p className="muted">Checklist is empty.</p>
        ) : (
          <ul className="list">
            {(checklistQuery.data ?? []).map((item) => (
              <li className="list-row" key={item.id}>
                <div>
                  <p>{item.label}</p>
                  <p className="muted">{item.note ?? item.state}</p>
                </div>
                <button
                  className="btn btn-outline"
                  disabled={!canInteract}
                  onClick={() =>
                    eventQuery.data &&
                    updateChecklistItem.mutate({
                      eventId: eventQuery.data.id,
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
        <div className="grid">
          <label className="field">
            New item
            <input
              className="input"
              onChange={(event) => setNewItemLabel(event.target.value)}
              value={newItemLabel}
            />
          </label>
          <label className="field">
            Note
            <input
              className="input"
              onChange={(event) => setNewItemNote(event.target.value)}
              value={newItemNote}
            />
          </label>
        </div>
        <button
          className="btn btn-primary"
          disabled={!canInteract || newItemLabel.trim().length === 0 || createChecklistItem.isPending}
          onClick={handleAddChecklistItem}
          type="button">
          Add item
        </button>
      </section>

      {status ? <p className="muted">{status}</p> : null}
    </div>
  );
}
