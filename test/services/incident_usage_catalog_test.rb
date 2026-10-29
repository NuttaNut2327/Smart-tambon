require "test_helper"

class IncidentUsageCatalogTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "usage_catalog_admin", email: "usage_catalog_admin@example.test",
      password: "Password123!", role: :system_admin)
    @team_dataset = create_dataset("ทีมปฏิบัติงาน", "teams", [{
      team_code: "TEAM-001", team_name: "ทีมกู้ภัย ชุด A", agency_code: "AG-001", agency_name: "อบต.ทดสอบ",
      team_type: "กู้ภัย", status: "พร้อมปฏิบัติงาน"
    }])
    create_dataset("บุคลากรปฏิบัติงาน", "workforce", [
      workforce("P-001", "พร้อมปฏิบัติงาน"), workforce("P-002", "พร้อมปฏิบัติงาน"),
      workforce("P-003", "กำลังปฏิบัติงาน"), workforce("P-004", "ไม่พร้อมปฏิบัติงาน")
    ])
    create_dataset("ทรัพยากรและอุปกรณ์", "resources", [
      resource("R-001", "พร้อมใช้"), resource("R-002", "กำลังใช้งาน"), resource("R-003", "ชำรุด")
    ])
    create_dataset("วัสดุสิ้นเปลือง", "consumables", [{ consumable_code: "C-001", name: "น้ำดื่ม", category: "ยังชีพ",
      unit: "ขวด", agency_code: "AG-001", agency_name: "อบต.ทดสอบ", current_quantity: 10, minimum_quantity: 2 }])
  end

  teardown do
    Incident.where(title: "เหตุทดสอบสถานะทีม").delete_all
    @user.destroy
  end

  test "team availability is calculated from workforce members" do
    team = IncidentUsageCatalog.team_availability_for(@user).find { |item| item[:code] == "TEAM-001" }

    assert_equal 4, team[:total]
    assert_equal 2, team[:ready]
    assert_equal 1, team[:active]
    assert_equal 1, team[:unavailable]
    assert_equal 2, team[:available]

    option = IncidentUsageCatalog.rule_options_for(@user).find { |item| item[:label] == "ทีมกู้ภัย ชุด A" }
    assert_equal "teams", option[:source_type]
    assert_equal "คน", option[:unit]
    assert_equal 2, option[:available]
  end

  test "only selected personnel move from ready to active" do
    workforce_dataset = ImportedDataset.where(data_type: "workforce").first
    assignment_key = Digest::SHA256.hexdigest(["workforce", workforce_dataset.id.to_s, "P-001"].join("\0"))[0, 20]
    Incident.create!(title: "เหตุทดสอบสถานะทีม", category: "general", status: "in_progress", severity: "watch",
      assigned_team_code: "TEAM-001", assigned_to: "ทีมกู้ภัย ชุด A",
      active_assignments: [{ "key" => assignment_key, "kind" => "workforce", "released_at" => nil }])

    team = IncidentUsageCatalog.team_availability_for(@user).find { |item| item[:code] == "TEAM-001" }

    assert_equal 1, team[:ready]
    assert_equal 2, team[:active]
    assert_equal 1, team[:unavailable]
  end

  test "resources and consumables use their current statuses and balances" do
    summaries = IncidentUsageCatalog.summary_for(@user)
    resource_summary = summaries.find { |item| item[:category] == "resources" && item[:name] == "รถกู้ภัย" }
    consumable_summary = summaries.find { |item| item[:category] == "consumables" && item[:name] == "น้ำดื่ม" }

    assert_equal 1, resource_summary[:available]
    assert_equal 1, resource_summary[:ready]
    assert_equal 1, resource_summary[:active]
    assert_equal 1, resource_summary[:unavailable]
    assert_equal 10, consumable_summary[:available]
  end

  private

  def create_dataset(name, data_type, records)
    dataset = ImportedDataset.create!(user: @user, name:, data_type:, geometry_type: "none",
      schema_definition: ImportedDataset.schema_for(data_type), shared_with_all: true)
    DatasetVersionImportService.new(dataset:, user: @user, manual_records: records).import!
    dataset
  end

  def workforce(code, status)
    { personnel_code: code, full_name: "เจ้าหน้าที่ #{code}", position: "เจ้าหน้าที่", agency_code: "AG-001",
      agency_name: "อบต.ทดสอบ", team_code: "TEAM-001", team_name: "ทีมกู้ภัย ชุด A",
      employment_status: "ปฏิบัติงาน", availability_status: status }
  end


  def resource(code, status)
    { code:, name: "รถกู้ภัย", resource_type: "ยานพาหนะ", status:, responsible_person: "อบต.ทดสอบ",
      agency_code: "AG-001" }
  end
end
