class DashboardController < ApplicationController
  def index
    @page_mode = :overview
    load_area_context
    load_overview_summary
  end

  def map
    redirect_to area_analysis_path
  end

  def area_analysis
    @page_mode = :analysis
    load_area_context
    render :index
  end

  def general_incidents
    load_incident_page("general", :general_incidents)
  end

  def disasters
    load_incident_page("disaster", :disasters)
  end

  def load_incident_page(category, page_mode)
    @page_mode = page_mode
    load_area_context
    @incident_category = category
    @incidents_path = category == "disaster" ? disasters_path : general_incidents_path
    @allow_incident_creation = category == "general"
    all_incidents = Incident.visible_to(current_user).where(category: category).desc(:created_at).to_a
    @incident_summary = {
      total: all_incidents.size,
      pending: all_incidents.count { |incident| incident.status == "pending" },
      in_progress: all_incidents.count { |incident| %w[assessing in_progress].include?(incident.status) },
      completed: all_incidents.count { |incident| incident.status == "completed" }
    }
    category_incidents = all_incidents
    @incident_status_counts = {
      all: category_incidents.size,
      pending: category_incidents.count { |incident| incident.status == "pending" },
      in_progress: category_incidents.count { |incident| %w[assessing in_progress].include?(incident.status) },
      completed: category_incidents.count { |incident| incident.status == "completed" }
    }
    @incidents = category_incidents
    team_datasets = ImportedDataset.visible_to(current_user).where(data_type: "teams").to_a
    @incident_team_options = team_datasets.flat_map do |dataset|
      Array(dataset.current_version&.records).filter_map do |record|
        [record["team_name"], record["team_code"]] if record["team_name"].present? && record["status"].to_s != "ไม่พร้อมปฏิบัติงาน"
      end
    end.uniq.sort_by(&:first)
    if @incident_team_options.empty?
      workforce_datasets = ImportedDataset.visible_to(current_user).where(data_type: "workforce").to_a
      @incident_team_options = workforce_datasets.flat_map { |dataset| Array(dataset.current_version&.records).filter_map { |record| [record["team_name"], record["team_name"]] if record["team_name"].present? } }.uniq.sort_by(&:first)
    end
    @incident_usage_options = IncidentUsageCatalog.for(current_user)
    @response_plan_resource_options = IncidentUsageCatalog.summary_for(current_user)
    @selected_incident = @incidents.find { |incident| incident.id.to_s == params[:incident_id] } || @incidents.first
    requested_version = params[:plan_version].to_i
    @selected_plan = if @selected_incident
      @selected_incident.response_plan_versions.find { |version| version["version"].to_i == requested_version } ||
        @selected_incident.active_plan || @selected_incident.response_plan_versions.max_by { |version| version["version"].to_i }
    end
    render :index
  end

  def resource_rules
    load_area_context
    @resource_rules = ResourceRule.visible_to(current_user).desc(:created_at).to_a
    @rule_resource_options = IncidentUsageCatalog.rule_options_for(current_user)
  end

  private

  def load_overview_summary
    incidents = Incident.visible_to(current_user).to_a
    now = Time.current
    recent_incidents = incidents.select { |incident| incident.created_at.present? && incident.created_at >= 24.hours.ago }
    today_incidents = incidents.select { |incident| incident.created_at.present? && incident.created_at.in_time_zone.to_date == now.to_date }

    @overview_incident_summary = {
      received: recent_incidents.size,
      today: today_incidents.size,
      unresolved: incidents.count { |incident| incident.status != "completed" },
      completed: incidents.count { |incident| incident.status == "completed" }
    }
    @overview_dashboard_data = {
      tasks: overview_tasks(incidents),
      hazards: overview_hazards(incidents),
      environment: overview_environment,
      baseline: overview_baseline
    }
  end

  def overview_tasks(incidents)
    status_rank = { "pending" => 0, "assessing" => 1, "in_progress" => 1 }
    severity_rank = { "critical" => 0, "very_urgent" => 1, "urgent" => 2, "watch" => 3, "non_urgent" => 4, "waiting" => 4, "general" => 5 }
    severity_label = { "critical" => "วิกฤต", "very_urgent" => "เร่งด่วนมาก", "urgent" => "เร่งด่วน", "watch" => "เฝ้าระวัง", "non_urgent" => "ไม่เร่งด่วน", "waiting" => "ไม่เร่งด่วน", "general" => "ทั่วไป" }
    severity_class = { "critical" => "emergency", "very_urgent" => "emergency", "urgent" => "priority", "watch" => "watch", "non_urgent" => "normal", "waiting" => "normal", "general" => "normal" }

    incidents.select { |incident| status_rank.key?(incident.status) }
      .sort_by { |incident| [status_rank.fetch(incident.status), severity_rank.fetch(incident.severity, 9), -(incident.created_at&.to_i || 0)] }
      .map do |incident|
        status_group = incident.status
        status_labels = { "pending" => "รอรับเรื่อง", "assessing" => "กำลังประเมิน", "in_progress" => "กำลังดำเนินการ" }
        location_name = incident.location_name.presence || "ไม่ระบุสถานที่"
        {
          id: incident.id.to_s, reference_code: incident.reference_code,
          title: incident.title, place: location_name,
          longitude: incident.longitude, latitude: incident.latitude,
          approximate_address: location_name.present? && !location_name.start_with?("ตำแหน่งที่") && location_name != "ไม่ระบุสถานที่",
          time: incident.created_at&.in_time_zone&.strftime("%d/%m/%Y %H:%M น."),
          reporter: [incident.reporter_name, incident.reporter_contact].compact_blank.join(" · ").presence || incident.report_source_label,
          team: incident.assigned_to.presence || "ยังไม่มอบหมายผู้รับผิดชอบ",
          impact: incident.initial_impact.presence || "ยังไม่มีข้อมูลผลกระทบเบื้องต้น",
          detail: incident.description.presence || "ไม่มีรายละเอียดเพิ่มเติม",
          next: status_group == "pending" ? ["ตรวจสอบรายละเอียดและยืนยันรับเรื่อง", "มอบหมายทีมรับผิดชอบ"] : ["ติดตามความคืบหน้าจากทีมรับผิดชอบ", "บันทึกผลการดำเนินงาน"],
          status: status_group, status_label: status_labels.fetch(status_group),
          level: severity_class.fetch(incident.severity, "normal"), severity_label: severity_label.fetch(incident.severity, "ทั่วไป")
        }
      end
  end

  def overview_hazards(incidents)
    active = incidents.reject { |incident| incident.status == "completed" }
    incident_hazards = [
      ["น้ำท่วม", "flood"], ["ไฟป่า", "local_fire_department"], ["พายุ", "air"],
      ["ดินถล่ม", "landslide"], ["ภัยแล้ง", "landscape"]
    ].map do |name, icon|
      count = active.count { |incident| incident.incident_type == name }
      { name:, icon:, count:, tone: count.positive? ? (name == "น้ำท่วม" ? "danger" : "watch") : "safe" }
    end
    incident_hazards
  end

  def overview_environment
    return [] if global_viewer?

    subdistricts = Subdistrict.where(id: current_user.accessible_subdistrict_ids).to_a
    snapshots = EnvironmentalSnapshotService.for(subdistricts)
    snapshots_by_code = snapshots.index_by { |snapshot| snapshot.subdistrict_code.to_s }
    pm25_by_code = Pm25SourceResolver.resolve(user: current_user, subdistricts:, snapshots:)
    rainfall_by_code = SubdistrictRainfallService.resolve(subdistricts, snapshots)

    subdistricts.map do |subdistrict|
      snapshot = snapshots_by_code[subdistrict.code.to_s]
      pm25 = pm25_by_code[subdistrict.code.to_s]
      rainfall = rainfall_by_code[subdistrict.code.to_s]
      {
        subdistrict_code: subdistrict.code.to_s,
        subdistrict_name: subdistrict.name_th,
        pm25: pm25[:value],
        pm25_avg_24h: pm25[:avg_24h],
        pm25_source: pm25[:source],
        pm25_source_label: pm25[:source_label],
        pm25_station_name: pm25[:station_name],
        pm25_station_id: pm25[:station_id],
        pm25_station_agency: pm25[:agency],
        temperature_c: snapshot&.temperature_c&.round(1),
        temperature_source: snapshot&.temperature_source,
        temperature_source_label: snapshot&.temperature_source_label,
        temperature_observed_at: snapshot&.temperature_observed_at&.in_time_zone&.iso8601,
        temperature_station_id: snapshot&.temperature_station_id,
        temperature_station_name: snapshot&.temperature_station_name,
        temperature_station_agency: snapshot&.temperature_station_agency,
        rain_24h_mm: rainfall[:value],
        rain_observed_at: rainfall[:observed_at]&.in_time_zone&.iso8601,
        rain_source: rainfall[:source],
        rain_source_label: rainfall[:source_label],
        rain_station_name: rainfall[:station_name],
        rain_station_code: rainfall[:station_code],
        pm25_observed_at: pm25[:observed_at]&.in_time_zone&.iso8601,
        weather_observed_at: snapshot&.weather_observed_at&.in_time_zone&.iso8601,
        stale: snapshot ? !snapshot.fresh? : true
      }
    end
  end

  def overview_baseline
    return empty_overview_baseline if global_viewer?

    registry = ImportedDataset.visible_to(current_user).where(:data_type.in => %w[population resources teams workforce]).to_a
    population_records = registry.select { |dataset| dataset.data_type == "population" }.flat_map { |dataset| Array(dataset.current_version&.records) }
    resource_records = registry.select { |dataset| dataset.data_type == "resources" }.flat_map { |dataset| Array(dataset.current_version&.records) }
    team_records = registry.select { |dataset| dataset.data_type == "teams" }.flat_map { |dataset| Array(dataset.current_version&.records) }
    workforce_records = registry.select { |dataset| dataset.data_type == "workforce" }.flat_map { |dataset| Array(dataset.current_version&.records) }
    population = population_records.sum { |record| record["population_total"].to_i }
    accessible_subdistricts = Subdistrict.where(id: current_user.accessible_subdistrict_ids)
      .select(:code, :name_th, :district_name_th).to_a
    jurisdiction = accessible_subdistricts.group_by { |subdistrict| subdistrict.district_name_th.presence || "ไม่ระบุอำเภอ" }
      .map do |district_name, subdistricts|
        {
          district_name:,
          subdistricts: subdistricts.sort_by { |subdistrict| [subdistrict.name_th.to_s, subdistrict.code.to_s] }
            .map { |subdistrict| { code: subdistrict.code, name: subdistrict.name_th } }
        }
      end.sort_by { |district| district[:district_name] }
    subdistrict_by_code = accessible_subdistricts.index_by { |subdistrict| subdistrict.code.to_s }
    subdistrict_by_name = accessible_subdistricts.index_by { |subdistrict| subdistrict.name_th.to_s.strip }
    population_by_area = population_records.group_by do |record|
      [record["subdistrict_code"].to_s, record["subdistrict"].presence || "ไม่ระบุตำบล"]
    end.map do |(subdistrict_code, subdistrict_name), records|
      administrative_area = subdistrict_by_code[subdistrict_code] || subdistrict_by_name[subdistrict_name.to_s.strip]
      villages = records.map do |record|
        {
          village_code: record["village_code"], village_number: record["village_number"].to_i,
          village_name: record["village_name"].presence || "ไม่ระบุชื่อหมู่บ้าน",
          male: record["population_male"].to_i, female: record["population_female"].to_i,
          population: record["population_total"].to_i, households: record["household_count"].to_i
        }
      end.sort_by { |record| [record[:village_number].zero? ? 9_999 : record[:village_number], record[:village_name]] }
      {
        subdistrict_code:, subdistrict_name:, district_name: administrative_area&.district_name_th.presence || "ไม่ระบุ",
        male: villages.sum { |village| village[:male] }, female: villages.sum { |village| village[:female] },
        population: villages.sum { |village| village[:population] },
        households: villages.sum { |village| village[:households] }, villages:
      }
    end.sort_by { |area| [area[:subdistrict_name], area[:subdistrict_code]] }

    available_catalog = IncidentUsageCatalog.for(current_user)
    available_resources = available_catalog.select { |item| item[:kind] == "resource" }.group_by { |item| item[:name] }
    resources = resource_records.group_by { |record| record["name"].presence || record["resource_type"].presence || "ไม่ระบุชื่อ" }.map do |name, records|
      ready = Array(available_resources[name]).sum { |item| item[:available].to_i }
      { name:, total: records.size, ready:, unavailable: records.size - ready, unit: records.first["unit"].presence || "รายการ" }
    end.sort_by { |row| [-row[:total], row[:name]] }.first(8)

    workforce_by_team = workforce_records.group_by { |record| record["team_name"].presence || "ยังไม่ระบุทีม" }
    available_workforce_by_team = available_catalog.select { |item| item[:kind] == "workforce" }.group_by { |item| item[:team_name].presence || "ยังไม่ระบุทีม" }
    teams = team_records.map do |team|
      members = workforce_by_team.delete(team["team_name"].to_s) || []
      ready = Array(available_workforce_by_team[team["team_name"]]).sum { |item| item[:available].to_i }
      { name: team["team_name"], total: members.size, ready:, unavailable: members.size - ready, unit: "คน", team_ready: team["status"] == "พร้อมปฏิบัติงาน" }
    end
    workforce_by_team.each do |name, members|
      ready = Array(available_workforce_by_team[name]).sum { |item| item[:available].to_i }
      teams << { name:, total: members.size, ready:, unavailable: members.size - ready, unit: "คน", team_ready: ready.positive? }
    end

    {
      area_sq_km: overview_area_sq_km, population:,
      organization_type: current_user.access_area&.organization_type_label || "องค์การบริหารส่วนตำบล (อบต.)",
      population_male: population_records.sum { |record| record["population_male"].to_i },
      population_female: population_records.sum { |record| record["population_female"].to_i },
      villages: population_records.map { |record| [record["subdistrict_code"], record["village_code"], record["village_number"]] }.uniq.size,
      households: population_records.sum { |record| record["household_count"].to_i },
      population_by_area:, jurisdiction:,
      resources:, teams: teams.sort_by { |row| [-row[:total], row[:name].to_s] }.first(8)
    }
  end

  def empty_overview_baseline
    {
      area_sq_km: 0,
      population: 0,
      organization_type: "ผู้ดูแลระบบ",
      population_male: 0,
      population_female: 0,
      villages: 0,
      households: 0,
      population_by_area: [],
      jurisdiction: [],
      resources: [],
      teams: []
    }
  end

  def overview_area_sq_km
    if current_user.access_area.present?
      UserAccessArea.where(id: current_user.access_area.id)
        .pick(Arel.sql("ST_Area(ST_SetSRID(boundary, 4326)::geography) / 1000000.0")).to_f.round(2)
    else
      Subdistrict.where(id: current_user.accessible_subdistrict_ids)
        .pick(Arel.sql("COALESCE(SUM(ST_Area(boundary::geography)), 0) / 1000000.0")).to_f.round(2)
    end
  rescue ActiveRecord::StatementInvalid
    0
  end

  def load_area_context
    @assigned_subdistrict = current_user.subdistrict unless system_admin?
    @provinces = if global_viewer?
      Province.alphabetical
    elsif @assigned_subdistrict
      [@assigned_subdistrict.province]
    else
      []
    end
  end
end
