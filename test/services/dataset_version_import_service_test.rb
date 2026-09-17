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

  private

  def import(records)
    DatasetVersionImportService.new(dataset: @dataset, user: @user, manual_records: records).import!
  end
end
