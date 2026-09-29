require "test_helper"

class ImportedDatasetTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "dataset_admin", email: "dataset_admin@example.test", password: "Password123!", role: :system_admin)
  end

  test "standard schemas are available for all system dataset types" do
    assert_equal %w[population village_boundaries resources consumables workforce teams agencies cctv_devices water_level_sensors pm25_sensors incidents], ImportedDataset::STANDARD_SCHEMAS.keys
    ImportedDataset::STANDARD_SCHEMAS.each_value { |schema| assert schema.any? }
  end

  test "device schemas contain static identity token and coordinates" do
    %w[cctv_devices water_level_sensors pm25_sensors].each do |type|
      schema = ImportedDataset.schema_for(type)
      assert_equal %w[sensor_id token latitude longitude], schema.map { |field| field.fetch("key") }
      assert schema.find { |field| field["key"] == "token" }.fetch("generated")
    end
  end

  test "consumable schema tracks stock and responsible agency" do
    assert_equal %w[consumable_code name category unit agency_code agency_name storage_location current_quantity minimum_quantity],
                 ImportedDataset.schema_for("consumables").map { |field| field.fetch("key") }
  end

  test "resource schema uses the defined asset register columns" do
    assert_equal %w[name code registration resource_type status responsible_person agency_code storage_location],
                 ImportedDataset.schema_for("resources").map { |field| field.fetch("key") }
  end

  test "workforce schema uses the defined team columns" do
    assert_equal %w[personnel_code full_name position skills agency_code agency_name team_code team_name employment_status availability_status phone],
                 ImportedDataset.schema_for("workforce").map { |field| field.fetch("key") }
  end

  test "map layer requires coordinates in schema" do
    dataset = ImportedDataset.new(user: @user, name: "ไม่มีพิกัด", data_type: "custom",
      geometry_type: "point", map_enabled: true,
      schema_definition: [{ "key" => "name", "label" => "ชื่อ", "type" => "text", "required" => true }])
    assert_not dataset.valid?
    assert_includes dataset.errors[:schema_definition], "ต้องมีคอลัมน์ latitude และ longitude"
  end
end
