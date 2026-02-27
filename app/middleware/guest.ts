import { defineNuxtRouteMiddleware, navigateTo } from '#imports';
import { useAuth } from '~/composables/useAuth';

export default defineNuxtRouteMiddleware(async () => {
  const auth = useAuth();
  const session = await auth.ensureLoaded();

  if (session.authenticated) {
    return navigateTo('/dashboard');
  }
});
