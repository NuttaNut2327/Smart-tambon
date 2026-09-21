require "digest"

class IncidentUsageCatalog
  def self.for(user)
    datasets = ImportedDataset.visible_to(user).where(:data_type.in => %w[resources workforce]).to_a
    items = datasets.flat_map do |dataset|
      Array(dataset.current_version&.records).filter_map do |record|
        if dataset.data_type == "workforce"
          name = record["team_name"].presence || record["name"].presence
          next if name.blank?

          catalog_item("workforce", name, "คน", record["ready_count"].to_i, dataset.name)
        else
          name = record["name"].presence
          next if name.blank?

          unit = record["unit"].presence || "รายการ"
          status = record["status"].to_s
          available = status.blank? || status.include?("พร้อม") || status.match?(/available|ready/i) ? 1 : 0
          catalog_item("resource", name, unit, available, dataset.name)
        end
      end
    end

    items.group_by { |item| [item[:kind], item[:name], item[:unit]] }.map do |(_, _, _), grouped|
      item = grouped.first
      item.merge(available: grouped.sum { |entry| entry[:available] }, sources: grouped.map { |entry| entry[:source] }.uniq)
    end.reject { |item| item[:available] <= 0 }.sort_by { |item| [item[:kind] == "workforce" ? 1 : 0, item[:name]] }
  end

  def self.catalog_item(kind, name, unit, available, source)
    normalized_name = name.to_s.strip
    normalized_unit = unit.to_s.strip
    {
      key: Digest::SHA256.hexdigest([kind, normalized_name, normalized_unit].join("\0"))[0, 20],
      kind: kind,
      name: normalized_name,
      unit: normalized_unit,
      available: [available.to_i, 0].max,
      source: source
    }
  end
  private_class_method :catalog_item
end
