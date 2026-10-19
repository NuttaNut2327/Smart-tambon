require "test_helper"
require "minitest/mock"

# SMS to the reporter (smsmkt): phone normalisation, provider result parsing, the send_sms contract, real SENT/FAIL
# status, audit and activity log, cooldown, access scope, the public tracking page, and the admin settings.
class SmsTest < ActionDispatch::IntegrationTest
  class FakeClient
    attr_reader :calls

    def initialize(ok: true)
      @ok = ok
      @calls = []
    end

    def send_message(**args)
      @calls << args
      body = @ok ? { "code" => "000", "detail" => "OK", "result" => { "transaction_id" => "tx-1" } } : { "code" => "400", "detail" => "Credit not enough" }
      Sms::SmsmktClient::Result.new(ok: @ok, http_status: "200", code: body["code"], detail: body["detail"], body: body, error: (@ok ? nil : "เครดิต SMS ไม่พอ (code 400)"))
    end
  end

  setup do
    @province = Province.create!(code: "A95", name_th: "จังหวัดทดสอบ SMS")
    @first = create_subdistrict("A9501", "ตำบลเอสเอ็มเอสหนึ่ง", 100.0)
    @second = create_subdistrict("A9502", "ตำบลเอสเอ็มเอสสอง", 101.0)
    @admin = User.create!(username: "sms_admin_one", password: "Password123!", role: :subdistrict_admin, subdistrict: @first)
    @other = User.create!(username: "sms_admin_two", password: "Password123!", role: :subdistrict_admin, subdistrict: @second)
    @setting = SmsSetting.current
    @setting.assign_sms_api_key("api-key-1234")
    @setting.assign_sms_secret_key("secret-key-5678")
    @setting.update!(sms_sender: "Demo-SMS", host_url: "https://tambon.test", cooldown_seconds: 60)
    @incident = Incident.create!(title: "ไฟฟ้าดับ", category: "general", status: "pending", severity: "urgent", incident_type: "อื่น ๆ", incident_type_other: "ไฟฟ้า",
                                 owner_user_id: @admin.id, user_id: @admin.id, subdistrict_id: @first.id,
                                 reporter_name: "นายผู้แจ้ง", reporter_contact: "+66 81-234-5678")
    sign_in @admin
  end

  teardown do
    [SmsMessage, SmsSetting, NotificationDelivery].each(&:delete_all)
    Incident.where(:owner_user_id.in => [@admin&.id, @other&.id].compact).delete_all
    [@admin, @other].compact.each(&:destroy)
    @province&.subdistricts&.destroy_all
    @province&.destroy
  end

  test "phone numbers are normalised to 08xxxxxxxx and non-mobile numbers are rejected" do
    assert_equal "0812345678", Sms::PhoneNumber.normalize("+66 81-234-5678")
    assert_equal "0912345678", Sms::PhoneNumber.normalize("66912345678")
    assert_equal "0612345678", Sms::PhoneNumber.normalize("061.234.5678")
    assert_nil Sms::PhoneNumber.normalize("02-123-4567")
    assert_nil Sms::PhoneNumber.normalize("")
  end

  test "a provider error code inside HTTP 200 counts as a failure" do
    client = Sms::SmsmktClient.new(@setting)
    ok = client.send(:parse, http_response("200", { code: "000", detail: "OK" }))
    failed = client.send(:parse, http_response("200", { code: "300", detail: "Sender not found" }))
    server = client.send(:parse, http_response("500", { code: "1001" }))

    assert ok.ok?
    assert_not failed.ok?
    assert_includes failed.error, "ชื่อผู้ส่ง"
    assert_not server.ok?
  end

  test "GET send_sms previews without sending and unknown modes fall back to tracking" do
    get send_sms_path(id: @incident.id, mode: "nonsense", ajax: 1)

    assert_response :success
    body = response.parsed_body
    assert_equal "tracking", body["mode"]
    assert_equal "0812345678", body["phone"]
    assert_match %r{\Ahttps://tambon\.test/t/[\w-]{16,}\z}, body["link"]
    assert_includes body["template"], "<TRACKING-URL>"
    assert_equal 0, SmsMessage.count
  end

  test "POST send_sms sends, marks the incident SENT, audits and logs, and the link opens the public status page" do
    fake = FakeClient.new
    Sms::SmsmktClient.stub(:new, fake) { post send_sms_path(id: @incident.id, mode: "tracking", ajax: 1) }

    assert_response :success
    body = response.parsed_body
    assert body["ok"]
    assert_equal %w[link mode ok phone provider status template].sort, (body.keys & %w[ok status mode phone link template provider]).sort
    assert_equal "0812345678", fake.calls.first[:phone]
    assert_equal body["link"], fake.calls.first[:url]

    @incident.reload
    assert_equal "SENT", @incident.sms_status
    assert @incident.sms_sent_at
    assert_equal "sms", @incident.histories.last["kind"]
    audit = SmsMessage.last
    assert_equal [body["link"], "SENT", "sms_admin_one"], [audit.link, audit.status, audit.sent_by]

    sign_out @admin
    get URI.parse(body["link"]).path
    assert_response :success
    assert_includes response.body, @incident.reference_code
    assert_not_includes response.body, "นายผู้แจ้ง"
    assert_not_includes response.body, "234-5678"
  end

  test "a provider failure marks the incident FAIL with the error instead of SENT" do
    Sms::SmsmktClient.stub(:new, FakeClient.new(ok: false)) { post send_sms_path(id: @incident.id, ajax: 1) }

    assert_response :bad_gateway
    assert_not response.parsed_body["ok"]
    @incident.reload
    assert_equal "FAIL", @incident.sms_status
    assert_includes @incident.sms_error, "เครดิต"
    assert_equal "FAIL", SmsMessage.last.status
  end

  test "repeat sends are blocked by the cooldown and bad numbers are refused" do
    Sms::SmsmktClient.stub(:new, FakeClient.new) do
      post send_sms_path(id: @incident.id, ajax: 1)
      post send_sms_path(id: @incident.id, ajax: 1)
    end
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "รออีก"

    landline = Incident.create!(title: "x", category: "general", status: "pending", severity: "general", incident_type: "อื่น ๆ", incident_type_other: "x",
                                owner_user_id: @admin.id, user_id: @admin.id, subdistrict_id: @first.id, reporter_contact: "02-123-4567")
    post send_sms_path(id: landline.id, ajax: 1)
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "มือถือ"
  end

  test "another อบต. cannot send SMS for this incident" do
    sign_in @other
    post send_sms_path(id: @incident.id, ajax: 1)
    assert_response :not_found
    assert_equal 0, SmsMessage.count
  end

  test "settings are system-admin only, hide secrets, and require the tracking tag" do
    get sms_settings_path
    assert_redirected_to root_path

    admin = User.create!(username: "sms_system_admin", password: "Password123!", role: :system_admin)
    sign_in admin
    get sms_settings_path
    assert_response :success
    assert_not_includes response.body, "api-key-1234"
    assert_includes response.body, "1234"

    patch sms_settings_path, params: { sms_setting: { sms_msg: "ไม่มีลิงก์" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "&lt;TRACKING-URL&gt;"
  ensure
    admin&.destroy
  end

  private

  def http_response(code, body)
    response = Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new("1.1", code, "")
    response.instance_variable_set(:@body, body.to_json)
    response.instance_variable_set(:@read, true)
    response
  end

  def create_subdistrict(code, name, longitude)
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    points = [[longitude, 14.0], [longitude + 0.1, 14.0], [longitude + 0.1, 14.1],
              [longitude, 14.1], [longitude, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    boundary = factory.multi_polygon([factory.polygon(factory.linear_ring(points))])
    @province.subdistricts.create!(code: code, name_th: name, boundary: boundary)
  end
end
