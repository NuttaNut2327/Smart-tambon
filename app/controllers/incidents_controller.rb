class IncidentsController < ApplicationController
  def notification
    pending_incidents = Incident.visible_to(current_user).where(status: "pending").desc(:created_at)
    latest_incident = pending_incidents.first

    render json: {
      pending_count: pending_incidents.count,
      incident: latest_incident && {
        id: latest_incident.id.to_s,
        reference_code: latest_incident.reference_code,
        title: latest_incident.title,
        severity: latest_incident.severity,
        url: disasters_path(incident_id: latest_incident.id)
      }
    }
  end

  def assessment
    @incident = find_incident
    return redirect_to disasters_path(incident_id: @incident.id), alert: "การประเมินสถานการณ์ใช้สำหรับเหตุการณ์ภัยพิบัติเท่านั้น" unless @incident.category == "disaster"

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
    render :assessment
  end

  def calculate_assessment
    incident = params[:id].present? ? find_incident : nil
    return render json: { error: "การประเมินสถานการณ์ใช้สำหรับเหตุการณ์ภัยพิบัติเท่านั้น" }, status: :unprocessable_entity if incident && incident.category != "disaster"

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
      workforce = workforce_records.find { |record| record["team_name"].to_s.casecmp?(name.to_s) }
      available = if workforce
        workforce["ready_count"].to_i
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
    incident.user_id = current_user.id
    incident.subdistrict_id = current_user.subdistrict_id || params.dig(:incident, :subdistrict_id)
    if incident.subdistrict_id.blank?
      return redirect_to disasters_path, alert: "กรุณาเลือกบัญชีประจำพื้นที่ก่อนบันทึกเหตุการณ์"
    end
    if incident.category == "disaster" && !Incident::DISASTER_INCIDENT_TYPES.include?(incident.incident_type)
      return redirect_to disasters_path, alert: "กรุณาเลือกประเภทภัยจากรายการที่กำหนด"
    end

    incident.save!
    redirect_to disasters_path(incident_id: incident.id), notice: "บันทึกเหตุการณ์ใหม่เรียบร้อยแล้ว"
  rescue Mongoid::Errors::Validations => error
    redirect_to disasters_path, alert: error.document.errors.full_messages.join(" · ")
  end

  def update
    incident = find_incident
    incident.update!(incident_attributes)
    redirect_to disasters_path(incident_id: incident.id), notice: "แก้ไขข้อมูลเหตุการณ์เรียบร้อยแล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  rescue Mongoid::Errors::Validations => error
    redirect_to disasters_path(incident_id: params[:id]), alert: error.document.errors.full_messages.join(" · ")
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
        return redirect_to disasters_path(incident_id: incident.id), alert: "จำนวนที่ใช้ของ #{item[:name]} มากกว่าจำนวนพร้อมใช้ #{item[:available]} #{item[:unit]}"
      end

      { "kind" => item[:kind], "name" => item[:name], "quantity" => quantity, "unit" => item[:unit] }
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
    if incident.status == "completed" && previous_status != "completed"
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
      existing = accumulated_resources.find do |item|
        same_kind = item["kind"].to_s == usage["kind"].to_s || (item["kind"].blank? && usage["kind"] == "resource")
        item["name"].to_s == usage["name"] && item["unit"].to_s == usage["unit"] && same_kind
      end
      if existing
        existing["kind"] = usage["kind"]
        existing["quantity"] = existing["quantity"].to_i + usage["quantity"].to_i
        existing["note"] = progress[:title].presence || "อัปเดตการทำงาน"
      else
        accumulated_resources << usage.merge("note" => progress[:title].presence || "อัปเดตการทำงาน")
      end
    end
    incident.resources_used = accumulated_resources
    incident.save!
    redirect_to disasters_path(incident_id: incident.id), notice: "อัปเดตการทำงานเรียบร้อยแล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def assess
    incident = find_incident
    assessment = params.require(:assessment).permit(:title, :affected_people, :budget, :resource_lines, :activate)
    next_version = incident.response_plan_versions.map { |item| item["version"].to_i }.max.to_i + 1
    resources = assessment[:resource_lines].to_s.lines.filter_map do |line|
      name, required, available, unit = line.strip.split("|").map(&:strip)
      next if name.blank?

      { "name" => name, "required" => required.to_f, "available" => available.to_f, "unit" => unit.presence || "รายการ" }
    end
    incident.response_plan_versions << {
      "version" => next_version,
      "title" => assessment[:title].presence || "ประเมินสถานการณ์ครั้งที่ #{next_version}",
      "affected_people" => assessment[:affected_people].to_i,
      "budget" => assessment[:budget].to_i,
      "assessed_at" => Time.current.utc.iso8601,
      "resources" => resources
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
    return redirect_to disasters_path(incident_id: incident.id), notice: "เหตุการณ์นี้ถูกรับเรื่องแล้ว" unless incident.status == "pending"

    assigned_to = params.require(:incident).require(:assigned_to)

    incident.histories << {
      "title" => "รับเรื่องแล้ว",
      "description" => "เจ้าหน้าที่รับเรื่องและเริ่มดำเนินการแล้ว",
      "occurred_at" => Time.current.utc.iso8601,
      "actor" => current_user.username,
      "resources" => []
    }
    incident.status = "in_progress"
    incident.assigned_to = assigned_to
    incident.received_by = current_user.username
    incident.received_by_user_id = current_user.id
    incident.received_at = Time.current
    incident.save!

    redirect_to disasters_path(incident_id: incident.id), notice: "รับเรื่องเรียบร้อยแล้ว"
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

  private

  def find_incident
    Incident.visible_to(current_user).find(params[:id])
  end

  def incident_attributes
    params.require(:incident).permit(
      :category, :incident_type, :title, :description, :severity, :status,
      :reporter_name, :reporter_contact, :location_name, :longitude, :latitude,
      :affected_people, :affected_households, :initial_impact, :assigned_to
    )
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
