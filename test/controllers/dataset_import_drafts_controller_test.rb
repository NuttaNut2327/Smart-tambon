require "test_helper"
require "tempfile"

class DatasetImportDraftsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "draft_admin", email: "draft_admin@example.test", password: "Password123!", role: :system_admin)
    sign_in @user
  end

  test "uploads maps previews and finalizes a csv as version one" do
    Tempfile.create(["population", ".csv"]) do |file|
      file.write("ตำบล,หมู่ที่,หมู่บ้าน,ชาย,หญิง,ทั้งหมด,ครัวเรือน\nตำบลทดสอบ,1,บ้านทดสอบ,3,5,8,4\n")
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "population.csv")
      post dataset_import_drafts_path, params: { data_type: "population", file: upload }, as: :multipart
    end
    assert_response :success, response.body
    draft_id = response.parsed_body.fetch("id")

    mapping = { subdistrict: "ตำบล", village_number: "หมู่ที่", village_name: "หมู่บ้าน", population_male: "ชาย", population_female: "หญิง",
                population_total: "ทั้งหมด", household_count: "ครัวเรือน" }
    post validate_dataset_import_draft_path(draft_id), params: { mapping: mapping }
    assert_response :success, response.body
    assert_equal 1, response.parsed_body.dig("validation", "valid")

    post finalize_dataset_import_draft_path(draft_id), params: { dataset_name: "ประชากรทดสอบ" }
    assert_response :success, response.body
    dataset = ImportedDataset.find(response.parsed_body.fetch("dataset_id"))
    assert_equal 1, dataset.current_version.version_number
    assert_equal "ตำบลทดสอบ", dataset.current_version.records.first["subdistrict"]
    assert_equal 1, dataset.current_version.records.first["village_number"]
    assert_equal "บ้านทดสอบ", dataset.current_version.records.first["village_name"]
    assert_equal "population.csv", dataset.current_version.source_filename
    assert_not dataset.map_enabled?
    assert_not DatasetImportDraft.exists?(draft_id)
  end

  test "manual entry appends a record and creates a new version" do
    dataset = ImportedDataset.create!(user: @user, name: "ประชากรเดิม", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)
    DatasetVersionImportService.new(dataset: dataset, user: @user,
      manual_records: [{ subdistrict: "ตำบลทดสอบ", village_number: 1, village_name: "บ้านหนึ่ง", population_male: 2, population_female: 2,
                         population_total: 4, household_count: 2 }]).import!

    post manual_dataset_import_drafts_path, params: { data_type: "population", target_dataset_id: dataset.id,
      record: { subdistrict: "ตำบลทดสอบ", village_number: 2, village_name: "บ้านสอง", population_male: 3, population_female: 3,
                population_total: 6, household_count: 3 } }
    assert_response :success, response.body
    assert_equal 2, dataset.reload.current_version.version_number
    assert_equal ["บ้านหนึ่ง", "บ้านสอง"], dataset.current_version.records.map { |record| record["village_name"] }
  end

  test "data layers renders the fixed table and both import dialogs" do
    get data_layers_path(data_type: "resources")
    assert_response :success
    assert_select "table.fixed-data-table"
    assert_select "#manual-data-dialog"
    assert_select "#file-import-dialog[data-selected-type='resources']"
  end

  test "edits and deletes a population row by creating new versions" do
    dataset = ImportedDataset.create!(user: @user, name: "ประชากรแก้ไข", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)
    original = { subdistrict: "ตำบลทดสอบ", village_number: 1, village_name: "บ้านหนึ่ง", population_male: 2, population_female: 3,
                 population_total: 5, household_count: 2 }
    DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [original]).import!

    patch imported_dataset_record_path(dataset, 0), params: { record: original.merge(population_total: 6) }
    assert_response :success, response.body
    assert_equal 2, dataset.reload.current_version.version_number
    assert_equal 6, dataset.current_version.records.first["population_total"]

    delete imported_dataset_record_path(dataset, 0)
    assert_response :success, response.body
    assert_equal 3, dataset.reload.current_version.version_number
    assert_empty dataset.current_version.records
    assert_equal 1, dataset.versions.find_by(version_number: 1).record_count
  end

  test "edits a resource row by creating a new version" do
    dataset = ImportedDataset.create!(user: @user, name: "ทรัพยากร", data_type: "resources", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("resources"), shared_with_all: true)
    record = { name: "เครื่องสูบน้ำ", code: "P-01", registration: "กข-123", resource_type: "เครื่องสูบน้ำ",
               status: "พร้อมใช้", storage_location: "คลังกลาง", responsible_person: "สมชาย" }
    DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [record]).import!

    patch imported_dataset_record_path(dataset, 0), params: { record: record.merge(status: "ซ่อมบำรุง") }
    assert_response :success, response.body
    assert_equal 2, dataset.reload.current_version.version_number
    assert_equal "ซ่อมบำรุง", dataset.current_version.records.first["status"]
  end

  test "edits a workforce row by creating a new version" do
    dataset = ImportedDataset.create!(user: @user, name: "ทีมงาน", data_type: "workforce", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("workforce"), shared_with_all: true)
    record = { team_name: "ทีมกู้ภัย", duty: "ช่วยเหลือฉุกเฉิน", member_count: 12, ready_count: 10,
               responsible_area: "หมู่ 1-3", team_leader: "สมหญิง" }
    DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [record]).import!

    patch imported_dataset_record_path(dataset, 0), params: { record: record.merge(ready_count: 11) }
    assert_response :success, response.body
    assert_equal 2, dataset.reload.current_version.version_number
    assert_equal 11, dataset.current_version.records.first["ready_count"]
  end
end
