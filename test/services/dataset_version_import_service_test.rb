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

  test "creates immutable sequential versions and updates current version" do
    first = import([{ "name" => "จุด A", "latitude" => "13.7", "longitude" => "100.5" }])
    second = import([{ "name" => "จุด B", "latitude" => "13.8", "longitude" => "100.6" }])
    assert_equal 1, first.version_number
    assert_equal 2, second.version_number
    assert_equal second, @dataset.reload.current_version
    assert_equal "จุด A", first.reload.records.first["name"]
  end

  test "rejects invalid coordinates" do
    error = assert_raises(ArgumentError) { import([{ "name" => "ผิด", "latitude" => "999", "longitude" => "100" }]) }
    assert_match "พิกัดไม่ถูกต้อง", error.message
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

  def import(records)
    DatasetVersionImportService.new(dataset: @dataset, user: @user, manual_records: records).import!
  end
end
