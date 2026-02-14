import { createCookie, redirect } from 'react-router';

import { db } from './db.server';
import { hashWithSecret, generateSessionToken } from './crypto.server';
import { env } from './env.server';

const SESSION_COOKIE_NAME = 'mpd_session';
const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 14;

type SessionUser = {
  id: number;
  email: string;
};

const sessionCookie = createCookie(SESSION_COOKIE_NAME, {
  path: '/',
  httpOnly: true,
  sameSite: 'lax',
  secure: env.NODE_ENV === 'production',
  maxAge: SESSION_MAX_AGE_SECONDS,
  secrets: [env.SESSION_SECRET],
});

export async function getSessionToken(request: Request): Promise<string | null> {
  const cookieHeader = request.headers.get('Cookie');
  const token = await sessionCookie.parse(cookieHeader);
  return typeof token === 'string' && token.length > 0 ? token : null;
}

export async function commitSessionCookie(token: string): Promise<string> {
  return sessionCookie.serialize(token);
}

export async function clearSessionCookie(): Promise<string> {
  return sessionCookie.serialize('', { maxAge: 0 });
}

export async function createSessionForUser(userId: number): Promise<string> {
  const token = generateSessionToken();
  const tokenHash = hashWithSecret(token);

  await db.query(
    `
      insert into sessions (token_hash, user_id, expires_at)
      values ($1, $2, now() + interval '14 days')
    `,
    [tokenHash, userId]
  );

  return token;
}

export async function getUserFromRequest(request: Request): Promise<SessionUser | null> {
  const token = await getSessionToken(request);
  if (!token) {
    return null;
  }

  const tokenHash = hashWithSecret(token);

  const result = await db.query<SessionUser>(
    `
      select u.id, u.email
      from sessions s
      inner join users u on u.id = s.user_id
      where s.token_hash = $1
        and s.expires_at > now()
      limit 1
    `,
    [tokenHash]
  );

  return result.rows[0] ?? null;
}

export async function requireUser(request: Request): Promise<SessionUser> {
  const user = await getUserFromRequest(request);
  if (!user) {
    throw redirect('/login');
  }
  return user;
}

export async function destroySession(token: string): Promise<void> {
  const tokenHash = hashWithSecret(token);
  await db.query('delete from sessions where token_hash = $1', [tokenHash]);
}
