# Security

Pod Tracker handles accounts, deck history, collection ownership, playgroup sessions, matchup notes, Codex account-auth metadata, and AI usage records. Security work belongs in product behavior and operational runbooks, not only in deployment cleanup.

## Authentication

Pod Tracker uses Rails-native email/password authentication as the baseline. Account flows include:

- Secure session handling.
- Email verification.
- Password reset.
- Account deletion.
- Data export.

Passkeys or external auth providers remain future hardening options.

## AI Auth And Secrets

OpenAI API keys must never be exposed to browsers. User-facing AI usage does not use app-owned API keys or bring-your-own API keys as the operating model.

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

Codex account login, logout, token-cache creation, refresh failure, and deletion are audit logged without logging credential values.

Implemented credential-handling review as of 2026-05-04:

- `CodexAccount` stores the opaque credential payload in an Active Record encrypted column and keeps one account record per user.
- Local disconnect and remote logout flows call `CodexAccount#disconnect!`, which clears credential payloads, credential metadata, rate-limit snapshots, expiration data, and error state before recording audit events.
- Account export exposes Codex account status, auth mode, displayed email, plan type, rate-limit snapshots, timestamp metadata, and credential metadata key names only. It does not export the encrypted credential body.
- Account pages render Codex status, plan, displayed email, quota state, and rate-limit summaries, but not credential payloads or credential metadata values.
- The default Codex App Server transport is fail-closed in development and test unless a test injects a fake transport.

## Privacy

Users control whether deck analyses, decks, pods, sessions, and public summaries stay private or are shared by link. Defaults favor privacy. Share links are opt-in, unlisted, and revocable.

Do not store provider passwords or private provider session cookies. Do not exfiltrate private deck data to providers or AI services beyond the explicit analysis workflow.

AI requests should include only the information needed for evaluation. Deterministic card facts and summarized deck features are preferred over raw unrelated user data.

Collection inventory, matchup notes, player names, and session history are private user or playgroup data. Include them in AI requests only when the user explicitly runs a workflow that needs that context, and summarize them to the minimum useful evidence.

## Abuse Controls

Current controls:

- Analysis jobs have user/global quota wiring, plus upstream Codex rate limits from the linked account.
- Text-file imports enforce size limits.
- Archidekt and Moxfield adapters translate provider rate limits into user-facing retry errors.
- Audit events cover authentication, deck import, analysis, sharing, and Codex account changes.

Remaining hardening work before opening signups broadly: request-level throttles for signups, login attempts, password resets, import endpoints, analysis creation, and public share pages.

## Audit Events

Audit events should cover:

- Authentication changes.
- Deck imports and refreshes.
- Collection imports and unresolved-card review.
- Analysis creation and failures.
- Pod/session creation, sharing, and result recording.
- Matchup note create, update, delete, and share-affecting actions.
- Codex account link, logout, token-cache, and auth failure events.
- Admin actions.
- Share visibility changes.

Audit logs must not contain secrets.

## Fan Content Notice

Pod Tracker is unofficial fan content. The app includes this notice in public/user-facing surfaces:

> Pod Tracker is unofficial fan content. It is not approved, endorsed, or sponsored by Wizards of the Coast. Portions of Magic: The Gathering materials are property of Wizards of the Coast LLC.

Do not place core access to WotC IP-backed fan content behind payment without legal review.

## Security Checks

`bin/verify` runs the baseline security and quality checks:

- Brakeman.
- RuboCop.
- Bundle audit.
- Importmap audit.
- Rails unit/controller/system tests for auth, exports, credential handling, public shares, and related flows.

Production also sets secure headers and cookie/SSL behavior through Rails and Caddy; see [deployment.md](deployment.md) for the live process shape.
