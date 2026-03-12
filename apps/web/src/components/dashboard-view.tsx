import type { DashboardSnapshot } from "@podwatch/domain";
import { CalendarFold, LoaderCircle, LogOut, Orbit, Plus } from "lucide-react";

import { CoachPanel } from "#/components/coach-panel";
import type { MutationResult, Viewer } from "#/lib/server-fns";
import { formatInTimeZone } from "#/lib/timezone";

type PodFormState = {
  name: string;
  description: string;
};

type EventFormState = {
  podId: string;
  title: string;
  location: string;
  scheduledFor: string;
  description: string;
};

type DashboardViewProps = {
  viewer: Viewer;
  snapshot: DashboardSnapshot;
  timezone: string;
  podForm: PodFormState;
  eventForm: EventFormState;
  podResult: MutationResult<unknown> | null;
  eventResult: MutationResult<unknown> | null;
  isCreatingPod: boolean;
  isCreatingEvent: boolean;
  onPodFormChange: (next: PodFormState) => void;
  onEventFormChange: (next: EventFormState) => void;
  onPodSubmit: (event: React.FormEvent<HTMLFormElement>) => void;
  onEventSubmit: (event: React.FormEvent<HTMLFormElement>) => void;
  onSignOut: () => void;
};

const ResultBanner = ({
  result,
}: {
  result: MutationResult<unknown> | null;
}) => {
  if (!result) {
    return null;
  }

  return (
    <p className={result.ok ? "result-banner success" : "result-banner error"}>
      {result.ok ? result.message : result.error}
    </p>
  );
};

