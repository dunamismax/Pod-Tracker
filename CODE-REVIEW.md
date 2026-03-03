# Code Review — PodWatch

**Date:** 2026-03-03
**Scope:** Full codebase (~1 840 lines across 30 source files)
**Toolchain results:** Lint clean (42 files), typecheck clean, build successful (SPA mode)

---

## 1. Architecture

**Stack:** React 19 + React Router 7 (SPA) / Bun HTTP server / PostgreSQL + Drizzle ORM / Better Auth / Tailwind CSS 4 / Zod 4

The high-level split is solid: `app/` for the React SPA, `backend/` for the API server, `db/` for schema and migrations, `scripts/` for tooling. Each module is small and focused.

### Strengths

- Clean separation between frontend and backend with no shared runtime dependencies.
- Drizzle schema is well-indexed and properly normalized, with cascade deletes and composite primary keys where appropriate.
- RBAC system (`roles` / `permissions` / `rolePermissions` / `userRoles`) is a real permission model, not just a boolean `isAdmin` flag.
- Zod validation on both env parsing and request bodies.
- Route guards (`AuthLayout`, `GuestLayout`) keep auth redirection logic out of individual pages.
- Build output is lean — client JS totals ~410 KB (~135 KB gzipped) with good code-splitting per route.

### Issues

| Severity | Issue | Location |
|----------|-------|----------|
| **Medium** | React Query is initialized in `root.tsx` but never used. Dashboard fetches data with raw `fetch` + `useState` instead of `useQuery`/`useMutation`. This defeats the purpose of the dependency and leaves the app without caching, deduplication, background refetch, or optimistic updates. | `app/root.tsx:5-12`, `app/routes/dashboard.tsx:47-60` |
| **Medium** | No CORS headers on business API routes (`/api/pods`, `/api/events`, `/health`). Better Auth only sets CORS on `/api/auth/*`. In production with separate origins the business endpoints will fail cross-origin requests. | `backend/index.ts` |
| **Medium** | README API table is stale — lists `/api/register`, `/api/login`, `/api/logout`, `/api/session` but actual auth routes are Better Auth's `/api/auth/sign-in/email`, `/api/auth/sign-up/email`, `/api/auth/sign-out`, `/api/auth/get-session`. | `README.md:76-83` |
| **Low** | No global error handler in `Bun.serve`. An unhandled throw in any handler propagates as a 500 with no structured body or logging. | `backend/index.ts:11` |

---

## 2. TypeScript & Type Safety

### Strengths

- `strict: true` in tsconfig — the strongest baseline.
- Drizzle schema types flow correctly into query results.
- Zod schemas for request validation produce typed outputs.
- `as const` used for auth status strings in `useAuth`.

### Issues

| Severity | Issue | Location |
|----------|-------|----------|
| **Medium** | `SessionUser` is defined twice with conflicting types: backend has `id: number`, frontend has `id: string`. Better Auth returns `id` as a string; the backend coerces it with `Number()`. This split creates a silent type mismatch if any frontend code sends the id back to the backend. | `backend/session.ts:3-7`, `app/hooks/use-auth.tsx:3-7` |
| **Low** | `apiFetch` return type is `Promise<T>` with no runtime check that the response actually matches `T`. The cast is fine for now but fragile if the API shape changes. | `app/lib/api.ts:6` |
| **Low** | `Pod`, `EventRecord`, and `DashboardData` types are defined locally in `dashboard.tsx`. If other routes need these they'll be duplicated. | `app/routes/dashboard.tsx:12-30` |
| **Low** | `colorClasses` in Button and Badge accepts `string` instead of the union type, losing type narrowing. | `app/components/ui/button.tsx:16`, `app/components/ui/badge.tsx:10` |

---

## 3. React Patterns

### Strengths

- Functional components throughout, no class components.
- `forwardRef` on `Input` and `Textarea` for proper form library integration.
- `displayName` set on forwarded-ref components.
- `useCallback` on `fetchData` with correct empty dependency array.
- Layout/outlet pattern for auth guards is clean and idiomatic RR7.

