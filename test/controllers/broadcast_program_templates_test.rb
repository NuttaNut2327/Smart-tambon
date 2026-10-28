require "test_helper"

# Prevention news "agents": the programme form can start from a ready-made template.
class BroadcastProgramTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    @province = Province.create!(code: "A96", name_th: "จังหวัดทดสอบแม่แบบ")
    @subdistrict = @province.subdistricts.create!(code: "A9601", name_th: "ทดสอบแม่แบบ")
    @admin = User.create!(username: "template_admin", password: "Password123!", role: :subdistrict_admin, subdistrict: @subdistrict)
    sign_in @admin
  end

  teardown do
    BroadcastProgram.where(organization_key: @admin&.organization_key).delete_all
    @admin&.destroy
    @subdistrict&.destroy
    @province&.destroy
  end

  test "new form prefills the forecast alert template and saves its settings" do
    get new_broadcast_program_path(template: "forecast_alert")
    assert_response :success
    assert_select "input[name='broadcast_program[name]'][value='เตือนภัยล่วงหน้า 3 วัน']"
    assert_select "input#source_disaster_history[checked]"
    assert_select "input[name='broadcast_program[schedule_times_text]'][value='06:30']"
    assert_select "input[type=checkbox][name='broadcast_program[alert_only]'][checked]"
    assert_select ".broadcast-templates a", BroadcastProgram::TEMPLATES.size

    post broadcast_programs_path, params: { broadcast_program: { name: "เตือนภัยเช้า", prompt: "เตือนภัย", data_sources: %w[weather_forecast disaster_history],
                                                                  schedule_enabled: "1", schedule_times_text: "06:30", schedule_days: %w[0 1 2 3 4 5 6],
                                                                  alert_only: "1", history_years: "3" } }
    program = BroadcastProgram.find_by(organization_key: @admin.organization_key)
    assert program.alert_only?
    assert_equal 3, program.history_years
    assert_equal ["06:30"], program.schedule_times
  end
end
