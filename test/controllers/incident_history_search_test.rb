require "test_helper"

class IncidentHistorySearchTest < ActionDispatch::IntegrationTest
  setup do
    Incident.where(title: /\Aประวัติทดสอบ/).delete_all
    ImportedDataset.where(name: "ทีมจำแนกหมวดทดสอบ").destroy_all
    @admin = User.create!(username: "history_admin", email: "history_admin@example.test", password: "Password123!", role: :system_admin)
    @old = Incident.create!(title: "ประวัติทดสอบ น้ำท่วมปีก่อน", category: "disaster", status: "completed", severity: "critical",
      longitude: 100.5, latitude: 14.0, backdated: true, occurred_at: Time.zone.local(2025, 10, 5, 9))
    @recent = Incident.create!(title: "ประวัติทดสอบ ดินถล่ม", category: "disaster", status: "in_progress", severity: "urgent",
      longitude: 100.6, latitude: 14.1)
    sign_in @admin
  end

  teardown do
    Incident.where(title: /\Aประวัติทดสอบ/).delete_all
    ImportedDataset.where(name: "ทีมจำแนกหมวดทดสอบ").destroy_all
    @admin&.destroy
  end

  test "filters the list and map to the event-time range, keeping the range in links" do
    get disasters_path(from: "2025-10-01", to: "2025-10-31")

    assert_response :success
    assert_select ".incident-list-card", text: /น้ำท่วมปีก่อน/
    assert_select ".incident-list-card", text: /ดินถล่ม/, count: 0
    assert_select ".incident-list-card[href*='from=2025-10-01'][href*='to=2025-10-31']"
    features = JSON.parse(css_select("[data-incident-history-map]").first["data-features"])
    assert_equal [@old.id.to_s], features.map { |feature| feature["id"] }
  end

  test "swaps a reversed range and shows a no-result message" do
    get disasters_path(from: "2024-02-01", to: "2024-01-01")

    assert_response :success
    assert_select "input[name=from][value='2024-01-01']"
    assert_select ".incident-empty h2", text: /ไม่พบภัยพิบัติในช่วงเวลานี้/
  end

  test "without a range the page lists everything and draws no results map" do
    get disasters_path

    assert_response :success
    assert_select ".incident-heading-side .disaster-future-plan-link", text: /แผนรับมือในอนาคต/
    assert_select ".incident-heading-side form.incident-history-form[action='#{disasters_path}']"
    assert_select "input[name=from][type=date]"
    assert_select "input[name=to][type=date]"
    assert_select "[data-incident-history-map]", count: 0
    assert_select ".incident-list-card", minimum: 2
  end

  test "an assessment stores its validated impact area for the history map" do
    area = { type: "Polygon", coordinates: [[[100.5, 14.0], [100.51, 14.0], [100.51, 14.01], [100.5, 14.01], [100.5, 14.0]]] }
    post incident_assessments_path(@old), params: { assessment: { title: "ประเมิน", area_sq_km: "1.2", area_geojson: area.to_json, activate: "1" } }
    assert_redirected_to disasters_path(incident_id: @old.id, plan_version: 1)
    assert_equal "Polygon", @old.reload.assessment_area_geojson["type"]

    post incident_assessments_path(@old), params: { assessment: { title: "ไม่มีพื้นที่", area_geojson: '{"type":"Point","coordinates":[1,2]}' } }
    assert_nil @old.reload.response_plan_versions.last["area_geojson"]
    assert_equal "Polygon", @old.assessment_area_geojson["type"], "falls back to the latest plan with an area"

    get disasters_path(from: "2025-10-01", to: "2025-10-31")
    features = JSON.parse(css_select("[data-incident-history-map]").first["data-features"])
    assert_equal "Polygon", features.first.dig("area", "type")
  end

  test "response plan separates personnel resources and consumables" do
    team_dataset = ImportedDataset.create!(user: @admin, name: "ทีมจำแนกหมวดทดสอบ", data_type: "teams", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("teams"), shared_with_all: true)
    DatasetVersionImportService.new(dataset: team_dataset, user: @admin, manual_records: [{
      team_name: "ทีมกู้ภัย", agency_code: "AG-001", agency_name: "อบต.ทดสอบ", team_type: "กู้ภัย", status: "กำลังปฏิบัติงาน"
    }]).import!
    @recent.update!(response_plan_versions: [{
      "version" => 1,
      "title" => "แผนแยกหมวด",
      "resources" => [
        { "category" => "resources", "name" => "ทีมกู้ภัย", "required" => 2, "available" => 0, "unit" => "คน" },
        { "category" => "resources", "name" => "เรือท้องแบน", "required" => 1, "available" => 1, "unit" => "ลำ" },
        { "category" => "consumables", "name" => "น้ำดื่ม", "required" => 100, "available" => 80, "unit" => "ขวด" }
      ]
    }])

    get disasters_path(incident_id: @recent.id, plan_version: 1)

    assert_response :success
    assert_select ".incident-plan-resource-section", count: 3
    assert_select ".incident-plan-resource-section h4", text: "บุคลากรที่ใช้"
    assert_select ".incident-plan-resource-section h4", text: "ทรัพยากรและอุปกรณ์ที่ใช้"
    assert_select ".incident-plan-resource-section h4", text: "วัสดุสิ้นเปลืองที่ใช้"
    assert_select ".incident-plan-resources td", text: "ทีมกู้ภัย"
    assert_select ".incident-plan-resources td", text: "เรือท้องแบน"
    assert_select ".incident-plan-resources td", text: "น้ำดื่ม"
    personnel_section = css_select(".incident-plan-resource-section").find { |section| section.at_css("h4")&.text == "บุคลากรที่ใช้" }
    resource_section = css_select(".incident-plan-resource-section").find { |section| section.at_css("h4")&.text == "ทรัพยากรและอุปกรณ์ที่ใช้" }
    assert_includes personnel_section.text, "ทีมกู้ภัย"
    refute_includes resource_section.text, "ทีมกู้ภัย"
  end
end
