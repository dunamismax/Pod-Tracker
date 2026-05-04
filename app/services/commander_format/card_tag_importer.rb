require "json"

module CommanderFormat
  class CardTagImporter
    DEFAULT_TAXONOMY_PATH = Rails.root.join("db/seeds/commander/card_tags/taxonomy.json")
    DEFAULT_OVERRIDES_PATH = Rails.root.join("db/seeds/commander/card_tags/overrides.json")

    Result = Struct.new(:tags, :assignments, keyword_init: true)

    def import!(taxonomy_path: DEFAULT_TAXONOMY_PATH, overrides_path: DEFAULT_OVERRIDES_PATH)
      tags = import_tags(taxonomy_path)
      assignments = import_overrides(overrides_path, tags)
      Result.new(tags: tags.values, assignments: assignments)
    end

    private

    def import_tags(path)
      payload = parse(path)
      Array(payload["tags"]).each_with_object({}) do |attrs, mapping|
        slug = attrs.fetch("slug")
        tag = CardTag.find_or_initialize_by(slug: slug)
        tag.assign_attributes(
          category: attrs.fetch("category"),
          label: attrs.fetch("label"),
          description: attrs["description"],
          salt_weight: attrs["salt_weight"],
          friction_weight: attrs["friction_weight"],
          default_severity: attrs["default_severity"],
          metadata: attrs["metadata"] || {}
        )
        tag.save!
        mapping[slug] = tag
      end
    end

    def import_overrides(path, tags)
      payload = parse(path)
      Array(payload["assignments"]).map do |attrs|
        slug = attrs.fetch("tag")
        tag = tags[slug] || CardTag.find_by!(slug: slug)
        card_name = attrs.fetch("card_name")
        normalized = ApplicationRecord.normalize_card_name(card_name)
        oracle = OracleCard.find_by(normalized_name: normalized)

        assignment = CardTagAssignment.find_or_initialize_by(
          card_tag: tag,
          normalized_card_name: normalized
        )
        assignment.assign_attributes(
          card_name: card_name,
          oracle_card: oracle,
          source: attrs["source"] || "curated",
          notes: attrs["notes"],
          weight: attrs["weight"],
          severity: attrs["severity"],
          metadata: attrs["metadata"] || {}
        )
        assignment.save!
        assignment
      end
    end

    def parse(path)
      JSON.parse(Pathname(path).read)
    end
  end
end
