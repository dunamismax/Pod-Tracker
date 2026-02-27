export function json(data: unknown, status = 200, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  headers.set('Content-Type', 'application/json');

  return new Response(JSON.stringify(data), {
    ...init,
    status,
    headers,
  });
}

export function parseCookies(request: Request): Map<string, string> {
  const header = request.headers.get('cookie');
  const map = new Map<string, string>();

  if (!header) {
    return map;
  }

  for (const chunk of header.split(';')) {
    const [key, ...valueParts] = chunk.trim().split('=');
    if (!key) {
      continue;
    }

    map.set(key, decodeURIComponent(valueParts.join('=')));
  }

  return map;
}

type CookieOptions = {
  expires?: Date;
  httpOnly?: boolean;
  maxAge?: number;
  path?: string;
  sameSite?: 'Lax' | 'None' | 'Strict';
  secure?: boolean;
};

export function serializeCookie(name: string, value: string, options: CookieOptions = {}): string {
  const segments = [`${name}=${encodeURIComponent(value)}`];

  if (options.path) {
    segments.push(`Path=${options.path}`);
  }

  if (options.expires) {
    segments.push(`Expires=${options.expires.toUTCString()}`);
  }

  if (typeof options.maxAge === 'number') {
    segments.push(`Max-Age=${options.maxAge}`);
  }

  if (options.httpOnly) {
    segments.push('HttpOnly');
  }

  if (options.secure) {
    segments.push('Secure');
  }

  if (options.sameSite) {
    segments.push(`SameSite=${options.sameSite}`);
  }

  return segments.join('; ');
}
