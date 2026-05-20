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
data. The normalized card tables now retain each printing's Scryfall
`lang`, `printed_name`, `printed_type_line`, and `printed_text` fields
when present, including face-level printed fields for multiface cards.

Canonical card identity still follows Scryfall `oracle_id` and English
`name`. Decklist imports first match canonical English names, then can
match localized printed names back to the same canonical Oracle card. This
keeps bracket checks, Game Changers counts, collection coverage, and
exports stable while allowing a player to paste a list from non-English
physical printings.

Card search combines canonical English search documents with
printed-language search documents where imported data supports them. A
`default_cards` import mostly provides English printings; use Scryfall's
`all_cards` bulk type when the local instance should index every language
Scryfall publishes.
