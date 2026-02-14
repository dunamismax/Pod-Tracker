import { index, route, type RouteConfig } from '@react-router/dev/routes';

export default [
  route('login', 'routes/login.tsx'),
  route('verify', 'routes/verify.tsx'),
  route('logout', 'routes/logout.ts'),
  route('api/pods', 'routes/api.pods.ts'),
  route('api/events', 'routes/api.events.ts'),
  index('routes/_index.tsx'),
] satisfies RouteConfig;
