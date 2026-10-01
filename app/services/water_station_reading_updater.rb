class WaterStationReadingUpdater
  class << self
    def call(station:, attributes:, payload: nil)
      reading = station.latest_reading || station.build_latest_reading
      changed = false
      changed |= apply_metric(reading, attributes, :water_level_m_msl, :water_level_observed_at, :water_level_source)
      changed |= apply_metric(reading, attributes, :rainfall_value, :rainfall_observed_at, :rainfall_source)

      %i[flow_rate_m3_s river_capacity_percent].each do |field|
        next unless attributes.key?(field)
        next if reading.public_send(field) == attributes[field]

        reading.public_send("#{field}=", attributes[field])
        changed = true
      end

      observed_at = [reading.water_level_observed_at, reading.rainfall_observed_at, attributes[:source_observed_at]].compact.max
      if observed_at && reading.source_observed_at != observed_at
        reading.source_observed_at = observed_at
        changed = true
      end
      reading.save! if reading.new_record? || changed
      changed
    end

    private

    def apply_metric(reading, attributes, value_field, time_field, source_field)
      incoming_time = attributes[time_field]
      incoming_value = attributes[value_field]
      return false unless incoming_time && !incoming_value.nil?
      return false if reading.public_send(time_field).present? && incoming_time <= reading.public_send(time_field)

      reading.public_send("#{value_field}=", incoming_value)
      reading.public_send("#{time_field}=", incoming_time)
      reading.public_send("#{source_field}=", attributes[source_field])
      true
    end
  end
end
