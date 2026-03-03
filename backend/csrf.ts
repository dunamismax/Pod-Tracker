const CSRF_COOKIE = 'csrf_token';
const CSRF_HEADER = 'x-csrf-token';

export function generateCsrfToken(): string {
  return crypto.randomUUID();
}

export function getCsrfCookie(request: Request): string | null {
  const cookies = request.headers.get('cookie') ?? '';
  const match = cookies.match(new RegExp(`(?:^|;\\s*)${CSRF_COOKIE}=([^;]+)`));
  return match?.[1] ?? null;
}

export function validateCsrf(request: Request): boolean {
  const cookieToken = getCsrfCookie(request);
  const headerToken = request.headers.get(CSRF_HEADER);

  if (!cookieToken || !headerToken) {
    return false;
  }

  return cookieToken === headerToken;
}

export function csrfCookieHeader(token: string): string {
  return `${CSRF_COOKIE}=${token}; Path=/; HttpOnly=false; SameSite=Lax; Max-Age=86400`;
}
