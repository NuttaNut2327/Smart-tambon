require "mqtt"

# Long-running MQTT subscriber that stores sensor readings (run with `bin/rails mqtt:listen`).
#
# Devices publish JSON to  <prefix>/<sensor_type>/<sensor_id>, e.g.
#   smart-tambon/sensors/pm25/PM-001         {"token":"...","pm25":38.2,"observed_at":"2026-10-14T10:00:00+07:00"}
#   smart-tambon/sensors/water_level/WL-001  {"token":"...","water_level_m":2.35}
# and receive the result on <topic>/ack:     {"status":"accepted","observed_at":"..."} or {"status":"rejected","error":"..."}
class MqttSensorListener
  TYPE_ALIASES = { "pm25" => "pm25", "pm2_5" => "pm25", "water_level" => "water_level", "water-level" => "water_level", "waterlevel" => "water_level" }.freeze
  MAX_PAYLOAD_BYTES = 16.kilobytes
  MAX_BACKOFF = 60

  def initialize(url: ENV.fetch("MQTT_URL"), prefix: ENV.fetch("MQTT_TOPIC_PREFIX", "smart-tambon/sensors"), logger: default_logger)
    @url = url
    @prefix = prefix.delete_suffix("/")
    @logger = logger
    @stopping = false
  end

  def run
    %w[TERM INT].each { |signal| Signal.trap(signal) { @stopping = true; Thread.main.raise(Interrupt) } }
    backoff = 1
    until @stopping
      begin
        connect_and_listen { backoff = 1 }
      rescue Interrupt
        break
      rescue MQTT::Exception, SystemCallError, SocketError, IOError, Timeout::Error => error
        @logger.warn("[mqtt] connection lost: #{error.class}: #{error.message}; retrying in #{backoff}s")
        sleep backoff
        backoff = [backoff * 2, MAX_BACKOFF].min
      end
    end
    @logger.info("[mqtt] listener stopped")
  end

  # Handles one message; public so it can be exercised without a broker.
  def handle(topic, message)
    sensor_type, sensor_id = parse_topic(topic)
    return { status: "ignored" } unless sensor_type

    payload = parse_payload(message)
    result = Rails.application.executor.wrap do
      SensorIngestion.call(sensor_type:, sensor_id:, token: payload["token"], payload:, source: "mqtt")
    end
    @logger.info("[mqtt] #{result.duplicate ? 'duplicate' : 'stored'} #{sensor_type}/#{sensor_id} @ #{result.reading.observed_at.iso8601}")
    { status: result.duplicate ? "duplicate" : "accepted", observed_at: result.reading.observed_at.iso8601 }
  rescue SensorIngestion::Error => error
    @logger.warn("[mqtt] rejected #{topic}: #{error.message}")
    { status: "rejected", error: error.message }
  rescue StandardError => error
    @logger.error("[mqtt] failed #{topic}: #{error.class}: #{error.message}")
    { status: "error", error: "เกิดข้อผิดพลาดในการบันทึกค่า" }
  end

  private

  def connect_and_listen
    client = MQTT::Client.new(@url)
    client.client_id = ENV.fetch("MQTT_CLIENT_ID", "smart-tambon-sensor-listener")
    # Persistent session: the broker queues QoS 1 messages while the listener restarts.
    client.clean_session = false
    client.keep_alive = 30
    client.connect do |connection|
      connection.subscribe("#{@prefix}/+/+" => 1)
      @logger.info("[mqtt] listening on #{@prefix}/+/+")
      yield
      connection.get do |topic, message|
        response = handle(topic, message)
        connection.publish("#{topic}/ack", response.to_json, false, 0) unless response[:status] == "ignored"
      end
    end
  end

  def parse_topic(topic)
    rest = topic.to_s.delete_prefix("#{@prefix}/")
    return if rest == topic.to_s

    type, sensor_id, extra = rest.split("/", 3)
    sensor_type = TYPE_ALIASES[type.to_s.downcase]
    return if sensor_type.nil? || sensor_id.blank? || extra.present?

    [sensor_type, sensor_id]
  end

  def parse_payload(message)
    raise SensorIngestion::Invalid, "ข้อความมีขนาดใหญ่เกินไป" if message.to_s.bytesize > MAX_PAYLOAD_BYTES

    payload = JSON.parse(message.to_s)
    raise SensorIngestion::Invalid, "ข้อความต้องเป็น JSON object" unless payload.is_a?(Hash)

    payload
  rescue JSON::ParserError
    raise SensorIngestion::Invalid, "ข้อความไม่ใช่ JSON ที่ถูกต้อง"
  end

  def default_logger
    ActiveSupport::Logger.new($stdout).tap { |logger| logger.formatter = proc { |severity, time, _, message| "#{time.utc.iso8601} #{severity} #{message}\n" } }
  end
end
