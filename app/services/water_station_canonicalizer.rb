class WaterStationCanonicalizer
  class << self
    def key(agency:, code:, name:, longitude:, latitude:)
      normalized_code = canonical_code(code)
      return "code:#{normalized_code}" if normalized_code.present?

      owner = normalize(agency)
      station_name = normalize(name)
      return "name:#{owner}:#{station_name}" if owner.present? && station_name.present?

      "point:#{Float(latitude).round(4)}:#{Float(longitude).round(4)}"
    rescue ArgumentError, TypeError
      nil
    end

    private

    def canonical_code(value)
      normalized = value.to_s.upcase.gsub(/[^A-Z0-9]/, "")
      telemetry_code = normalized.match(/(TA|TC)\d{6}/)&.to_s
      telemetry_code.presence || normalized.presence
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9ก-๙]/, "")
    end
  end
end
