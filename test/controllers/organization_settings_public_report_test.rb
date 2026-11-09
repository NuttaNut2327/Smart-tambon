require "test_helper"

class OrganizationSettingsPublicReportTest < ActionDispatch::IntegrationTest
  setup do
    @province = Province.create!(code: "O97", name_th: "จังหวัดทดสอบการตั้งค่า")
    @subdistrict = create_subdistrict
    @admin = User.create!(username: "organization_settings_admin", email: "organization_settings@example.test",
      password: "Password123!", role: :subdistrict_admin, subdistrict: @subdistrict)
    UserAccessAreaService.new(user: @admin, name: "องค์การบริหารส่วนตำบลทดสอบ",
      subdistrict_ids: [@subdistrict.id], boundary_file: nil).save!
    OrganizationSetting.where(organization_key: @admin.organization_key).delete_all
  end

  teardown do
    OrganizationSetting.where(organization_key: @admin&.organization_key).delete_all
    @admin&.destroy
    @subdistrict&.destroy
    @province&.destroy
  end

  test "organization details are persisted and rendered on the public report form" do
    sign_in @admin

    patch organization_settings_path, params: { organization_setting: {
      organization_name: "องค์การบริหารส่วนตำบลทดสอบ",
      executive_name: "นายกทดสอบ ระบบดี",
      address: "99 หมู่ 1 ตำบลทดสอบ อำเภอทดสอบ จังหวัดทดสอบ 55000",
      phone: "054-123456",
      email: "contact@example.test",
      website: "https://example.test",
      notify_new_incidents: "1",
      notification_sound: "0",
      notify_pending_activities: "1",
      public_report_enabled: "1",
      public_report_welcome: "กรณีเร่งด่วน กรุณาติดต่อเจ้าหน้าที่",
      report_sources_text: "ประชาชน",
      map_layers_mode: "system"
    } }

    assert_redirected_to organization_settings_path
    setting = OrganizationSetting.where(organization_key: @admin.organization_key).first
    assert_equal "องค์การบริหารส่วนตำบลทดสอบ", setting.organization_name
    assert_equal "นายกทดสอบ ระบบดี", setting.executive_name
    assert_equal "99 หมู่ 1 ตำบลทดสอบ อำเภอทดสอบ จังหวัดทดสอบ 55000", setting.address
    assert_equal "054-123456", setting.phone
    assert_equal "contact@example.test", setting.email
    assert_equal "https://example.test", setting.website
    assert_equal "กรณีเร่งด่วน กรุณาติดต่อเจ้าหน้าที่", setting.public_report_welcome

    sign_out @admin
    get public_incident_report_path(token: public_report_token(setting))

    assert_response :success
    assert_select ".public-report-brand strong", text: "องค์การบริหารส่วนตำบลทดสอบ"
    assert_select ".public-report-brand small", text: "แบบฟอร์มแจ้งเหตุสำหรับประชาชน"
    assert_select ".public-report-secure", text: /แบบฟอร์มสำหรับประชาชน/
    assert_select ".public-report-secure a[href^='tel:']", count: 0
    assert_select ".public-report-organization" do
      assert_select "h2", text: "องค์การบริหารส่วนตำบลทดสอบ"
      assert_select "dd", text: "นายกทดสอบ ระบบดี"
      assert_select "dd", text: /99 หมู่ 1/
      assert_select "a[href='tel:054123456']", text: "054-123456"
      assert_select "a[href='mailto:contact@example.test']", text: "contact@example.test"
      assert_select "a[href='https://example.test']", text: "https://example.test"
    end
    assert_select ".public-report-welcome", text: /กรณีเร่งด่วน/
  end

  test "organization information can be reset to system defaults" do
    setting = OrganizationSetting.for(@admin)
    setting.update!(organization_name: "อบต. กำหนดเอง", executive_name: "ผู้บริหารทดสอบ", address: "ที่อยู่ทดสอบ",
                    phone: "054-000000", email: "custom@example.test", website: "https://custom.example.test")
    sign_in @admin

    patch organization_settings_path, params: { reset_organization_information: "1" }

    assert_redirected_to organization_settings_path(anchor: "settings-organization")
    setting.reload
    assert_nil setting.organization_name
    assert_nil setting.executive_name
    assert_nil setting.address
    assert_nil setting.phone
    assert_nil setting.email
    assert_nil setting.website
    assert_nil setting.logo
  end

  private

  def public_report_token(setting)
    Rails.application.message_verifier(:public_incident_form).generate({
      scope: "access_area", id: @admin.access_area.id.to_s, version: setting.public_report_version,
      source_type: "citizen", source_name: "ประชาชน"
    })
  end

  def create_subdistrict
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    points = [[100.0, 14.0], [100.1, 14.0], [100.1, 14.1], [100.0, 14.1], [100.0, 14.0]]
      .map { |longitude, latitude| factory.point(longitude, latitude) }
    boundary = factory.multi_polygon([factory.polygon(factory.linear_ring(points))])
    @province.subdistricts.create!(code: "O9701", name_th: "ตำบลทดสอบ", boundary:)
  end
end
