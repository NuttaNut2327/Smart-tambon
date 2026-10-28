# Generates a plausible multi-year disaster history for demos of the statistics and outlook features.
# Dates follow each hazard's season in northern Thailand, yearly totals swing with a random wet/dry year,
# events recur around fixed risk hotspots chosen from the terrain, and footprints are clipped to the subdistrict.
# See `rake disasters:simulate`.
class DisasterSimulator
  # mean: events per subdistrict per year; seasons: [day-of-year centre, spread in days, weight];
  # window: [first, last] day of year an event may start; radius_m: footprint radius range at severity 1.
  PROFILES = {
    "flood" => { mean: 3.0, seasons: [[258, 20, 0.7], [232, 14, 0.3]], window: [196, 320], radius_m: 110..320, stretch: 2.6, hotspot: :low },
    "landslide" => { mean: 0.8, seasons: [[245, 18, 1.0]], window: [200, 290], radius_m: 40..120, stretch: 1.8, hotspot: :high },
    "wildfire" => { mean: 4.0, seasons: [[72, 18, 0.8], [100, 12, 0.2]], window: [20, 130], radius_m: 150..600, stretch: 1.6, hotspot: :high },
    "drought" => { mean: 0.9, seasons: [[80, 25, 1.0]], window: [32, 151], radius_m: 1_500..3_500, stretch: 1.2, hotspot: :any },
    "storm" => { mean: 1.6, seasons: [[105, 18, 0.8], [240, 15, 0.2]], window: [60, 260], radius_m: 250..700, stretch: 1.3, hotspot: :any }
  }.freeze
  # How a wet or dry year scales each hazard's frequency (wetness ranges from -1 dry to +1 wet).
  WETNESS_EFFECT = { "flood" => 0.6, "landslide" => 0.7, "wildfire" => -0.35, "drought" => -0.7, "storm" => 0.15 }.freeze
  SEVERITY_WEIGHTS = { 1 => 45, 2 => 32, 3 => 17, 4 => 6 }.freeze
  HOUSEHOLDS_PER_RAI = 0.18
  PEOPLE_PER_HOUSEHOLD = 3.1
  SQ_M_PER_RAI = 1600.0

  def initialize(subdistrict_ids:, years:, seed:, until_time: Time.current)
    @subdistricts = Subdistrict.where(id: subdistrict_ids).where.not(boundary: nil).to_a
    raise ArgumentError, "No subdistricts with boundaries found" if @subdistricts.empty?

    @range = (until_time - years.years)..until_time
    @random = Random.new(seed)
    @elevation = TerrainElevationSampler.new
  end

  def run
    removed = DisasterEvent.where(simulated: true, :subdistrict_id.in => @subdistricts.map(&:id)).delete_all
    wetness = (@range.begin.year..@range.end.year).index_with { (@random.rand * 2 - 1).round(2) }
    events = @subdistricts.flat_map { |subdistrict| events_for(subdistrict, wetness) }
    invalid = events.reject(&:valid?)
    raise "Generated invalid events: #{invalid.first.errors.full_messages}" if invalid.any?

    DisasterEvent.collection.insert_many(events.map(&:as_document)) if events.any?
    { removed:, created: events.size, wetness:, range: @range, subdistricts: @subdistricts.map(&:name_th) }
  end

  private

  def events_for(subdistrict, wetness)
    context = area_context(subdistrict)
    hotspots = PROFILES.transform_values { |profile| pick_hotspots(context[:candidates], profile[:hotspot]) }
    wetness.flat_map do |year, wet|
      PROFILES.flat_map do |hazard, profile|
        count = poisson(profile[:mean] * (1 + WETNESS_EFFECT[hazard] * wet))
        Array.new(count) { build(hazard, profile, year, wet, subdistrict, context, hotspots[hazard]) }.compact
      end
    end
  end

  def build(hazard, profile, year, wet, subdistrict, context, hotspots)
    day = seasonal_day(profile)
    started_at = Time.zone.local(year, 1, 1) + (day - 1).days + @random.rand(0..86_399).seconds
    return unless @range.cover?(started_at)

    severity = severity_for(hazard, wet)
    hotspot = hotspots.sample(random: @random)
    origin = jitter(hotspot, hazard == "drought" ? 900 : 350, subdistrict) || hotspot
    radius = @random.rand(profile[:radius_m]) * (0.75 + severity * 0.35)
    footprint = footprint(subdistrict, origin, radius, profile[:stretch])
    duration = duration_for(hazard, severity)
    ended_at = started_at + duration
    villages = Array.new(severity.clamp(1, 3) + (hazard == "drought" ? 4 : 0)) { @random.rand(1..12) }.uniq.sort
    impact = impact_for(hazard, severity, footprint[:area_rai], context)
    weather = weather_for(hazard, severity)

    DisasterEvent.new(
      hazard:, severity:, subdistrict_id: subdistrict.id, villages:,
      title: "#{DisasterEvent::HAZARDS[hazard][:label]} หมู่ที่ #{villages.join(', ')} ต.#{subdistrict.name_th}",
      description: "ข้อมูลจำลองเพื่อการสาธิต",
      cause: cause_for(hazard, weather),
      started_at:, peak_at: started_at + duration * @random.rand(0.2..0.45), ended_at:,
      latitude: origin[:lat], longitude: origin[:lon], elevation_m: origin[:elevation]&.round,
      affected_area: footprint[:geometry], area_rai: footprint[:area_rai],
      source: "simulated", simulated: true, created_at: ended_at, updated_at: ended_at,
      **impact, **weather
    )
  end

  # Candidate points with elevation, used to place hotspots on plausible terrain.
  def area_context(subdistrict)
    sql = Subdistrict.sanitize_sql_array([
      "SELECT ST_X(geom), ST_Y(geom) FROM (SELECT (ST_Dump(ST_GeneratePoints(boundary::geometry, 160, ?))).geom FROM subdistricts WHERE id = ?) points",
      @random.rand(1..1_000_000), subdistrict.id
    ])
    candidates = Subdistrict.connection.select_rows(sql).map do |lon, lat|
      { lon: lon.to_f, lat: lat.to_f, elevation: @elevation.elevation(lon.to_f, lat.to_f) }
    end
    area_rai = Subdistrict.where(id: subdistrict.id).pick(Arel.sql("ST_Area(boundary::geography)")).to_f / SQ_M_PER_RAI
    households = (area_rai * HOUSEHOLDS_PER_RAI).round
    { candidates:, area_rai:, households: }
  end

  def pick_hotspots(candidates, preference)
    known = candidates.select { |point| point[:elevation] }
    pool = if known.size < 10 || preference == :any
      candidates
    else
      sorted = known.sort_by { |point| point[:elevation] }
      preference == :low ? sorted.first((sorted.size * 0.15).ceil) : sorted.last((sorted.size * 0.3).ceil)
    end
    pool.sample(preference == :any ? 4 : 3, random: @random)
  end

  def jitter(point, metres, subdistrict)
    angle = @random.rand * 2 * Math::PI
    distance = @random.rand * metres
    lat = point[:lat] + distance * Math.sin(angle) / 111_320.0
    lon = point[:lon] + distance * Math.cos(angle) / (111_320.0 * Math.cos(point[:lat] * Math::PI / 180))
    inside = Subdistrict.where(id: subdistrict.id).where("ST_Covers(boundary::geometry, ST_SetSRID(ST_Point(?, ?), 4326))", lon, lat).exists?
    inside ? { lon:, lat:, elevation: @elevation.elevation(lon, lat) || point[:elevation] } : nil
  end

  # Irregular, stretched blob around the origin, clipped to the subdistrict boundary.
  def footprint(subdistrict, origin, radius, stretch)
    rotation = @random.rand * Math::PI
    noise = Array.new(20) { 0.65 + @random.rand * 0.7 }
    smoothed = noise.each_index.map { |index| (noise[index - 1] + noise[index] * 2 + noise[(index + 1) % noise.size]) / 4 }
    lat_scale = 111_320.0
    lon_scale = lat_scale * Math.cos(origin[:lat] * Math::PI / 180)
    ring = smoothed.each_with_index.map do |factor, index|
      angle = 2 * Math::PI * index / smoothed.size
      x = Math.cos(angle) * radius * stretch * factor
      y = Math.sin(angle) * radius * factor
      rx = x * Math.cos(rotation) - y * Math.sin(rotation)
      ry = x * Math.sin(rotation) + y * Math.cos(rotation)
      "#{origin[:lon] + rx / lon_scale} #{origin[:lat] + ry / lat_scale}"
    end
    wkt = "POLYGON((#{(ring + [ring.first]).join(', ')}))"
    sql = Subdistrict.sanitize_sql_array([<<~SQL, wkt, subdistrict.id])
      SELECT ST_AsGeoJSON(clip, 6), ST_Area(clip::geography)
      FROM (SELECT ST_CollectionExtract(ST_Intersection(boundary::geometry, ST_SetSRID(ST_GeomFromText(?), 4326)), 3) AS clip
            FROM subdistricts WHERE id = ?) shape
    SQL
    geojson, area = Subdistrict.connection.select_rows(sql).first
    geometry = geojson && JSON.parse(geojson)
    if geometry.nil? || area.to_f <= 0
      geometry = { "type" => "Point", "coordinates" => [origin[:lon], origin[:lat]] }
      area = Math::PI * radius**2
    end
    { geometry:, area_rai: (area.to_f / SQ_M_PER_RAI).round(1) }
  end

  def impact_for(hazard, severity, area_rai, context)
    share = (area_rai / context[:area_rai]).clamp(0.0, 1.0)
    exposure = { "flood" => 1.8, "landslide" => 3.0, "wildfire" => 0.08, "drought" => 0.9, "storm" => 1.2 }.fetch(hazard)
    households = (context[:households] * share * exposure * @random.rand(0.6..1.3)).round
    households = [households, severity * 2].max unless hazard == "wildfire"
    damage_rate = { "flood" => 0.04 * severity, "landslide" => 0.15 * severity, "wildfire" => 0.0, "drought" => 0.0, "storm" => 0.04 * severity }.fetch(hazard)
    damaged_houses = (households * damage_rate * @random.rand(0.5..1.2)).round
    farm_share = { "flood" => 0.55, "landslide" => 0.25, "wildfire" => 0.12, "drought" => 0.35, "storm" => 0.3 }.fetch(hazard)
    farmland_rai = (area_rai * farm_share * @random.rand(0.7..1.1)).round(1)
    roads_km = case hazard
               when "flood" then (area_rai / 450 * @random.rand(0.5..1.5)).round(1)
               when "landslide" then (@random.rand(0.05..0.4) * severity).round(2)
               when "storm" then (@random.rand(0.0..0.3) * severity).round(1)
               else 0.0
               end
    injuries = severity >= 3 && hazard.in?(%w[flood landslide storm]) ? poisson(severity - 2.0) : 0
    deaths = severity == 4 && hazard.in?(%w[landslide flood]) && @random.rand < 0.3 ? @random.rand(1..2) : 0
    crop_loss_per_rai = { "flood" => 4_500, "landslide" => 6_000, "wildfire" => 1_200, "drought" => 900, "storm" => 3_000 }.fetch(hazard)
    loss = damaged_houses * 25_000 * severity + farmland_rai * crop_loss_per_rai + roads_km * 900_000
    {
      affected_households: households, affected_people: (households * PEOPLE_PER_HOUSEHOLD).round,
      damaged_houses:, farmland_rai:, roads_km:, injuries:, deaths:, estimated_loss_baht: (loss / 1000).round * 1000.0
    }
  end

  def weather_for(hazard, severity)
    case hazard
    when "flood" then { rain_3d_mm: (55 + severity * 35 + @random.rand(0..60)).to_f }
    when "landslide" then { rain_3d_mm: (90 + severity * 40 + @random.rand(0..70)).to_f }
    when "storm" then { rain_3d_mm: @random.rand(15..80).to_f }
    when "wildfire" then { days_without_rain: @random.rand(12..45), max_temperature_c: @random.rand(35.5..40.5).round(1) }
    else { days_without_rain: 25 + severity * 12 + @random.rand(0..20), max_temperature_c: @random.rand(35.0..40.0).round(1) }
    end
  end

  def cause_for(hazard, weather)
    case hazard
    when "flood" then "ฝนตกหนักต่อเนื่อง สะสม 3 วัน #{weather[:rain_3d_mm].round} มม. น้ำป่าไหลหลากและน้ำล้นตลิ่ง"
    when "landslide" then "ดินอุ้มน้ำหลังฝนตกหนัก สะสม 3 วัน #{weather[:rain_3d_mm].round} มม."
    when "storm" then "พายุฤดูร้อน ลมกระโชกแรงและลูกเห็บ"
    when "wildfire" then "อากาศร้อนแห้ง (#{weather[:max_temperature_c]}°C) และการเผาในพื้นที่เกษตรลุกลาม"
    else "ฝนทิ้งช่วง ไม่มีฝนติดต่อกัน #{weather[:days_without_rain]} วัน น้ำในแหล่งน้ำไม่เพียงพอ"
    end
  end

  def duration_for(hazard, severity)
    days = case hazard
           when "flood" then @random.rand(1..3) + severity * 2
           when "landslide" then @random.rand(0..1)
           when "wildfire" then @random.rand(1..2) + severity
           when "drought" then 20 + severity * 15 + @random.rand(0..20)
           else 0
           end
    days.days + @random.rand(3..20).hours
  end

  def severity_for(hazard, wet)
    shift = hazard.in?(%w[flood landslide]) ? wet : (hazard.in?(%w[drought wildfire]) ? -wet : 0)
    weights = SEVERITY_WEIGHTS.to_h { |level, weight| [level, weight * Math.exp(shift * 0.5 * (level - 2))] }
    pick = @random.rand * weights.values.sum
    weights.each { |level, weight| return level if (pick -= weight) <= 0 }
    1
  end

  def seasonal_day(profile)
    first, last = profile[:window]
    loop do
      pick = @random.rand * profile[:seasons].sum(&:last)
      center, spread, = profile[:seasons].find { |season| (pick -= season.last) <= 0 } || profile[:seasons].last
      day = (center + gaussian * spread).round
      return day if day.between?(first, last)
    end
  end

  def gaussian
    Math.sqrt(-2 * Math.log(1 - @random.rand)) * Math.cos(2 * Math::PI * @random.rand)
  end

  def poisson(mean)
    limit = Math.exp(-[mean, 0].max)
    count = 0
    product = @random.rand
    while product > limit
      count += 1
      product *= @random.rand
    end
    count
  end
end
