require "test_helper"

class ContingencyPlansTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "plan_system_admin", email: "plan_system_admin@example.test",
      password: "Password123!", role: :system_admin)
    sign_in @user
  end

  teardown do
    ContingencyPlan.delete_all
    AdminAuditLog.where(action: "delete_contingency_plan").delete_all
    @user&.destroy
  end

  test "system admin creates a draft plan and opens area analysis" do
    post contingency_plans_path, params: { contingency_plan: {
      name: "แผนน้ำท่วม", disaster_type: "flood", description: "พื้นที่ลุ่มต่ำ", status: "draft"
    } }

    plan = ContingencyPlan.last
    assert_redirected_to situation_assessment_path(plan_id: plan.id)
    assert_equal "แผนน้ำท่วม", plan.name
    assert_empty plan.versions
  end

  test "area assessment is stored as an editable plan version snapshot" do
    plan = ContingencyPlan.create!(organization_key: "system", user_id: @user.id,
      name: "แผนไฟป่า", disaster_type: "fire", created_by: @user.username)
    entries = [{ category: "resources", name: "รถดับเพลิง", unit: "คัน",
      required: 3, available: 2, sufficient: false }]

    post versions_contingency_plan_path(plan), params: { contingency_plan: {
      version_title: "แผนหลัก", area_sq_km: 4.5, affected_people: 120,
      affected_households: 40, affected_villages: 2,
      geometry_json: { type: "Polygon", coordinates: [] }.to_json,
      entries_json: entries.to_json, mark_ready: "1"
    } }

    assert_redirected_to disasters_path(view: "plans", plan_id: plan.id)
    plan.reload
    assert_equal "ready", plan.status
    assert_equal 1, plan.active_version
    assert_equal 3.0, plan.current_version.dig("entries", 0, "required")
    assert_not plan.current_version.dig("entries", 0, "sufficient")

    get disasters_path(view: "plans", plan_id: plan.id)
    assert_response :success
    assert_includes response.body, "พื้นที่ประเมินของแผน"
    assert_includes response.body, "data-contingency-detail-map"
    assert_includes response.body, "data-contingency-geometry"
  end

  test "plan analysis shows area analysis without simulation mode" do
    plan = ContingencyPlan.create!(organization_key: "system", user_id: @user.id,
      name: "แผนภัยแล้ง", disaster_type: "drought", created_by: @user.username)

    get situation_assessment_path(plan_id: plan.id)

    assert_response :success
    assert_includes response.body, "จัดทำแผนรับมือ"
    assert_includes response.body, "บันทึกเป็น Version ใหม่"
    assert_includes response.body, 'data-city-map="true"'
    assert_includes response.body, "data-assessment-boundary"
    assert_includes response.body, "data-assessment-disaster-type"
    assert_not_includes response.body, "data-assessment-disaster-type disabled"
    assert_not_includes response.body, "จำลองสถานการณ์</b>"
  end

  test "saving a new version updates the selected disaster type" do
    plan = ContingencyPlan.create!(organization_key: "system", user_id: @user.id,
      name: "แผนหลายประเภทภัย", disaster_type: "flood", created_by: @user.username)

    post versions_contingency_plan_path(plan), params: { contingency_plan: {
      disaster_type: "landslide", version_title: "ปรับเป็นแผนดินถล่ม",
      geometry_json: { type: "Polygon", coordinates: [] }.to_json,
      entries_json: [].to_json
    } }

    assert_redirected_to disasters_path(view: "plans", plan_id: plan.id)
    assert_equal "landslide", plan.reload.disaster_type
  end

  test "required quantities are edited from the saved plan version" do
    plan = ContingencyPlan.create!(organization_key: "system", user_id: @user.id,
      name: "แผนแก้ทรัพยากร", disaster_type: "flood", created_by: @user.username,
      active_version: 1, versions: [{ "version" => 1, "title" => "ฉบับแรก", "entries" => [
        { "category" => "resources", "name" => "เรือท้องแบน", "unit" => "ลำ",
          "required" => 2.0, "available" => 1.0, "sufficient" => false }
      ] }])

    patch update_version_contingency_plan_path(plan, version: 1), params: { contingency_plan: {
      entries: { "0" => { category: "resources", name: "เรือท้องแบน", unit: "ลำ",
        required: 1, available: 1 } }
    } }

    assert_redirected_to disasters_path(view: "plans", plan_id: plan.id, plan_version: 1)
    entry = plan.reload.current_version.fetch("entries").first
    assert_equal 1.0, entry["required"]
    assert entry["sufficient"]
  end

  test "plan details show required quantities as read only until edit is selected" do
    plan = ContingencyPlan.create!(organization_key: "system", user_id: @user.id,
      name: "แผนอ่านก่อนแก้", disaster_type: "flood", created_by: @user.username,
      active_version: 1, versions: [{ "version" => 1, "title" => "ฉบับแรก", "entries" => [
        { "category" => "resources", "name" => "เรือ", "unit" => "ลำ",
          "required" => 2.0, "available" => 1.0, "sufficient" => false }
      ] }])

    get disasters_path(view: "plans", plan_id: plan.id)

    assert_response :success
    assert_includes response.body, "data-edit-contingency-resources"
    assert_includes response.body, "data-contingency-required-value"
    assert_includes response.body, "กลับไปแผนรับมือทั้งหมด"
    assert_not_includes response.body, "ค้นหาชื่อแผนรับมือ"
    assert_not_includes response.body, "data-contingency-plan-row"
    assert_match(/data-contingency-required-editor[^>]*hidden/, response.body)
    assert_match(/data-contingency-edit-actions[^>]*hidden/, response.body)
  end

  test "plan list provides searchable action rows and disaster filter" do
    plan = ContingencyPlan.create!(organization_key: "system", user_id: @user.id,
      name: "แผนรับมือน้ำท่วม", disaster_type: "flood", created_by: @user.username)

    get disasters_path(view: "plans")

    assert_response :success
    assert_includes response.body, "ค้นหาชื่อแผนรับมือ"
    assert_includes response.body, "data-contingency-disaster-filter"
    assert_includes response.body, "data-contingency-plan-row"
    assert_includes response.body, "แผนรับมือน้ำท่วม"
    assert_includes response.body, "ดูรายละเอียดฉบับเต็ม"
  end

  test "deleting a plan requires a reason and records an audit log" do
    plan = ContingencyPlan.create!(organization_key: "system", user_id: @user.id,
      name: "แผนที่ต้องลบ", disaster_type: "flood", created_by: @user.username)

    assert_no_difference("ContingencyPlan.count") do
      delete contingency_plan_path(plan), params: { contingency_plan: { deletion_reason: "" } }
    end
    assert_redirected_to disasters_path(view: "plans", plan_id: plan.id)

    assert_difference("ContingencyPlan.count", -1) do
      delete contingency_plan_path(plan), params: { contingency_plan: { deletion_reason: "ข้อมูลซ้ำกับแผนหลัก" } }
    end
    log = AdminAuditLog.where(action: "delete_contingency_plan").desc(:created_at).first
    assert_equal "ข้อมูลซ้ำกับแผนหลัก", log.details["reason"]
    assert_equal "แผนที่ต้องลบ", log.details["plan_name"]
  end

  test "city map assessment can create a plan with its first version" do
    post contingency_plans_path, params: { contingency_plan: {
      name: "แผนจากแผนที่เมือง", disaster_type: "flood", description: "บันทึกจากผลวิเคราะห์",
      from_assessment: "1", mark_ready: "1", area_sq_km: 1.25,
      affected_people: 50, affected_households: 20, affected_villages: 1,
      geometry_json: { type: "Polygon", coordinates: [] }.to_json,
      entries_json: [{ category: "teams", name: "ทีมกู้ภัย", unit: "ทีม", required: 2, available: 1 }].to_json
    } }

    plan = ContingencyPlan.last
    assert_redirected_to disasters_path(view: "plans", plan_id: plan.id)
    assert_equal 1, plan.active_version
    assert_equal "ready", plan.status
    assert_equal "teams", plan.current_version.dig("entries", 0, "category")
  end


  test "city map asks for plan details only when saving an analysis" do
    get situation_assessment_path

    assert_response :success
    assert_includes response.body, 'data-open-plan-save'
    assert_includes response.body, 'id="save-contingency-plan-dialog"'
    assert_includes response.body, "สร้างแผนและบันทึก Version 1"
    assert_includes response.body, "ผลการวิเคราะห์ครั้งแรกเป็นข้อมูลตั้งต้นแบบอ่านอย่างเดียว"
  end

  test "disaster page links to future plans without a tab bar" do
    get disasters_path(view: "plans")

    assert_response :success
    assert_includes response.body, "ภัยพิบัติที่เกิดขึ้นจริง"
    assert_not_includes response.body, "disaster-section-nav"
    assert_includes response.body, "สร้างแผนรับมือ"

    get disasters_path
    assert_response :success
    assert_includes response.body, "แผนรับมือในอนาคต"
    assert_not_includes response.body, "disaster-section-nav"
  end
end
