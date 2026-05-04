require "json"

module CommanderFormat
  class LegalitySnapshotImporter
    DEFAULT_PATH = Rails.root.join("db/seeds/commander/legality_snapshots/current.json")

    def import!(path: DEFAULT_PATH)
      payload = JSON.parse(Pathname(path).read)
      snapshot = LegalitySnapshot.find_or_initialize_by(
        source: payload.fetch("source"),
        format: payload.fetch("format"),
        effective_on: Date.iso8601(payload.fetch("effective_on"))
      )

      snapshot.assign_attributes(
        fetched_at: parse_time(payload.fetch("fetched_at")),
        source_url: payload.fetch("source_url"),
        source_checked_on: parse_date(payload["source_checked_on"]),
        banned_names: payload.fetch("banned_names"),
        restricted_names: payload.fetch("restricted_names", []),
        category_bans: payload.fetch("category_bans", []),
        rules_snapshot: payload.fetch("rules_snapshot"),
        raw_payload: payload,
        notes: payload["notes"]
      )
      snapshot.save!
      snapshot
    end

    private

    def parse_date(value)
      Date.iso8601(value) if value.present?
    end

    def parse_time(value)
      Time.zone.parse(value) if value.present?
    end
  end
end
