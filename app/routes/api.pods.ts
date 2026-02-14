import type { ActionFunctionArgs, LoaderFunctionArgs } from 'react-router';

import { createPodForUser, listPodsForUser } from '../lib/pods.server';
import { getUserFromRequest } from '../lib/session.server';
import { createPodSchema } from '../lib/validation';

export async function loader({ request }: LoaderFunctionArgs) {
  const user = await getUserFromRequest(request);
  if (!user) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const pods = await listPodsForUser(user.id);
  return Response.json({ pods });
}

export async function action({ request }: ActionFunctionArgs) {
  const user = await getUserFromRequest(request);
  if (!user) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return Response.json({ error: 'Request body must be valid JSON.' }, { status: 400 });
  }

  const parseResult = createPodSchema.safeParse(payload);
  if (!parseResult.success) {
    return Response.json(
      {
        error: parseResult.error.issues[0]?.message ?? 'Invalid payload.',
      },
      { status: 400 }
    );
  }

  const pod = await createPodForUser(user.id, parseResult.data.name, parseResult.data.description);
  return Response.json({ pod }, { status: 201 });
}
