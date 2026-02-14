# PodDashboard

Magic Pod Dashboard is a Laravel + Livewire app for organizing tabletop play groups (“pods”), tracking memberships, and viewing upcoming events. It is built for developers who want a clean Laravel 12 codebase with OTP authentication and a fast local workflow.

![PHP](https://img.shields.io/badge/PHP-8.2%2B-777BB4?logo=php&logoColor=white)
![Laravel](https://img.shields.io/badge/Laravel-12-FF2D20?logo=laravel&logoColor=white)
![Livewire](https://img.shields.io/badge/Livewire-4-4E56A6)
![Pest](https://img.shields.io/badge/Tests-Pest%204-22C55E)
![License](https://img.shields.io/badge/License-MIT-blue)

## Quick Start

### Prerequisites

- PHP `8.2+` (repo currently runs on PHP `8.4.1`)
- Composer `2+`
- Node.js + npm (required for Vite asset build)
- Database server (PostgreSQL is the default in `.env.example`)

### Run Locally

```bash
cp .env.example .env
composer install
npm install
php artisan key:generate
php artisan migrate
npm run build
php artisan serve
```

Expected result: app available at `http://127.0.0.1:8000` with login at `http://127.0.0.1:8000/login`.

### Verified Commands (This Repo Session)

```bash
php artisan test --compact
npm run build
php artisan route:list
```

## Features

### Authentication

- Email OTP sign-in flow with expiring one-time codes
- Session-based authentication for protected pages
- OTP send and verify throttling to reduce abuse and brute-force attempts

### Pod Management

- Create pods from the dashboard
- Automatic owner membership creation on pod creation
- View all pods for the authenticated user

### Event Visibility

- Upcoming events feed scoped to pods the user belongs to
- JSON API endpoint for upcoming events

### API Endpoints

- `GET /api/pods` lists current user pods
- `POST /api/pods` creates a pod
- `GET /api/events` lists upcoming events

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Runtime | [PHP](https://www.php.net/) 8.2+ | Application runtime |
| Framework | [Laravel](https://laravel.com/docs/12.x) 12 | Web framework, routing, validation, auth/session plumbing |
| UI | [Livewire](https://livewire.laravel.com/) 4 | Reactive server-driven UI |
| Components | [Flux UI](https://fluxui.dev/) 2 (free) | UI component primitives |
| Auth | [Laravel Fortify](https://laravel.com/docs/12.x/fortify) | Headless auth backend utilities |
| Frontend Build | [Vite](https://vite.dev/) 7 + [Tailwind CSS](https://tailwindcss.com/) 4 | Asset pipeline and styling |
| Database | PostgreSQL (default config), SQLite in tests | Persistent data + fast test runtime |
| Testing | [Pest](https://pestphp.com/) 4 + PHPUnit 12 | Feature and unit testing |
| Formatting | [Laravel Pint](https://laravel.com/docs/12.x/pint) | Code style enforcement |

## Project Structure

```text
poddashboard/
├── app/
│   ├── Http/Controllers/Api/    # JSON API controllers for pods/events
│   ├── Http/Requests/           # API validation requests
│   ├── Livewire/                # Livewire page components (login/verify/dashboard)
│   ├── Models/                  # Eloquent models (User, Pod, Event, etc.)
│   ├── Providers/               # Service provider bootstrapping and defaults
│   └── Services/                # OTP auth service logic
├── database/
│   ├── migrations/              # Schema for users, pods, events, otp codes, etc.
│   └── factories/               # Test model factories
├── resources/
│   ├── views/                   # Blade and Livewire view templates
│   ├── css/                     # Tailwind CSS entry
│   └── js/                      # Vite JS entry
├── routes/
│   ├── web.php                  # Main web + API routes
│   ├── console.php              # Console route definitions
│   └── settings.php             # Settings routes reference
├── tests/
│   ├── Feature/                 # End-to-end behavior tests
│   └── Unit/                    # Unit tests
├── composer.json                # PHP dependencies and Composer scripts
├── package.json                 # Frontend dependencies and npm scripts
└── phpunit.xml                  # Test configuration
```

## Development Workflow and Common Commands

### Setup

```bash
composer install
npm install
cp .env.example .env
php artisan key:generate
php artisan migrate
```

### Run

```bash
php artisan serve
npm run dev
composer run dev
```

### Test

```bash
php artisan test --compact
php artisan test --compact tests/Feature/OtpAuthenticationTest.php
composer test
```

### Lint and Format

```bash
vendor/bin/pint --dirty --format agent
composer run lint
composer run test:lint
```

### Build

```bash
npm run build
```

Notes:

- `composer run dev` starts server, queue listener, log tailing, and Vite in one command.
- `composer run setup` exists for first-time bootstrap; it was not re-run in this session because dependencies were already installed.

## Deployment and Operations

This repository does not include infra manifests (Docker/Kubernetes/Terraform), but it follows standard Laravel deployment patterns.

### Deployment Model

- PHP application server (Nginx/Apache + PHP-FPM) with built frontend assets from `npm run build`

### Required Environment Setup

- Application key: `APP_KEY`
- App URL: `APP_URL`
- Database credentials (`DB_*` or `DATABASE_URL`)
- SMTP settings for OTP email delivery (`MAIL_*` / `SMTP_*`)

### Operational Entry Points

- Health check route: `GET /up`
- App logs: `storage/logs/laravel.log`
- Live log tailing in development: `php artisan pail`

## Security and Reliability Notes

### Authentication Model

- OTP-based email sign-in backed by Laravel session auth
- OTP codes are stored as hashes and have expiry/consumption tracking

### Abuse Protection

- Request throttling for OTP issuance
- Attempt throttling for OTP verification

### Input and Transport Safeguards

- Request validation in Livewire actions and Form Requests
- Eloquent ORM usage for query safety and maintainability
- CSRF protection via Laravel `web` middleware stack

### Quality Controls

- Pest feature tests cover authentication and API behavior
- Pint formatting enforced via Composer scripts

## Documentation

| Path | Purpose |
|---|---|
| [`README.md`](README.md) | Primary onboarding and workflow guide |
| [`AGENTS.md`](AGENTS.md) | Repository-specific engineering instructions and constraints |
| [`.env.example`](.env.example) | Environment variable template and defaults |
| [`routes/web.php`](routes/web.php) | Source of truth for user-facing and API routes |
| [`tests/Feature`](tests/Feature) | Executable behavior documentation via feature tests |

## Contributing

Contributions are welcome via pull requests.

1. Create a branch for your change.
2. Run formatting and tests locally.
3. Open a PR with a clear summary and test evidence.

If you plan to make larger changes, open an issue first to align on scope.

## License

Licensed under the [MIT License](LICENSE).
