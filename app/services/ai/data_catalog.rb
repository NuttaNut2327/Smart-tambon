module Ai
  # The data the AI assistant may query. Every source loads rows through the app's own visibility rules
  # (visible_to / the user's access boundary), so a chat can only ever see what that account can see in the UI.
  # Rows are flat hashes keyed by field id; enum fields hold their Thai label. Contact details of reporters are
  # never loaded, so they cannot reach the LLM.
  class DataCatalog
    MAX_SCAN = 20_000

    Field = Struct.new(:key, :label, :type, :values, keyword_init: true) do
      def as_catalog_json = { id: key, label: label, type: type, values: values&.first(30) }.compact
    end

    Source = Struct.new(:key, :label, :description, :date_field, :fields, :loader, keyword_init: true) do
      def field(key) = fields.find { |field| field.key == key.to_s }
      def as_catalog_json = { id: key, label: label, description: description, date_field: date_field, fields: fields.map(&:as_catalog_json) }
    end

    INCIDENT_STATUSES = { "pending" => "รอรับเรื่อง", "assessing" => "กำลังประเมิน", "in_progress" => "กำลังดำเนินการ", "completed" => "เสร็จสิ้น" }.freeze
    INCIDENT_SEVERITIES = { "critical" => "วิกฤต", "very_urgent" => "เร่งด่วนมาก", "urgent" => "เร่งด่วน", "watch" => "เฝ้าระวัง",
                            "non_urgent" => "ไม่เร่งด่วน", "waiting" => "รอประเมิน", "general" => "ทั่วไป" }.freeze
    INCIDENT_CATEGORIES = { "general" => "เหตุการณ์ทั่วไป", "disaster" => "ภัยพิบัติ", "activity" => "กิจกรรมในพื้นที่" }.freeze

    def initialize(user)
      @user = user
    end

    attr_reader :user

    def sources
      @sources ||= [incidents, projects, cctv_cameras, subdistricts, environment, water_stations, fire_hotspots,
                    sensor_readings("pm25"), sensor_readings("water_level")].index_by(&:key)
    end

    def source(key)
      key = key.to_s
      return sources[key] if sources.key?(key)

      imported_dataset_source(key.delete_prefix("dataset:")) if key.start_with?("dataset:")
    end

    def as_catalog_json = sources.values.map(&:as_catalog_json)

    # Imported datasets the user can see, for the list_imported_datasets tool.
    def imported_datasets
      visible_datasets.map do |dataset|
        { id: "dataset:#{dataset.id}", name: dataset.display_name, type: dataset.type_label, records: dataset.record_count,
          area: subdistrict_names[dataset.subdistrict_id], updated_at: dataset.updated_at&.iso8601 }.compact
      end
    end

    def area_summary
      ids = user.system_admin? ? [] : user.accessible_subdistrict_ids
      areas = Subdistrict.where(id: ids).includes(:province).map { |area| "ต.#{area.name_th} อ.#{area.district_name_th} จ.#{area.province&.name_th}" }
      {
        organization: OrganizationSetting.for(user)&.display_name(user.access_area&.name) || user.access_area&.name,
        scope: user.system_admin? ? "ทุกพื้นที่ทั่วประเทศ (ผู้ดูแลระบบ)" : areas.join(", ").presence || user.access_area&.name,
        role: user.role_label
      }.compact
    end

    private

    def incidents
      Source.new(
        key: "incidents", label: "เหตุการณ์ ภัยพิบัติ และกิจกรรมในพื้นที่", date_field: "reported_at",
        description: "เรื่องที่แจ้งเข้ามา (เหตุการณ์ทั่วไป/ภัยพิบัติ) และกิจกรรมในพื้นที่ แยกด้วย category",
        fields: [
          f("reference_code", "เลขที่เรื่อง"), f("category", "หมวด", "enum", INCIDENT_CATEGORIES.values),
          f("incident_type", "ประเภท"), f("title", "หัวข้อ"), f("status", "สถานะ", "enum", INCIDENT_STATUSES.values),
          f("severity", "ความรุนแรง", "enum", INCIDENT_SEVERITIES.values.uniq), f("report_source", "ช่องทางแจ้ง"),
          f("location_name", "สถานที่"), f("subdistrict", "ตำบล"), f("affected_people", "ผู้ได้รับผลกระทบ (คน)", "number"),
          f("affected_households", "ครัวเรือนที่ได้รับผลกระทบ", "number"), f("reported_at", "วันที่เกิด/แจ้ง", "date"),
          f("received_at", "วันที่รับเรื่อง", "date"), f("activity_starts_at", "วันเริ่มกิจกรรม", "date"),
          f("activity_ends_at", "วันสิ้นสุดกิจกรรม", "date"), f("expected_attendees", "ผู้เข้าร่วมที่คาด (คน)", "number"),
          f("organizer", "ผู้จัด")
        ],
        loader: lambda {
          Incident.visible_to(user).desc(:created_at).limit(MAX_SCAN)
                  .only(:reference_code, :category, :incident_type, :incident_type_other, :title, :status, :severity, :report_source_name,
                        :location_name, :subdistrict_id, :affected_people, :affected_households, :occurred_at, :created_at, :received_at,
                        :starts_at, :ends_at, :expected_attendees, :organizer).map do |incident|
            type = incident.category == "activity" ? Incident::ACTIVITY_TYPES.dig(incident.incident_type, :label) : incident.incident_type_other.presence || incident.incident_type
            { "reference_code" => incident.reference_code, "category" => INCIDENT_CATEGORIES[incident.category], "incident_type" => type,
              "title" => incident.title, "status" => INCIDENT_STATUSES.fetch(incident.status, incident.status),
              "severity" => INCIDENT_SEVERITIES.fetch(incident.severity, incident.severity), "report_source" => incident.report_source_name,
              "location_name" => incident.location_name, "subdistrict" => subdistrict_names[incident.subdistrict_id],
              "affected_people" => incident.affected_people, "affected_households" => incident.affected_households,
              "reported_at" => incident.occurred_at || incident.created_at, "received_at" => incident.received_at,
              "activity_starts_at" => incident.starts_at, "activity_ends_at" => incident.ends_at,
              "expected_attendees" => incident.expected_attendees, "organizer" => incident.organizer }
          end
        }
      )
    end

    def projects
      Source.new(
        key: "projects", label: "โครงการพัฒนาพื้นที่", date_field: "created_at",
        description: "โครงการ งบประมาณ (บาท) ปีงบประมาณ (พ.ศ.) หน่วยงาน สถานะ และความคืบหน้า",
        fields: [
          f("name", "ชื่อโครงการ"), f("code", "รหัสโครงการ"), f("group", "กลุ่มโครงการ", "enum", Project::GROUPS.values.map { |group| group[:label] }),
          f("project_type", "ประเภท"), f("budget", "งบประมาณ (บาท)", "number"), f("budget_source", "แหล่งงบประมาณ"),
          f("agency", "หน่วยงานรับผิดชอบ"), f("fiscal_year", "ปีงบประมาณ (พ.ศ.)", "number"),
          f("status", "สถานะ", "enum", Project::STATUSES.values), f("approval_status", "การอนุมัติ", "enum", Project::APPROVAL_STATUSES.values),
          f("progress_percent", "ความคืบหน้า (%)", "number"), f("location_name", "สถานที่"), f("subdistrict", "ตำบล"),
          f("created_at", "วันที่บันทึก", "date")
        ],
        loader: lambda {
          Project.visible_to(user).limit(MAX_SCAN).map do |project|
            { "name" => project.name, "code" => project.code, "group" => project.group_label, "project_type" => project.project_type,
              "budget" => project.budget, "budget_source" => project.budget_source, "agency" => project.agency,
              "fiscal_year" => project.fiscal_year, "status" => project.status_label, "approval_status" => project.approval_status_label,
              "progress_percent" => project.progress_percent, "location_name" => project.location_name,
              "subdistrict" => subdistrict_names[project.subdistrict_id], "created_at" => project.created_at }
          end
        }
      )
    end

    def cctv_cameras
      Source.new(
        key: "cctv_cameras", label: "กล้องวงจรปิด", date_field: "created_at",
        description: "ทะเบียนกล้องวงจรปิด สถานะการใช้งาน และที่ตั้ง",
        fields: [
          f("name", "ชื่อกล้อง"), f("code", "รหัส"), f("status", "สถานะ", "enum", CctvCamera::STATUSES.values),
          f("stream_type", "ประเภทสตรีม", "enum", CctvCamera::STREAM_TYPES.values), f("location_name", "สถานที่"),
          f("subdistrict", "ตำบล"), f("created_at", "วันที่ติดตั้ง/บันทึก", "date")
        ],
        loader: lambda {
          CctvCamera.visible_to(user).limit(MAX_SCAN).map do |camera|
            { "name" => camera.name, "code" => camera.code, "status" => CctvCamera::STATUSES.fetch(camera.status, camera.status),
              "stream_type" => CctvCamera::STREAM_TYPES.fetch(camera.stream_type, camera.stream_type), "location_name" => camera.location_name,
              "subdistrict" => subdistrict_names[camera.subdistrict_id], "created_at" => camera.created_at }
          end
        }
      )
    end

    def subdistricts
      Source.new(
        key: "subdistricts", label: "ตำบลในพื้นที่ดูแล", date_field: nil,
        description: "รายชื่อตำบลที่บัญชีนี้ดูแล พร้อมอำเภอ จังหวัด และจำนวนประชากรตามทะเบียนขอบเขต",
        fields: [f("code", "รหัสตำบล"), f("name", "ตำบล"), f("district", "อำเภอ"), f("province", "จังหวัด"), f("population", "ประชากร (คน)", "number")],
        loader: lambda {
          accessible_subdistricts.includes(:province).limit(MAX_SCAN).map do |area|
            { "code" => area.code, "name" => area.name_th, "district" => area.district_name_th, "province" => area.province&.name_th, "population" => area.population }
          end
        }
      )
    end

    def environment
      Source.new(
        key: "environment", label: "สภาพแวดล้อมรายตำบล (ค่าล่าสุด)", date_field: "pm25_observed_at",
        description: "ค่าฝุ่น PM2.5 อุณหภูมิ และฝนสะสม 24 ชม. ล่าสุดของแต่ละตำบล (ข้อมูลแคชจากบริการภายนอก)",
        fields: [
          f("subdistrict", "ตำบล"), f("subdistrict_code", "รหัสตำบล"), f("pm25", "PM2.5 (µg/m³)", "number"),
          f("pm25_avg_24h", "PM2.5 เฉลี่ย 24 ชม.", "number"), f("temperature_c", "อุณหภูมิ (°C)", "number"),
          f("rain_24h_mm", "ฝน 24 ชม. (มม.)", "number"), f("pm25_observed_at", "เวลาวัด PM2.5", "date"),
          f("weather_observed_at", "เวลาวัดอากาศ", "date")
        ],
        loader: lambda {
          codes = accessible_subdistricts.pluck(:code).map(&:to_s)
          EnvironmentalSnapshot.in(subdistrict_code: codes).limit(MAX_SCAN).map do |snapshot|
            { "subdistrict" => snapshot.subdistrict_name, "subdistrict_code" => snapshot.subdistrict_code, "pm25" => snapshot.pm25,
              "pm25_avg_24h" => snapshot.pm25_avg_24h, "temperature_c" => snapshot.temperature_c, "rain_24h_mm" => snapshot.rain_24h_mm,
              "pm25_observed_at" => snapshot.pm25_observed_at, "weather_observed_at" => snapshot.weather_observed_at }
          end
        }
      )
    end

    def water_stations
      Source.new(
        key: "water_stations", label: "สถานีวัดระดับน้ำและฝน (ค่าล่าสุด)", date_field: "observed_at",
        description: "สถานีโทรมาตรในพื้นที่ดูแล พร้อมระดับน้ำ ฝน อัตราการไหล และร้อยละความจุลำน้ำล่าสุด",
        fields: [
          f("station_id", "รหัสสถานี"), f("name", "ชื่อสถานี"), f("agency", "หน่วยงาน"), f("source", "แหล่งข้อมูล"),
          f("subdistrict", "ตำบล"), f("district", "อำเภอ"), f("province", "จังหวัด"), f("basin", "ลุ่มน้ำ"),
          f("water_level_m_msl", "ระดับน้ำ (ม.รทก.)", "number"), f("rainfall", "ฝน (มม.)", "number"),
          f("flow_rate_m3_s", "อัตราการไหล (ลบ.ม./วินาที)", "number"), f("river_capacity_percent", "ความจุลำน้ำ (%)", "number"),
          f("data_status", "สถานะข้อมูล", "enum", %w[ออนไลน์ ข้อมูลล่าช้า ออฟไลน์ ไม่มีข้อมูล]), f("observed_at", "เวลาวัด", "date")
        ],
        loader: lambda {
          inside_boundary(WaterStation.includes(:latest_reading)).limit(MAX_SCAN).map do |station|
            { "station_id" => station.station_id, "name" => station.station_name_th.presence || station.station_code,
              "agency" => station.agency_name.presence || station.agency, "source" => station.source_label,
              "subdistrict" => station.subdistrict_name_th, "district" => station.district_name_th, "province" => station.province_name_th,
              "basin" => station.main_basin_name_th, "water_level_m_msl" => station.water_level_m_msl, "rainfall" => station.rainfall_value,
              "flow_rate_m3_s" => station.flow_rate_m3_s, "river_capacity_percent" => station.river_capacity_percent,
              "data_status" => station.data_status, "observed_at" => station.source_observed_at }
          end
        }
      )
    end

    def fire_hotspots
      Source.new(
        key: "fire_hotspots", label: "จุดความร้อนจากดาวเทียม (FIRMS)", date_field: "acquired_at",
        description: "จุดความร้อนจากดาวเทียมในพื้นที่ดูแล ย้อนหลังสูงสุด 365 วัน",
        fields: [
          f("acquired_at", "เวลาตรวจพบ", "date"), f("source", "ดาวเทียม/แหล่งข้อมูล", "enum", FireHotspot::SOURCE_LABELS.values),
          f("confidence", "ความเชื่อมั่น"), f("frp", "ค่าพลังงานความร้อน FRP (MW)", "number"),
          f("brightness", "อุณหภูมิความสว่าง (K)", "number"), f("daynight", "กลางวัน/กลางคืน", "enum", %w[กลางวัน กลางคืน]),
          f("latitude", "ละติจูด", "number"), f("longitude", "ลองจิจูด", "number")
        ],
        loader: lambda {
          inside_boundary(FireHotspot.recent(24 * 365)).order(acquired_at: :desc).limit(MAX_SCAN).map do |hotspot|
            { "acquired_at" => hotspot.acquired_at, "source" => FireHotspot::SOURCE_LABELS.fetch(hotspot.source, hotspot.source),
              "confidence" => hotspot.confidence, "frp" => hotspot.frp, "brightness" => hotspot.brightness,
              "daynight" => { "D" => "กลางวัน", "N" => "กลางคืน" }[hotspot.daynight], "latitude" => hotspot.location&.y, "longitude" => hotspot.location&.x }
          end
        }
      )
    end

    def sensor_readings(type)
      config = SensorIngestion::TYPES.fetch(type)
      pm25 = type == "pm25"
      measurement_fields = if pm25
        [f("pm25", "PM2.5 (µg/m³)", "number"), f("pm25_avg_24h", "PM2.5 เฉลี่ย 24 ชม.", "number"), f("pm10", "PM10 (µg/m³)", "number"),
         f("temperature_c", "อุณหภูมิ (°C)", "number"), f("humidity_percent", "ความชื้น (%)", "number")]
      else
        [f("water_level_m", "ระดับน้ำ (ม.)", "number"), f("rainfall_mm", "ฝน (มม.)", "number")]
      end
      Source.new(
        key: "#{type}_readings", label: pm25 ? "ค่าที่อ่านได้จากเซนเซอร์ PM2.5 ของ อบต." : "ค่าที่อ่านได้จากเซนเซอร์วัดระดับน้ำของ อบต.",
        date_field: "observed_at", description: "ประวัติค่าที่เซนเซอร์ส่งเข้าระบบ (HTTP/MQTT) ใช้ดูแนวโน้มตามเวลา (ล่าสุด #{MAX_SCAN} ค่า)",
        fields: [f("sensor_id", "รหัสเซนเซอร์"), f("observed_at", "เวลาวัด", "date"), *measurement_fields, f("source", "ช่องทางส่งข้อมูล")],
        loader: lambda {
          dataset_ids = visible_datasets.select { |dataset| dataset.data_type == config[:dataset_type] }.map(&:id)
          attributes = measurement_fields.map(&:key)
          config[:model].where(:imported_dataset_id.in => dataset_ids).desc(:observed_at).limit(MAX_SCAN).map do |reading|
            { "sensor_id" => reading.sensor_id, "observed_at" => reading.observed_at, "source" => reading.source }
              .merge(attributes.index_with { |attribute| reading[attribute] })
          end
        }
      )
    end

    def imported_dataset_source(id)
      dataset = visible_datasets.find { |candidate| candidate.id.to_s == id.to_s }
      return unless dataset

      schema = dataset.effective_schema_definition.reject { |field| field["hidden"] }
      fields = schema.map do |field|
        type = { "number" => "number", "integer" => "number", "date" => "date" }.fetch(field["type"], "text")
        f(field["key"], field["label"].presence || field["key"], type)
      end
      date_keys = fields.select { |field| field.type == "date" }.map(&:key)
      Source.new(
        key: "dataset:#{dataset.id}", label: dataset.display_name, date_field: date_keys.first,
        description: "ชุดข้อมูลนำเข้า (#{dataset.type_label}) ฉบับปัจจุบัน #{dataset.record_count} แถว", fields: fields,
        loader: lambda {
          Array(dataset.current_version&.records).first(MAX_SCAN).map do |record|
            fields.to_h do |field|
              value = record[field.key]
              value = parse_time(value) if field.type == "date"
              value = number(value) if field.type == "number"
              [field.key, value]
            end
          end
        }
      )
    end

    def f(key, label, type = "text", values = nil) = Field.new(key: key, label: label, type: type, values: values)

    def visible_datasets
      @visible_datasets ||= ImportedDataset.visible_to(user).only(:_id, :name, :data_type, :subdistrict_id, :schema_definition, :current_version_id, :updated_at).to_a
    end

    def accessible_subdistricts
      user.system_admin? ? Subdistrict.all : Subdistrict.where(id: user.accessible_subdistrict_ids)
    end

    def subdistrict_names
      @subdistrict_names ||= Hash.new do |cache, id|
        cache[id] = id && Subdistrict.where(id: id).pick(:name_th)
      end
    end

    def inside_boundary(scope)
      return scope if user.system_admin?

      boundary = user.access_boundary
      boundary ? scope.inside(boundary) : scope.none
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.nil?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def number(value)
      return value if value.is_a?(Numeric) || value.nil?

      Float(value.to_s.delete(","), exception: false)
    end
  end
end
