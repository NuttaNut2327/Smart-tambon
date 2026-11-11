require "test_helper"
require "minitest/mock"

class CitizenLineNotificationJobTest < ActiveJob::TestCase
  setup do
    CitizenLineDelivery.delete_all
    CitizenIncidentFollower.delete_all
    @incident = Incident.create!(title: "ไฟถนนดับ", category: "general", status: "pending", severity: "general",
      reporter_line_user_id: "U#{'a' * 32}", reporter_line_display_name: "ผู้แจ้งทดสอบ",
      reporter_line_verified_at: Time.current, line_notification_enabled: true)
  end

  teardown do
    CitizenLineDelivery.delete_all
    CitizenIncidentFollower.delete_all
    NotificationTemplate.where(organization_key: "test").delete_all
    @incident&.destroy
  end

  test "sends updates to followers once without exposing the original reporter" do
    calls = []
    client = Object.new
    client.define_singleton_method(:push) { |user_id, text| calls << [user_id, text]; true }
    setting = OrganizationSetting.new(organization_key: "test", citizen_line_enabled: true)
    setting.assign_citizen_line_channel_access_token("token")
    @incident.set(reporter_name: "ชื่อผู้แจ้งเดิม", reporter_contact: "0812345678")
    follower = CitizenIncidentFollower.create!(incident_id: @incident.id, line_user_id: "U#{'b' * 32}", line_display_name: "ผู้ติดตาม")

    OrganizationSetting.stub(:for, setting) do
      CitizenLine::Client.stub(:new, client) do
        CitizenLineNotificationJob.perform_now(@incident.id.to_s, "acknowledged")
        CitizenLineNotificationJob.perform_now(@incident.id.to_s, "acknowledged")
      end
    end

    assert_equal [@incident.reporter_line_user_id, follower.line_user_id], calls.map(&:first)
    follower_message = calls.find { |user_id, _text| user_id == follower.line_user_id }.last
    assert_not_includes follower_message, "ชื่อผู้แจ้งเดิม"
    assert_not_includes follower_message, "0812345678"
    assert_includes follower.reload.notified_events, "acknowledged"
  end

  test "sends each citizen status only once" do
    calls = []
    client = Object.new
    client.define_singleton_method(:push) { |user_id, text| calls << [user_id, text]; true }
    setting = OrganizationSetting.new(organization_key: "test", citizen_line_enabled: true)
    setting.assign_citizen_line_channel_access_token("token")

    OrganizationSetting.stub(:for, setting) do
      CitizenLine::Client.stub(:new, client) do
        CitizenLineNotificationJob.perform_now(@incident.id.to_s, "submitted")
        CitizenLineNotificationJob.perform_now(@incident.id.to_s, "submitted")
      end
    end

    assert_equal 1, calls.size
    assert_equal @incident.reporter_line_user_id, calls.first.first
    delivery = CitizenLineDelivery.find_by(incident_id: @incident.id, event: "submitted")
    assert_equal "sent", delivery.status
    assert_match @incident.reference_code, delivery.message
  end

  test "uses the organization's editable status template" do
    calls = []
    client = Object.new
    client.define_singleton_method(:push) { |_user_id, text| calls << text; true }
    setting = OrganizationSetting.new(organization_key: "test", organization_name: "อบต. ทดสอบ", citizen_line_enabled: true)
    setting.assign_citizen_line_channel_access_token("token")
    @incident.set(description: "หลอดไฟเสียสองจุด", incident_type: "ไฟฟ้าขัดข้อง", reporter_name: "สมชาย",
      reporter_contact: "0812345678", initial_impact: "ถนนมืด")
    NotificationTemplate.create!(organization_key: "test", name: "รับเรื่องประชาชน", tag: "citizen.acknowledged",
      body: "{{organization_name}} รับเรื่อง {{reference_code}}: {{title}} แล้ว\nระดับ: {{severity}}\n{{description}}\nผู้แจ้ง: {{reporter_name}} {{reporter_contact}}\nผลกระทบ: {{initial_impact}}")

    OrganizationSetting.stub(:for, setting) do
      CitizenLine::Client.stub(:new, client) do
        CitizenLineNotificationJob.perform_now(@incident.id.to_s, "acknowledged")
      end
    end

    assert_equal ["อบต. ทดสอบ รับเรื่อง #{@incident.reference_code}: ไฟถนนดับ แล้ว\nระดับ: ทั่วไป\nหลอดไฟเสียสองจุด\nผู้แจ้ง: สมชาย 0812345678\nผลกระทบ: ถนนมืด"], calls
  end
end
