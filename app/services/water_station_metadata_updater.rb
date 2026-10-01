class WaterStationMetadataUpdater
  class << self
    def call(station, attributes)
      attributes.each do |field, incoming|
        next if field == :source_payload && station.persisted?
        next if equivalent?(station.public_send(field), incoming)

        station.public_send("#{field}=", incoming)
      end
      station.save! if station.new_record? || station.changed?
    end

    private

    def equivalent?(current, incoming)
      if current.respond_to?(:x) && incoming.respond_to?(:x)
        current.x == incoming.x && current.y == incoming.y
      elsif current.is_a?(Hash) || current.is_a?(Array)
        current.as_json == incoming.as_json
      else
        current == incoming
      end
    end
  end
end
