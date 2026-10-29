# GISTDA flood polygons / hotspot points for one user's map. The query box is the envelope of the user's access
# boundary (narrowed to the area selected on the map, if any); the weather service clips the result to the
# boundary itself. System admins see the requested area, or the whole country.
#
# GISTDA's tambon polygons differ slightly from ours, so a hotspot GISTDA tags with one of the user's tambon codes
# (tb_idn) can fall just outside our boundary. With `tambon_codes`, hotspots are fetched for a slightly larger box
# and kept when they lie inside the boundary OR carry one of those codes.
class GistdaDisasterLayer
  THAILAND_BBOX = [97.3, 5.6, 105.7, 20.5].freeze
  DATASETS = %w[flood hotspots].freeze
  CODE_MATCH_BUFFER = 0.03 # degrees (~3 km) around the boundary envelope

  def initialize(client:, boundary:, global: false, tambon_codes: [])
    @client = client
    @boundary = boundary
    @global = global
    @tambon_codes = Array(tambon_codes).map(&:to_s).compact_blank.to_set
  end

  def call(dataset, period:, bbox: nil)
    raise ArgumentError, "Unknown GISTDA dataset #{dataset}" unless DATASETS.include?(dataset)

    match_codes = dataset == "hotspots" && !@global && @tambon_codes.any?
    area_bbox = resolve_bbox(bbox, buffer: match_codes ? CODE_MATCH_BUFFER : 0)
    return empty(dataset, period) unless area_bbox

    clip = @boundary.as_text unless @global || match_codes
    payload = @client.features(dataset, period:, bbox: area_bbox, boundary_wkt: clip)
    payload = keep_in_area(payload) if match_codes
    payload.merge("key_source" => @client.key_source, "bbox" => area_bbox)
  end

  private

  def empty(dataset, period)
    { "type" => "FeatureCollection", "dataset" => dataset, "period_days" => period, "source" => "GISTDA",
      "key_source" => @client.key_source, "count" => 0, "number_matched" => 0, "truncated" => false, "features" => [] }
  end

  def keep_in_area(payload)
    features = Array(payload["features"])
    inside = AccessBoundaryPointFilter.new(@boundary).filter(features) { |feature| feature.dig("geometry", "coordinates") }.to_set
    kept = features.select { |feature| inside.include?(feature) || @tambon_codes.include?(feature.dig("properties", "tambon_code").to_s) }
    payload.merge("features" => kept, "count" => kept.size)
  end

  # [west, south, east, north]: the boundary's envelope (or Thailand), narrowed to the requested bbox.
  def resolve_bbox(requested, buffer: 0)
    requested = parse_bbox(requested)
    limit = @global ? THAILAND_BBOX : boundary_envelope
    return nil unless limit

    limit = [limit[0] - buffer, limit[1] - buffer, limit[2] + buffer, limit[3] + buffer] if buffer.positive?

    box = requested ? [[requested[0], limit[0]].max, [requested[1], limit[1]].max, [requested[2], limit[2]].min, [requested[3], limit[3]].min] : limit
    box[0] < box[2] && box[1] < box[3] ? box.map { |value| value.round(4) } : nil
  end

  def parse_bbox(value)
    numbers = value.to_s.split(",").map { |part| Float(part, exception: false) }
    return nil unless numbers.size == 4 && numbers.all? && numbers[0] < numbers[2] && numbers[1] < numbers[3]

    numbers
  end

  def boundary_envelope
    return nil if @boundary.blank?

    row = ActiveRecord::Base.connection.select_rows(ActiveRecord::Base.sanitize_sql_array([
      "SELECT ST_XMin(g), ST_YMin(g), ST_XMax(g), ST_YMax(g) FROM (SELECT ST_Envelope(ST_GeomFromText(?, 4326)) AS g) envelope",
      @boundary.as_text
    ])).first
    row&.map(&:to_f)
  end
end
