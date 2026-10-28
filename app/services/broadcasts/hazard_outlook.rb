module Broadcasts
  # Forward-looking hazard facts for a news broadcast, from real feeds only:
  # - rain forecast for the next days from the weather service (services/weather, ECMWF IFS / GFS fallback)
  # - hotspots detected in the last 24 hours and recent flood areas from GISTDA (via the weather service cache)
  # Values a feed does not provide stay nil; nothing is estimated here.
  class HazardOutlook
    FORECAST_DAYS = 3
    # Thai Meteorological Department daily rainfall criteria (mm/day).
    RAIN_LEVELS = [[90.1, "ฝนหนักมาก"], [35.1, "ฝนหนัก"], [10.1, "ฝนปานกลาง"], [0.1, "ฝนเล็กน้อย"]].freeze
    SQ_M_PER_RAI = 1600.0

    def initialize(user, now: Time.current, weather_client: WeatherFeedClient.new, gistda_client: nil)
      @user = user
      @now = now
      @weather_client = weather_client
      @gistda_client = gistda_client
    end

    # Today plus the next FORECAST_DAYS days for the weather location nearest the user's area (fetched once per instance).
    def weather_forecast(days: FORECAST_DAYS)
      (@weather_forecasts ||= {})[days] ||= fetch_weather_forecast(days)
    end

    # Weekly hazard trend from the disaster archive of the last `years` years (DisasterOutlook), plus the past events
    # recorded in this same week of the year and, for rain-driven hazards, the places hit after no more rain than the
    # coming 3-day forecast. Simulated archive rows are only used while demo data is switched on, and are flagged.
    def disaster_history(years: 5)
      scope = DemoData.filter(DisasterEvent.visible_to(@user).where(:started_at.gte => (@now - years.years).beginning_of_day))
      outlook = DisasterOutlook.new(@user, scope:, date: @now.to_date, weather: self)
      result = outlook.call
      rain = result[:rain_forecast]
      past = outlook.events_in_week
      {
        "source" => "สถิติภัยพิบัติที่ อบต. บันทึกไว้ย้อนหลัง #{years} ปี (ข้อมูลตั้งแต่ #{thai_date(result[:data_from])})",
        "note" => "เป็นสถิติจากอดีต ไม่ใช่การพยากรณ์ว่าจะเกิดแน่นอน",
        "demo_data" => scope.where(simulated: true).exists? ? "ข้อมูลภัยพิบัติชุดนี้เป็นข้อมูลจำลองเพื่อสาธิตระบบ ต้องบอกผู้ฟังว่าเป็นข้อมูลจำลอง" : nil,
        "week" => result[:hazards].first&.dig(:weeks)&.find { |row| row[:offset].zero? }&.dig(:label),
        "rain_next_3_days_mm" => rain[:total_mm],
        "hazards" => result[:hazards].reject { |row| row[:weeks].all? { |week| week[:average].zero? } }.map do |row|
          trigger = row[:rain_trigger_mm]
          { "hazard" => row[:label], "risk" => row[:risk], "trend_next_weeks" => row[:trend],
            "this_week_average_per_year" => row[:this_week_avg], "this_week_last_year" => row[:this_week_last_year],
            "rain_3d_before_past_events_mm" => trigger && { "watch" => trigger[:watch_mm], "median" => trigger[:median_mm] },
            "frequent_places" => row[:hotspots].map { |spot| "#{spot[:label]} (#{spot[:count]} ครั้ง)" }.presence }.compact
        end,
        "summary" => result[:summary].presence,
        "past_events_this_week" => past.first(10).map { |event| past_event(event) }.presence,
        "places_hit_after_similar_rain" => rain_matched(past, rain[:total_mm]).presence
      }.compact
    rescue StandardError => error
      Rails.logger.warn("Broadcast disaster history failed: #{error.class}: #{error.message}")
      { "error" => "ยังสรุปสถิติภัยพิบัติย้อนหลังไม่ได้" }
    end

    # GISTDA VIIRS hotspots in the user's area from GISTDA's daily product (the latest satellite passes), grouped by
    # place. GISTDA publishes passes with a delay, so the strict last-24-hours count is given separately.
    def gistda_hotspots
      payload = gistda_layer.call("hotspots", period: 1)
      since = @now - 24.hours
      points = Array(payload["features"]).filter_map do |feature|
        props = feature["properties"] || {}
        at = props["acquired_at"].presence && Time.zone.parse(props["acquired_at"])
        props.merge("at" => at) if at
      end
      {
        "source" => "GISTDA ดาวเทียม VIIRS (ข้อมูล ณ #{thai_datetime(payload['fetched_at'])})",
        "count_24h" => points.count { |point| point["at"] >= since },
        "count_latest_day" => points.size,
        "latest_detection" => thai_datetime(points.map { |point| point["at"] }.max),
        "places" => points.group_by { |point| point.values_at("village", "tambon", "amphoe", "province") }.map do |(village, tambon, amphoe, province), group|
          { "village" => village, "tambon" => tambon && "ต.#{tambon.delete_prefix('ต.')}", "amphoe" => amphoe && "อ.#{amphoe.delete_prefix('อ.')}",
            "province" => province && "จ.#{province.delete_prefix('จ.')}", "land_use" => group.filter_map { |point| point["land_use"] }.uniq.join(", ").presence,
            "count" => group.size, "count_24h" => group.count { |point| point["at"] >= since },
            "detected" => group.map { |point| point["at"] }.uniq.sort.map { |at| thai_datetime(at) } }.compact
        end.sort_by { |place| -place["count"] }.first(10)
      }.compact
    rescue GistdaDisasterClient::Error => error
      Rails.logger.warn("Broadcast GISTDA hotspots failed: #{error.message}")
      { "error" => "ยังดึงข้อมูลจุดความร้อนจาก GISTDA ไม่ได้" }
    end

    # GISTDA flood polygons of the last `days` days inside the user's area, summed per tambon.
    def gistda_flood(days: 7)
      payload = gistda_layer.call("flood", period: days)
      props = Array(payload["features"]).map { |feature| feature["properties"] || {} }
      {
        "source" => "GISTDA ภาพดาวเทียม (ข้อมูล ณ #{thai_datetime(payload['fetched_at'])})",
        "period_days" => days,
        "flood_areas" => props.size,
        "incomplete" => payload["truncated"] ? "แสดงไม่ครบ มีทั้งหมด #{payload['number_matched']} แปลง" : nil,
        "by_tambon" => props.group_by { |item| item.values_at("tambon", "amphoe") }.map do |(tambon, amphoe), group|
          { "tambon" => tambon, "amphoe" => amphoe, "areas" => group.size, "area_rai" => rai(group, "area_sq_m"),
            "rice_area_rai" => rai(group, "rice_area_sq_m"), "population" => total(group, "population"), "buildings" => total(group, "buildings"),
            "updated" => thai_datetime(group.filter_map { |item| item["updated_at"] }.max) }.compact
        end.sort_by { |row| -row["areas"] }.first(10)
      }.compact
    rescue GistdaDisasterClient::Error => error
      Rails.logger.warn("Broadcast GISTDA flood failed: #{error.message}")
      { "error" => "ยังดึงข้อมูลพื้นที่น้ำท่วมจาก GISTDA ไม่ได้" }
    end

    private

    def fetch_weather_forecast(days)
      location, distance_km = WeatherPanelService.new(user: @user, global_viewer: false, client: @weather_client).location
      forecast = @weather_client.daily_forecast(location["id"], days: days + 1)
      rows = Array(forecast["days"]).map { |day| forecast_day(day) }
      {
        "source" => "พยากรณ์จากแบบจำลอง #{forecast.dig('run', 'model')} (ออกเมื่อ #{thai_datetime(forecast.dig('run', 'run_init_time'))})",
        "location" => location["name_th"].presence || location["name"],
        "distance_km" => distance_km&.round(1),
        "rain_criteria" => "เกณฑ์กรมอุตุนิยมวิทยา: เล็กน้อย 0.1–10 มม. ปานกลาง 10.1–35 มม. หนัก 35.1–90 มม. หนักมากเกิน 90 มม. ต่อวัน",
        "days" => rows,
        "heavy_rain_days" => rows.select { |row| row["rain_level"].in?(%w[ฝนหนัก ฝนหนักมาก]) }.map { |row| row.slice("date", "rain_mm", "rain_level") }
      }.compact
    rescue WeatherFeedClient::Error => error
      Rails.logger.warn("Broadcast weather forecast failed: #{error.message}")
      { "error" => "ยังดึงพยากรณ์อากาศไม่ได้" }
    end

    def past_event(event)
      { "year" => event.started_at.year + 543, "date" => thai_date(event.started_at), "hazard" => event.hazard_label,
        "place" => place_name(event), "severity" => event.severity_label, "rain_3d_before_mm" => event.rain_3d_mm&.round,
        "affected_households" => event.affected_households.to_i.positive? ? event.affected_households : nil }.compact
    end

    # Floods and landslides of this week in past years that followed no more 3-day rain than is forecast now.
    def rain_matched(events, rain_mm)
      return [] unless rain_mm.to_f.positive?

      events.select { |event| event.hazard.in?(DisasterOutlook::RAIN_HAZARDS) && event.rain_3d_mm && event.rain_3d_mm <= rain_mm }
        .group_by { |event| [event.hazard_label, place_name(event)] }
        .map { |(hazard, place), group| { "hazard" => hazard, "place" => place, "times" => group.size, "years" => group.map { |event| event.started_at.year + 543 }.uniq.sort } }
        .sort_by { |row| -row["times"] }.first(8)
    end

    def place_name(event)
      @subdistrict_names ||= {}
      name = @subdistrict_names[event.subdistrict_id] ||= Subdistrict.where(id: event.subdistrict_id).pick(:name_th)
      moo = Array(event.villages).map { |village| "หมู่ #{village}" }.join(", ").presence
      [moo, name && "ต.#{name}"].compact.join(" ")
    end

    def thai_date(value) = value && ApplicationController.helpers.thai_short_date(value)

    def gistda_layer
      @gistda_layer ||= GistdaDisasterLayer.new(client: @gistda_client || GistdaDisasterClient.for(@user), boundary: @user.access_boundary,
                                                tambon_codes: Subdistrict.where(id: @user.accessible_subdistrict_ids).pluck(:code))
    end

    def forecast_day(day)
      rain = day["precipitation_sum_mm"]
      date = Date.parse(day["forecast_date"])
      {
        "date" => "#{%w[อาทิตย์ จันทร์ อังคาร พุธ พฤหัสบดี ศุกร์ เสาร์][date.wday]} #{ApplicationController.helpers.thai_short_date(date)}",
        "when" => %w[วันนี้ พรุ่งนี้ มะรืนนี้][day["forecast_lead_days"].to_i],
        "rain_mm" => rain, "rain_level" => rain_level(rain), "rain_chance_percent" => day["precipitation_probability_max_pct"],
        "rain_hours" => day["precipitation_hours"], "temperature_max_c" => day["temperature_max_c"], "temperature_min_c" => day["temperature_min_c"],
        "wind_gust_kmh" => day["wind_gusts_max_kmh"]
      }.compact
    end

    def rain_level(mm)
      return nil if mm.nil?

      RAIN_LEVELS.find { |min, _label| mm.to_f >= min }&.last || "ไม่มีฝน"
    end

    def rai(group, key)
      values = group.filter_map { |item| item[key] }
      values.any? ? (values.sum / SQ_M_PER_RAI).round(1) : nil
    end

    def total(group, key)
      values = group.filter_map { |item| item[key] }
      values.any? ? values.sum.round : nil
    end

    def thai_datetime(value)
      time = value.is_a?(String) ? Time.zone.parse(value) : value
      time && ApplicationController.helpers.thai_short_datetime(time)
    rescue ArgumentError
      nil
    end
  end
end
