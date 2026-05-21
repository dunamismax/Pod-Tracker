# Privacy Model

Pod Tracker stores game-night coordination data for self-hosted
playgroups. The privacy model is scoped around playgroup membership,
event participation, invite tokens, and host-controlled address
visibility. This document describes product expectations and implementation
boundaries; it is not a security guarantee beyond the code and database
checks that exist.

## Sensitive Data

Treat these fields as sensitive:

- Host street addresses, location notes, and schedule details for private
  events.
- Email addresses, phone numbers, guest names, RSVP notes, and travel
  timing details.
- Session cookies, CSRF tokens, invite tokens, calendar feed access, and
  production environment values.
- Production logs, database dumps, backups, and restore artifacts.

Do not commit sensitive data, database dumps, `.env` files, production
logs, private config, or real invite tokens.

## Viewer Scopes

Authenticated users may see data for playgroups where they have a
membership role. Playgroup roles determine management permissions and
event access.

Guests are scoped by invite token. A guest RSVP flow may show only the
event fields intentionally exposed by that invite scope. Guest flows must
not become a general playgroup browser.

Public event pages are tokenized and must use public-safe queries or
equivalent authorization. They can show event planning context, but must
not reveal private host details unless the event and address visibility
rules explicitly allow it.

Deck, collection, wishlist, and recommendation surfaces must preserve the
same viewer scopes. Heuristic recommendations may use decklists and
collection quantities only after the source collection and candidate decks
are visible to the requesting user, and should return aggregate coverage
or reason labels rather than private notes or card storage locations.
Optional semantic search must follow the same visibility rules and must
not embed private notes, host addresses, invite tokens, contact details,
production logs, backups, or database dumps.

## Address Visibility

Host address visibility is event-specific. Supported address visibility
states are:

- `hidden`: visible only to hosts and managers.
- `members`: visible to authenticated playgroup members.
- `rsvps`: visible to members with a yes or maybe RSVP.
- `public`: visible anywhere the event itself is visible.

When address visibility is not satisfied, UI may show a location name,
but must not render street address fields.

## Calendar Feeds

Calendar output is authenticated in the current Rust surface. Calendar
events may include location names, but must not include private street
addresses unless the requesting user is authorized to see the address.

Future tokenized calendar feeds should use independently revocable tokens
and the same address visibility rules.

## Logging

Application logs should favor request IDs, route names, status codes, and
high-level failure reasons over user-provided content. Logs must not print
session tokens, CSRF tokens, invite tokens, passwords, environment values,
raw production email payloads, host street addresses, or database URLs.

When debugging requires sensitive production context, capture the minimum
necessary data outside the repository and delete it when the incident is
closed.

## Database Boundaries

The app currently relies on scoped repository queries and route-level
authorization checks. RLS or equivalent scoped-query tests should be added
before claiming tenant isolation as a database-enforced guarantee.

Public-safe views remain the preferred shape for tokenized public event
and guest surfaces as the schema matures.

Natural-language meta exploration must not execute arbitrary SQL against
raw tables. Keep it constrained to approved SQL Observatory query shapes
or security-barrier views with declared viewer scope and public-safe
outputs.

## Backups And Restores

Backups are sensitive production data. Store them outside the repository,
restrict filesystem permissions, and copy them only through the normal
server backup channel.

Restore drills must target non-production databases unless Stephen has
approved a production maintenance window and a specific recovery plan.