### Issues

| Severity | Issue | Location |
|----------|-------|----------|
| **High** | No error boundaries. Any render-time throw in a route component shows a white screen with no recovery path. | Entire `app/routes/` tree |
| **Medium** | Dashboard does full refetch of *both* pods and events after creating a single pod. With React Query this would be a targeted invalidation. | `app/routes/dashboard.tsx:78` |
| **Low** | Auth guard layouts (`home.tsx`, `guest-layout.tsx`, `auth-layout.tsx`) return `null` during the loading state, causing a flash of empty screen before content renders. A skeleton or spinner would improve perceived performance. | `app/routes/home.tsx:8`, `app/routes/guest-layout.tsx:8`, `app/routes/auth-layout.tsx:8` |
| **Low** | `QueryClient` is created at module scope outside the component tree. This is fine for SPA but would break with SSR if the config ever changes. | `app/root.tsx:5` |

---

## 4. Backend & API Design

### Strengths

- `requirePermission` helper centralizes auth + permission check with proper 401/403 distinction.
- Pod creation uses a transaction to atomically insert the pod and its membership row.
- Zod validation returns the first issue message as a user-facing error string.
- Event query scopes to user's pods via `innerJoin` on `podMembers` — no data leakage.
- `parseJson` handles malformed JSON gracefully with a 400.

### Issues

| Severity | Issue | Location |
|----------|-------|----------|
| **High** | No rate limiting on any endpoint. Auth endpoints (login, register) are especially vulnerable to brute-force/credential-stuffing. | `backend/index.ts` |
| **Medium** | `userHasPermission` runs 2 sequential queries per call. Every authenticated request hits this. Could be a single join query or cached per-request. | `backend/permissions.ts:21-46` |
| **Medium** | `ensureAccessControlBootstrap` uses sequential `await` in `for` loops for permission and role-permission inserts. Could batch with `Promise.all` or multi-row `INSERT`. | `backend/permissions.ts:48-91` |
| **Medium** | No pagination on `GET /api/pods`. If a user belongs to hundreds of pods, the response will be unbounded. | `backend/api.ts:43-62` |
| **Low** | Event query includes past events (last 24 hours) but the dashboard labels the section "Upcoming events" — semantically misleading. | `backend/api.ts:145`, `app/routes/dashboard.tsx:251` |
| **Low** | No request logging. Failed requests, slow queries, and errors are invisible in production. | `backend/index.ts` |

---

## 5. Security

### Strengths

- Password hashing via bcryptjs with 12 salt rounds.
- Session cookies managed by Better Auth with cookie caching.
- RBAC checked on every business endpoint.
- SQL injection prevented by Drizzle ORM parameterized queries.
- No secrets in source — env vars validated through Zod.

### Issues

| Severity | Issue | Location |
|----------|-------|----------|
| **High** | Login page unconditionally displays seeded credentials (`test@example.com / password`). This should be gated on `NODE_ENV === 'development'` or removed. In production it tells attackers exactly what to try. | `app/routes/login.tsx:88-92` |
| **Medium** | `AUTH_SECRET` defaults to `'dev-secret-change-me'`. If the app is deployed without setting this env var, all sessions are signed with a known secret. The default should be removed for production, or startup should throw when `NODE_ENV=production` and the secret is the default. | `backend/env.ts:7` |
| **Medium** | No CSRF token verification on the custom API routes. Better Auth handles its own routes, but `POST /api/pods` relies solely on cookie-based auth with no additional CSRF protection. | `backend/api.ts:64` |
| **Low** | Password placeholder on the login form is the literal string `"password"`, which doubles as the actual seeded password. Placeholder should be generic (e.g., `"••••••••"`). | `app/routes/login.tsx:70` |

---

## 6. UI / UX

### Strengths

