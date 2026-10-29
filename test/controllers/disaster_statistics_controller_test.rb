require "test_helper"

class DisasterStatisticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @province = Province.create!(code: "D98", name_th: "จังหวัดทดสอบสถิติภัย")
    @subdistrict = @province.subdistricts.create!(code: "D9801", name_th: "ตำบลทดสอบสถิติภัย")
    @user = User.create!(username: "disaster_stats_user", email: "disaster_stats_user@example.test", password: "Password123!",
      role: :subdistrict_user, subdistrict: @subdistrict)
    sign_in @user
  end

  teardown do
    @user&.destroy
    @subdistrict&.destroy
    @province&.destroy
  end

  test "requires sign in" do
    sign_out @user
    get disaster_statistics_path
    assert_response :redirect
  end

  test "renders the page shell with hazards in stacking order and the sidebar entry" do
    get disaster_statistics_path

    assert_response :success
    hazards = JSON.parse(css_select("[data-disaster-stats]").first["data-hazards"])
    assert_equal %w[flood landslide storm drought wildfire], hazards.map { |hazard| hazard["key"] }
    assert_equal DisasterEvent::HAZARDS["flood"][:color], hazards.first["color"]
    assert_select "a.primary-nav-item.active[href=?]", disaster_statistics_path
    assert_select "[data-outlook-form] input[name=rain_3d_mm]"
  end
end
