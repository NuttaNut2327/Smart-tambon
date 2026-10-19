require "aws-sdk-s3"
require "net/http"
require "mqtt"

# Health checks shown on the system settings status page. Each check is time-boxed and never raises.
class SystemStatusService
  Check = Struct.new(:key, :name, :status, :detail, :duration_ms, keyword_init: true)
  TIMEOUT = 5

  def self.call = new.call

  def call
    [
      check("postgres", "PostgreSQL / PostGIS") { "ตำบล #{Subdistrict.count.to_fs(:delimited)} · ผู้ใช้ #{User.count}" },
      check("mongo", "MongoDB") { Mongoid.default_client.database.command(ping: 1); "เหตุการณ์ #{Incident.count.to_fs(:delimited)} รายการ" },
      check("minio", "MinIO (เก็บรูปภาพ)") { minio_check },
      check("mqtt", "MQTT broker") { mqtt_check },
      check("longdo", "Longdo Map API") { longdo_check },
      check("geocoder", "บริการค้นหาสถานที่ (Geocoder)") { geocoder_check },
      check("mqtt_listener", "ตัวรับค่าเซนเซอร์ (MQTT listener)") { freshness([Pm25SensorReading, WaterLevelSensorReading].filter_map { |model| model.where(source: "mqtt").max(:created_at) }.max, warn_after: 1.day, empty: "ยังไม่มีค่าที่รับผ่าน MQTT") },
      check("water_sync", "ซิงก์สถานีวัดน้ำ (ทุก 15 นาที)") { freshness(WaterStationLatestReading.maximum(:updated_at), warn_after: 2.hours) },
      check("environment_sync", "ซิงก์ข้อมูลสิ่งแวดล้อม (ทุก 15 นาที)") { freshness(EnvironmentalSnapshot.max(:updated_at), warn_after: 2.hours) },
      check("activities", "สิ้นสุดกิจกรรมอัตโนมัติ") { activities_check }
    ]
  end

  private

  def check(key, name)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Timeout.timeout(TIMEOUT + 1) { yield }
    status, detail = result.is_a?(Array) ? result : ["ok", result]
    Check.new(key:, name:, status:, detail:, duration_ms: elapsed(started))
  rescue StandardError, Timeout::Error => error
    Check.new(key:, name:, status: "error", detail: "#{error.class.name.demodulize}: #{error.message.to_s.truncate(140)}", duration_ms: elapsed(started))
  end

  def elapsed(started) = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

  def minio_check
    client = Aws::S3::Client.new(
      endpoint: ENV.fetch("MINIO_ENDPOINT", "http://localhost:9000"), region: "us-east-1", force_path_style: true,
      access_key_id: ENV.fetch("MINIO_ACCESS_KEY", "minioadmin"), secret_access_key: ENV.fetch("MINIO_SECRET_KEY", "minioadmin123"),
      http_open_timeout: TIMEOUT, http_read_timeout: TIMEOUT
    )
    bucket = ENV.fetch("MINIO_BUCKET", "smart-tambon-incidents")
    client.head_bucket(bucket:)
    "bucket #{bucket} พร้อมใช้งาน"
  end

  def mqtt_check
    url = ENV["MQTT_URL"].presence
    return ["warning", "ยังไม่ได้กำหนด MQTT_URL"] unless url

    client = MQTT::Client.new(url)
    client.client_id = "smart-tambon-status-#{SecureRandom.hex(3)}"
    client.connect
    client.disconnect
    "เชื่อมต่อ #{URI(url).host}:#{URI(url).port} ได้"
  end

  def longdo_check
    key = SystemSetting.current.longdo_map_key
    return ["warning", "ยังไม่ได้กำหนด API key"] if key.blank?

    uri = URI("https://api.longdo.com/map/services/address")
    uri.query = URI.encode_www_form(lat: 13.7563, lon: 100.5018, key:, locale: "th", noelevation: 1)
    body = http_get(uri)
    payload = JSON.parse(body) rescue nil
    return ["error", "API key ไม่ถูกต้องหรือถูกระงับ"] unless payload.is_a?(Hash)

    "API key ใช้งานได้ (แหล่งที่มา: #{SystemSetting.current.secret_source('longdo_map_key') == 'settings' ? 'หน้าตั้งค่า' : '.env'})"
  end

  def geocoder_check
    base = SystemSetting.current.effective_geocoder_url
    uri = URI("#{base}/search")
    uri.query = URI.encode_www_form(q: "กรุงเทพมหานคร", format: "jsonv2", limit: 1, countrycodes: "th")
    results = JSON.parse(http_get(uri))
    results.is_a?(Array) && results.any? ? "#{URI(base).host} ตอบกลับปกติ" : ["warning", "#{URI(base).host} ไม่พบผลลัพธ์"]
  end

  def activities_check
    overdue = Incident.activities.where(deleted_at: nil, :status.ne => "completed", :ends_at.lte => 30.minutes.ago).count
    overdue.zero? ? "ไม่มีกิจกรรมค้างสถานะ" : ["warning", "มี #{overdue} กิจกรรมเลยเวลาสิ้นสุดแต่ยังไม่ปิด (ตรวจสอบ worker environmental_sync)"]
  end

  def freshness(time, warn_after:, empty: "ยังไม่มีข้อมูล")
    return ["warning", empty] unless time

    label = "อัปเดตล่าสุด #{ApplicationController.helpers.thai_short_datetime(time)}"
    time < warn_after.ago ? ["warning", "#{label} (ล่าช้า)"] : label
  end

  def http_get(uri)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |http| http.get(uri.request_uri, { "Accept" => "application/json" }) }
    raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end
end
