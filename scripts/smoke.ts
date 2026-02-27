type SessionPayload = {
  authenticated: boolean;
  user: {
    email: string;
    id: number;
    name: string | null;
  } | null;
};

type CookieJar = Map<string, string>;

const appUrl = process.env.SMOKE_APP_URL ?? 'http://localhost:3000';
const seededEmail = process.env.SMOKE_SEEDED_EMAIL ?? 'test@example.com';
const seededPassword = process.env.SMOKE_SEEDED_PASSWORD ?? 'password';
const uniqueSuffix = Date.now();
const registeredEmail = `smoke-${uniqueSuffix}@example.com`;
const registeredPassword = 'password123';

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function applySetCookie(jar: CookieJar, response: Response) {
  const getSetCookie = Reflect.get(response.headers, 'getSetCookie');
  const values =
    typeof getSetCookie === 'function'
      ? (getSetCookie.call(response.headers) as string[])
      : response.headers.get('set-cookie')
        ? [response.headers.get('set-cookie') as string]
        : [];

  for (const header of values) {
    const [cookie = ''] = header.split(';', 1);
    const [rawName, ...rawValue] = cookie.split('=');
    const name = rawName?.trim() ?? '';

    if (!name) {
      continue;
    }

    const value = rawValue.join('=');

    if (value.length === 0) {
      jar.delete(name);
      continue;
    }

    jar.set(name, value);
  }
}

function serializeCookies(jar: CookieJar): string | undefined {
  if (jar.size === 0) {
    return undefined;
  }

  return [...jar.entries()].map(([name, value]) => `${name}=${value}`).join('; ');
}

async function request(jar: CookieJar, path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  const cookieHeader = serializeCookies(jar);

  if (cookieHeader) {
    headers.set('cookie', cookieHeader);
  }

  if (init.body && !headers.has('content-type')) {
    headers.set('content-type', 'application/json');
  }

  const response = await fetch(new URL(path, appUrl), {
    ...init,
    headers,
    redirect: 'manual',
  });

  applySetCookie(jar, response);
  return response;
}

async function readJson<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

async function main() {
  const jar = new Map<string, string>();

  let response = await request(jar, '/api/session');
  let payload = await readJson<SessionPayload>(response);
  assert(response.ok, 'Anonymous session request failed.');
  assert(payload.authenticated === false, 'Anonymous session should be unauthenticated.');

  response = await request(jar, '/api/login', {
    method: 'POST',
    body: JSON.stringify({
      email: seededEmail,
      password: seededPassword,
    }),
  });
  assert(response.ok, 'Seeded user login failed.');
  assert(jar.has('authjs.session-token'), 'Seeded user login did not set a session cookie.');

  response = await request(jar, '/api/session');
  payload = await readJson<SessionPayload>(response);
  assert(payload.authenticated === true, 'Seeded user session did not persist.');
  assert(payload.user?.email === seededEmail, 'Seeded user session resolved the wrong user.');

  response = await request(jar, '/dashboard');
  const dashboardHtml = await response.text();
  assert(response.status === 200, 'Authenticated dashboard request should return 200.');
  assert(
    dashboardHtml.includes('PodDashboard'),
    'Dashboard response did not render the app shell.',
  );

  response = await request(jar, '/api/pods');
  assert(response.ok, 'Seeded user pod list failed.');

  response = await request(jar, '/api/events');
  assert(response.ok, 'Seeded user event list failed.');

  response = await request(jar, '/api/pods', {
    method: 'POST',
    body: JSON.stringify({
      name: `Smoke Pod ${uniqueSuffix}`,
      description: 'Created by the smoke check.',
    }),
  });
  assert(response.status === 201, 'Seeded user pod creation failed.');

  response = await request(jar, '/api/logout', {
    method: 'POST',
  });
  assert(response.ok, 'Seeded user logout failed.');

  response = await request(jar, '/api/session');
  payload = await readJson<SessionPayload>(response);
  assert(payload.authenticated === false, 'Session should be cleared after logout.');

  response = await request(jar, '/api/register', {
    method: 'POST',
    body: JSON.stringify({
      email: registeredEmail,
      name: 'Smoke User',
      password: registeredPassword,
      passwordConfirmation: registeredPassword,
    }),
  });
  assert(response.status === 201, 'User registration failed.');

  response = await request(jar, '/api/login', {
    method: 'POST',
    body: JSON.stringify({
      email: registeredEmail,
      password: registeredPassword,
    }),
  });
  assert(response.ok, 'Registered user login failed.');

  response = await request(jar, '/api/session');
  payload = await readJson<SessionPayload>(response);
  assert(payload.user?.email === registeredEmail, 'Registered user session did not persist.');

  response = await request(jar, '/api/pods', {
    method: 'POST',
    body: JSON.stringify({
      name: `Smoke Member Pod ${uniqueSuffix}`,
      description: 'Created by the registered member.',
    }),
  });
  assert(response.status === 201, 'Registered member pod creation failed.');

  console.log(`Smoke check passed against ${appUrl}`);
}

main().catch((error) => {
  console.error('Smoke check failed.');
  console.error(error);
  process.exitCode = 1;
});
