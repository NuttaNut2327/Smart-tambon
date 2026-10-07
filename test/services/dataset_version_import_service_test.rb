require "test_helper"

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