- Cohesive dark theme with custom CSS properties and gradient backgrounds.
- Responsive layout with sensible breakpoints (sm, lg, xl).
- Consistent component design language across Card, Button, Badge, Input, Textarea.
- Good empty states with personality ("the dashboard stops feeling like an abandoned bridge").
- Proper loading and disabled states on buttons.

### Issues

| Severity | Issue | Location |
|----------|-------|----------|
| **Medium** | No feedback during the loading state on initial page load for auth guard routes — user sees a blank screen while the session check resolves. | `app/routes/home.tsx`, `app/routes/guest-layout.tsx`, `app/routes/auth-layout.tsx` |
| **Low** | No real-time validation on forms. Password mismatch on register is only caught on submit. Email format, password length requirements, and name presence give no inline feedback. | `app/routes/register.tsx:21-24`, `app/routes/login.tsx` |
| **Low** | No toast/notification system. Success of pod creation is only visible by the pod appearing in the list. An explicit success confirmation would improve UX. | `app/routes/dashboard.tsx:76-78` |
| **Low** | No confirmation dialog for sign-out. One click and the user is logged out. | `app/routes/dashboard.tsx:86-89` |
| **Low** | `session?.email` rendered in the header has no fallback if null. | `app/routes/dashboard.tsx:116` |

---

## 7. Accessibility

### Strengths

- `lang="en"` on `<html>`.
- Proper `<label htmlFor>` on all form inputs.
- Semantic HTML: `<main>`, `<header>`, `<form>`, `<ul>`/`<li>`.
- `aria-hidden="true"` on the spinner SVG in Button.
- Focus-visible styling on inputs via ring/border transitions.

### Issues

| Severity | Issue | Location |
|----------|-------|----------|
| **Medium** | No skip-to-content link. Keyboard users must tab through the full header before reaching main content. | `app/root.tsx` |
| **Medium** | Error messages (`displayError`, form errors) are not announced to screen readers. Need `role="alert"` or `aria-live="polite"` on error containers. | `app/routes/dashboard.tsx:131-135`, `app/routes/login.tsx:77-80`, `app/routes/register.tsx:112-115` |
| **Low** | Loading text ("Loading pods...", "Loading events...") is not announced. Screen reader users don't know content is loading. | `app/routes/dashboard.tsx:208, 255` |
| **Low** | The "Signed in as" box and sign-out button lack landmark designation. Consider `<nav>` or `aria-label` for the user controls region. | `app/routes/dashboard.tsx:113-127` |
| **Low** | Color contrast not verified. The dark theme uses `text-slate-300` on dark backgrounds and `text-amber-200/80` labels — worth running through WCAG AA checker. | Various |

---

## 8. Performance

### Strengths

- Vite `optimizeDeps.include` pre-bundles heavy dependencies.
- React Router automatic code-splitting per route.
- Database indexes on all foreign keys and query-path columns.
- Event query limited to 20 rows.
- `Promise.all` for parallel data fetching on dashboard load.

### Issues

| Severity | Issue | Location |
|----------|-------|----------|
| **Medium** | Permission check is 2 sequential DB queries on every authenticated request. A single `JOIN` query or per-request cache would halve latency. | `backend/permissions.ts:21-46` |
| **Medium** | After pod creation, `fetchData()` re-fetches both pods and events. Only the pods list changed. | `app/routes/dashboard.tsx:78` |
| **Low** | No pagination on pods. Linear growth in response size as pods scale. | `backend/api.ts:43-62` |
| **Low** | Bootstrap runs sequential inserts in a loop. For the current 6 permissions this is fine, but it should batch if the permission set grows. | `backend/permissions.ts:49-54, 78-90` |

---

## 9. Dead Code & Tech Debt

