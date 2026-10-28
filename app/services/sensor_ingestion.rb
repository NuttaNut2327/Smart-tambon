# Validates and stores one reading from a registered sensor. Shared by the HTTP
# endpoints and the MQTT listener so both paths authenticate and store readings
# the same way.
#
#   SensorIngestion.call(sensor_type: "pm25", sensor_id: "PM-001", token: "...",
#                        payload: { "pm25" => 38.2, "observed_at" => "2026-10-14T10:00:00+07:00" }, source: "mqtt")
#   SensorIngestion.call(sensor_type: "location", sensor_id: "GPS-001", token: "...",
#                        payload: { "latitude" => 13.75, "longitude" => 100.50, "speed_kmh" => 32 }, source: "http")
class SensorIngestion
  class Error < StandardError; end
  class Unauthorized < Error; end
  class Invalid < Error; end

  Result = Struct.new(:reading, :duplicate, keyword_init: true)

  TYPES = {
    "pm25" => {
      dataset_type: "pm25_sensors", model: Pm25SensorReading,
      primary: :pm25, primary_keys: %w[pm25 value], primary_range: 0..2000,
      optional: { pm25_avg_24h: 0..2000, pm10: 0..5000, temperature_c: -50..80, humidity_percent: 0..100 }
    },
    "water_level" => {
      dataset_type: "water_level_sensors", model: WaterLevelSensorReading,
      primary: :water_level_m, primary_keys: %w[water_level_m water_level value], primary_range: -500..10_000,
      optional: { rainfall_mm: 0..2000 }
    },
    # Moving devices (vehicles, field staff): each reading carries its own position instead of the registered one.
    "location" => {
      dataset_type: "location_trackers", model: LocationTrackerReading, moving: true,
      optional: { speed_kmh: 0..500, heading_deg: 0..360, accuracy_m: 0..100_000, altitude_m: -500..10_000 }
    }
  }.freeze
  POSITION_KEYS = { latitude: [%w[latitude lat], -90..90], longitude: [%w[longitude lon lng], -180..180] }.freeze
  # Device extras worth keeping (battery, signal) without letting payloads grow unbounded.
  METADATA_KEYS = %w[battery battery_v battery_percent rssi snr firmware].freeze
  MAX_FUTURE_SKEW = 5.minutes

  def self.call(...) = new(...).call

  def initialize(sensor_type:, payload:, token:, source:, sensor_id: nil)
    @config = TYPES.fetch(sensor_type.to_s) { raise Invalid, "ไม่รู้จักประเภทเซนเซอร์ #{sensor_type}" }
    @payload = payload.to_h.stringify_keys
    @token = token.to_s
    @sensor_id = sensor_id.to_s.presence
    @source = source
  end

  def call
    dataset, sensor = find_sensor!
    attributes = {
      imported_dataset_id: dataset.id,
      sensor_id: sensor.fetch("sensor_id").to_s,
      observed_at: observed_at,
      latitude: Float(sensor["latitude"], exception: false),
      longitude: Float(sensor["longitude"], exception: false),
      source: @source,
      metadata: @payload.slice(*METADATA_KEYS)
    }
    if @config[:moving]
      POSITION_KEYS.each do |attribute, (keys, range)|
        attributes[attribute] = number!(first_present(keys), keys.first, range, required: true)
      end
    else
      attributes[@config[:primary]] = number!(first_present(@config[:primary_keys]), @config[:primary_keys].first,
                                              @config[:primary_range], required: true)
    end
    @config[:optional].each { |key, range| attributes[key] = number!(@payload[key.to_s], key.to_s, range) }

    model = @config[:model]
    existing = model.where(imported_dataset_id: dataset.id, sensor_id: attributes[:sensor_id], observed_at: attributes[:observed_at]).first
    return Result.new(reading: existing, duplicate: true) if existing

    Result.new(reading: model.create!(attributes), duplicate: false)
  rescue Mongoid::Errors::Validations => error
    raise Invalid, error.document.errors.full_messages.to_sentence
  end

  private

  def first_present(keys) = keys.lazy.map { |key| @payload[key] }.find { |value| !value.nil? }

  def find_sensor!
    raise Unauthorized, "ต้องระบุ Sensor Token" if @token.blank?

    datasets = ImportedDataset.where(data_type: @config[:dataset_type], :current_version_id.ne => nil).only(:_id, :current_version_id).to_a
    dataset_by_version = datasets.index_by(&:current_version_id)
    records = ImportedDatasetRecord.where(:imported_dataset_version_id.in => dataset_by_version.keys)
    records = @sensor_id ? records.where("payload.sensor_id" => @sensor_id) : records.where("payload.token" => @token)
    record = records.to_a.find { |candidate| token_match?(candidate.payload["token"]) }
    raise Unauthorized, "Sensor ID หรือ Token ไม่ถูกต้อง" unless record

    [dataset_by_version.fetch(record.imported_dataset_version_id), record.payload]
  end

  def token_match?(stored)
    return false if stored.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      OpenSSL::Digest::SHA256.hexdigest(stored.to_s), OpenSSL::Digest::SHA256.hexdigest(@token)
    )
  end

  def number!(value, key, range, required: false)
    if value.nil? || value.to_s.strip.empty?
      raise Invalid, "ต้องระบุค่า #{key}" if required
      return nil
    end
    number = Float(value)
    raise Invalid, "ค่า #{key} ต้องอยู่ระหว่าง #{range.min} ถึง #{range.max}" unless number.finite? && range.cover?(number)

    number
  rescue ArgumentError, TypeError
    raise Invalid, "ค่า #{key} ต้องเป็นตัวเลข"
  end

  # Accepts ISO 8601 strings or Unix epoch in seconds or milliseconds; defaults to now.
  def observed_at
    raw = @payload["observed_at"] || @payload["timestamp"] || @payload["ts"]
    time = case raw
           when nil, "" then Time.current
           when Numeric then epoch_time(raw)
           when /\A\d+(\.\d+)?\z/ then epoch_time(raw.to_f)
           else Time.zone.parse(raw.to_s) || raise(ArgumentError)
           end
    raise Invalid, "เวลาที่วัดค่าอยู่ในอนาคต" if time > MAX_FUTURE_SKEW.from_now

    time.change(usec: (time.usec / 1000) * 1000)
  rescue ArgumentError, RangeError
    raise Invalid, "รูปแบบเวลา observed_at ไม่ถูกต้อง"
  end

  def epoch_time(value)
    Time.zone.at(value > 100_000_000_000 ? value / 1000.0 : value)
  end
end
