import { redirect, type ActionFunctionArgs } from 'react-router';

import { clearSessionCookie, destroySession, getSessionToken } from '../lib/session.server';

export async function loader() {
  throw redirect('/');
}

export async function action({ request }: ActionFunctionArgs) {
  const sessionToken = await getSessionToken(request);

  if (sessionToken) {
    await destroySession(sessionToken);
  }

  throw redirect('/login', {
    headers: {
      'Set-Cookie': await clearSessionCookie(),
    },
  });
}
