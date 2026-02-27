import { randomUUID } from 'node:crypto';
import { and, eq, gt } from 'drizzle-orm';
import { sessions, users } from '../db/schema';
import { db } from './db';
import { env } from './env';
import { parseCookies, serializeCookie } from './http';

const SESSION_COOKIE_NAMES = ['__Secure-authjs.session-token', 'authjs.session-token'] as const;
const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 30;

export type SessionUser = {
  id: number;
  email: string;
  name: string | null;
};

function getSessionCookieName() {
  return env.APP_URL.startsWith('https://')
    ? '__Secure-authjs.session-token'
    : 'authjs.session-token';
}

export function appendSessionCookie(headers: Headers, token: string, expires: Date) {
  headers.append(
    'Set-Cookie',
    serializeCookie(getSessionCookieName(), token, {
      expires,
      httpOnly: true,
      path: '/',
      sameSite: 'Lax',
      secure: env.APP_URL.startsWith('https://'),
    }),
  );
}

export function clearSessionCookies(headers: Headers) {
  const expires = new Date(0);

  for (const name of SESSION_COOKIE_NAMES) {
    headers.append(
      'Set-Cookie',
      serializeCookie(name, '', {
        expires,
        httpOnly: true,
        maxAge: 0,
        path: '/',
        sameSite: 'Lax',
        secure: name.startsWith('__Secure-'),
      }),
    );
  }
}

export async function createSession(userId: number) {
  const sessionToken = randomUUID();
  const expires = new Date(Date.now() + SESSION_MAX_AGE_SECONDS * 1000);

  await db.insert(sessions).values({
    sessionToken,
    userId,
    expires,
  });

  return {
    expires,
    sessionToken,
  };
}

export async function destroySession(request: Request) {
  const cookies = parseCookies(request);

  for (const cookieName of SESSION_COOKIE_NAMES) {
    const sessionToken = cookies.get(cookieName);

    if (!sessionToken) {
      continue;
    }

    await db.delete(sessions).where(eq(sessions.sessionToken, sessionToken));
  }
}

export async function resolveSessionUser(request: Request): Promise<SessionUser | null> {
  const cookies = parseCookies(request);
  const sessionToken =
    cookies.get('__Secure-authjs.session-token') ?? cookies.get('authjs.session-token') ?? null;

  if (!sessionToken) {
    return null;
  }

  const now = new Date();
  const record = await db
    .select({
      id: users.id,
      email: users.email,
      name: users.name,
    })
    .from(sessions)
    .innerJoin(users, eq(users.id, sessions.userId))
    .where(and(eq(sessions.sessionToken, sessionToken), gt(sessions.expires, now)))
    .limit(1);

  if (!record[0]) {
    return null;
  }

  return record[0];
}
