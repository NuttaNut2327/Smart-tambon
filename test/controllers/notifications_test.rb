require "test_helper"
require "minitest/mock"

# Group-chat notifications: templates, per-อบต. channels, the new-incident pipeline, the test page and the LINE webhook.
class NotificationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # Records what would have been sent instead of calling LINE/Telegram/Signal.
  class FakeSender
    attr_reader :sent

    def initialize(fail_for: nil)
      @sent = []
      @fail_for = fail_for
    end

    def for(channel, _setting = nil)
      sender = self
      Object.new.tap do |proxy|
        proxy.define_singleton_method(:deliver) do |text, **|
          raise Notifications::Senders::DeliveryError, "ทดสอบล้มเหลว" if channel.name == sender.instance_variable_get(:@fail_for)

          sender.sent << [channel.name, text]
        end
      end
    end
  end

  LINE_GROUP = "C#{'a' * 32}".freeze

  setup do
    @province = Province.create!(code: "A96", name_th: "จังหวัดทดสอบแจ้งเตือน")
    @first = create_subdistrict("A9601", "ตำบลแจ้งหนึ่ง", 100.0)
    @second = create_subdistrict("A9602", "ตำบลแจ้งสอง", 101.0)
    @admin = User.create!(username: "notify_admin_one", password: "Password123!", role: :subdistrict_admin, subdistrict: @first)
    @staff = User.create!(username: "notify_staff_one", password: "Password123!", role: :subdistrict_user, subdistrict: @first)
    @other = User.create!(username: "notify_admin_two", password: "Password123!", role: :subdistrict_admin, subdistrict: @second)
    @line = NotificationChannel.create!(organization_key: @admin.organization_key, name: "กลุ่มเวร", kind: "line", target: LINE_GROUP, tags: %w[incident.created disaster.created])
    @disaster_only = NotificationChannel.create!(organization_key: @admin.organization_key, name: "กลุ่มภัยพิบัติ", kind: "telegram", target: "-1001234567890", tags: %w[disaster.created])
    @foreign = NotificationChannel.create!(organization_key: @other.organization_key, name: "กลุ่มตำบลอื่น", kind: "line", target: "C#{'b' * 32}", tags: %w[incident.created])
    sign_in @admin
  end

  teardown do
    [NotificationDelivery, CitizenLineDelivery, NotificationChannel, NotificationTemplate, LineGroup, LineWebhookLog, NotificationSetting].each(&:delete_all)
    OrganizationSetting.where(:organization_key.in => [@admin&.organization_key, @other&.organization_key].compact).delete_all
    Incident.where(:owner_user_id.in => [@admin&.id, @other&.id].compact).delete_all
    [@admin, @staff, @other].compact.each(&:destroy)
    @province&.subdistricts&.destroy_all
    @province&.destroy
  end

  test "a new incident is sent to the owner's subscribed channels with the อบต. template" do
    NotificationTemplate.create!(organization_key: @admin.organization_key, name: "ด่วน", tag: "incident.created", body: "เหตุใหม่ {{reference_code}}: {{title}} ({{severity}})")
    fake = FakeSender.new

    incident = nil
    assert_enqueued_jobs 1, only: NotificationDispatchJob do
      incident = create_incident(title: "น้ำประปาไม่ไหล", severity: "urgent")
    end
    Notifications::Senders.stub(:for, ->(channel, setting = nil) { fake.for(channel, setting) }) { perform_enqueued_jobs }

    assert_equal [["กลุ่มเวร", "เหตุใหม่ #{incident.reference_code}: น้ำประปาไม่ไหล (เร่งด่วน)"]], fake.sent
    delivery = NotificationDelivery.find_by(channel_id: @line.id)
    assert delivery.sent?
    assert_equal incident.id, delivery.incident_id
    assert @line.reload.last_sent_at
  end

  test "imported incidents are not announced and reporter contacts never reach the message" do
    imported = build_incident(title: "นำเข้า")
    imported[:imported_dataset_id] = "abc"
    assert_no_enqueued_jobs(only: NotificationDispatchJob) { imported.save! }

    incident = create_incident(title: "มีผู้แจ้ง", reporter_name: "นายทดสอบ", reporter_contact: "0812345678")
    text = Notifications::Dispatcher.render(NotificationTemplate::DEFAULTS["incident.created"], Notifications::Dispatcher.incident_variables(incident, @admin.organization_key))
    assert_includes text, "มีผู้แจ้ง"
    assert_not_includes text, "0812345678"
    assert_not_includes text, "นายทดสอบ"
  end

  test "promoting a general incident dispatches disaster notification to subscribed LINE OA" do
    incident = create_incident(title: "น้ำท่วมฉับพลัน", status: "in_progress")
    clear_enqueued_jobs

    assert_enqueued_with(job: NotificationDispatchJob, args: [incident.id.to_s, "disaster.created"]) do
      patch promote_incident_to_disaster_path(incident)
    end

    assert_redirected_to disasters_path(incident_id: incident.id)
    assert_equal "disaster", incident.reload.category
    fake = FakeSender.new
    Notifications::Senders.stub(:for, ->(channel, setting = nil) { fake.for(channel, setting) }) { perform_enqueued_jobs }
    assert_includes fake.sent.map(&:first), "กลุ่มเวร"
    delivery = NotificationDelivery.find_by(channel_id: @line.id, incident_id: incident.id, tag: "disaster.created")
    assert delivery&.sent?
  end

  test "templates reject unknown variables" do
    template = NotificationTemplate.new(organization_key: @admin.organization_key, name: "ผิด", tag: "incident.created", body: "{{title}} {{reporter_contact}}")
    assert_not template.valid?
    assert_includes template.errors[:body].join, "{{reporter_contact}}"
  end

  test "admin explicitly selects the active template for each message type" do
    first = NotificationTemplate.create!(organization_key: @admin.organization_key, name: "แบบแรก",
      tag: "incident.created", body: "แบบแรก {{title}}")
    second = NotificationTemplate.create!(organization_key: @admin.organization_key, name: "แบบที่สอง",
      tag: "incident.created", body: "แบบที่สอง {{title}}")

    assert first.reload.active?
    assert_not second.reload.active?
    assert_equal "แบบแรก {{title}}", NotificationTemplate.body_for(@admin.organization_key, "incident.created")

    patch activate_notification_template_path(second)

    assert_redirected_to notification_templates_path(anchor: "template-incident-created")
    assert_not first.reload.active?
    assert second.reload.active?
    assert_equal "แบบที่สอง {{title}}", NotificationTemplate.body_for(@admin.organization_key, "incident.created")
  end

  test "admin edits citizen status templates from the message templates page" do
    get notification_templates_path
    assert_response :success
    assert_select ".settings-card h2", text: "ข้อความแจ้งความคืบหน้าสำหรับประชาชน", count: 1
    assert_select ".notify-tag-card", minimum: NotificationTemplate::TAGS.size

    post notification_templates_path, params: { notification_template: {
      name: "แจ้งประชาชนเมื่อรับเรื่อง",
      tag: "citizen.acknowledged",
      body: "{{organization_name}} กำลังดูแล {{title}} ({{reference_code}})"
    } }

    assert_redirected_to notification_templates_path
    template = NotificationTemplate.for_organization(@admin.organization_key).where(tag: "citizen.acknowledged").first
    assert_equal "แจ้งประชาชนเมื่อรับเรื่อง", template.name
    assert_equal "{{organization_name}} กำลังดูแล {{title}} ({{reference_code}})", template.body

    get edit_notification_template_path(template)
    assert_response :success
    assert_select "select[name='notification_template[tag]'] option[value='citizen.acknowledged'][selected]", count: 1
  end

  test "shared test page can send a citizen status template to a linked reporter" do
    incident = create_incident(title: "ไฟถนนดับ")
    incident.set(line_notification_enabled: true, reporter_line_user_id: "U#{'c' * 32}", reporter_line_display_name: "ผู้แจ้งทดสอบ")
    setting = OrganizationSetting.for(@admin)
    setting.update!(citizen_line_enabled: true)
    setting.assign_citizen_line_channel_access_token("token")
    setting.save!
    calls = []
    client = Object.new
    client.define_singleton_method(:push) { |user_id, text| calls << [user_id, text]; true }

    CitizenLine::Client.stub(:new, client) do
      post notification_tests_path, params: {
        mode: "simulate", tag: "citizen.submitted", data: "sample",
        citizen_incident_id: incident.id.to_s, commit_action: "send"
      }
    end

    assert_redirected_to notification_tests_path
    assert_equal 1, calls.size
    assert_equal incident.reporter_line_user_id, calls.first.first
    assert_includes calls.first.last, incident.reference_code
  end

  test "channel validation follows the kind" do
    assert_not NotificationChannel.new(organization_key: "x", name: "a", kind: "line", target: "groupid").valid?
    assert_not NotificationChannel.new(organization_key: "x", name: "a", kind: "telegram", target: "abc").valid?
    assert NotificationChannel.new(organization_key: "x", name: "a", kind: "signal", target: "+66812345678").valid?
    assert_not NotificationChannel.new(organization_key: "x", name: "a", kind: "webhook", target: "ftp://x").valid?
  end

  test "each อบต. sees and edits only its own channels; staff cannot manage them" do
    get notification_channels_path
    assert_response :success
    assert_includes response.body, "กลุ่มเวร"
    assert_not_includes response.body, "กลุ่มตำบลอื่น"

    get edit_notification_channel_path(@foreign)
    assert_response :not_found

    sign_in @staff
    get notification_channels_path
    assert_redirected_to root_path
  end

  test "simulating a new incident sends through the same tag routing and is logged" do
    fake = FakeSender.new
    Notifications::Senders.stub(:for, ->(channel, setting = nil) { fake.for(channel, setting) }) do
      post notification_tests_path, params: { mode: "simulate", tag: "disaster.created", data: "sample", commit_action: "send" }
    end

    assert_redirected_to notification_tests_path
    assert_equal ["กลุ่มเวร", "กลุ่มภัยพิบัติ"], fake.sent.map(&:first)
    assert fake.sent.all? { |_name, text| text.include?("แจ้งเตือนภัยพิบัติ") }
    assert_equal "simulation", NotificationDelivery.last.source
  end

  test "simulation sends only to the selected eligible group" do
    fake = FakeSender.new
    Notifications::Senders.stub(:for, ->(channel, setting = nil) { fake.for(channel, setting) }) do
      post notification_tests_path, params: {
        mode: "simulate", tag: "disaster.created", data: "sample",
        channel_selection_present: "1", channel_ids: [@disaster_only.id.to_s], commit_action: "send"
      }
    end

    assert_redirected_to notification_tests_path
    assert_equal ["กลุ่มภัยพิบัติ"], fake.sent.map(&:first)
  end

  test "preview uses the template for the selected event tag" do
    post notification_tests_path, params: { mode: "simulate", tag: "disaster.created", data: "sample", commit_action: "preview" }

    assert_response :success
    assert_select ".notify-preview-box" do |preview|
      assert_includes preview.text, "แจ้งเตือนภัยพิบัติ"
      assert_not_includes preview.text, "มีเหตุการณ์แจ้งเข้ามาใหม่"
    end
  end

  test "preview responds with JSON for the AJAX test form" do
    post notification_tests_path,
      params: { mode: "simulate", tag: "disaster.created", data: "sample", commit_action: "preview" },
      as: :json

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal true, payload["ok"]
    assert_includes payload["preview"], "แจ้งเตือนภัยพิบัติ"
    assert_equal "ใช้ข้อมูลตัวอย่าง", payload["preview_source"]
  end

  test "delivery history filters by an inclusive date range and displays Thai date and time" do
    before_range = NotificationDelivery.create!(organization_key: @admin.organization_key, channel_name: "ก่อนช่วง", tag: "disaster.created", status: "sent", created_at: Time.zone.local(2026, 11, 6, 12, 0))
    in_range = NotificationDelivery.create!(organization_key: @admin.organization_key, channel_name: "ในช่วง", tag: "disaster.created", status: "sent", created_at: Time.zone.local(2026, 11, 7, 19, 0))
    other_tag = NotificationDelivery.create!(organization_key: @admin.organization_key, channel_name: "คนละแท็ก", tag: "incident.created", status: "sent", created_at: Time.zone.local(2026, 11, 7, 20, 0))
    after_range = NotificationDelivery.create!(organization_key: @admin.organization_key, channel_name: "หลังช่วง", tag: "disaster.created", status: "sent", created_at: Time.zone.local(2026, 11, 8, 12, 0))

    get notification_tests_path, params: { history_start_date: "2026-11-07", history_end_date: "2026-11-07", history_tag: "disaster.created" }

    assert_response :success
    assert_includes response.body, in_range.channel_name
    assert_includes response.body, "7 พ.ย. 2569 19.00 น."
    assert_not_includes response.body, before_range.channel_name
    assert_not_includes response.body, other_tag.channel_name
    assert_not_includes response.body, after_range.channel_name
  end

  test "test page reports a failed channel without stopping the others" do
    fake = FakeSender.new(fail_for: "กลุ่มเวร")
    Notifications::Senders.stub(:for, ->(channel, setting = nil) { fake.for(channel, setting) }) do
      post notification_tests_path, params: { mode: "custom", message: "สวัสดี", channel_ids: [@line.id.to_s, @disaster_only.id.to_s], commit_action: "send" }
    end

    assert_equal [["กลุ่มภัยพิบัติ", "สวัสดี"]], fake.sent
    assert_includes flash[:alert], "ทดสอบล้มเหลว"
    assert_equal "ทดสอบล้มเหลว", @line.reload.last_error
  end

  test "webhook sender refuses internal network addresses" do
    channel = NotificationChannel.new(organization_key: "x", name: "hook", kind: "webhook", target: "http://127.0.0.1:27017/")
    error = assert_raises(Notifications::Senders::DeliveryError) do
      Notifications::Senders::Webhook.new(channel, NotificationSetting.new).deliver("hi", tag: "announcement")
    end
    assert_includes error.message, "ภายในเครือข่าย"
  end

  test "LINE webhook checks the signature, records the group and replies with its ID" do
    assert_equal "/line/webhooks", line_webhook_path

    setting = NotificationSetting.current
    setting.assign_line_channel_secret("line-secret")
    setting.save!
    body = { events: [{ type: "join", replyToken: "reply-1", source: { type: "group", groupId: LINE_GROUP } }] }.to_json

    post line_webhook_path, params: body, headers: { "Content-Type" => "application/json", "X-Line-Signature" => "bad" }
    assert_response :unauthorized
    rejected = LineWebhookLog.newest_first.first
    assert_equal "invalid_signature", rejected.status
    assert_not rejected.signature_valid?

    replies = []
    client = Object.new
    client.define_singleton_method(:group_summary) { |_id| { "groupName" => "เวร อบต." } }
    client.define_singleton_method(:reply) { |token, text| replies << [token, text] }
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "line-secret", body))
    Notifications::Senders::Line.stub(:client, client) do
      post line_webhook_path, params: body, headers: { "Content-Type" => "application/json", "X-Line-Signature" => signature }
    end

    assert_response :success
    group = LineGroup.find_by(group_id: LINE_GROUP)
    assert_equal "เวร อบต.", group.group_name
    assert_equal "reply-1", replies.first.first
    assert_includes replies.first.last, LINE_GROUP
    log = LineWebhookLog.where(status: "accepted").first
    assert_equal ["join"], log.event_types
    assert_equal [LINE_GROUP], log.group_ids
    assert_equal "join", log.payload.dig("events", 0, "type")
  end

  test "LINE webhook log page is restricted to system admins" do
    LineWebhookLog.create!(received_at: Time.current, status: "accepted", signature_valid: true,
      event_types: ["join"], group_ids: [LINE_GROUP], payload: { "events" => [{ "type" => "join" }] })

    get admin_webhook_path
    assert_redirected_to root_path

    admin = User.create!(username: "webhook_system_admin", password: "Password123!", role: :system_admin)
    sign_in admin
    get admin_webhook_path
    assert_response :success
    assert_includes response.body, LINE_GROUP
    assert_includes response.body, "LINE Webhook Log"
  ensure
    admin&.destroy
  end

  test "citizen LINE webhook uses its own secret and audit account" do
    setting = OrganizationSetting.for(@admin)
    setting.assign_citizen_line_channel_secret("citizen-secret")
    setting.save!
    body = { events: [{ type: "follow", source: { type: "user", userId: "U#{'c' * 32}" } }] }.to_json
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "citizen-secret", body))

    post citizen_line_webhook_path(organization_key: @admin.organization_key), params: body,
      headers: { "Content-Type" => "application/json", "X-Line-Signature" => signature }

    assert_response :success
    log = LineWebhookLog.where(account_key: "citizen", organization_key: @admin.organization_key, status: "accepted").first
    assert_equal ["follow"], log.event_types

    other_setting = OrganizationSetting.for(@other)
    other_setting.assign_citizen_line_channel_secret("other-secret")
    other_setting.save!
    post citizen_line_webhook_path(organization_key: @other.organization_key), params: body,
      headers: { "Content-Type" => "application/json", "X-Line-Signature" => signature }
    assert_response :unauthorized
  end

  test "central settings are system-admin only and never render saved tokens" do
    get notification_settings_path
    assert_redirected_to notification_channels_path

    admin = User.create!(username: "notify_system_admin", password: "Password123!", role: :system_admin)
    sign_in admin
    patch notification_settings_path, params: { notification_setting: { line_channel_access_token: "line-token-abcd1234", public_base_url: "https://tambon.test" } }
    assert_redirected_to notification_settings_path
    assert_equal "line-token-abcd1234", NotificationSetting.current.secret("line_channel_access_token")

    get notification_settings_path
    assert_not_includes response.body, "line-token-abcd1234"
    assert_includes response.body, "https://tambon.test/line/webhooks"
  ensure
    admin&.destroy
  end

  private

  def create_incident(**attributes) = build_incident(**attributes).tap(&:save!)

  def build_incident(**attributes)
    Incident.new({ title: "เหตุทดสอบ", category: "general", status: "pending", severity: "general", incident_type: "อื่น ๆ",
                       incident_type_other: "ทดสอบ", owner_user_id: @admin.id, user_id: @admin.id, subdistrict_id: @first.id }.merge(attributes))
  end

  def create_subdistrict(code, name, longitude)
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    points = [[longitude, 14.0], [longitude + 0.1, 14.0], [longitude + 0.1, 14.1],
              [longitude, 14.1], [longitude, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    boundary = factory.multi_polygon([factory.polygon(factory.linear_ring(points))])
    @province.subdistricts.create!(code: code, name_th: name, boundary: boundary)
  end
end
