import { Form, redirect, useActionData, useLoaderData, type ActionFunctionArgs, type LoaderFunctionArgs } from 'react-router';

import { createPodForUser, listPodsForUser, listUpcomingEventsForUser } from '../lib/pods.server';
import { requireUser } from '../lib/session.server';
import { createPodSchema } from '../lib/validation';

type ActionData = {
  error?: string;
};

export async function loader({ request }: LoaderFunctionArgs) {
  const user = await requireUser(request);
  const [pods, events] = await Promise.all([listPodsForUser(user.id), listUpcomingEventsForUser(user.id)]);

  return { user, pods, events };
}

export async function action({ request }: ActionFunctionArgs) {
  const user = await requireUser(request);
  const formData = await request.formData();

  const parseResult = createPodSchema.safeParse({
    name: formData.get('name'),
    description: formData.get('description'),
  });

  if (!parseResult.success) {
    return {
      error: parseResult.error.issues[0]?.message ?? 'Invalid pod input.',
    } satisfies ActionData;
  }

  await createPodForUser(user.id, parseResult.data.name, parseResult.data.description);
  return redirect('/');
}

export default function DashboardRoute() {
  const { pods, events } = useLoaderData<typeof loader>();
  const actionData = useActionData<ActionData>();

  return (
    <div className="grid">
      <section className="panel">
        <h1>Dashboard</h1>
        <p className="muted">All reads and writes are handled via React Router loaders/actions.</p>
      </section>

      <section className="panel">
        <h2>Create a pod</h2>
        <Form method="post" className="stack">
          <label htmlFor="name">Pod name</label>
          <input id="name" name="name" type="text" required maxLength={120} />

          <label htmlFor="description">Description</label>
          <textarea id="description" name="description" rows={3} maxLength={500} />

          {actionData?.error ? <p className="error">{actionData.error}</p> : null}
          <button type="submit" className="button">
            Create pod
          </button>
        </Form>
      </section>

      <section className="panel">
        <h2>Your pods</h2>
        {pods.length === 0 ? (
          <p className="muted">No pods yet. Create your first pod above.</p>
        ) : (
          <ul className="list">
            {pods.map((pod) => (
              <li key={pod.id}>
                <strong>{pod.name}</strong>
                {pod.description ? <span className="muted">{pod.description}</span> : null}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="panel">
        <h2>Upcoming events</h2>
        {events.length === 0 ? (
          <p className="muted">No upcoming events.</p>
        ) : (
          <ul className="list">
            {events.map((event) => (
              <li key={event.id}>
                <strong>{event.title}</strong>
                <span className="muted">
                  {event.podName} ·{' '}
                  {new Intl.DateTimeFormat(undefined, {
                    dateStyle: 'medium',
                    timeStyle: 'short',
                  }).format(new Date(event.scheduledFor))}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
