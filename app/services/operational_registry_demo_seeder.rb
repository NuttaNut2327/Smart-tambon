class OperationalRegistryDemoSeeder
  AGENCIES = [
    { "agency_code" => "AG-001", "agency_name" => "องค์การบริหารส่วนตำบลป่ากลาง", "agency_type" => "องค์กรปกครองส่วนท้องถิ่น" },
    { "agency_code" => "AG-002", "agency_name" => "โรงพยาบาลส่งเสริมสุขภาพตำบลป่ากลาง", "agency_type" => "สาธารณสุข" },
    { "agency_code" => "AG-003", "agency_name" => "กองช่าง อบต.ป่ากลาง", "agency_type" => "งานช่างและสาธารณูปโภค" }
  ].freeze

  TEAM_AGENCIES = {
    "ทีมสาธารณสุข" => "AG-002",
    "ทีมช่างและไฟฟ้า" => "AG-003"
  }.freeze

  def initialize(user:)
    @user = user
    @datasets = ImportedDataset.where(user_id: user.id).to_a
  end

  def run!
    agencies = seed_agencies!
    teams = seed_teams!(agencies)
    seed_personnel!(agencies, teams)
    seed_resources!(agencies)
    { agencies: agencies.size, teams: teams.size,
      personnel: workforce_datasets.sum(&:record_count), resources: resource_datasets.sum(&:record_count) }
  end

  private

  def seed_agencies!
    dataset = @datasets.find { |item| item.data_type == "agencies" } || create_dataset("agencies")
    existing = Array(dataset.current_version&.records)
    template = existing.first || {}
    records = AGENCIES.map.with_index do |agency, index|
      prior = existing.find { |record| record["agency_code"] == agency["agency_code"] }
      next prior if prior

      agency.merge(
        "contact_person" => index.zero? ? "เจ้าหน้าที่ประสานงานกลาง" : nil,
        "phone" => nil, "email" => nil,
        "address" => template["address"].presence || "ต.ป่ากลาง อ.ปัว จ.น่าน 55120",
        "road" => template["road"], "subdistrict" => template["subdistrict"].presence || "ป่ากลาง",
        "district" => template["district"].presence || "ปัว", "province" => template["province"].presence || "น่าน",
        "postcode" => template["postcode"].presence || "55120",
        "latitude" => template["latitude"], "longitude" => template["longitude"]
      )
    end.compact
    records += existing.reject { |record| records.any? { |item| item["agency_code"] == record["agency_code"] } }
    import(dataset, records, "เพิ่มหน่วยงานตัวอย่างสำหรับทะเบียนปฏิบัติการ")
    AGENCIES.index_by { |item| item["agency_code"] }
  end

  def seed_teams!(agencies)
    legacy_teams = workforce_datasets.flat_map { |dataset| Array(dataset.current_version&.records) }
      .filter_map { |record| record.slice("team_name", "duty", "responsible_area", "team_leader") if record["team_name"].present? }
      .uniq { |record| record["team_name"] }
    legacy_teams = [{ "team_name" => "ทีมกู้ภัย ชุด A", "duty" => "กู้ชีพและอพยพ", "responsible_area" => "ทุกหมู่บ้าน", "team_leader" => "หัวหน้าทีมตัวอย่าง" }] if legacy_teams.empty?
    records = legacy_teams.map.with_index(1) do |record, index|
      agency_code = TEAM_AGENCIES.fetch(record["team_name"], "AG-001")
      { "team_code" => format("TEAM-%03d", index), "team_name" => record["team_name"],
        "agency_code" => agency_code, "agency_name" => agencies.fetch(agency_code)["agency_name"],
        "team_type" => record["duty"].presence || "ทีมสนับสนุน", "leader_name" => record["team_leader"],
        "responsible_area" => record["responsible_area"], "status" => "พร้อมปฏิบัติงาน" }
    end
    dataset = @datasets.find { |item| item.data_type == "teams" } || create_dataset("teams")
    import(dataset, records, "สร้างทะเบียนทีมปฏิบัติงานจากข้อมูลเดิม")
    records.index_by { |record| record["team_name"] }
  end

  def seed_personnel!(agencies, teams)
    sequence = 0
    workforce_datasets.each do |dataset|
      source = Array(dataset.current_version&.records)
      next if source.any? { |record| record["personnel_code"].present? }

      records = source.flat_map do |record|
        member_count = [record["member_count"].to_i, 1].max
        ready_count = [record["ready_count"].to_i, member_count].min
        team = teams[record["team_name"]] || teams.values.first
        agency = agencies.fetch(team["agency_code"])
        Array.new(member_count) do |index|
          sequence += 1
          { "personnel_code" => format("PER-%04d", sequence),
            "full_name" => index.zero? && record["team_leader"].present? ? record["team_leader"] : "บุคลากรตัวอย่าง #{format('%03d', sequence)}",
            "position" => index.zero? ? "หัวหน้าทีม" : record["duty"].presence || "เจ้าหน้าที่",
            "skills" => record["duty"], "agency_code" => agency["agency_code"], "agency_name" => agency["agency_name"],
            "team_code" => team["team_code"], "team_name" => team["team_name"],
            "employment_status" => "ปฏิบัติงาน",
            "availability_status" => index < ready_count ? "พร้อมปฏิบัติงาน" : "ไม่พร้อมปฏิบัติงาน", "phone" => nil }
        end
      end
      import(dataset, records, "แปลงข้อมูลกำลังคนแบบยอดรวมเป็นทะเบียนรายบุคคล")
    end
  end

  def seed_resources!(agencies)
    resource_datasets.each do |dataset|
      used_codes = Hash.new(0)
      records = Array(dataset.current_version&.records).map.with_index(1) do |record, index|
        base_code = record["code"].presence || format("RES-%04d", index)
        used_codes[base_code] += 1
        code = used_codes[base_code] == 1 ? base_code : "#{base_code}-#{used_codes[base_code]}"
        agency_code = if record["responsible_person"].to_s.include?("สาธารณสุข") || record["name"].to_s.include?("พยาบาล")
                        "AG-002"
                      elsif record["responsible_person"].to_s.include?("ช่าง") || record["name"].to_s.include?("สูบน้ำ")
                        "AG-003"
                      else
                        "AG-001"
                      end
        record.merge("code" => code, "status" => normalize_resource_status(record["status"]),
          "agency_code" => agency_code, "responsible_person" => agencies.fetch(agency_code)["agency_name"])
      end
      import(dataset, records, "เชื่อมทรัพยากรรายชิ้นกับหน่วยงานและแก้รหัสซ้ำ")
    end
  end

  def normalize_resource_status(value)
    %w[พร้อมใช้ กำลังใช้งาน ซ่อมบำรุง ชำรุด ปลดระวาง].include?(value) ? value : "พร้อมใช้"
  end

  def workforce_datasets = @datasets.select { |dataset| dataset.data_type == "workforce" }
  def resource_datasets = @datasets.select { |dataset| dataset.data_type == "resources" }

  def create_dataset(data_type)
    dataset = ImportedDataset.create!(user: @user, subdistrict: @user.subdistrict,
      name: ImportedDataset::TYPE_LABELS.fetch(data_type), data_type: data_type, geometry_type: "none",
      schema_definition: ImportedDataset.schema_for(data_type), map_enabled: false, shared_with_all: true)
    @datasets << dataset
    dataset
  end

  def import(dataset, records, note)
    DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: records,
      source_kind: "manual", change_note: note).import!
  end
end
