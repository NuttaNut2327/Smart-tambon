require "csv"
require "digest"
require "net/http"

# Pulls near-real-time active fire detections from NASA FIRMS into the PostGIS `fire_hotspots` table.
# With FIRMS_MAP_KEY it uses the area API (https://firms.modaps.eosdis.nasa.gov/api/area/); without a key it
# falls back to the public Southeast Asia 24h CSV files and keeps only rows inside the bbox.
class FirmsHotspotSync
  API_BASE = "https://firms.modaps.eosdis.nasa.gov/api/area/csv".freeze
  PUBLIC_BASE = "https://firms.modaps.eosdis.nasa.gov/data/active_fire".freeze
  PUBLIC_FILES = {
    "VIIRS_SNPP_NRT" => "suomi-npp-viirs-c2/csv/SUOMI_VIIRS_C2_SouthEast_Asia_24h.csv",
    "VIIRS_NOAA20_NRT" => "noaa-20-viirs-c2/csv/J1_VIIRS_C2_SouthEast_Asia_24h.csv",
    "VIIRS_NOAA21_NRT" => "noaa-21-viirs-c2/csv/J2_VIIRS_C2_SouthEast_Asia_24h.csv",
    "MODIS_NRT" => "modis-c6.1/csv/MODIS_C6_1_SouthEast_Asia_24h.csv"
  }.freeze
  DEFAULT_SOURCES = PUBLIC_FILES.keys.freeze
  # west,south,east,north covering Thailand
  DEFAULT_BBOX = "97.3,5.6,105.7,20.5".freeze

  def initialize(map_key: ENV["FIRMS_MAP_KEY"], sources: ENV["FIRMS_SOURCES"], bbox: ENV["FIRMS_BBOX"],
                 day_range: ENV["FIRMS_DAY_RANGE"], retention_days: ENV["FIRMS_RETENTION_DAYS"], fetcher: nil)
    @map_key = map_key.to_s.strip
    @sources = sources.present? ? sources.split(",").map(&:strip) : DEFAULT_SOURCES
    @bbox = bbox.presence || DEFAULT_BBOX
    @west, @south, @east, @north = @bbox.split(",").map { |value| Float(value) }
    @day_range = (day_range.presence || 2).to_i.clamp(1, 5)
    @retention_days = (retention_days.presence || 30).to_i
    @fetcher = fetcher || method(:fetch_csv)
    @factory = RGeo::Geographic.spherical_factory(srid: 4326)
  end

  # Returns { "SOURCE" => rows_upserted, ..., "pruned" => n }
  def call
    result = @sources.index_with do |source|
      rows = parse(@fetcher.call(url_for(source)), source)
      FireHotspot.upsert_all(rows, unique_by: :hotspot_key, record_timestamps: true) if rows.any?
      rows.size
    end
    result["pruned"] = FireHotspot.where(acquired_at: ...@retention_days.days.ago).delete_all
    result
  end

  def parse(body, source)
    text = body.to_s.strip
    raise "FIRMS returned an error for #{source}: #{text.truncate(200)}" unless text.start_with?("latitude")

    CSV.parse(text, headers: true).filter_map { |row| attributes_for(row, source) }.uniq { |row| row[:hotspot_key] }
  end

  private

  def public_mode?
    @map_key.blank?
  end

  def url_for(source)
    return "#{API_BASE}/#{@map_key}/#{source}/#{@bbox}/#{@day_range}" unless public_mode?

    "#{PUBLIC_BASE}/#{PUBLIC_FILES.fetch(source) { raise ArgumentError, "No public FIRMS file for #{source}" }}"
  end

  def attributes_for(row, source)
    latitude = Float(row["latitude"])
    longitude = Float(row["longitude"])
    return nil unless longitude.between?(@west, @east) && latitude.between?(@south, @north)

    acquired_at = Time.strptime("#{row["acq_date"]} #{row["acq_time"].to_s.rjust(4, "0")} UTC", "%Y-%m-%d %H%M %Z")
    {
      hotspot_key: Digest::SHA1.hexdigest([source, row["acq_date"], row["acq_time"], row["latitude"], row["longitude"]].join("|")),
      source:,
      satellite: row["satellite"],
      instrument: row["instrument"].presence || source.split("_").first,
      location: @factory.point(longitude, latitude),
      acquired_at:,
      brightness: number(row["bright_ti4"] || row["brightness"]),
      brightness_t31: number(row["bright_ti5"] || row["bright_t31"]),
      frp: number(row["frp"]),
      confidence: row["confidence"],
      daynight: row["daynight"],
      scan: number(row["scan"]),
      track: number(row["track"]),
      version: row["version"]
    }
  rescue ArgumentError, TypeError
    nil
  end

  def number(value)
    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def fetch_csv(url)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 300) do |http|
      http.request(Net::HTTP::Get.new(uri, "Accept" => "text/csv"))
    end
    raise "FIRMS API returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body.force_encoding(Encoding::UTF_8)
  end
end