| Severity | Item | Location |
|----------|------|----------|
| **Medium** | `parseCookies()` and `serializeCookie()` are exported from `backend/http.ts` but never imported anywhere. Dead code. | `backend/http.ts:12-69` |
| **Medium** | `@tanstack/react-query` is a runtime dependency, configured in `root.tsx`, but zero `useQuery`/`useMutation` calls exist. Either migrate dashboard to React Query or remove the dependency. | `package.json:24`, `app/root.tsx:1` |
| **Low** | `CookieOptions` type in `http.ts` is only used by the dead `serializeCookie`. | `backend/http.ts:32-39` |
| **Low** | `backend/db.ts` exports `pool` — only consumed by `db/seed.ts` for cleanup. Consider exporting a `close()` function instead of the raw pool. | `backend/db.ts` |
| **Low** | Button `colorClasses` has an implicit fallback — `warning + soft` is unhandled and silently returns the same as `warning + default`. Badge has the same pattern for unhandled combos like `info + outline`. | `app/components/ui/button.tsx:16-27`, `app/components/ui/badge.tsx:10-24` |
| **Low** | Smoke tests (`scripts/smoke.ts`) duplicate cookie utilities already in `backend/http.ts` (though the backend ones are dead). If the backend utilities are kept, smoke tests should import them. | `scripts/smoke.ts:17-52` |
| **Info** | README lists "Dark/light UI" as a feature, but there is no light mode — the app is dark-only. | `README.md:12` |

---

## 10. Testing

- **Smoke tests** (`scripts/smoke.ts`): Good coverage of the happy path — anonymous session, login, session persistence, dashboard render, pod CRUD, registration flow. Uses a proper cookie jar.
- **No unit tests.** No component tests. No integration tests beyond smoke.
- **No CI pipeline.** Lint/typecheck/build are manual.

### Recommended additions (by priority)

1. Unit tests for `userHasPermission` and `requirePermission` — these are the security boundary.
2. API endpoint tests covering error paths (bad JSON, missing fields, unauthorized, forbidden).
3. Component tests for form validation behavior (login, register, pod creation).
4. CI workflow running `bun run lint && bun run typecheck && bun run build`.

---

## 11. Prioritized Improvements

### P0 — Fix before production

1. **Gate seeded credentials display** on dev mode or remove entirely (`login.tsx:88-92`).
2. **Add rate limiting** to auth endpoints at minimum.
3. **Add CORS headers** to business API routes or use a global CORS middleware.
4. **Fail-safe on AUTH_SECRET** — throw on startup if production and secret is the default.
5. **Add error boundaries** to the React Router tree.

### P1 — High value

6. **Migrate dashboard to React Query** — replace manual fetch/setState with `useQuery`/`useMutation`. Enables caching, deduplication, background refetch, targeted invalidation.
7. **Single-query permission check** — rewrite `userHasPermission` as one JOIN.
8. **Add `role="alert"`** to error message containers for screen reader announcement.
9. **Add pagination** to `GET /api/pods` (and eventually events).
10. **Fix README** API table to match actual Better Auth routes.

### P2 — Quality of life

11. Remove dead code (`parseCookies`, `serializeCookie`, `CookieOptions`).
12. Add a loading skeleton or spinner to auth guard layouts instead of returning `null`.
13. Extract shared API types to `app/lib/types.ts`.
14. Add skip-to-content link in root layout.
15. Add request logging to the backend.
16. Add inline form validation (password match, email format, field length).
17. Unify `SessionUser` type — single source of truth shared between frontend and backend.
18. Batch permission bootstrap inserts.

### P3 — Nice to have

19. Add toast/notification for successful actions.
20. Global error handler in `Bun.serve` with structured error responses.
21. Tighten `colorClasses` type signatures in Button and Badge to handle all variant/color combos explicitly.
22. CI pipeline (GitHub Actions) for lint + typecheck + build.
23. Add unit and component tests.
24. Consider removing React Query dependency if migration isn't planned soon.

---

## Summary

PodWatch is a clean, well-organized early-stage dashboard. The TypeScript is strict, the schema is solid, the component library is consistent, and the RBAC model is thoughtfully designed. The main gaps are: security hardening for production (rate limiting, CORS, credential leak), adopting React Query for the data layer it was installed for, adding error boundaries, and building out test coverage. None of these are deep architectural problems — they're checklist items for the next hardening pass.