export function DashboardView(props: DashboardViewProps) {
  const { snapshot } = props;

  return (
    <main className="page-shell">
      <section className="hero-panel">
        <div className="hero-copy">
          <p className="eyebrow">Pod Scheduling Board</p>
          <h1>PodWatch</h1>
          <p className="lede">
            Build small recurring groups, put real meetings on the calendar, and
            keep the board readable enough that the next move is obvious.
          </p>
        </div>

        <div className="hero-actions">
          <div className="viewer-chip">
            <span>{props.viewer.name}</span>
            <small>{props.viewer.email}</small>
          </div>
          <button
            className="ghost-button"
            type="button"
            onClick={props.onSignOut}
          >
            <LogOut size={16} />
            Sign out
          </button>
        </div>

        <div className="stat-rail">
          <article className="stat-card">
            <span>Pods tracked</span>
            <strong>{snapshot.summary.podCount}</strong>
          </article>
          <article className="stat-card">
            <span>Total events</span>
            <strong>{snapshot.summary.eventCount}</strong>
          </article>
          <article className="stat-card">
            <span>Upcoming</span>
            <strong>{snapshot.summary.upcomingCount}</strong>
          </article>
          <article className="stat-card timezone-card">
            <span>Timeline timezone</span>
            <strong suppressHydrationWarning>{props.timezone}</strong>
          </article>
        </div>
      </section>

      <section className="dashboard-grid">
        <div className="column-stack">
          <article className="panel form-panel">
            <div className="panel-heading">
              <p className="eyebrow">Pods</p>
              <h2>Create a pod</h2>
            </div>
            <p className="panel-copy">
              A pod is just a named recurring group. Keep the object tight, then
              schedule concrete events against it.
            </p>
            <ResultBanner result={props.podResult} />
            <form className="stacked-form" onSubmit={props.onPodSubmit}>
              <label className="field">
                <span>Name</span>
                <input
                  value={props.podForm.name}
                  onChange={(event) =>
                    props.onPodFormChange({
                      ...props.podForm,
                      name: event.target.value,
                    })
                  }
                  placeholder="Friday Pod"
                  required
                />
              </label>
              <label className="field">
                <span>Description</span>
                <textarea
                  value={props.podForm.description}
                  onChange={(event) =>
                    props.onPodFormChange({
                      ...props.podForm,
                      description: event.target.value,
                    })
                  }
                  placeholder="Small recurring group with a standing purpose."
                  rows={4}
                />
              </label>
              <button
                className="primary-button"
                type="submit"
                disabled={props.isCreatingPod}
              >
                {props.isCreatingPod ? (
                  <LoaderCircle className="spin" size={18} />
                ) : (
                  <Plus size={18} />
                )}
                Create pod
              </button>
            </form>
          </article>

          <article className="panel form-panel">
            <div className="panel-heading">
              <p className="eyebrow">Schedule</p>
              <h2>Schedule an event</h2>
            </div>
            <p className="panel-copy">
              Event times are stored as UTC and rendered back in the browser
              timezone. The board keeps the most recent day visible so a
              just-finished meeting still has context.
            </p>
            <ResultBanner result={props.eventResult} />
            <form className="stacked-form" onSubmit={props.onEventSubmit}>
              <label className="field">
                <span>Pod</span>
                <select
                  value={props.eventForm.podId}
                  onChange={(event) =>
                    props.onEventFormChange({
                      ...props.eventForm,
                      podId: event.target.value,
                    })
                  }
                  required
                >
                  <option value="">Select a pod</option>
                  {snapshot.pods.map((pod) => (
                    <option key={pod.id} value={pod.id}>
                      {pod.name}
                    </option>
                  ))}
                </select>
              </label>
              <label className="field">
                <span>Title</span>
                <input
                  value={props.eventForm.title}
                  onChange={(event) =>
                    props.onEventFormChange({
                      ...props.eventForm,
                      title: event.target.value,
                    })
                  }
                  placeholder="Commander Night"
                  required
                />
              </label>
              <div className="field-row">
                <label className="field">
                  <span>Location</span>
                  <input
                    value={props.eventForm.location}
                    onChange={(event) =>
                      props.onEventFormChange({
                        ...props.eventForm,
                        location: event.target.value,
                      })
                    }
                    placeholder="Library meeting room"
                  />
                </label>
                <label className="field">
                  <span>Local date and time</span>
                  <input
                    type="datetime-local"
                    value={props.eventForm.scheduledFor}
                    onChange={(event) =>
                      props.onEventFormChange({
                        ...props.eventForm,
                        scheduledFor: event.target.value,
                      })
                    }
                    required
                  />
                </label>
              </div>
              <label className="field">
                <span>Notes</span>
                <textarea
                  value={props.eventForm.description}
                  onChange={(event) =>
                    props.onEventFormChange({
                      ...props.eventForm,
                      description: event.target.value,
                    })
                  }
                  placeholder="Optional notes, agenda, or what to bring."
                  rows={4}
                />
              </label>
              <button
                className="primary-button"
                type="submit"
                disabled={props.isCreatingEvent || snapshot.pods.length === 0}
              >
                {props.isCreatingEvent ? (
                  <LoaderCircle className="spin" size={18} />
                ) : (
                  <CalendarFold size={18} />
                )}
                Schedule event
              </button>
            </form>
          </article>
        </div>

        <div className="column-stack">
          <article className="panel list-panel">
            <div className="panel-heading">
              <p className="eyebrow">Directory</p>
              <h2>Current pods</h2>
            </div>
            {snapshot.pods.length > 0 ? (
              <ul className="list-grid">
                {snapshot.pods.map((pod) => (
                  <li className="list-card" key={pod.id}>
                    <div className="list-card-heading">
                      <h3>{pod.name}</h3>
                      <span>{pod.eventCount} event(s)</span>
                    </div>
                    <p>{pod.description || "No description yet."}</p>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="empty-state">
                No pods exist yet. Create one to unlock scheduling.
              </p>
            )}
          </article>

          <article className="panel list-panel timeline-panel">
            <div className="panel-heading">
              <p className="eyebrow">Timeline</p>
              <h2>Recent and upcoming events</h2>
            </div>
            {snapshot.events.length > 0 ? (
              <ul className="timeline-list">
                {snapshot.events.map((event) => (
                  <li className="timeline-row" key={event.id}>
                    <div className="timeline-icon">
                      <Orbit size={16} />
                    </div>
                    <div className="timeline-content">
                      <div className="list-card-heading">
                        <h3>{event.title}</h3>
                        <span>{event.podName}</span>
                      </div>
                      <p suppressHydrationWarning>
                        {formatInTimeZone(event.scheduledFor, props.timezone)}
                      </p>
                      {event.location ? (
                        <small>Location: {event.location}</small>
                      ) : null}
                      {event.description ? (
                        <small>{event.description}</small>
                      ) : null}
                    </div>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="empty-state">
                No events yet. Schedule one once a pod exists.
              </p>
            )}
          </article>

          <article className="panel coach-panel">
            <div className="panel-heading">
              <p className="eyebrow">AI Layer</p>
              <h2>Schedule coach</h2>
            </div>
            <CoachPanel />
          </article>
        </div>
      </section>
    </main>
  );
}
