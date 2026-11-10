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

  test "admin can preview and download a PNG QR for each public report link" do
    sign_in @admin
    OrganizationSetting.for(@admin).update!(report_sources_text: "ประชาชน")

    get public_report_qr_organization_settings_path(source_type: "citizen", source_name: "ประชาชน")
    assert_response :success
    assert_equal "image/png", response.media_type
    assert response.body.start_with?("\x89PNG".b)

    get public_report_qr_organization_settings_path(source_type: "citizen", source_name: "ประชาชน", download: "1")
    assert_match(/attachment/, response.headers["Content-Disposition"])
  end

  test "citizen LINE credentials are encrypted and scoped to the organization" do
    sign_in @admin
    patch organization_settings_path, params: { organization_setting: {
      citizen_line_enabled: "1", citizen_line_login_channel_id: "login-123", citizen_line_liff_id: "liff-123",
      citizen_line_channel_access_token: "organization-access-token",
      citizen_line_channel_secret: "organization-secret"
    } }

    assert_redirected_to organization_settings_path
    setting = OrganizationSetting.for(@admin).reload
    assert_equal "organization-access-token", setting.citizen_line_channel_access_token
    assert_equal "organization-secret", setting.citizen_line_channel_secret
    assert_not_includes setting.citizen_line_channel_access_token_ciphertext, "organization-access-token"

    get public_reporting_organization_settings_path
    assert_not_includes response.body, "organization-access-token"
    assert_includes response.body, citizen_line_webhook_path(organization_key: @admin.organization_key)
  end

  test "public reporting settings are separated into their own tab" do
    sign_in @admin

    get organization_settings_path
    assert_response :success
    assert_select "#settings-organization", count: 1
    assert_select "#settings-citizen-line", count: 0
    assert_select "#settings-public-report", count: 0

    get public_reporting_organization_settings_path
    assert_response :success
    assert_select "#settings-organization", count: 0
    assert_select "#settings-citizen-line", count: 1
    assert_select "#settings-public-report", count: 1
    assert_select "textarea[name='organization_setting[citizen_line_submitted_template]']", count: 0
    assert_select "textarea[name='organization_setting[citizen_line_acknowledged_template]']", count: 0
    assert_select "textarea[name='organization_setting[citizen_line_completed_template]']", count: 0
  end

  test "LIFF bootstrap initializes the organization app and permanent URL uses a secondary path" do
    setting = OrganizationSetting.for(@admin)
    setting.update!(citizen_line_enabled: true, citizen_line_login_channel_id: "login-123", citizen_line_liff_id: "liff-123")
    token = public_report_token(setting)

    assert_equal "https://liff.line.me/liff-123/report/#{token}", setting.citizen_liff_url(liff_public_incident_report_path(token:))
    payload = Rails.application.message_verifier(:public_incident_form).verify(token)
    assert_equal @admin.access_area.id.to_s, (payload["id"] || payload[:id]).to_s
    assert OrganizationSetting.for(@admin).citizen_liff_ready?
    get "#{liff_bootstrap_path}?liff.state=#{CGI.escape("/report/#{token}")}"

    assert_response :success
    assert_includes response.body, 'liff.init({ liffId: "liff-123" })'
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
