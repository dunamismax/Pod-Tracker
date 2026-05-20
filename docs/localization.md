# Localization And Card Languages

Pod Tracker is not ready for broad UI translation. The supported
application locale policy is intentionally narrow until the core event,
RSVP, pod, game, collection, and SQL Observatory flows settle.

## Application Locales

Supported application locales:

- `en-US`

`en-US` is the only supported UI locale for now. New user-facing copy can
remain inline in Rust/Leptos components until the product surface is more
stable. Do not extract or translate broad UI copy before there is a
clearer copy inventory and a Rust-owned localization workflow.

## User Preferences

Users can store:

- application locale;
- IANA timezone from the supported list;
- date/time display format.

Event and authenticated RSVP `datetime-local` form values are interpreted
in the signed-in user's stored timezone and stored as UTC timestamps.
Authenticated event views render timestamps back through the viewer's
stored timezone and display format. Calendar feeds continue to emit UTC
`DTSTART`/`DTEND` values so clients can safely convert them to their own
calendar timezone.

## Card Languages

Scryfall raw payloads remain the source of truth for multilingual card
data. Future language work should preserve Scryfall language fields for
printings and names, then add multilingual search and display without
breaking English canonical decklist matching.
