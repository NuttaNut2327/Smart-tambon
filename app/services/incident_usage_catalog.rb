require "digest"

class IncidentUsageCatalog
  def self.rule_options_for(user, exclude_incident: nil)
    summaries = summary_for(user, exclude_incident: exclude_incident)
    labels = { "teams" => "ทีมปฏิบัติงาน", "resources" => "ทรัพยากรและอุปกรณ์", "consumables" => "วัสดุสิ้นเปลือง" }
    summaries.map do |item|
      { label: item[:name], source_type: item[:category], source_label: labels.fetch(item[:category]), unit: item[:unit],
        available: item[:available], ready: item[:ready], active: item[:active], unavailable: item[:unavailable], total: item[:total],
        agency_name: item[:agency_name] }
    end.sort_by { |item| [%w[teams resources consumables].index(item[:source_type]) || 9, item[:label]] }
  end

  def self.summary_for(user, exclude_incident: nil)
    items = all_items_for(user, exclude_incident: exclude_incident)
    non_people = items.reject { |item| %w[team workforce].include?(item[:kind]) }
    rows = non_people.group_by { |item| [summary_category(item[:kind]), item[:name], item[:unit]] }.map do |(category, name, unit), grouped|
      available = grouped.sum { |item| item[:available].to_f }
      total = category == "consumables" ? available : grouped.size
      ready = category == "consumables" ? available : grouped.count { |item| item[:state] == :ready }
      active = category == "consumables" ? 0 : grouped.count { |item| item[:state] == :active }
      unavailable = category == "consumables" ? grouped.count { |item| item[:state] == :unavailable } : grouped.count { |item| item[:state] == :unavailable }
      { category:, name:, unit:, available:, ready:, active:, unavailable:, total:,
        agency_name: grouped.filter_map { |item| item[:agency_name].presence }.uniq.join(", ") }
    end
    rows.concat(team_availability_for(user, exclude_incident: exclude_incident).map do |team|
      team.slice(:name, :unit, :available, :ready, :active, :unavailable, :total, :agency_name).merge(category: "teams")
    end)
    rows.sort_by { |item| [%w[teams resources consumables].index(item[:category]) || 9, item[:name]] }
  end

  def self.team_availability_for(user, exclude_incident: nil)
    datasets = ImportedDataset.visible_to(user).where(:data_type.in => %w[teams workforce]).to_a
    team_records = datasets.select { |dataset| dataset.data_type == "teams" }.flat_map do |dataset|
      Array(dataset.current_version&.records).map { |record| record.merge("_dataset_id" => dataset.id.to_s) }
    end
    active_incidents = active_incidents_for(user, exclude_incident: exclude_incident)
    assigned_keys = active_incidents.pluck(:active_assignments).flatten.compact
      .select { |assignment| assignment["released_at"].blank? }.map { |assignment| assignment["key"] }.to_set
    member_rows = datasets.select { |dataset| dataset.data_type == "workforce" }.flat_map do |dataset|
      Array(dataset.current_version&.records).filter_map.with_index do |record, position|
        if record["full_name"].blank?
          next unless record["team_name"].present?
          next({ team_code: record["team_code"].to_s.strip, team_name: record["team_name"].to_s.strip,
            ready: record["ready_count"].to_i, active: 0, unavailable: 0, total: record["ready_count"].to_i })
        end
        code = record["personnel_code"].presence || "#{dataset.id}-#{position}"
        key = Digest::SHA256.hexdigest(["workforce", dataset.id.to_s, code].join("\0"))[0, 20]
        member_team_code = record["team_code"].to_s.strip
        state = workforce_state(record, assigned: assigned_keys.include?(key))
        { team_code: member_team_code, team_name: record["team_name"].presence || "ยังไม่ระบุทีม",
          ready: state == :ready ? 1 : 0, active: state == :active ? 1 : 0, unavailable: state == :unavailable ? 1 : 0, total: 1 }
      end
    end
    known_team_keys = team_records.map { |team| [team["team_code"].to_s.strip, team["team_name"].to_s.strip] }.to_set
    team_records.map do |team|
      code = team["team_code"].to_s.strip
      name = team["team_name"].to_s.strip
      members = member_rows.select do |member|
        code.present? && member[:team_code].present? ? member[:team_code] == code : member[:team_name] == name
      end
      team_status_row(name:, code:, members:, agency_name: team["agency_name"])
    end.concat(member_rows.group_by { |member| [member[:team_code], member[:team_name]] }.filter_map do |(code, name), members|
      next if known_team_keys.include?([code, name]) || team_records.any? do |team|
        team_code = team["team_code"].to_s.strip
        team_name = team["team_name"].to_s.strip
        code.present? && team_code.present? ? team_code == code : team_name == name
      end
      team_status_row(name:, code:, members:, agency_name: nil)
    end).uniq { |team| [team[:code], team[:name]] }
  end

  def self.summary_category(kind)
    case kind.to_s
    when "team", "workforce" then "teams"
    when "consumable" then "consumables"
    else "resources"
    end
  end

  def self.for(user, exclude_incident: nil)
    all_items_for(user, exclude_incident: exclude_incident).reject { |item| item[:available] <= 0 }
      .sort_by { |item| [{ "resource" => 0, "team" => 1, "workforce" => 2, "consumable" => 3 }.fetch(item[:kind], 9), item[:name]] }
  end

  def self.all_items_for(user, exclude_incident: nil)
    datasets = ImportedDataset.visible_to(user).where(:data_type.in => %w[resources workforce consumables teams]).to_a
    active_incidents = active_incidents_for(user, exclude_incident: exclude_incident)
    assigned_keys = active_assignment_keys_for(user, exclude_incident: exclude_incident)
    assigned_team_codes = active_incidents.pluck(:assigned_team_code).compact.map { |code| code.to_s.strip }.reject(&:blank?).to_set
    assigned_team_names = active_incidents.pluck(:assigned_to).compact.map { |name| name.to_s.strip.downcase }.reject(&:blank?).to_set
    items = datasets.flat_map do |dataset|
      Array(dataset.current_version&.records).filter_map.with_index do |record, position|
        if dataset.data_type == "workforce"
          name = record["full_name"].presence
          if name.blank? && record["team_name"].present?
            next legacy_workforce_item(dataset, record)
          end
          next if name.blank?
          code = record["personnel_code"].presence || "#{dataset.id}-#{position}"
          key = Digest::SHA256.hexdigest(["workforce", dataset.id.to_s, code].join("\0"))[0, 20]
          state = workforce_state(record, assigned: assigned_keys.include?(key))
          catalog_item("workforce", name, "คน", state == :ready ? 1 : 0, dataset, code, position, record, assigned_keys, state:)
        elsif dataset.data_type == "teams"
          name = record["team_name"].presence
          next if name.blank?
          code = record["team_code"].presence || "#{dataset.id}-#{position}"
          ready = record["status"].to_s == "พร้อมปฏิบัติงาน"
          assigned = assigned_team_codes.include?(code.to_s.strip) || assigned_team_names.include?(name.to_s.strip.downcase)
          state = ready && !assigned ? :ready : assigned ? :active : :unavailable
          catalog_item("team", name, "ทีม", state == :ready ? 1 : 0, dataset, code, position, record, assigned_keys, state:)
        elsif dataset.data_type == "consumables"
          name = record["name"].presence
          next if name.blank?
          code = record["consumable_code"].presence || "#{dataset.id}-#{position}"
          quantity = record["current_quantity"].to_i
          catalog_item("consumable", name, record["unit"].presence || "หน่วย",
            quantity, dataset, code, position, record, assigned_keys, state: quantity.positive? ? :ready : :unavailable)
        else
          name = record["name"].presence
          next if name.blank?
          code = record["code"].presence || "#{dataset.id}-#{position}"
          unit = record["unit"].presence || "รายการ"
          status = record["status"].to_s.strip.downcase
          key = Digest::SHA256.hexdigest(["resource", dataset.id.to_s, code].join("\0"))[0, 20]
          state = if assigned_keys.include?(key) || %w[กำลังใช้งาน in_use assigned].include?(status)
            :active
          elsif %w[พร้อมใช้ พร้อมใช้งาน available ready].include?(status)
            :ready
          else
            :unavailable
          end
          catalog_item("resource", name, unit, state == :ready ? 1 : 0, dataset, code, position, record, assigned_keys, state:)
        end
      end
    end
    items
  end

  def self.active_incidents_for(user, exclude_incident: nil)
    scope = Incident.visible_to(user).where(:status.ne => "completed")
    exclude_incident ? scope.where(:id.ne => exclude_incident.id) : scope
  end

  def self.active_assignment_keys_for(user, exclude_incident: nil)
    active_incidents_for(user, exclude_incident: exclude_incident).pluck(:active_assignments).flatten.compact
      .select { |assignment| assignment["released_at"].blank? }.map { |assignment| assignment["key"] }.to_set
  end

  def self.workforce_state(record, assigned: false)
    return :unavailable if record["employment_status"].to_s == "พ้นสภาพ"
    availability = record["availability_status"].to_s
    return :unavailable if availability == "ไม่พร้อมปฏิบัติงาน"
    return :active if assigned || %w[กำลังปฏิบัติงาน ติดภารกิจ].include?(availability)
    availability == "พร้อมปฏิบัติงาน" ? :ready : :unavailable
  end

  def self.team_status_row(name:, code:, members:, agency_name:)
    ready = members.sum { |member| member[:ready] }
    active = members.sum { |member| member[:active] }
    unavailable = members.sum { |member| member[:unavailable] }
    { name: name.presence || "ยังไม่ระบุทีม", code:, unit: "คน", available: ready, ready:, active:, unavailable:,
      total: members.sum { |member| member[:total] }, agency_name: }
  end

  def self.catalog_item(kind, name, unit, available, dataset, record_code, position, record, assigned_keys, state: nil)
    normalized_name = name.to_s.strip
    normalized_unit = unit.to_s.strip
    key = Digest::SHA256.hexdigest([kind, dataset.id.to_s, record_code].join("\0"))[0, 20]
    {
      key: key,
      kind: kind,
      name: normalized_name,
      unit: normalized_unit,
      available: kind != "consumable" && assigned_keys.include?(key) ? 0 : [available.to_i, 0].max,
      state: state || (available.to_i.positive? ? :ready : :unavailable),
      source: dataset.name,
      dataset_id: dataset.id.to_s,
      record_position: position,
      record_code: record_code,
      agency_code: record["agency_code"],
      agency_name: record["agency_name"].presence || record["responsible_person"],
      team_code: record["team_code"],
      team_name: record["team_name"],
      display_name: "#{normalized_name} (#{record_code})"
    }
  end

  def self.legacy_workforce_item(dataset, record)
    name = record["team_name"]
    key = Digest::SHA256.hexdigest(["legacy-workforce", dataset.id.to_s, name].join("\0"))[0, 20]
    { key: key, kind: "workforce", name: name, unit: "คน", available: record["ready_count"].to_i,
      source: dataset.name, record_code: name, agency_code: nil, agency_name: nil, team_code: nil, team_name: name }
  end
  private_class_method :catalog_item, :legacy_workforce_item, :summary_category, :all_items_for,
    :active_incidents_for, :active_assignment_keys_for, :workforce_state, :team_status_row
end
