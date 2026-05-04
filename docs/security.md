# Security

Ideal Magic will handle accounts, deck history, Codex account-auth metadata, and AI usage records. Security work should be implemented as product behavior, not saved for deployment cleanup.

## Authentication

V1 should use Rails-native email/password authentication as the baseline. Account flows must include:

- Secure session handling.
- Email verification.
- Password reset.
- Account deletion.
- Data export.

Passkeys or external auth providers are future hardening options after the baseline is stable.

## AI Auth And Secrets

OpenAI API keys must never be exposed to browsers. V1 user-facing AI usage should not use app-owned API keys or bring-your-own API keys as the operating model.

Supported v1 mode:

- Codex App Server ChatGPT-managed account auth, started through Codex browser OAuth or device-code login, with Codex handling token refresh.

Allowed implementation boundaries:

- Store only the minimum account metadata needed by Rails, such as auth mode, displayed email, plan type when returned, rate-limit snapshots, and timestamps.
- Keep Codex credential material isolated per user or per serialized workflow stream.
- Treat any Codex `auth.json` or equivalent token cache like a password.
- Let Codex refresh managed ChatGPT sessions; do not call private refresh endpoints directly.

Blocked modes:

- Asking for ChatGPT passwords.
- Scraping ChatGPT.
- Browser-visible OpenAI API keys.
- Generic OpenAI API OAuth outside the documented Codex App Server account surface.
- Hand-rolled ChatGPT token refresh or token exchange code outside Codex's documented flow.
- Claiming ChatGPT billing pays for arbitrary OpenAI API calls.

Codex account login, logout, token-cache creation, refresh failure, and deletion should be audit logged without logging credential values.

## Privacy

Users should control whether deck analyses are private, shared by link, or public. Defaults should favor privacy until the sharing model is implemented and visible.

Do not store provider passwords or private provider session cookies. Do not exfiltrate private deck data to providers or AI services beyond the explicit analysis workflow.

AI requests should include only the information needed for evaluation. Deterministic card facts and summarized deck features are preferred over raw unrelated user data.

## Abuse Controls

Before public launch, add rate limits for:

- Signups and login attempts.
- Password resets.
- Deck imports.
- Analysis creation.
- Public share pages.

Analysis jobs should have user and global quotas so account rate limits and server resources are bounded.

## Audit Events

Audit events should cover:

- Authentication changes.
- Deck imports and refreshes.
- Analysis creation and failures.
- Codex account link, logout, token-cache, and auth failure events.
- Admin actions.
- Share visibility changes.

Audit logs must not contain secrets.

## Fan Content Notice Plan

Ideal Magic is unofficial fan content. The app must include a visible notice before public launch:

> Ideal Magic is unofficial fan content. It is not approved, endorsed, or sponsored by Wizards of the Coast. Portions of Magic: The Gathering materials are property of Wizards of the Coast LLC.

The notice should appear in site footer or legal pages and any public pages that materially display Magic card names, text, images, or related material.

Do not place core access to WotC IP-backed fan content behind payment without legal review.

## Security Checks

The planned Rails foundation should include:

- Brakeman.
- RuboCop security-oriented rules where practical.
- Bundle audit tooling.
- Tests for key handling and auth flows.
- Review of CSRF, CSP, secure cookies, CORS, and security headers before public launch.
