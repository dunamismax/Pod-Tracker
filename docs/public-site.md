# Public marketing site

The public marketing surface lives under `PublicController` and renders without authentication. It is the only part of `pod-tracker.app` that anonymous visitors can read.

## Routes

| Path | Controller action | Purpose |
| --- | --- | --- |
| `/` | `public#home` | Landing page — pitch, brackets explainer teaser, CTAs. Resolves to the same action for signed-in visitors (header swaps to "Open app"). |
| `/brackets` | `public#brackets` | Long-form Commander Brackets guide. Renders the canonical Game Changers list (`db/seeds/commander/brackets/game_changers.json`) and the current Commander banned list (`LegalitySnapshot.current_commander`). |
| `/brackets/game-changers` | `public#game_changers` | Dedicated Game Changers list grouped by category. |
| `/brackets/pregame-template` | `public#pregame_template` | Copy-pasteable Rule 0 template with worked examples for each bracket. |
| `/about` | `public#about` | What Pod Tracker is, fan-content disclaimer, GitHub link. |
| `/privacy` | `public#privacy` | Privacy policy stub. |
| `/terms` | `public#terms` | Terms stub. |
| `/sitemap.xml` | `public#sitemap` | XML sitemap of the public marketing URLs. |

`PublicController` declares `allow_unauthenticated_access` once at the top; every action inherits it. The rest of the app sits behind the global `Authentication#require_authentication` before-action.

The signed-in dashboard lives at `/app` (`dashboard#show`). The root path was historically a redirect to `/session/new`; it now renders the marketing landing for everyone.

## Layout

There is no separate `marketing.html.erb` layout. `app/views/layouts/application.html.erb` is public-aware:

- Header shows **Sign in** + **Create account** when anonymous and **Open app** + **Sign out** when signed in.
- Footer renders the fan-content disclaimer and links to GitHub, Privacy, and Terms.
- `<title>`, `<meta name="description">`, `og:title`, `og:description`, `og:url`, `og:image`, `twitter:title`, `twitter:description`, and `twitter:image` are populated from per-page `content_for :title` / `content_for :meta_description`. The OG/Twitter image defaults to `/hero-screens.png`.
- A site-wide JSON-LD `Organization` + `WebSite` graph is emitted on every page via `ApplicationHelper#jsonld_tag`.
- A `<link rel="canonical">` tag is emitted on every page; pages can override it via `content_for :canonical_url` if a query-string variant ever needs to point at a clean URL.
- Per-page JSON-LD (e.g. `Article`, `BreadcrumbList`) is appended via `content_for :jsonld_extra` and rendered in `<head>` after the site-wide graph.

If the marketing surface ever diverges enough from the app shell to warrant a dedicated layout, split it then — not before.

## Content edit workflow

Most pages are static ERB under `app/views/public/`. Edit, run the relevant tests, redeploy.

- **Brackets data is source-controlled, not hard-coded.** The Game Changers list is read from `db/seeds/commander/brackets/game_changers.json`. The two-card combo catalog is `db/seeds/commander/brackets/two_card_combos.json`. The banned list is read from `LegalitySnapshot.current_commander`. Changing what those pages display almost always means editing the seed data and re-seeding (`bin/rails db:seed`), not editing the view.
- **Bracket-level definitions** live in `Decks::BracketEvaluator::BRACKETS`. The `/brackets` page reads metadata from there (label, expected minimum turn, restrictions). Update the constant when official rules change.
- **Bracket section partials.** `/brackets` includes `_bracket_section_1.html.erb` through `_bracket_section_5.html.erb`. Each partial owns the long-form prose for one bracket; edit those files when refining the explanation.
- **Worked examples on `/brackets/pregame-template`** are inline in the template. Update them when the Game Changers or banned list shifts the right reference deck.
- **Meta description.** Every public page sets `content_for :meta_description`. Keep it under ~160 characters and make it a single sentence that stands alone in a search snippet.

After any content edit, run `bin/rails test test/controllers/public_controller_test.rb` and `bin/verify` before pushing.

## SEO baseline

Currently shipped on every public page:

- `<title>` and `<meta name="description">`.
- `og:title`, `og:description`, `og:url`, `og:site_name`, `og:type`, `og:image`, `og:image:alt`.
- `twitter:card=summary_large_image`, `twitter:title`, `twitter:description`, `twitter:image`.
- `<link rel="canonical">`.
- JSON-LD `Organization` + `WebSite` graph (site-wide).
- JSON-LD `BreadcrumbList` on `/brackets`, `/brackets/game-changers`, `/brackets/pregame-template`.
- JSON-LD `Article` on `/brackets`.
- `/sitemap.xml` listing the public URLs with `lastmod`, `changefreq`, and `priority`.
- `public/robots.txt` allows crawling of the public surface, disallows authenticated paths (`/account`, `/decks`, `/pods`, `/app`, `/session`, `/p/`, etc.), and references the sitemap.

What is intentionally **not** done yet:

- No automated sitemap regeneration; the controller emits a hand-curated set of public URLs each request. Add deck/pod public-share URLs to the sitemap only if and when those become indexable on purpose.
- No `Article` / `FAQPage` schema on `/brackets/game-changers`, `/brackets/pregame-template`, or `/about`. Breadcrumbs cover navigation; expand to richer schema if a specific page starts getting search traffic that warrants it.
- No `og:image` per page — every page uses the same hero screenshot. Per-page OG images are a follow-up if individual pages start needing custom share previews.

## Auth gating

- The controllers listed above explicitly opt out of the auth before-action via `allow_unauthenticated_access`.
- Every other controller in the app stays behind `require_authentication` (defined in `Authentication` concern).
- The header and footer adapt based on `authenticated?`; no auth-required data is rendered on the public surface.

## Tests

`test/controllers/public_controller_test.rb` covers:

- Each public page renders without authentication.
- Signed-in users are not redirected away from public pages.
- The site-wide JSON-LD graph is present on every page.
- `/brackets` emits both `Article` and `BreadcrumbList` structured data.
- Every public page declares a single canonical link.
- `/sitemap.xml` returns XML containing the bracket URLs.
