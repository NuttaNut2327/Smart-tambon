require "test_helper"

class BroadcastsPublisherTest < ActiveSupport::TestCase
  ORG = "subdistrict:test-publisher".freeze

  setup do
    [Broadcast, BroadcastProgram, NotificationChannel].each { |model| model.where(organization_key: ORG).delete_all }
    Announcement.where(target_organization_key: ORG).each(&:destroy)
    @pa = NotificationChannel.create!(organization_key: ORG, name: "หอกระจายข่าว ม.1", kind: "pa_mqtt", target: "smart-tambon/pa/test", tags: ["broadcast"])
    @line = NotificationChannel.create!(organization_key: ORG, name: "กลุ่ม LINE อบต.", kind: "line", target: "C#{'a' * 32}", tags: ["broadcast"])
  end

  def broadcast(**attributes)
    Broadcast.create!(organization_key: ORG, title: "เตือนฝนหนัก", bullets: ["ฝนหนักพรุ่งนี้"], script: "ขอให้เตรียมรับมือ", status: "draft", **attributes)
  end

  test "programmes keep several delivery modes and drop unknown ones" do
    program = BroadcastProgram.new(organization_key: ORG, name: "ข่าวเช้า", delivery_modes: ["pa", "internal", "", "sms"])
    assert program.valid?
    assert_equal %w[pa internal], program.delivery_modes
  end

  test "records saved before modes existed derive them from their channels" do
    program = BroadcastProgram.new(organization_key: ORG, name: "ข่าวเก่า", channel_ids: [@line.id])
    assert_equal %w[notification], program.delivery_modes
  end

  test "only channels of the active modes are used" do
    record = broadcast(channel_ids: [@pa.id, @line.id], delivery_modes: %w[notification])
    assert_equal [@line.id], record.channels.map(&:id)
  end

  test "internal alert creates an announcement for the organisation's staff only" do
    record = broadcast(delivery_modes: %w[internal], internal_alert_level: "urgent", internal_alert_hours: 6)
    Broadcasts::Publisher.call(record)

    announcement = Announcement.find_by(broadcast_id: record.id)
    assert_equal "เตือนฝนหนัก", announcement.title
    assert_equal "urgent", announcement.level
    assert_in_delta 6.hours.from_now, announcement.ends_at, 5
    assert announcement.targets?(User.new(organization_key: ORG, role: :subdistrict_user))
    refute announcement.targets?(User.new(organization_key: "subdistrict:other", role: :subdistrict_user))
    refute Announcement.managed_by_admins.where(id: announcement.id).exists?

    record.reload
    assert_equal "published", record.status
    assert_equal [["internal_alert", "sent"]], record.deliveries.map { |entry| [entry["kind"], entry["status"]] }
  end

  test "publishing again refreshes the same alert and shows it again" do
    record = broadcast(delivery_modes: %w[internal])
    Broadcasts::Publisher.call(record)
    announcement = Announcement.find_by(broadcast_id: record.id)
    AnnouncementReceipt.create!(announcement:, user_id: 1, acknowledged_at: Time.current)

    Broadcasts::Publisher.call(record.reload)
    assert_equal 1, Announcement.where(broadcast_id: record.id).count
    assert_equal 0, announcement.receipts.count
  end

  test "nothing selected is refused" do
    record = broadcast(channel_ids: [@pa.id], delivery_modes: %w[notification])
    error = assert_raises(RuntimeError) { Broadcasts::Publisher.call(record) }
    assert_match "ยังไม่ได้เลือก", error.message
  end
end
