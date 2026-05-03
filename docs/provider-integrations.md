# Provider Integrations

Ideal Magic imports Commander decks from public and user-provided sources. Provider integrations must be isolated behind adapters so provider changes do not leak into deck storage, analysis, or UI logic.

## Allowed V1 Sources

- Pasted decklists.
- Uploaded or pasted text exports.
- Public Archidekt deck URLs.
- Public Moxfield deck URLs.

These sources are allowed because they do not require storing third-party passwords or bypassing private account boundaries.

## Blocked Sources Without Approval

- Private Archidekt or Moxfield account sync.
- Browser scraping behind user login.
- Provider password collection.
- Undocumented private APIs for user-only data.
- Any integration that requires pretending to be the user's browser session.

Authenticated provider sync can be reconsidered only if the provider offers documented auth/API support or Stephen explicitly approves a constrained integration after reviewing the risk.

## Adapter Contract

Each provider adapter should expose clear methods for:

- Validating whether a URL or export belongs to the provider.
- Fetching public data with polite headers and timeouts.
- Parsing provider-specific payloads or page data.
- Normalizing cards into Ideal Magic's internal deck representation.
- Returning source attribution.
- Reporting actionable errors.
- Refreshing imported decks with backoff and cache discipline.

Provider adapters must not write analysis results directly. Their job ends at normalized deck intake and source metadata.

## Public URL Policy

Public deck URL imports should:

- Fetch only the requested public deck.
- Use a clear user agent once implemented.
- Respect provider rate limits and retry-after behavior when available.
- Cache successful imports enough to avoid repeated unnecessary requests.
- Fail with a human-readable reason when the provider changes or blocks access.

Public provider behavior can be unstable even when visible in a browser. Tests should use fixtures so parser behavior is covered without hammering providers.

## Source Attribution

Imported decks must store:

- Provider name.
- Public source URL or export type.
- Provider deck ID when safely available.
- Import timestamp.
- Refresh timestamp.
- Raw provider version or checksum when available.
- Parser version.

The UI should show where a deck came from and whether it may be stale.

## Scryfall

Scryfall bulk data is the primary source for card facts. Ideal Magic should use bulk downloads for card corpus refreshes and avoid per-card API calls for normal analysis workloads.

Scryfall usage must include polite request behavior and should stay below Scryfall's published rate guidance.

