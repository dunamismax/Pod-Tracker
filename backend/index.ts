import {
  handleEventsIndex,
  handleLogin,
  handleLogout,
  handlePodsCreate,
  handlePodsIndex,
  handleRegister,
  handleSession,
} from './api';
import { env } from './env';
import { json } from './http';
import { ensureAccessControlBootstrap } from './permissions';

await ensureAccessControlBootstrap();

const server = Bun.serve({
  port: env.PORT,
  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === '/api/session' && request.method === 'GET') {
      return handleSession(request);
    }

    if (url.pathname === '/api/login' && request.method === 'POST') {
      return handleLogin(request);
    }

    if (url.pathname === '/api/logout' && request.method === 'POST') {
      return handleLogout(request);
    }

    if (url.pathname === '/api/register' && request.method === 'POST') {
      return handleRegister(request);
    }

    if (url.pathname === '/api/pods' && request.method === 'GET') {
      return handlePodsIndex(request);
    }

    if (url.pathname === '/api/pods' && request.method === 'POST') {
      return handlePodsCreate(request);
    }

    if (url.pathname === '/api/events' && request.method === 'GET') {
      return handleEventsIndex(request);
    }

    if (url.pathname === '/health' && request.method === 'GET') {
      return json({ status: 'ok' });
    }

    return json({ error: 'Not Found' }, 404);
  },
});

console.log(`API listening on ${server.url}`);
