import { createAuthClient } from 'better-auth/react';
import { apiBaseUrl } from './api-base';

export const authClient = createAuthClient({
  baseURL: apiBaseUrl || undefined,
  credentials: 'include',
});
