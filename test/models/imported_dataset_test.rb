require "test_helper"

class ImportedDatasetTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "dataset_admin", email: "dataset_admin@example.test", password: "Password123!", role: :system_admin)
  end

  test "standard schemas are available for all system dataset types" do
    assert_equal %w[population resources workforce], ImportedDataset::STANDARD_SCHEMAS.keys
    ImportedDataset::STANDARD_SCHEMAS.each_value { |schema| assert schema.any? }
  end

  test "resource schema uses the defined asset register columns" do
    assert_equal %w[name code registration resource_type status storage_location responsible_person],
                 ImportedDataset.schema_for("resources").map { |field| field.fetch("key") }
  end

  test "workforce schema uses the defined team columns" do
    assert_equal %w[team_name duty member_count ready_count responsible_area team_leader],
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
