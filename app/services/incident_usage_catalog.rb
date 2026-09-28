require "digest"

class IncidentUsageCatalog
  def self.rule_options_for(user)
    type_config = {
      "resources" => { label: "ทรัพยากร", default_unit: "รายการ" },
      "consumables" => { label: "วัสดุสิ้นเปลือง", default_unit: "หน่วย" },
      "teams" => { label: "ทีมปฏิบัติงาน", default_unit: "ทีม" }
    }
    rows = ImportedDataset.visible_to(user).where(:data_type.in => type_config.keys).flat_map do |dataset|
      Array(dataset.current_version&.records).filter_map do |record|
        name = dataset.data_type == "teams" ? record["team_name"].presence : record["name"].presence
        next if name.blank?

        config = type_config.fetch(dataset.data_type)
        unit = dataset.data_type == "consumables" ? record["unit"].presence || config[:default_unit] : config[:default_unit]
        available = case dataset.data_type
        when "consumables" then [record["current_quantity"].to_f, 0].max
        when "teams" then record["status"].to_s == "พร้อมปฏิบัติงาน" ? 1 : 0
        else %w[พร้อมใช้ พร้อมใช้งาน available ready].include?(record["status"].to_s.strip.downcase) ? 1 : 0
        end
        { label: name.to_s.strip, source_type: dataset.data_type, source_label: config[:label], unit: unit.to_s.strip,
          available: available, agency_name: record["agency_name"].presence || record["responsible_person"].presence }
      end
    end
    rows.group_by { |item| [item[:source_type], item[:label], item[:unit]] }.map do |(_, label, unit), items|
      { label: label, source_type: items.first[:source_type], source_label: items.first[:source_label], unit: unit,
        available: items.sum { |item| item[:available] }, agency_name: items.filter_map { |item| item[:agency_name] }.uniq.join(", ") }
    end.sort_by { |item| [%w[resources consumables teams].index(item[:source_type]) || 9, item[:label]] }
  end

  def self.summary_for(user)
    self.for(user).group_by { |item| [item[:name], item[:unit]] }.map do |(name, unit), items|
      { name: name, unit: unit, available: items.sum { |item| item[:available].to_f } }
    end.sort_by { |item| item[:name] }
  end

  def self.for(user)
    datasets = ImportedDataset.visible_to(user).where(:data_type.in => %w[resources workforce consumables]).to_a
    assigned_keys = Incident.visible_to(user).where(:status.ne => "completed").pluck(:active_assignments).flatten.compact
      .select { |assignment| assignment["released_at"].blank? }.map { |assignment| assignment["key"] }.to_set
    items = datasets.flat_map do |dataset|
      Array(dataset.current_version&.records).filter_map.with_index do |record, position|
        if dataset.data_type == "workforce"
          name = record["full_name"].presence
          if name.blank? && record["team_name"].present?
            next legacy_workforce_item(dataset, record)
          end
          next if name.blank?
          code = record["personnel_code"].presence || "#{dataset.id}-#{position}"
          ready = record["employment_status"].to_s != "พ้นสภาพ" && record["availability_status"].to_s == "พร้อมปฏิบัติงาน"
          catalog_item("workforce", name, "คน", ready ? 1 : 0, dataset, code, position, record, assigned_keys)
        elsif dataset.data_type == "consumables"
          name = record["name"].presence
          next if name.blank?
          code = record["consumable_code"].presence || "#{dataset.id}-#{position}"
          catalog_item("consumable", name, record["unit"].presence || "หน่วย",
            record["current_quantity"].to_i, dataset, code, position, record, assigned_keys)
        else
          name = record["name"].presence
          next if name.blank?
          code = record["code"].presence || "#{dataset.id}-#{position}"
          unit = record["unit"].presence || "รายการ"
          status = record["status"].to_s
          available = status.blank? || status.include?("พร้อม") || status.match?(/available|ready/i) ? 1 : 0
          catalog_item("resource", name, unit, available, dataset, code, position, record, assigned_keys)
        end
      end
    end
    kind_order = { "resource" => 0, "workforce" => 1, "consumable" => 2 }
    items.reject { |item| item[:available] <= 0 }.sort_by { |item| [kind_order.fetch(item[:kind], 9), item[:name]] }
  end

  def self.catalog_item(kind, name, unit, available, dataset, record_code, position, record, assigned_keys)
    normalized_name = name.to_s.strip
    normalized_unit = unit.to_s.strip
    key = Digest::SHA256.hexdigest([kind, dataset.id.to_s, record_code].join("\0"))[0, 20]
    {
      key: key,
      kind: kind,
      name: normalized_name,
      unit: normalized_unit,
      available: kind != "consumable" && assigned_keys.include?(key) ? 0 : [available.to_i, 0].max,
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
  private_class_method :catalog_item, :legacy_workforce_item
end
