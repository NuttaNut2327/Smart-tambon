class IncidentsController < ApplicationController
  def notification
    pending_incidents = Incident.visible_to(current_user).where(category: "general", status: "pending").desc(:created_at)
    latest_incident = pending_incidents.first

    render json: {
      pending_count: pending_incidents.count,
      incident: latest_incident && {
        id: latest_incident.id.to_s,
        reference_code: latest_incident.reference_code,
        title: latest_incident.title,
        severity: latest_incident.severity,
        url: general_incidents_path(incident_id: latest_incident.id)
      }
    }
  end

  def assessment
    @incident = find_incident

    @page_mode = :disasters
    @assigned_subdistrict = current_user.subdistrict unless current_user.system_admin?
    @provinces = current_user.system_admin? ? Province.alphabetical : [@assigned_subdistrict&.province].compact
    render :assessment
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def standalone_assessment
    @incident = nil
    @page_mode = :city_map
    @assigned_subdistrict = current_user.subdistrict unless current_user.system_admin?
    @provinces = current_user.system_admin? ? Province.alphabetical : [@assigned_subdistrict&.province].compact
    @map_incidents = Incident.visible_to(current_user).where(category: "general").to_a.filter_map do |incident|
      next unless incident.longitude.present? && incident.latitude.present?

      {
        id: incident.id.to_s, reference_code: incident.reference_code, title: incident.title,
        source: incident.report_source_label, longitude: incident.longitude, latitude: incident.latitude,
        severity: incident.severity, description: incident.description.to_s.truncate(180),
        status: incident.status, url: general_incidents_path(incident_id: incident.id)
      }
    end
    @map_incident_sources = @map_incidents.group_by { |incident| incident[:source] }
    @map_datasets = ImportedDataset.visible_to(current_user)
      .where(map_enabled: true)
      .to_a
      .reject { |dataset| dataset.data_type == "village_boundaries" }
      .sort_by { |dataset| dataset.name.to_s }
    render :assessment
  end

  def calculate_assessment
    incident = params[:id].present? ? find_incident : nil

    area_sq_km = [params[:area_sq_km].to_f, 0].max
    coverage_ratio = params[:coverage_ratio].to_f.clamp(0, 1)
    sensor_metrics = {}
    boundary = current_user.access_boundary
    if params[:geometry].present? && boundary.present?
      connection = ActiveRecord::Base.connection
      selected_geojson = connection.quote(params[:geometry].to_json)
      boundary_wkt = connection.quote(boundary.as_text)
      area_result = connection.select_one(<<~SQL.squish)
        WITH shapes AS (
          SELECT
            ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(#{selected_geojson}), 4326)) AS selected,
            ST_MakeValid(ST_SetSRID(ST_GeomFromText(#{boundary_wkt}), 4326)) AS boundary
        )
        SELECT
          ST_Area(ST_CollectionExtract(ST_Intersection(selected, boundary), 3)::geography) / 1000000.0 AS selected_area,
          ST_Area(ST_CollectionExtract(boundary, 3)::geography) / 1000000.0 AS boundary_area
        FROM shapes
      SQL
      area_sq_km = area_result["selected_area"].to_f
      boundary_area_sq_km = area_result["boundary_area"].to_f
      coverage_ratio = boundary_area_sq_km.positive? ? (area_sq_km / boundary_area_sq_km).clamp(0, 1) : 0
      station_result = connection.select_one(<<~SQL.squish)
        WITH shapes AS (
          SELECT
            ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(#{selected_geojson}), 4326)) AS selected,
            ST_MakeValid(ST_SetSRID(ST_GeomFromText(#{boundary_wkt}), 4326)) AS boundary
        )
        SELECT MAX(water_level_m_msl) AS water_level, MAX(rainfall_value) AS rainfall
        FROM water_stations, shapes
        WHERE ST_Intersects(location, ST_Intersection(selected, boundary))
      SQL
      sensor_metrics["water_level"] = station_result["water_level"] if station_result["water_level"].present?
      sensor_metrics["rainfall"] = station_result["rainfall"] if station_result["rainfall"].present?
    end
    datasets = ImportedDataset.visible_to(current_user).where(:data_type.in => %w[population resources workforce custom]).to_a
    records_by_type = datasets.group_by(&:data_type).transform_values do |group|
      group.flat_map { |dataset| Array(dataset.current_version&.records) }
    end
    population_records = records_by_type.fetch("population", [])
    affected_people = (population_records.sum { |record| record["population_total"].to_i } * coverage_ratio).round
    affected_households = (population_records.sum { |record| record["household_count"].to_i } * coverage_ratio).round
    affected_villages = [(population_records.size * coverage_ratio).ceil, population_records.size].min
    resource_records = records_by_type.fetch("resources", [])
    workforce_records = records_by_type.fetch("workforce", [])
    custom_records = records_by_type.fetch("custom", [])
    %w[water_level rainfall wind_speed].each do |key|
      values = custom_records.filter_map { |record| Float(record[key], exception: false) }
      sensor_metrics[key] ||= values.max if values.any?
    end
    hotspot_count = custom_records.sum { |record| Float(record["hotspot_count"], exception: false).to_f }
    simulated = params[:simulation_metrics].respond_to?(:to_unsafe_h) ? params[:simulation_metrics].to_unsafe_h : {}
    %w[water_level rainfall wind_speed].each do |key|
      sensor_metrics[key] = simulated[key].to_f if simulated[key].present?
    end
    hotspot_count = simulated["hotspot_count"].to_f if simulated["hotspot_count"].present?
    disaster_type = incident ? incident_disaster_type(incident) : params[:disaster_type].to_s
    disaster_type = "other" unless ResourceRule::DISASTER_TYPES.include?(disaster_type)
    candidate_rules = ResourceRule.visible_to(current_user).where(active: true, disaster_type: disaster_type).to_a
    hotspot_scopes = candidate_rules.flat_map(&:conditions).select { |condition| condition["variable"] == "hotspot_count" }.map do |condition|
      { "area_value" => condition["area_value"], "area_unit" => condition["area_unit"], "count" => hotspot_count }
    end
    metrics = sensor_metrics.merge(
      "population" => affected_people,
      "households" => affected_households,
      "area" => area_sq_km,
      "hotspot_scopes" => hotspot_scopes
    )
    matched_rules = candidate_rules.select { |rule| rule.matches_metrics?(metrics) }
    selected_rule = if params[:rule_id].present?
      matched_rules.find { |rule| rule.id.to_s == params[:rule_id].to_s } || matched_rules.first
    else
      matched_rules.first
    end
    rules = selected_rule ? [selected_rule] : []
    formulas = rules.flat_map(&:formulas)
    resources = formulas.group_by { |formula| [formula["resource"], formula["unit"]] }.map do |(name, unit), grouped|
      required = grouped.sum do |formula|
        basis = case formula["basis"]
        when "population" then affected_people
        when "households" then affected_households
        when "villages" then affected_villages
        else area_sq_km
        end
        (basis.to_f / [formula["per_value"].to_f, 1].max * formula["amount"].to_f).ceil
      end
      workforce = workforce_records.select do |record|
        record["team_name"].to_s.casecmp?(name.to_s) || record["full_name"].to_s.casecmp?(name.to_s)
      end
      available = if workforce.any?
        workforce.sum do |record|
          if record["availability_status"].present?
            record["employment_status"].to_s != "พ้นสภาพ" && record["availability_status"] == "พร้อมปฏิบัติงาน" ? 1 : 0
          else
            record["ready_count"].to_i
          end
        end
      else
        resource_records.count { |record| record["name"].to_s.casecmp?(name.to_s) && record["status"].to_s.include?("พร้อม") }
      end
      { name: name, unit: unit, required: required, available: available, sufficient: available >= required }
    end
    render json: {
      area_sq_km: area_sq_km.round(3), coverage_ratio: coverage_ratio.round(4),
      affected_people: affected_people, affected_households: affected_households,
      affected_villages: affected_villages, disaster_type: disaster_type,
      rule_names: rules.map(&:name), resources: resources,
      available_rules: matched_rules.map { |rule| { id: rule.id.to_s, name: rule.name } },
      selected_rule_id: selected_rule&.id&.to_s,
      evaluated_rule_count: candidate_rules.size, matched_rule_count: matched_rules.size
    }
  rescue Mongoid::Errors::DocumentNotFound
    render json: { error: "ไม่พบเหตุการณ์ที่ต้องการ" }, status: :not_found
  end

  def create
    incident = Incident.new(incident_attributes)
    incident.category = "general"
    incident.status = "pending"
    incident.user_id = current_user.id
    incident.owner_user_id = current_user.id
    incident.access_area_id = current_user.access_area&.id
    incident.report_source_type = "staff"
    incident.report_source_name = "เจ้าหน้าที่"
    incident.subdistrict_id = current_user.subdistrict_id || params.dig(:incident, :subdistrict_id)
    if incident.subdistrict_id.blank?
      return redirect_to general_incidents_path, alert: "กรุณาเลือกบัญชีประจำพื้นที่ก่อนบันทึกเหตุการณ์"
    end

    incident.save!
    redirect_to general_incidents_path(incident_id: incident.id), notice: "บันทึกเหตุการณ์ใหม่เรียบร้อยแล้ว"
  rescue Mongoid::Errors::Validations => error
    redirect_to general_incidents_path, alert: error.document.errors.full_messages.join(" · ")
  end

  def update
    incident = find_incident
    attributes = incident_attributes
    if attributes[:assigned_team_code].present?
      attributes[:assigned_to] = team_name_for(attributes[:assigned_team_code])
    end
    incident.update!(attributes)
    redirect_to incident_page_path(incident, incident_id: incident.id), notice: "แก้ไขข้อมูลเหตุการณ์เรียบร้อยแล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to general_incidents_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  rescue Mongoid::Errors::Validations => error
    redirect_to incident_page_path(error.document, incident_id: params[:id]), alert: error.document.errors.full_messages.join(" · ")
  end

  def destroy
    incident = find_incident
    redirect_path = incident.category == "disaster" ? disasters_path : general_incidents_path
    incident.set(deleted_at: Time.current, deleted_by: current_user.username)
    redirect_to redirect_path, notice: "ลบข้อมูลเหตุการณ์ออกจากหน้าระบบแล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to general_incidents_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def add_progress
    incident = find_incident
    progress = params.require(:progress).permit(:status, :title, :description, :assigned_to, usages: %i[key quantity])
    previous_status = incident.status
    catalog = IncidentUsageCatalog.for(current_user).index_by { |item| item[:key] }
    requested_usages = Array(progress[:usages]).each_with_object(Hash.new(0)) do |usage, totals|
      totals[usage[:key]] += usage[:quantity].to_i if usage[:key].present?
    end
    usages = requested_usages.filter_map do |key, quantity|
      item = catalog[key]
      next if item.blank? || quantity <= 0

      if quantity > item[:available]
        return redirect_to incident_page_path(incident, incident_id: incident.id), alert: "จำนวนที่ใช้ของ #{item[:name]} มากกว่าจำนวนพร้อมใช้ #{item[:available]} #{item[:unit]}"
      end

      { "catalog_key" => key, "kind" => item[:kind], "name" => item[:name], "quantity" => quantity, "unit" => item[:unit],
        "agency_name" => item[:agency_name], "team_name" => item[:team_name],
        "remaining" => item[:available] - quantity }
    end

    usages.select { |usage| usage["kind"] == "consumable" }.each do |usage|
      source_item = catalog.fetch(usage["catalog_key"])
      dataset = ImportedDataset.visible_to(current_user).find(source_item[:dataset_id])
      ConsumableStockMovementService.new(dataset: dataset, record_position: source_item[:record_position],
        movement_type: "issue", quantity: usage["quantity"], user: current_user,
        incident_reference: incident.reference_code,
        note: "ใช้ในเหตุการณ์ #{incident.title}").call
    end
    incident.status = progress[:status] if Incident::STATUSES.include?(progress[:status])
    incident.assigned_to = progress[:assigned_to] if progress[:assigned_to].present?
    incident.histories << {
      "title" => progress[:title].presence || "อัปเดตการทำงาน",
      "description" => progress[:description],
      "occurred_at" => Time.current.utc.iso8601,
      "actor" => current_user.username,
      "resources" => usages
    }
    incident.active_assignments = Array(incident.active_assignments)
    if incident.status == "completed" && previous_status != "completed"
      released_at = Time.current.utc.iso8601
      incident.active_assignments = incident.active_assignments.map { |assignment| assignment.merge("released_at" => assignment["released_at"].presence || released_at) }
      incident.histories << {
        "title" => "ดำเนินการเสร็จสิ้นแล้ว",
        "description" => "เจ้าหน้าที่ดำเนินงานเสร็จสิ้น",
        "occurred_at" => Time.current.utc.iso8601,
        "actor" => current_user.username,
        "resources" => []
      }
    end
    accumulated_resources = Array(incident.resources_used).map(&:deep_dup)
    usages.each do |usage|
      source_item = catalog[usage["catalog_key"]]
      incident.active_assignments << {
        "key" => source_item[:key], "kind" => source_item[:kind], "name" => source_item[:name],
        "record_code" => source_item[:record_code], "agency_code" => source_item[:agency_code],
        "agency_name" => source_item[:agency_name], "team_code" => source_item[:team_code],
        "team_name" => source_item[:team_name], "assigned_at" => Time.current.utc.iso8601,
        "released_at" => (Time.current.utc.iso8601 if incident.status == "completed")
      } if source_item && source_item[:kind] != "consumable"
    end
    usages.each do |usage|
      existing = accumulated_resources.find do |item|
        same_kind = item["kind"].to_s == usage["kind"].to_s || (item["kind"].blank? && usage["kind"] == "resource")
        item["name"].to_s == usage["name"] && item["unit"].to_s == usage["unit"] && same_kind
      end
      if existing
        existing["kind"] = usage["kind"]
        existing["quantity"] = existing["quantity"].to_i + usage["quantity"].to_i
        existing["remaining"] = usage["remaining"] if usage["kind"] == "consumable"
        existing["note"] = progress[:title].presence || "อัปเดตการทำงาน"
      else
        accumulated_resources << usage.merge("note" => progress[:title].presence || "อัปเดตการทำงาน")
      end
    end
    incident.resources_used = accumulated_resources
    incident.save!
    redirect_to incident_page_path(incident, incident_id: incident.id), notice: "อัปเดตการทำงานเรียบร้อยแล้ว"
  rescue ArgumentError, Mongoid::Errors::Validations => error
    redirect_to incident_page_path(incident, incident_id: incident.id), alert: error.message
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to general_incidents_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def assess
    incident = find_incident
    assessment = params.require(:assessment).permit(:title, :area_sq_km, :affected_people, :affected_households, :budget, :resource_lines, :activate)
    next_version = incident.response_plan_versions.map { |item| item["version"].to_i }.max.to_i + 1
    resources = assessment[:resource_lines].to_s.lines.filter_map do |line|
      name, required, available, unit = line.strip.split("|").map(&:strip)
      next if name.blank?

      { "name" => name, "required" => required.to_f, "available" => available.to_f, "unit" => unit.presence || "รายการ" }
    end
    assessed_at = Time.current.utc.iso8601
    assessment_title = assessment[:title].presence || "ประเมินสถานการณ์ครั้งที่ #{next_version}"
    incident.response_plan_versions << {
      "version" => next_version,
      "title" => assessment_title,
      "area_sq_km" => assessment[:area_sq_km].to_f,
      "affected_people" => assessment[:affected_people].to_i,
      "affected_households" => assessment[:affected_households].to_i,
      "budget" => assessment[:budget].to_i,
      "assessed_at" => assessed_at,
      "resources" => resources
    }
    incident.histories << {
      "title" => "ประเมินสถานการณ์ Version #{next_version}",
      "description" => "#{assessment_title} · พื้นที่ #{assessment[:area_sq_km].to_f.round(3)} ตร.กม. · ประชากร #{assessment[:affected_people].to_i} คน · #{assessment[:affected_households].to_i} ครัวเรือน",
      "occurred_at" => assessed_at,
      "actor" => current_user.username,
      "resources" => []
    }
    incident.active_plan_version = next_version if assessment[:activate] == "1"
    incident.status = "assessing" if incident.status == "pending"
    incident.save!
    redirect_to disasters_path(incident_id: incident.id, plan_version: next_version), notice: "บันทึกผลประเมิน Version #{next_version} แล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def acknowledge
    incident = Incident.visible_to(current_user).find(params[:id])
    return redirect_to incident_page_path(incident, incident_id: incident.id), notice: "เหตุการณ์นี้ถูกรับเรื่องแล้ว" unless incident.status == "pending"

    assigned_team_code = params.require(:incident).require(:assigned_team_code)
    assigned_to = team_name_for(assigned_team_code)

    incident.histories << {
      "title" => "รับเรื่องแล้ว",
      "description" => "เจ้าหน้าที่รับเรื่องและเริ่มดำเนินการแล้ว",
      "occurred_at" => Time.current.utc.iso8601,
      "actor" => current_user.username,
      "resources" => []
    }
    incident.status = "in_progress"
    incident.assigned_to = assigned_to
    incident.assigned_team_code = assigned_team_code
    incident.received_by = current_user.username
    incident.received_by_user_id = current_user.id
    incident.received_at = Time.current
    incident.save!

    redirect_to incident_page_path(incident, incident_id: incident.id), notice: "รับเรื่องเรียบร้อยแล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def activate_plan
    incident = Incident.visible_to(current_user).find(params[:id])
    version_number = params.require(:version).to_i
    unless incident.response_plan_versions.any? { |version| version["version"].to_i == version_number }
      return redirect_to disasters_path(incident_id: incident.id), alert: "ไม่พบ Version แผนรับมือที่เลือก"
    end

    incident.update!(active_plan_version: version_number)
    redirect_to disasters_path(incident_id: incident.id, plan_version: version_number), notice: "เลือกใช้แผนรับมือ Version #{version_number} แล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def promote_to_disaster
    incident = find_incident
    unless current_user.system_admin? || current_user.subdistrict_admin?
      return redirect_to general_incidents_path(incident_id: incident.id), alert: "บัญชีนี้ไม่มีสิทธิ์เปิดเหตุการณ์ภัยพิบัติ"
    end
    return redirect_to disasters_path(incident_id: incident.id), notice: "เหตุการณ์นี้เป็นภัยพิบัติอยู่แล้ว" if incident.category == "disaster"
    unless %w[assessing in_progress].include?(incident.status)
      return redirect_to general_incidents_path(incident_id: incident.id), alert: "กรุณารับเรื่องก่อนเปิดเป็นภัยพิบัติ"
    end

    incident.category = "disaster"
    incident.histories << {
      "title" => "เปิดเป็นเหตุการณ์ภัยพิบัติ",
      "description" => "ผู้ดูแลระบบยกระดับเหตุการณ์ทั่วไปเป็นเหตุการณ์ภัยพิบัติ",
      "occurred_at" => Time.current.utc.iso8601,
      "actor" => current_user.username,
      "resources" => []
    }
    incident.save!
    redirect_to disasters_path(incident_id: incident.id), notice: "เปิดเหตุการณ์เป็นภัยพิบัติเรียบร้อยแล้ว สามารถประเมินสถานการณ์ได้"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to general_incidents_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  private

  def find_incident
    Incident.visible_to(current_user).find(params[:id])
  end

  def team_name_for(team_code)
    team_record = ImportedDataset.visible_to(current_user).where(data_type: "teams").flat_map do |dataset|
      Array(dataset.current_version&.records)
    end.find { |record| record["team_code"] == team_code }
    team_record&.dig("team_name") || team_code
  end

  def incident_attributes
    params.require(:incident).permit(
      :incident_type, :title, :description, :backdated, :occurred_at, :severity,
      :reporter_name, :reporter_contact, :location_name, :longitude, :latitude,
      :affected_people, :affected_households, :initial_impact, :assigned_to, :assigned_team_code
    )
  end

  def incident_page_path(incident, options = {})
    incident.category == "disaster" ? disasters_path(options) : general_incidents_path(options)
  end

  def incident_disaster_type(incident)
    value = "#{incident.incident_type} #{incident.title}".downcase
    return "flood" if value.match?(/น้ำ|ท่วม|flood/)
    return "fire" if value.match?(/ไฟ|hotspot|fire/)
    return "wind" if value.match?(/ลม|พายุ|wind|storm/)
    return "drought" if value.match?(/แล้ง|drought/)

    "other"
  end
end
