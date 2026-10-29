module Broadcasts
  # Collects the real data a news broadcast may talk about, scoped to one อบต. through a representative user so the
  # normal visibility rules apply. Only public-safe facts are included: no reporter names, phone numbers or photos.
  class Context
    THAI_MONTHS = %w[มกราคม กุมภาพันธ์ มีนาคม เมษายน พฤษภาคม มิถุนายน กรกฎาคม สิงหาคม กันยายน ตุลาคม พฤศจิกายน ธันวาคม].freeze

    def self.for(program, now: Time.current) = new(program, now).build

    def initialize(program, now)
      @program = program
      @now = now
      @user = User.where(organization_key: program.organization_key).order(role: :asc, id: :asc).first
      raise ArgumentError, "ไม่พบผู้ใช้ของหน่วยงานนี้" unless @user
    end

    def build
      subdistricts = Subdistrict.where(id: @user.accessible_subdistrict_ids).includes(:province).to_a
      context = {
        "organization" => organization_name(subdistricts),
        "area" => subdistricts.map { |area| "ต.#{area.name_th} อ.#{area.district_name_th} จ.#{area.province&.name_th}" },
        "generated_at" => thai_datetime(@now),
        "today" => "#{%w[อาทิตย์ จันทร์ อังคาร พุธ พฤหัสบดี ศุกร์ เสาร์][@now.wday]} #{thai_date(@now)}",
        # Spelled-out date so the announcer script doesn't misread the abbreviated one.
        "today_full" => "วัน#{%w[อาทิตย์ จันทร์ อังคาร พุธ พฤหัสบดี ศุกร์ เสาร์][@now.wday]}ที่ #{@now.day} #{THAI_MONTHS[@now.month - 1]} พ.ศ. #{@now.year + 543}"
      }
      sources = @program.data_sources
      environment = environment(subdistricts) if (sources & %w[weather pm25]).any?
      context["weather"] = environment.map { |row| row.except("pm25", "pm25_avg_24h", "pm25_level", "pm25_source") } if sources.include?("weather")
      context["air_quality"] = environment.map { |row| row.slice("area", "pm25", "pm25_avg_24h", "pm25_level", "pm25_source") } if sources.include?("pm25")
      context["water_levels"] = water_levels if sources.include?("water")
      context["fire_hotspots"] = fire_hotspots if sources.include?("fire_hotspots")
      outlook = HazardOutlook.new(@user, now: @now) if (sources & %w[weather_forecast gistda_hotspots gistda_flood disaster_history]).any?
      context["weather_forecast"] = outlook.weather_forecast if sources.include?("weather_forecast")
      context["disaster_history"] = outlook.disaster_history(years: @program.history_years) if sources.include?("disaster_history")
      context["gistda_hotspots_24h"] = outlook.gistda_hotspots if sources.include?("gistda_hotspots")
      context["gistda_flood"] = outlook.gistda_flood if sources.include?("gistda_flood")
      context["activities"] = activities if sources.include?("activities")
      context["incidents_last_24h"] = incidents("general") if sources.include?("incidents")
      context["disasters_active"] = incidents("disaster", active_only: true) if sources.include?("disasters")
      context["projects"] = projects if sources.include?("projects")
      context["contact"] = contact
      context["alerts"] = alerts(context)
      context.compact
    end

    # What is worth warning about in the collected data; an alert-only programme skips the day when this is nil.
    def self.alerts(context)
      list = Array(context.dig("weather_forecast", "heavy_rain_days")).map { |day| "#{day['rain_level']} #{day['date']} (#{day['rain_mm']} มม.)" }
      list += Array(context.dig("disaster_history", "hazards")).select { |row| row["risk"].in?(%w[สูง สูงมาก]) }
        .map { |row| "#{row['hazard']} ความเสี่ยง#{row['risk']} ตามสถิติย้อนหลัง" }
      list << "พื้นที่น้ำท่วมจาก GISTDA #{context.dig('gistda_flood', 'flood_areas')} แปลง" if context.dig("gistda_flood", "flood_areas").to_i.positive?
      list << "จุดความร้อน 24 ชม. #{context.dig('gistda_hotspots_24h', 'count_24h')} จุด" if context.dig("gistda_hotspots_24h", "count_24h").to_i.positive?
      list << "ภัยพิบัติที่กำลังดำเนินการ #{context.dig('disasters_active', 'count')} เรื่อง" if context.dig("disasters_active", "count").to_i.positive?
      list.presence
    end

    private

    def alerts(context) = self.class.alerts(context)

    def organization_name(subdistricts)
      OrganizationSetting.for(@user)&.organization_name.presence || "องค์การบริหารส่วนตำบล#{subdistricts.first&.name_th}"
    end

    def contact
      setting = OrganizationSetting.for(@user)
      { "phone" => setting&.phone, "website" => setting&.website }.compact.presence
    end

    def environment(subdistricts)
      snapshots = EnvironmentalSnapshotService.for(subdistricts)
      by_code = snapshots.index_by { |snapshot| snapshot.subdistrict_code.to_s }
      pm25 = Pm25SourceResolver.resolve(user: @user, subdistricts:, snapshots:)
      rain = SubdistrictRainfallService.resolve(subdistricts, snapshots)
      subdistricts.map do |area|
        code = area.code.to_s
        snapshot = by_code[code]
        reading = pm25[code] || {}
        {
          "area" => "ต.#{area.name_th}",
          "temperature_c" => snapshot&.temperature_c&.round(1),
          "rain_24h_mm" => rain.dig(code, :value),
          "observed_at" => thai_datetime(snapshot&.weather_observed_at || snapshot&.temperature_observed_at),
          "pm25" => reading[:value],
          "pm25_avg_24h" => reading[:avg_24h],
          "pm25_level" => pm25_level(reading[:avg_24h] || reading[:value]),
          "pm25_source" => reading[:source_label]
        }.compact
      end
    rescue StandardError => error
      Rails.logger.warn("Broadcast environment context failed: #{error.class}: #{error.message}")
      []
    end

    # Thai PCD AQI bands for 24-h PM2.5 (µg/m³).
    def pm25_level(value)
      return if value.nil?

      case value.to_f
      when 0...15.1 then "ดีมาก"
      when 15.1...25.1 then "ดี"
      when 25.1...37.6 then "ปานกลาง"
      when 37.6...75.1 then "เริ่มมีผลต่อสุขภาพ"
      else "มีผลต่อสุขภาพ"
      end
    end

    def water_levels
      boundary = @user.access_boundary
      return [] unless boundary

      WaterStation.includes(:latest_reading).inside(boundary).limit(10).map do |station|
        { "station" => station.station_name_th.presence || station.station_code, "water_level_m_msl" => station.water_level_m_msl&.round(2),
          "rain_24h_mm" => station.rainfall_value, "capacity_percent" => station.river_capacity_percent&.round,
          "observed_at" => thai_datetime(station.source_observed_at), "status" => station.data_status }.compact
      end
    rescue StandardError
      []
    end

    def fire_hotspots
      boundary = @user.access_boundary
      return nil unless boundary && defined?(FireHotspot)

      { "count_24h" => FireHotspot.recent(24).inside(boundary).count }
    rescue StandardError
      nil
    end

    def activities
      Incident.finish_expired_activities!(@now)
      horizon = @now + @program.lookahead_days.days
      Incident.visible_to(@user).activities.where(:status.ne => "completed", :starts_at.lte => horizon).asc(:starts_at).limit(15).map do |activity|
        { "title" => activity.title, "type" => activity.activity_type_label, "phase" => activity.activity_phase_label,
          "starts" => thai_datetime(activity.starts_at), "ends" => thai_datetime(activity.ends_at),
          "place" => activity.location_name, "organizer" => activity.organizer, "expected_attendees" => activity.expected_attendees,
          "details" => activity.description.to_s.truncate(300).presence }.compact
      end
    end

    def incidents(category, active_only: false)
      scope = Incident.visible_to(@user).where(category:)
      scope = active_only ? scope.where(:status.ne => "completed") : scope.where(:created_at.gte => @now - 24.hours)
      list = scope.desc(:created_at).limit(15).to_a
      statuses = { "pending" => "รอรับเรื่อง", "assessing" => "กำลังประเมิน", "in_progress" => "กำลังดำเนินการ", "completed" => "แก้ไขแล้ว" }
      {
        "count" => list.size,
        "items" => list.map do |incident|
          { "type" => incident.incident_type.presence || incident.incident_type_other, "title" => incident.title,
            "place" => incident.location_name.to_s.start_with?("ตำแหน่งที่") ? nil : incident.location_name,
            "status" => statuses.fetch(incident.status, incident.status), "reported" => thai_datetime(incident.created_at) }.compact
        end
      }
    end

    def projects
      return [] unless defined?(Project)

      Project.visible_to(@user).where(:status.in => %w[procurement in_progress]).limit(10).map do |project|
        { "name" => project.name, "type" => project.project_type, "status" => project.status_label,
          "progress_percent" => project.progress_percent, "place" => project.location_name }.compact
      end
    rescue StandardError
      []
    end

    def thai_datetime(time) = time && ApplicationController.helpers.thai_short_datetime(time)
    def thai_date(time) = ApplicationController.helpers.thai_short_date(time)
  end
end
