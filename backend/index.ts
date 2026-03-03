import { handleEventsIndex, handlePodsCreate, handlePodsIndex } from './api';
import { auth } from './auth';
import { csrfCookieHeader, generateCsrfToken, getCsrfCookie, validateCsrf } from './csrf';
import { env } from './env';
import { json } from './http';
import { ensureAccessControlBootstrap } from './permissions';
import { isRateLimited } from './rate-limit';

await ensureAccessControlBootstrap();

const allowedOrigins = new Set([env.APP_URL, env.APP_URL.replace('localhost', '127.0.0.1')]);

function corsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get('origin');
  if (origin && allowedOrigins.has(origin)) {
    return {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, x-csrf-token',
      'Access-Control-Allow-Credentials': 'true',
    };
  }
  return {};
}

const server = Bun.serve({
  port: env.PORT,
  async fetch(request) {
    const url = new URL(request.url);
    const start = Date.now();

    try {
      // Handle CORS preflight
      if (request.method === 'OPTIONS') {
        return new Response(null, { status: 204, headers: corsHeaders(request) });
      }

      // Rate limit auth endpoints
      if (url.pathname.startsWith('/api/auth') && isRateLimited(request)) {
        console.warn(`[${request.method}] ${url.pathname} — 429 (rate limited)`);
        return json({ error: 'Too many requests. Try again later.' }, 429);
      }

      // CSRF: reject mutating custom API requests without valid CSRF token
      const isMutating =
        request.method === 'POST' || request.method === 'PUT' || request.method === 'DELETE';
      if (isMutating && url.pathname.startsWith('/api/') && !url.pathname.startsWith('/api/auth')) {
        if (!validateCsrf(request)) {
          return json({ error: 'Invalid CSRF token.' }, 403);
        }
      }

      let response: Response;

      // Better Auth handles all /api/auth/* routes
      if (url.pathname.startsWith('/api/auth')) {
        response = await auth.handler(request);
      } else if (url.pathname === '/api/pods' && request.method === 'GET') {
        response = await handlePodsIndex(request);
      } else if (url.pathname === '/api/pods' && request.method === 'POST') {
        response = await handlePodsCreate(request);
      } else if (url.pathname === '/api/events' && request.method === 'GET') {
        response = await handleEventsIndex(request);
      } else if (url.pathname === '/health' && request.method === 'GET') {
        response = json({ status: 'ok' });
      } else {
        response = json({ error: 'Not Found' }, 404);
      }

      // Append CORS headers to all responses
      const headers = corsHeaders(request);
      for (const [key, value] of Object.entries(headers)) {
        response.headers.set(key, value);
      }

      // Ensure CSRF cookie is always set
      if (!getCsrfCookie(request)) {
        response.headers.append('Set-Cookie', csrfCookieHeader(generateCsrfToken()));
      }

      const ms = Date.now() - start;
      console.log(`[${request.method}] ${url.pathname} — ${response.status} (${ms}ms)`);

      return response;
    } catch (err) {
      const ms = Date.now() - start;
      console.error(`[${request.method}] ${url.pathname} — 500 (${ms}ms)`, err);
      return json({ error: 'Internal server error.' }, 500);
    }
  },
});

console.log(`API listening on ${server.url}`);
