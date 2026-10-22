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
    assert_equal "ข้อมูลประชากร #{Time.zone.today.strftime('%d-%m-%Y')}", dataset.current_version.display_name
    assert_not dataset.map_enabled?
    assert_not DatasetImportDraft.exists?(draft_id)

    Tempfile.create(["population-more", ".csv"]) do |file|
      file.write("ตำบล,หมู่ที่,หมู่บ้าน,ชาย,หญิง,ทั้งหมด,ครัวเรือน\nตำบลทดสอบ,2,บ้านถัดไป,4,6,10,5\n")
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "population-more.csv")
      post dataset_import_drafts_path, params: { data_type: "population", file: upload }, as: :multipart
    end
    assert_response :success, response.body
    append_draft_id = response.parsed_body.fetch("id")
    post validate_dataset_import_draft_path(append_draft_id), params: { mapping: mapping }
    assert_response :success, response.body
    post finalize_dataset_import_draft_path(append_draft_id), params: { import_mode: "insert" }
    assert_response :success, response.body

    assert_equal 2, dataset.reload.current_version.version_number
    assert_equal ["บ้านทดสอบ", "บ้านถัดไป"], dataset.current_version.records.map { |record| record["village_name"] }
  end

  test "manual entry appends a record to the current manual working version" do
    dataset = ImportedDataset.create!(user: @user, name: "ประชากรเดิม", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)
    DatasetVersionImportService.new(dataset: dataset, user: @user,
      manual_records: [{ subdistrict: "ตำบลทดสอบ", village_number: 1, village_name: "บ้านหนึ่ง", population_male: 2, population_female: 2,
                         population_total: 4, household_count: 2 }]).import!

    post manual_dataset_import_drafts_path, params: { data_type: "population",
      record: { subdistrict: "ตำบลทดสอบ", village_number: 2, village_name: "บ้านสอง", population_male: 3, population_female: 3,
                population_total: 6, household_count: 3 } }
    assert_response :success, response.body
    assert_equal 1, dataset.reload.current_version.version_number
    assert_equal 1, dataset.versions.count
    assert_equal ["บ้านหนึ่ง", "บ้านสอง"], dataset.current_version.records.map { |record| record["village_name"] }
  end

  test "data layers renders the fixed table and both import dialogs" do
    get data_layers_path(data_type: "resources")
    assert_response :success
    assert_select "table.fixed-data-table"
    assert_select "#manual-data-dialog" do
      assert_select "[name='import_mode']", count: 0
      assert_select ".automatic-destination-note", text: /เพิ่มรายการนี้ในรุ่นข้อมูลที่กรอกด้วยตนเองล่าสุด/
    end
    assert_select "#file-import-dialog[data-selected-type='resources']" do
      assert_select "[data-import-agency]", count: 1
      assert_select "[name='import_mode'][value='insert'][checked]", count: 1
      assert_select "[name='import_mode'][value='upsert']", count: 1
      assert_select "[name='import_mode'][value='replace']", count: 1
      assert_select "[data-replace-warning]", text: /ข้อมูล.*เชื่อมโยง/
      assert_select "[name='version_name'][value='ข้อมูลทรัพยากรและอุปกรณ์ #{Time.zone.today.strftime('%d-%m-%Y')}']", count: 1
    end
    assert_select "[name='target_dataset_id']", count: 0
    assert_select ".automatic-destination-note", text: /รุ่นข้อมูลใหม่/
    assert_select ".mapping-guidance", text: /ไม่บังคับ.*ไม่จับคู่.*เว้นค่าว่าง/
  end

  test "does not show the CCTV import navigation item" do
    get data_layers_path(data_type: "resources")

    assert_response :success
    assert_select ".dataset-type-nav a[href*='data_type=cctv_devices']", count: 0
  end

  test "places status columns immediately before the updated timestamp" do
    %w[resources workforce teams population].each do |data_type|
      get data_layers_path(data_type: data_type)
      assert_response :success
      headings = css_select("table.fixed-data-table thead th").map { |heading| heading.text.strip }
      updated_index = headings.index("อัปเดตล่าสุด")
      status_indexes = headings.each_index.select { |index| headings[index].include?("สถานะ") || headings[index] == "ความพร้อมปฏิบัติงาน" }
      assert status_indexes.any?, "expected #{data_type} to have a status column"
      assert_equal (status_indexes.min..status_indexes.max).to_a, status_indexes
      assert_equal updated_index - 1, status_indexes.max
    end
  end

  test "workforce file import requires agency and team selections" do
    get data_layers_path(data_type: "workforce")

    assert_response :success
    assert_select "#file-import-dialog" do
      assert_select "[data-import-agency]", count: 1
      assert_select "[data-import-team]", count: 1
    end
  end

  test "team file import injects the selected agency instead of requiring agency columns" do
    agency_dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("agencies"), shared_with_all: true)
    DatasetVersionImportService.new(dataset: agency_dataset, user: @user, manual_records: [
      { agency_code: "AG-001", agency_name: "อบต.ทดสอบ", agency_type: "ท้องถิ่น" }
    ]).import!

    Tempfile.create(["teams", ".csv"]) do |file|
      file.write("ชื่อทีม,ประเภททีม,สถานะทีม\nทีมกู้ภัย,กู้ภัย,พร้อมปฏิบัติงาน\n")
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "teams.csv")
      post dataset_import_drafts_path, params: { data_type: "teams", agency_code: "AG-001", file: upload }, as: :multipart
    end

    assert_response :success, response.body
    draft = response.parsed_body
    assert_equal "AG-001", draft.dig("import_context", "agency_code")
    assert_not_includes draft.fetch("schema").map { |field| field.fetch("key") }, "agency_code"
    assert_not_includes draft.fetch("schema").map { |field| field.fetch("key") }, "agency_name"
  end

  test "agency replace mode displays the stronger relationship warning" do
    get data_layers_path(data_type: "agencies")

    assert_response :success
    assert_select "#file-import-dialog [data-replace-warning]", text: /ทีม.*บุคลากร.*ทรัพยากร.*วัสดุสิ้นเปลือง/
  end

  test "agency import does not expose the generated approximate address for mapping" do
    Tempfile.create(["agencies", ".csv"]) do |file|
      file.write("ชื่อหน่วยงาน,ประเภทหน่วยงาน,ถนน,ตำบล,อำเภอ,จังหวัด,รหัสไปรษณีย์\nอบต.ทดสอบ,ท้องถิ่น,ถนนหลัก,ทดสอบ,เมือง,น่าน,55000\n")
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "agencies.csv")
      post dataset_import_drafts_path, params: { data_type: "agencies", file: upload }, as: :multipart
    end

    assert_response :success, response.body
    assert_not_includes response.parsed_body.fetch("schema").map { |field| field.fetch("key") }, "address"
  end

  test "downloads a real Excel template with importable headers" do
    get dataset_template_path("agencies")

    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.media_type
    assert_match(/agencies_template\.xlsx/, response.headers.fetch("Content-Disposition"))
    Tempfile.create(["agencies-template", ".xlsx"]) do |file|
      file.binmode
      file.write(response.body)
      file.flush
      sheet = Roo::Spreadsheet.open(file.path).sheet(0)
      assert_equal ["ชื่อหน่วยงาน", "ประเภทหน่วยงาน"], sheet.row(1).first(2)
      assert_not_includes sheet.row(1), "ที่อยู่โดยประมาณ"
    end
  end

  test "team edit dialog selects an agency from a dropdown" do
    get data_layers_path(data_type: "teams")

    assert_response :success
    assert_select "#edit-population-form select[name='record[agency_name]'][data-edit-agency-select]"
    assert_select "#edit-population-form input[type='hidden'][name='record[agency_code]']"
  end

  test "workforce edit dialog selects an agency and team from dropdowns" do
    get data_layers_path(data_type: "workforce")

    assert_response :success
    assert_select "#edit-population-form select[name='record[agency_name]'][data-edit-agency-select]"
    assert_select "#edit-population-form select[name='record[team_name]'][data-edit-team-select]"
    assert_select "#edit-population-form input[type='hidden'][name='record[agency_code]']"
    assert_select "#edit-population-form input[type='hidden'][name='record[team_code]']"
  end

  test "resource edit dialog exposes the responsible agency and agency code fields" do
    get data_layers_path(data_type: "resources")

    assert_response :success
    assert_select "#edit-population-form input[name='record[responsible_person]'][data-edit-field='responsible_person']"
    assert_select "#edit-population-form input[type='hidden'][name='record[agency_code]']"
  end

  test "consumable edit dialog exposes the agency and agency code fields" do
    get data_layers_path(data_type: "consumables")

    assert_response :success
    assert_select "#edit-population-form input[name='record[agency_name]'][data-edit-field='agency_name']"
    assert_select "#edit-population-form input[type='hidden'][name='record[agency_code]']"
  end

  test "village boundary data page has a back link to population data" do
    get data_layers_path(data_type: "village_boundaries")

    assert_response :success
    assert_select "a.boundary-back-link[href='#{data_layers_path(data_type: "population")}']", text: /กลับไปข้อมูลประชากร/
  end

  test "audit page hides legacy add and delete artifacts from the same edit" do
    dataset = ImportedDataset.create!(user: @user, name: "หน่วยงาน", data_type: "agencies", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("agencies"), shared_with_all: true)
    record = { agency_name: "อบต.ทดสอบ", agency_type: "ท้องถิ่น", latitude: 13.7, longitude: 100.5 }
    version = DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [record]).import!
    DatasetChangeLog.where(imported_dataset_id: dataset.id).delete_all
    timestamp = Time.zone.now.change(usec: 100_000)
    common = { imported_dataset_id: dataset.id, imported_dataset_version_id: version.id, user_id: @user.id,
               source_kind: "manual", note: "แก้ไขหน่วยงาน" }
    DatasetChangeLog.create!(common.merge(action: "update", record_id: "agency-1", record_label: "อบต.ทดสอบ",
      before_data: { "phone" => "" }, after_data: { "phone" => "0812345678" }, changed_fields: ["phone"], created_at: timestamp))
    DatasetChangeLog.create!(common.merge(action: "add", record_id: "legacy-new", record_label: "กองช่าง",
      after_data: { "agency_name" => "กองช่าง" }, changed_fields: ["agency_name"], created_at: timestamp + 0.2.seconds))
    DatasetChangeLog.create!(common.merge(action: "delete", record_id: "legacy-old", record_label: "กองช่าง",
      before_data: { "agency_name" => "กองช่าง" }, changed_fields: ["agency_name"], created_at: timestamp + 0.3.seconds))

    get data_layers_path(data_type: "agencies")

    assert_response :success
    assert_select ".dataset-audit-table tbody > tr:not(.dataset-audit-detail-row)", count: 1
    assert_select ".audit-action.update", text: "แก้ไข", count: 1
  end

  test "renames one population version without changing its dataset or records" do
    dataset = ImportedDataset.create!(user: @user, name: "ข้อมูลประชากร", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)
    version = DatasetVersionImportService.new(dataset: dataset, user: @user,
      manual_records: [{ subdistrict: "ตำบลทดสอบ", village_number: 1, village_name: "บ้านหนึ่ง", population_male: 2,
                         population_female: 3, population_total: 5, household_count: 2 }]).import!

    patch imported_dataset_version_path(dataset, version),
      params: { imported_dataset_version: { display_name: "ข้อมูลประชากรเดือนตุลาคม 2569" } }

    assert_redirected_to data_layers_path(data_type: "population")
    assert_equal "ข้อมูลประชากรเดือนตุลาคม 2569", version.reload.display_name
    assert_equal "ข้อมูลประชากร", dataset.reload.name
    assert_equal 1, dataset.versions.count
    assert_equal 5, version.records.first["population_total"]
  end

  test "shows the records stored in a historical version without activating it" do
    dataset = ImportedDataset.create!(user: @user, name: "ข้อมูลประชากร", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)
    first_record = { subdistrict: "ตำบลทดสอบ", village_number: 1, village_name: "บ้าน Version แรก",
                     population_male: 2, population_female: 3, population_total: 5, household_count: 2 }
    second_record = first_record.merge(village_name: "บ้าน Version ใหม่", population_total: 6)
    first_version = DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [first_record],
      source_kind: "file", display_name: "ข้อมูลประชากร Version แรก").import!
    second_version = DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [second_record],
      source_kind: "file", display_name: "ข้อมูลประชากร Version ใหม่").import!

    get imported_dataset_version_path(dataset, first_version)

    assert_response :success
    assert_select ".version-snapshot-header h1", text: "ข้อมูลประชากร Version แรก"
    assert_select ".version-snapshot-meta", text: /รุ่นข้อมูลย้อนหลัง/
    assert_select ".version-snapshot-table", text: /บ้าน Version แรก/
    assert_select ".version-snapshot-table", text: /บ้าน Version ใหม่/, count: 0
    assert_equal second_version.id, dataset.reload.current_version_id

    get imported_dataset_version_path(dataset, first_version), params: { paginated: "1", page: 1 }, as: :json
    assert_response :success
    assert_equal "ข้อมูลประชากร Version แรก", response.parsed_body["display_name"]
    assert_equal 1, response.parsed_body.dig("pagination", "total")
    assert_equal "บ้าน Version แรก", response.parsed_body.dig("records", 0, "village_name")
  end

  test "does not rename the standard population dataset" do
    dataset = ImportedDataset.create!(user: @user, name: "ข้อมูลประชากร", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)

    patch imported_dataset_path(dataset), params: { imported_dataset: { name: "ชื่อที่ไม่ควรถูกบันทึก" } }

    assert_redirected_to data_layers_path(data_type: "population")
    assert_equal "ข้อมูลประชากร", dataset.reload.name
  end

  test "links the current population and village boundary versions without dropdown ids" do
    population = ImportedDataset.create!(user: @user, name: "ข้อมูลประชากร", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)
    boundary = ImportedDataset.create!(user: @user, name: "ขอบเขตหมู่บ้าน", data_type: "village_boundaries", geometry_type: "polygon",
      schema_definition: ImportedDataset.schema_for("village_boundaries"), shared_with_all: true, map_enabled: true)
    population_record = { subdistrict: "ตำบลทดสอบ", village_code: "V001", village_number: 1, village_name: "บ้านหนึ่ง",
                          population_male: 2, population_female: 3, population_total: 5, household_count: 2 }
    boundary_record = { subdistrict: "ตำบลทดสอบ", village_code: "V001", village_number: 1, village_name: "บ้านหนึ่ง",
                        geometry: { type: "Polygon", coordinates: [[[100.0, 13.0], [100.1, 13.0], [100.1, 13.1], [100.0, 13.0]]] }.to_json }
    DatasetVersionImportService.new(dataset: population, user: @user, manual_records: [population_record]).import!
    DatasetVersionImportService.new(dataset: boundary, user: @user, manual_records: [boundary_record]).import!
    assert_equal "needs_matching", population.reload.boundary_link_status

    get data_layers_path(data_type: "village_boundaries")
    assert_response :success
    assert_select ".boundary-link-form select", count: 0
    assert_select ".boundary-link-form", text: /จับคู่ข้อมูล/

    post link_village_boundaries_path

    assert_redirected_to data_layers_path(data_type: "village_boundaries")
    linked_record = population.reload.current_version.records.first
    assert_equal "เชื่อมแล้ว", linked_record["boundary_status"]
    assert_equal boundary.id.to_s, linked_record["boundary_dataset_id"]
    assert_equal boundary.current_version.records.first["record_id"], linked_record["boundary_record_id"]
    assert_equal "linked", population.reload.boundary_link_status
    assert_equal boundary.current_version_id, population.linked_boundary_version_id

    changed_boundary = boundary.current_version.records.first.merge("village_name" => "บ้านหนึ่งปรับปรุง")
    DatasetVersionImportService.new(dataset: boundary, user: @user, manual_records: [changed_boundary]).import!
    assert_equal "needs_matching", population.reload.boundary_link_status
  end

  test "edits and deletes a population row in the current manual working version" do
    dataset = ImportedDataset.create!(user: @user, name: "ประชากรแก้ไข", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)
    original = { subdistrict: "ตำบลทดสอบ", village_number: 1, village_name: "บ้านหนึ่ง", population_male: 2, population_female: 3,
                 population_total: 5, household_count: 2, boundary_status: "เชื่อมแล้ว",
                 boundary_dataset_id: BSON::ObjectId.new.to_s, boundary_record_id: "boundary-1", boundary_record_position: 0 }
    DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [original]).import!
    original_record_id = dataset.reload.current_version.records.first["record_id"]

    patch imported_dataset_record_path(dataset, 0), params: { record: original.merge(village_number: 2, population_total: 6) }
    assert_response :success, response.body
    assert_equal 1, dataset.reload.current_version.version_number
    assert_equal 2, dataset.current_version.records.first["village_number"]
    assert_equal 6, dataset.current_version.records.first["population_total"]
    assert_equal original_record_id, dataset.current_version.records.first["record_id"]
    assert_equal "ยังไม่เชื่อมขอบเขต", dataset.current_version.records.first["boundary_status"]
    assert_nil dataset.current_version.records.first["boundary_record_id"]
    assert_equal "needs_matching", dataset.boundary_link_status
    update_log = DatasetChangeLog.where(imported_dataset_id: dataset.id, action: "update").first
    assert_equal %w[population_total village_number], update_log.changed_fields.sort

    delete imported_dataset_record_path(dataset, 0)
    assert_response :success, response.body
    assert_equal 1, dataset.reload.current_version.version_number
    assert_empty dataset.current_version.records
    assert_equal 1, dataset.versions.count
    assert_equal 3, dataset.current_version.change_history.size
    assert_equal %w[add update delete], DatasetChangeLog.where(imported_dataset_id: dataset.id).asc(:created_at).pluck(:action)
  end

  test "rejects changing a population row into a duplicate village" do
    dataset = ImportedDataset.create!(user: @user, name: "ประชากรซ้ำ", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)
    first = { subdistrict: "ตำบลทดสอบ", village_number: 1, village_name: "บ้านหนึ่ง", population_male: 2,
              population_female: 3, population_total: 5, household_count: 2 }
    second = first.merge(village_number: 2, village_name: "บ้านสอง")
    DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [first, second]).import!

    patch imported_dataset_record_path(dataset, 0), params: { record: first.merge(village_number: 2, village_name: "บ้านสอง") }

    assert_response :unprocessable_entity
    assert_match(/มีข้อมูลหมู่บ้านนี้อยู่แล้ว/, response.parsed_body["error"])
    assert_equal [1, 2], dataset.reload.current_version.records.map { |record| record["village_number"] }
  end

  test "creates an immutable checkpoint from the current manual version" do
    dataset = ImportedDataset.create!(user: @user, name: "ข้อมูลประชากร", data_type: "population", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("population"), shared_with_all: true)
    record = { subdistrict: "ตำบลทดสอบ", village_number: 1, village_name: "บ้านหนึ่ง", population_male: 2,
               population_female: 3, population_total: 5, household_count: 2 }
    manual = DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [record]).import!

    post checkpoint_imported_dataset_versions_path(dataset)

    assert_redirected_to data_layers_path(data_type: "population")
    checkpoint = dataset.reload.current_version
    assert_equal 2, checkpoint.version_number
    assert_equal "checkpoint", checkpoint.source_kind
    assert_equal manual.records, checkpoint.records
    assert_equal "checkpoint", DatasetChangeLog.where(imported_dataset_id: dataset.id).desc(:created_at).first.action
  end

  test "edits a resource row in the current manual working version" do
    dataset = ImportedDataset.create!(user: @user, name: "ทรัพยากร", data_type: "resources", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("resources"), shared_with_all: true)
    record = { name: "เครื่องสูบน้ำ", code: "P-01", registration: "กข-123", resource_type: "เครื่องสูบน้ำ",
               status: "พร้อมใช้", storage_location: "คลังกลาง", responsible_person: "อบต.ทดสอบ",
               agency_code: "AG-001" }
    DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [record]).import!

    patch imported_dataset_record_path(dataset, 0), params: { record: record.merge(status: "ซ่อมบำรุง") }
    assert_response :success, response.body
    assert_equal 1, dataset.reload.current_version.version_number
    assert_equal "ซ่อมบำรุง", dataset.current_version.records.first["status"]
  end

  test "editing a legacy row without a record id is logged as one update" do
    dataset = ImportedDataset.create!(user: @user, name: "ทรัพยากรเดิม", data_type: "resources", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("resources"), shared_with_all: true)
    record = { name: "เครื่องสูบน้ำเดิม", registration: "กข-123", resource_type: "เครื่องสูบน้ำ",
               status: "พร้อมใช้", storage_location: "คลังกลาง", responsible_person: "อบต.ทดสอบ",
               agency_code: "AG-001" }
    another_record = record.merge(name: "รถบรรทุกน้ำ", registration: "กข-456")
    DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [record, another_record]).import!
    dataset.current_version.record_documents.each do |document|
      document.set(payload: document.payload.except("record_id", "code"))
    end
    DatasetChangeLog.where(imported_dataset_id: dataset.id).delete_all

    patch imported_dataset_record_path(dataset, 0), params: { record: record.merge(name: "เครื่องสูบน้ำใหม่") }

    assert_response :success
    assert_equal "เครื่องสูบน้ำใหม่", dataset.reload.current_version.records.first["name"]
    assert dataset.current_version.records.all? { |item| item["record_id"].present? }
    assert_equal ["update"], DatasetChangeLog.where(imported_dataset_id: dataset.id).pluck(:action)
  end

  test "edits a workforce row in the current manual working version" do
    dataset = ImportedDataset.create!(user: @user, name: "ทีมงาน", data_type: "workforce", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("workforce"), shared_with_all: true)
    record = { full_name: "สมหญิง ทดสอบ", position: "เจ้าหน้าที่กู้ภัย", skills: "ช่วยเหลือฉุกเฉิน",
               agency_code: "AG-001", agency_name: "อบต.ทดสอบ", team_code: "TEAM-001",
               team_name: "ทีมกู้ภัย", employment_status: "ปฏิบัติงาน",
               availability_status: "พร้อมปฏิบัติงาน", phone: "0812345678" }
    DatasetVersionImportService.new(dataset: dataset, user: @user, manual_records: [record]).import!

    patch imported_dataset_record_path(dataset, 0), params: { record: record.merge(availability_status: "กำลังปฏิบัติงาน") }
    assert_response :success, response.body
    assert_equal 1, dataset.reload.current_version.version_number
    assert_equal "กำลังปฏิบัติงาน", dataset.current_version.records.first["availability_status"]
  end
end
