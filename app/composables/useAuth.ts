import { computed, readonly } from 'vue';
import { useState } from '#imports';
import { apiFetch } from '~/utils/api-fetch';

export type SessionUser = {
  email: string;
  id: number;
  name: string | null;
};

export type SessionPayload = {
  authenticated: boolean;
  user: SessionUser | null;
};

type AuthStatus = 'authenticated' | 'loading' | 'unauthenticated';

export function useAuth() {
  const session = useState<SessionUser | null>('auth:session', () => null);
  const status = useState<AuthStatus>('auth:status', () => 'loading');

  function applySession(data: SessionPayload) {
    session.value = data.user;
    status.value = data.authenticated ? 'authenticated' : 'unauthenticated';
    return data;
  }

  function clearSession() {
    session.value = null;
    status.value = 'unauthenticated';
  }

  async function refreshSession() {
    status.value = 'loading';

    try {
      const data = await apiFetch<SessionPayload>('/api/session');
      return applySession(data);
    } catch {
      return applySession({
        authenticated: false,
        user: null,
      });
    }
  }

  async function ensureLoaded() {
    if (status.value !== 'loading') {
      return {
        authenticated: Boolean(session.value),
        user: session.value,
      } satisfies SessionPayload;
    }

    return refreshSession();
  }

  async function signIn(payload: { email: string; password: string }) {
    await apiFetch('/api/login', {
      method: 'POST',
      body: payload,
    });

    await refreshSession();
  }

  async function signOut() {
    await apiFetch('/api/logout', {
      method: 'POST',
    });

    clearSession();
  }

  return {
    session: readonly(session),
    status: readonly(status),
    isAuthenticated: computed(() => status.value === 'authenticated'),
    applySession,
    clearSession,
    ensureLoaded,
    refreshSession,
    signIn,
    signOut,
  };
}
