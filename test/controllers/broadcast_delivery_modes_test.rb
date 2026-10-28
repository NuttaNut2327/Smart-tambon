require "test_helper"

# News "agents" can deliver through several modes at once; the internal alert pops up for the อบต.'s signed-in staff.
class BroadcastDeliveryModesTest < ActionDispatch::IntegrationTest
  setup do
    @province = Province.create!(code: "A97", name_th: "จังหวัดทดสอบการแจ้งเตือน")
    @subdistrict = @province.subdistricts.create!(code: "A9701", name_th: "ทดสอบการแจ้งเตือน")
    @admin = User.create!(username: "delivery_admin", password: "Password123!", role: :subdistrict_admin, subdistrict: @subdistrict)
    @staff = User.create!(username: "delivery_staff", password: "Password123!", role: :subdistrict_user, subdistrict: @subdistrict)
    @line = NotificationChannel.create!(organization_key: @admin.organization_key, name: "กลุ่ม LINE อบต.", kind: "line", target: "C#{'b' * 32}", tags: ["broadcast"])
  end

  teardown do
    Announcement.where(target_organization_key: @admin&.organization_key).each(&:destroy)
    [Broadcast, BroadcastProgram, NotificationChannel].each { |model| model.where(organization_key: @admin&.organization_key).delete_all }
    [@staff, @admin, @subdistrict, @province].each { |record| record&.destroy }
  end

  test "programme form offers the three modes and saves more than one" do
    sign_in @admin
    get new_broadcast_program_path
    assert_response :success
    assert_select ".broadcast-delivery-mode", 3
    assert_select "input#broadcast_program_delivery_pa[checked]"
    assert_select "input#broadcast_program_delivery_internal:not([checked])"
    assert_select "input#broadcast_program_channel_#{@line.id}"

    post broadcast_programs_path, params: { broadcast_program: { name: "ข่าวเตือนภัย", prompt: "เตือนภัย", delivery_modes: ["notification", "internal", ""],
                                                                  channel_ids: [@line.id.to_s, ""], internal_alert_level: "urgent", internal_alert_hours: "12" } }
    program = BroadcastProgram.find_by(organization_key: @admin.organization_key)
    assert_equal %w[notification internal], program.delivery_modes
    assert_equal ["urgent", 12], [program.internal_alert_level, program.internal_alert_hours]

    get broadcasts_path
    assert_select ".broadcast-program-channels", /กลุ่ม LINE อบต\..*แจ้งเตือนภายในระบบ/m
  end

  test "signed-in staff receive the internal alert through the live feed" do
    broadcast = Broadcast.create!(organization_key: @admin.organization_key, title: "เตือนน้ำป่า", bullets: ["ฝนหนักบนดอย"], status: "draft", delivery_modes: %w[internal])
    sign_in @staff
    get feed_announcements_path
    assert_response :no_content

    Broadcasts::Publisher.call(broadcast)
    get feed_announcements_path
    assert_response :success
    assert_select "[data-announcement-modal]", 1
    assert_select "small", /แจ้งเตือนจาก อบต\./
    assert_select "h2", "เตือนน้ำป่า"

    announcement = Announcement.find_by(broadcast_id: broadcast.id)
    get feed_announcements_path, params: { shown: [announcement.id.to_s] }
    assert_response :no_content
  end
end
