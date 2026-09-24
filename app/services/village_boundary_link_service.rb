class VillageBoundaryLinkService
  def initialize(population_dataset:, boundary_dataset:, user:)
    @population_dataset = population_dataset
    @boundary_dataset = boundary_dataset
    @user = user
  end

  def link!
    populations = Array(@population_dataset.current_version&.records).map(&:deep_dup)
    boundaries = Array(@boundary_dataset.current_version&.records)
    raise ArgumentError, "ชุดข้อมูลประชากรยังไม่มีข้อมูล" if populations.empty?
    raise ArgumentError, "ชุดข้อมูลขอบเขตหมู่บ้านยังไม่มีข้อมูล" if boundaries.empty?

    exact_code = index_unique(boundaries) { |record| normalized_code(record["village_code"]) }
    exact_area = index_unique(boundaries) { |record| area_key(record) }
    exact_name = index_unique(boundaries) { |record| name_key(record) }
    counts = { matched: 0, suggested: 0, unmatched: 0 }

    populations.each do |record|
      match = exact_code[normalized_code(record["village_code"])] || exact_area[area_key(record)]
      if match
        attach(record, match)
        counts[:matched] += 1
      elsif exact_name[name_key(record)]
        record["boundary_status"] = "รอตรวจสอบ"
        counts[:suggested] += 1
      else
        record["boundary_status"] = "ยังไม่เชื่อมขอบเขต"
        record.delete("boundary_dataset_id")
        record.delete("boundary_record_position")
        counts[:unmatched] += 1
      end
    end

    DatasetVersionImportService.new(dataset: @population_dataset, user: @user, manual_records: populations,
      source_kind: "manual", change_note: "เชื่อมข้อมูลกับ #{@boundary_dataset.name}").import!
    counts
  end

  private

  def index_unique(records)
    grouped = records.each_with_index.group_by { |record, _position| yield(record) }.reject { |key, _| key.blank? }
    grouped.filter_map { |key, values| [key, values.first] if values.one? }.to_h
  end

  def attach(record, match)
    _boundary_record, position = match
    record["boundary_status"] = "เชื่อมแล้ว"
    record["boundary_dataset_id"] = @boundary_dataset.id.to_s
    record["boundary_record_position"] = position
  end

  def normalized_code(value) = value.to_s.strip.downcase.presence

  def area_key(record)
    subdistrict = normalized_code(record["subdistrict_code"]).presence || normalize_name(record["subdistrict"])
    village_number = record["village_number"].to_s.gsub(/\D/, "").presence
    [subdistrict, village_number].join(":") if subdistrict && village_number
  end

  def name_key(record)
    subdistrict = normalize_name(record["subdistrict"])
    village = normalize_name(record["village_name"])
    [subdistrict, village].join(":") if subdistrict && village
  end

  def normalize_name(value)
    value.to_s.downcase.gsub(/\s+/, "").gsub(/^(ตำบล|ต\.|หมู่บ้าน|บ้าน)/, "").presence
  end
end
