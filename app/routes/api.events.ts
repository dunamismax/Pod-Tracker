import type { LoaderFunctionArgs } from 'react-router';

import { listUpcomingEventsForUser } from '../lib/pods.server';
import { getUserFromRequest } from '../lib/session.server';

export async function loader({ request }: LoaderFunctionArgs) {
  const user = await getUserFromRequest(request);
  if (!user) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const events = await listUpcomingEventsForUser(user.id);
  return Response.json({ events });
}
