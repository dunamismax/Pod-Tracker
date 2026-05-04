module CommanderFormat
  class OracleCardLookup
    def initialize(records: nil)
      @records = records
      @cache = {}
    end

    def lookup(normalized_name)
      return nil if normalized_name.blank?
      return @cache[normalized_name] if @cache.key?(normalized_name)

      @cache[normalized_name] = fetch(normalized_name)
    end

    def preload(normalized_names)
      missing = normalized_names.uniq - @cache.keys
      return if missing.empty?

      OracleCard.where(normalized_name: missing).each do |record|
        @cache[record.normalized_name] = record
      end
      missing.each { |name| @cache[name] ||= nil }
    end

    private

    def fetch(normalized_name)
      if @records
        @records[normalized_name]
      else
        OracleCard.find_by(normalized_name: normalized_name)
      end
    end
  end
end
