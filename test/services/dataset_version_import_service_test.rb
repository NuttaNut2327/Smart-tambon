require "test_helper"
require "minitest/mock"

class DatasetVersionImportServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "version_admin", email: "version_admin@example.test", password: "Password123!", role: :system_admin)
    @dataset = ImportedDataset.create!(user: @user, name: "จุดช่วยเหลือ", data_type: "custom",
      geometry_type: "point", map_enabled: true, schema_definition: [
        { "key" => "name", "label" => "ชื่อ", "type" => "text", "required" => true },
        { "key" => "latitude", "label" => "ละติจูด", "type" => "number", "required" => true },
        { "key" => "longitude", "label" => "ลองจิจูด", "type" => "number", "required" => true }
      ])
  end

  test "reuses the current manual working version" do
    first = import([{ "name" => "จุด A", "latitude" => "13.7", "longitude" => "100.5" }], change_note: "เพิ่มจุด A")
    second = import(first.records + [{ "name" => "จุด B", "latitude" => "13.8", "longitude" => "100.6" }], change_note: "เพิ่มจุด B")
    assert_equal 1, first.version_number
    assert_equal 1, second.version_number
    assert_equal first.id, second.id
    assert_equal 1, @dataset.versions.count
    assert_equal second, @dataset.reload.current_version
    assert_equal ["จุด A", "จุด B"], second.records.map { |record| record["name"] }
    assert_equal ["เพิ่มจุด A", "เพิ่มจุด B"], second.change_history.map { |entry| entry["note"] }
    assert_equal "จุดช่วยเหลือ", second.display_name
    assert second.records.all? { |record| record["record_id"].present? }
    logs = DatasetChangeLog.where(imported_dataset_id: @dataset.id).asc(:created_at).to_a
    assert_equal %w[add add], logs.map(&:action)
    assert_equal "จุด B", logs.last.record_label
  end

  test "consumable stock movement is recorded only in movement history" do
    dataset = ImportedDataset.create!(user: @user, name: "วัสดุสิ้นเปลือง", data_type: "consumables",
      geometry_type: "none", schema_definition: ImportedDataset.schema_for("consumables"), shared_with_all: true)
    record = { name: "ถุงยังชีพ", category: "บรรเทาสาธารณภัย", unit: "ถุง", agency_code: "AG-1",
               agency_name: "อบต.ทดสอบ", current_quantity: 10, minimum_quantity: 2 }
    version = DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [record]).import!
    record_id = version.records.first["record_id"]
    DatasetChangeLog.where(imported_dataset_id: dataset.id).delete_all

    result = ConsumableStockMovementService.new(dataset: dataset, record_position: 0, movement_type: "receive",
      quantity: 5, user: @user).call

    assert_equal 15, result.quantity_after
    assert_equal record_id, dataset.reload.current_version.records.first["record_id"]
    assert_equal 15, dataset.current_version.records.first["current_quantity"]
    assert_equal 1, ConsumableMovement.where(imported_dataset_id: dataset.id).count
    assert_empty DatasetChangeLog.where(imported_dataset_id: dataset.id)
  end

  test "upsert updates a matching resource and keeps unrelated records" do
    dataset = ImportedDataset.create!(user: @user, name: "ทรัพยากร", data_type: "resources", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("resources"), shared_with_all: true)
    base = { resource_type: "เครื่องมือ", status: "พร้อมใช้", responsible_person: "อบต.ทดสอบ", agency_code: "AG-001" }
    first = DatasetVersionImportService.new(dataset: dataset, user: @user,
      manual_records: [base.merge(name: "เครื่องสูบน้ำ"), base.merge(name: "รถดับเพลิง")]).import!
    pump = first.records.find { |record| record["name"] == "เครื่องสูบน้ำ" }

    result = DatasetVersionImportService.new(dataset: dataset, user: @user, source_kind: "file", import_mode: "upsert",
      manual_records: [base.merge(name: "เครื่องสูบน้ำ", status: "ซ่อมบำรุง")]).import!

    assert_equal 2, result.records.size
    updated = result.records.find { |record| record["name"] == "เครื่องสูบน้ำ" }
    assert_equal "ซ่อมบำรุง", updated["status"]
    assert_equal pump["code"], updated["code"]
    assert_equal pump["record_id"], updated["record_id"]
    assert result.records.any? { |record| record["name"] == "รถดับเพลิง" }
  end

  test "normalizes the legacy busy team status when importing" do
    dataset = ImportedDataset.create!(user: @user, name: "ทีมปฏิบัติงาน", data_type: "teams", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("teams"), shared_with_all: true)
    version = DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [{
      team_name: "ทีมกู้ภัย", agency_code: "AG-001", agency_name: "อบต.ทดสอบ",
      team_type: "กู้ภัย", status: "ติดภารกิจ"
    }]).import!

    assert_equal "กำลังปฏิบัติงาน", version.records.first["status"]
  end

  test "normalizes the legacy workforce availability status when importing" do
    dataset = ImportedDataset.create!(user: @user, name: "บุคลากร", data_type: "workforce", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("workforce"), shared_with_all: true)
    version = DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [{
      full_name: "สมชาย ทดสอบ", position: "เจ้าหน้าที่", agency_code: "AG-001", agency_name: "อบต.ทดสอบ",
      team_code: "TEAM-001", team_name: "ทีมกู้ภัย", employment_status: "ปฏิบัติงาน",
      availability_status: "ติดภารกิจ"
    }]).import!

    assert_equal "กำลังปฏิบัติงาน", version.records.first["availability_status"]
  end

  test "creates a new file version and then one new manual working version" do
    first = import([{ "name" => "จุด A", "latitude" => "13.7", "longitude" => "100.5" }])
    file_version = import([{ "name" => "จุดจากไฟล์", "latitude" => "13.75", "longitude" => "100.55" }], source_kind: "file")
    manual_version = import(file_version.records + [{ "name" => "จุดเพิ่มเอง", "latitude" => "13.8", "longitude" => "100.6" }])
    same_manual_version = import(manual_version.records + [{ "name" => "จุดเพิ่มอีก", "latitude" => "13.9", "longitude" => "100.7" }])

    assert_equal 1, first.version_number
    assert_equal 2, file_version.version_number
    assert_equal 3, manual_version.version_number
    assert_equal manual_version.id, same_manual_version.id
    assert_equal 3, @dataset.versions.count
    assert_equal 3, same_manual_version.records.size
    assert_equal "จุดจากไฟล์", file_version.reload.records.first["name"]
  end

  test "creates a separate snapshot for every file import" do
    first_file = import([{ "name" => "ไฟล์ชุดแรก", "latitude" => "13.7", "longitude" => "100.5" }], source_kind: "file")
    second_file = import([{ "name" => "ไฟล์ชุดใหม่", "latitude" => "13.8", "longitude" => "100.6" }], source_kind: "file")

    assert_equal 1, first_file.version_number
    assert_equal 2, second_file.version_number
    assert_not_equal first_file.id, second_file.id
    assert_equal 2, @dataset.versions.count
    assert_equal "ไฟล์ชุดแรก", first_file.reload.records.first["name"]
    assert_equal "ไฟล์ชุดใหม่", second_file.reload.records.first["name"]
  end

  test "uses an editable display name or a dataset name with the current date for a new version" do
    custom_name = DatasetVersionImportService.new(dataset: @dataset, user: @user, source_kind: "file",
      display_name: "จุดช่วยเหลือรอบพิเศษ", manual_records: [
        { "name" => "จุด A", "latitude" => "13.7", "longitude" => "100.5" }
      ]).import!
    automatic_name = import([{ "name" => "จุด B", "latitude" => "13.8", "longitude" => "100.6" }], source_kind: "file")

    assert_equal "จุดช่วยเหลือรอบพิเศษ", custom_name.display_name
    assert_equal "จุดช่วยเหลือ #{Time.zone.today.strftime('%d-%m-%Y')}", automatic_name.display_name
  end

  test "carries the previous version name unchanged into a new manual working version" do
    population = ImportedDataset.create!(user: @user, name: "ข้อมูลประชากร 15-09-2026", data_type: "population",
      geometry_type: "none", map_enabled: false, schema_definition: ImportedDataset.schema_for("population"))
    record = { "subdistrict" => "ตำบลทดสอบ", "village_number" => 1, "village_name" => "บ้านหนึ่ง",
               "population_male" => 2, "population_female" => 3, "population_total" => 5, "household_count" => 2 }
    file_version = DatasetVersionImportService.new(dataset: population, user: @user, source_kind: "file",
      display_name: "ข้อมูลประชากรเดือนตุลาคม", manual_records: [record]).import!
    manual_version = DatasetVersionImportService.new(dataset: population, user: @user, source_kind: "manual",
      manual_records: file_version.records).import!

    assert_equal "ข้อมูลประชากรเดือนตุลาคม", manual_version.display_name
    assert_equal file_version.display_name, manual_version.display_name
  end

  test "adds the date only to a file version name" do
    manual_dataset = ImportedDataset.create!(user: @user, name: "ข้อมูลเริ่มต้น", data_type: "custom",
      geometry_type: "none", map_enabled: false,
      schema_definition: [{ "key" => "name", "label" => "ชื่อ", "type" => "text", "required" => true }])
    manual = DatasetVersionImportService.new(dataset: manual_dataset, user: @user,
      manual_records: [{ "name" => "รายการแรก" }], source_kind: "manual").import!

    assert_equal "ข้อมูลเริ่มต้น", manual.display_name
  end

  test "replaces a previous file date with todays date when manual work starts" do
    population = ImportedDataset.create!(user: @user, name: "ข้อมูลประชากร", data_type: "population",
      geometry_type: "none", map_enabled: false, schema_definition: ImportedDataset.schema_for("population"))
    record = { "subdistrict" => "ตำบลทดสอบ", "village_number" => 1, "village_name" => "บ้านหนึ่ง",
               "population_male" => 2, "population_female" => 3, "population_total" => 5, "household_count" => 2 }
    yesterday = (Time.zone.today - 1.day).strftime("%d-%m-%Y")
    today = Time.zone.today.strftime("%d-%m-%Y")
    file_version = DatasetVersionImportService.new(dataset: population, user: @user, source_kind: "file",
      display_name: "ข้อมูลประชากร #{yesterday}", manual_records: [record]).import!
    manual_version = DatasetVersionImportService.new(dataset: population, user: @user, source_kind: "manual",
      manual_records: file_version.records).import!

    assert_equal "ข้อมูลประชากร #{today}", manual_version.display_name
    assert_not_includes manual_version.display_name, yesterday unless yesterday == today
  end

  test "keeps the same version name when its date is already today" do
    today = Time.zone.today.strftime("%d-%m-%Y")
    file_version = import([{ "name" => "จุด A", "latitude" => "13.7", "longitude" => "100.5" }],
      source_kind: "file", display_name: "จุดช่วยเหลือ #{today}")
    manual_version = import(file_version.records, source_kind: "manual")

    assert_equal file_version.display_name, manual_version.display_name
  end

  test "starts a new manual working version after a restored snapshot" do
    original = import([{ "name" => "จุดเดิม", "latitude" => "13.7", "longitude" => "100.5" }], source_kind: "file")
    restored = import(original.records.map(&:deep_dup), source_kind: "restored")
    manual = import(restored.records + [{ "name" => "จุดแก้เอง", "latitude" => "13.8", "longitude" => "100.6" }])
    updated_manual = import(manual.records + [{ "name" => "จุดแก้เพิ่ม", "latitude" => "13.9", "longitude" => "100.7" }])

    assert_equal [1, 2, 3], [original.version_number, restored.version_number, manual.version_number]
    assert_equal manual.id, updated_manual.id
    assert_equal 3, @dataset.versions.count
    assert_equal 1, restored.reload.records.size
    assert_equal 3, updated_manual.records.size
  end

  test "rejects invalid coordinates" do
    error = assert_raises(ArgumentError) { import([{ "name" => "ผิด", "latitude" => "999", "longitude" => "100" }]) }
    assert_match "พิกัดไม่ถูกต้อง", error.message
  end

  test "imports an agency without coordinates and builds its approximate address" do
    dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies",
      geometry_type: "point", map_enabled: true, schema_definition: ImportedDataset.schema_for("agencies"))

    version = DatasetVersionImportService.new(dataset: dataset, user: @user, source_kind: "file",
      manual_records: [{ "agency_name" => "โรงพยาบาลส่งเสริมสุขภาพตำบล", "agency_type" => "สาธารณสุข",
        "road" => "ถนนทดสอบ", "subdistrict" => "ป่ากลาง", "district" => "ปัว", "province" => "น่าน",
        "postcode" => "55120" }]).import!

    record = version.records.first
    assert_nil record["latitude"]
    assert_nil record["longitude"]
    assert_equal "ถนนทดสอบ ต.ป่ากลาง อ.ปัว จ.น่าน 55120", record["address"]
    assert_nil version.record_documents.first.location
  end

  test "imports an agency when address and coordinates are all blank" do
    dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies",
      geometry_type: "point", map_enabled: true, schema_definition: ImportedDataset.schema_for("agencies"))

    version = DatasetVersionImportService.new(dataset: dataset, user: @user, source_kind: "file",
      manual_records: [{ "agency_name" => "หน่วยงานไม่มีที่อยู่", "agency_type" => "อื่น ๆ" }]).import!

    assert_nil version.records.first["address"]
    assert_nil version.record_documents.first.location
  end

  test "fills agency address fields from coordinates" do
    dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies",
      geometry_type: "point", map_enabled: true, schema_definition: ImportedDataset.schema_for("agencies"))
    geocoded = { address: "12 ถนนทดสอบ ต.ป่ากลาง อ.ปัว จ.น่าน 55120", road: "ถนนทดสอบ",
      subdistrict: "ป่ากลาง", district: "ปัว", province: "น่าน", postcode: "55120" }

    ReverseGeocoder.stub(:call, geocoded) do
      version = DatasetVersionImportService.new(dataset: dataset, user: @user, source_kind: "file",
        manual_records: [{ "agency_name" => "หน่วยงานมีพิกัด", "agency_type" => "ราชการ",
          "latitude" => "19.15", "longitude" => "100.80" }]).import!
      record = version.records.first

      assert_equal "12 ถนนทดสอบ ต.ป่ากลาง อ.ปัว จ.น่าน 55120", record["address"]
      assert_equal "ถนนทดสอบ", record["road"]
      assert_equal "ป่ากลาง", record["subdistrict"]
      assert_equal "ปัว", record["district"]
      assert_equal "น่าน", record["province"]
      assert_equal "55120", record["postcode"]
      assert_equal [100.8, 19.15], version.record_documents.first.location
    end
  end

  test "rejects an agency with only one coordinate" do
    dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies",
      geometry_type: "point", map_enabled: true, schema_definition: ImportedDataset.schema_for("agencies"))

    error = assert_raises(ArgumentError) do
      DatasetVersionImportService.new(dataset: dataset, user: @user, source_kind: "file",
        manual_records: [{ "agency_name" => "พิกัดไม่ครบ", "agency_type" => "อื่น ๆ", "latitude" => "19.15" }]).import!
    end

    assert_match "ระบุละติจูดและลองจิจูดให้ครบ", error.message
  end

  test "preserves an existing agency code when an imported name matches" do
    dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies",
      geometry_type: "none", schema_definition: ImportedDataset.schema_for("agencies"))
    existing = [{ "agency_code" => "AG-001", "agency_name" => "องค์การบริหารส่วนตำบลป่ากลาง",
      "agency_type" => "ท้องถิ่น" }]

    version = DatasetVersionImportService.new(dataset: dataset, user: @user, source_kind: "file",
      registry_records: existing,
      manual_records: [{ "agency_name" => "อบต. ป่ากลาง", "agency_type" => "ท้องถิ่น" }]).import!

    assert_equal "AG-001", version.records.first["agency_code"]
  end

  test "generates a new agency code only when the imported name is new" do
    dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies",
      geometry_type: "none", schema_definition: ImportedDataset.schema_for("agencies"))

    version = DatasetVersionImportService.new(dataset: dataset, user: @user, source_kind: "file",
      registry_records: [{ "agency_code" => "AG-001", "agency_name" => "อบต.ป่ากลาง" }],
      manual_records: [{ "agency_name" => "สถานีตำรวจภูธรปัว", "agency_type" => "ราชการ" }]).import!

    assert_match(/\AAG-[0-9A-F]{6}\z/, version.records.first["agency_code"])
    assert_not_equal "AG-001", version.records.first["agency_code"]
  end

  test "requires an agency code when a name matches multiple existing agencies" do
    dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies",
      geometry_type: "none", schema_definition: ImportedDataset.schema_for("agencies"))
    existing = [
      { "agency_code" => "AG-001", "agency_name" => "อบต.ป่ากลาง" },
      { "agency_code" => "AG-002", "agency_name" => "องค์การบริหารส่วนตำบลป่ากลาง" }
    ]

    error = assert_raises(ArgumentError) do
      DatasetVersionImportService.new(dataset: dataset, user: @user, source_kind: "file",
        registry_records: existing,
        manual_records: [{ "agency_name" => "อบต. ป่ากลาง", "agency_type" => "ท้องถิ่น" }]).import!
    end

    assert_match "ตรงกับข้อมูลเดิมหลายรายการ", error.message
    assert_match "AG-001, AG-002", error.message
  end

  test "rejects duplicate agency codes in one import" do
    dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies",
      geometry_type: "none", schema_definition: ImportedDataset.schema_for("agencies"))

    error = assert_raises(ArgumentError) do
      DatasetVersionImportService.new(dataset: dataset, user: @user, source_kind: "file", manual_records: [
        { "agency_code" => "AG-001", "agency_name" => "หน่วยงานหนึ่ง", "agency_type" => "ราชการ" },
        { "agency_code" => "AG-001", "agency_name" => "หน่วยงานสอง", "agency_type" => "ราชการ" }
      ]).import!
    end

    assert_match "รหัสหน่วยงาน AG-001 ซ้ำในไฟล์", error.message
  end

  test "accepts comma thousands separators in numeric columns" do
    dataset = ImportedDataset.create!(user: @user, name: "ข้อมูลประชากร", data_type: "custom",
      geometry_type: "none", map_enabled: false, schema_definition: [
        { "key" => "population", "label" => "ประชากร", "type" => "integer", "required" => true },
        { "key" => "budget", "label" => "งบประมาณ", "type" => "number", "required" => true }
      ])

    version = DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [
      { "population" => "1,223", "budget" => "12,345.50" }
    ]).import!

    assert_equal 1_223, version.records.first["population"]
    assert_equal 12_345.5, version.records.first["budget"]
  end

  test "generates and preserves device tokens" do
    device = ImportedDataset.create!(user: @user, name: "กล้องวงจรปิด", data_type: "cctv_devices",
      geometry_type: "point", map_enabled: true,
      schema_definition: ImportedDataset.schema_for("cctv_devices"))
    first = DatasetVersionImportService.new(dataset: device, user: @user, manual_records: [
      { "sensor_id" => "CCTV-001", "latitude" => "13.7", "longitude" => "100.5" }
    ]).import!
    token = first.records.first["token"]

    second = DatasetVersionImportService.new(dataset: device, user: @user,
      manual_records: first.records.map(&:deep_dup)).import!

    assert token.present?
    assert_equal token, second.records.first["token"]
  end

  test "rejects duplicate sensor ids within a device dataset" do
    device = ImportedDataset.create!(user: @user, name: "PM 2.5", data_type: "pm25_sensors",
      geometry_type: "point", map_enabled: true,
      schema_definition: ImportedDataset.schema_for("pm25_sensors"))

    error = assert_raises(ArgumentError) do
      DatasetVersionImportService.new(dataset: device, user: @user, manual_records: [
        { "sensor_id" => "PM-001", "latitude" => "13.7", "longitude" => "100.5" },
        { "sensor_id" => "pm-001", "latitude" => "13.8", "longitude" => "100.6" }
      ]).import!
    end

    assert_match "Sensor ID ซ้ำ", error.message
  end

  private

  def import(records, source_kind: "manual", change_note: nil, display_name: nil)
    DatasetVersionImportService.new(dataset: @dataset, user: @user, manual_records: records,
      source_kind: source_kind, change_note: change_note, display_name: display_name).import!
  end
end
