<p align="center">
  <img src="public/favicon.svg" alt="PodDashboard logo" width="84" />
</p>

<p align="center">
  Dark-themed TALL app for auth, pod management, and upcoming event visibility.
</p>

# PodDashboard

PodDashboard is a focused TALL-stack application for organizing tabletop pods and events.  
It uses Laravel Fortify for authentication, Livewire for server-driven UI, Flux UI for components, and Tailwind for styling.

## Current Features

- Dark-themed dashboard UI built with Flux components and Tailwind
- Laravel Fortify auth flows:
  - login/logout
  - register
  - forgot/reset password
  - confirm password routes
- Authenticated dashboard at `/dashboard`:
  - create pods
  - list your pods
  - list upcoming events across pods you belong to
- Session-authenticated JSON API:
  - `GET /api/pods`
  - `POST /api/pods`
  - `GET /api/events`

## Tech Stack

- Laravel 12
- Livewire 4
- Alpine.js (bundled via Livewire)
- Flux UI Free
- Tailwind CSS 4
- Vite 7
- Pest 4 / PHPUnit 12

## Requirements

- PHP 8.2+ (currently tested in this repo on 8.4.1)
- Composer 2+
- Node.js 22+ (Node 24 also works)
- npm 10+
- PostgreSQL 14+ by default (`.env.example`), or another Laravel-supported database

## Setup

### One-command setup

```bash
composer setup
```

`composer setup` installs PHP + JS dependencies, creates `.env` if needed, generates the app key, runs migrations, and builds frontend assets.

### Manual setup

```bash
cp .env.example .env
composer install
npm install
php artisan key:generate
php artisan migrate
npm run build
```

## Run Locally

```bash
composer dev
```

This starts:

- `php artisan serve`
- `php artisan queue:listen`
- `php artisan pail`
- `npm run dev`

If UI changes are not visible, run `npm run dev` or `npm run build`.

## Route Surface (Current)

### Web

- `GET /` redirects to `/dashboard`
- `GET /dashboard` (auth)
- `GET /login` / `POST /login`
- `POST /logout`
- `GET /register` / `POST /register`
- `GET /forgot-password` / `POST /forgot-password`
- `GET /reset-password/{token}` / `POST /reset-password`
- `GET /user/confirm-password` / `POST /user/confirm-password`
- `GET /user/confirmed-password-status`
- `GET /up`

### API (session-authenticated)

- `GET /api/pods`
- `POST /api/pods`
- `GET /api/events`

Notes:

- API endpoints rely on the authenticated session user (`$request->user()`); unauthenticated requests return `401`.
- `POST /api/pods` expects valid JSON and returns `400` when the request body is malformed.

## Example API Request

Create pod:

```http
POST /api/pods
Content-Type: application/json
```

```json
{
  "name": "Friday Pod",
  "description": "Casual commander table"
}
```

Success response (`201`):

```json
{
  "pod": {
    "id": 1,
    "name": "Friday Pod",
    "description": "Casual commander table",
    "role": "owner"
  }
}
```

## Seed Data

```bash
php artisan db:seed
```

Default seeded user:

- Email: `test@example.com`
- Password: `password`

## Quality Commands

```bash
php artisan test --compact
php artisan test --compact tests/Feature/OtpAuthenticationTest.php
php artisan test --compact tests/Feature/DashboardFeatureTest.php
composer lint
vendor/bin/pint --dirty --format agent
npm run build
```

## Project Layout

```text
app/
  Actions/Fortify/           Fortify user/password actions
  Http/Controllers/Api/      API endpoints
  Http/Requests/             API request validation
  Livewire/                  Dashboard Livewire component
  Models/                    User, Pod, PodMember, Event
  Providers/FortifyServiceProvider.php
resources/views/
  auth/                      Fortify auth views (Flux UI)
  layouts/pod.blade.php      Global app shell
  livewire/                  Dashboard view
routes/web.php               Web + API route definitions
tests/Feature/               Auth, dashboard, and API behavior tests
```

## Security Notes

- Auth is provided by Laravel Fortify (web guard).
- Login is rate-limited at 5 attempts/minute by email+IP.
- Passwords are hashed via Laravel’s user password casting/hashing pipeline.
- Dashboard and API responses are scoped to the authenticated user.

## Reference Files

- `routes/web.php` for route definitions
- `app/Providers/FortifyServiceProvider.php` for auth views and rate limiter
- `tests/Feature/OtpAuthenticationTest.php` for auth flow coverage
- `tests/Feature/DashboardFeatureTest.php` for dashboard behavior
- `tests/Feature/ApiEndpointsTest.php` for API behavior and auth responses
- `AGENTS.md` for repository-specific agent instructions

## License

MIT (`LICENSE`)
