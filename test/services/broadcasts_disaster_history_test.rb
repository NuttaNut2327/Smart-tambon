require "test_helper"
require "minitest/mock"

class BroadcastsDisasterHistoryTest < ActiveSupport::TestCase
  class FakeWeather
    def initialize(rain) = @rain = rain
    def admin? = false
    def nearest(lat:, lon:, max_km: nil) = { "id" => 8, "name_th" => "ต.ทดสอบ", "distance_km" => 0.0 }

    def daily_forecast(_id, days:)
      { "run" => { "model" => "ecmwf_ifs025", "run_init_time" => "2026-10-27T18:00:00Z" },
        "days" => @rain.each_with_index.map do |mm, lead|
          { "forecast_date" => (Date.new(2026, 10, 28) + lead).iso8601, "forecast_lead_days" => lead, "precipitation_sum_mm" => mm }
        end }
    end
  end

  setup do
    @now = Time.zone.parse("2026-10-28 06:30 +07:00")
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    ring = [[100.88, 19.11], [100.95, 19.11], [100.95, 19.16], [100.88, 19.16], [100.88, 19.11]].map { |lon, lat| factory.point(lon, lat) }
    @province = Province.create!(code: "H97", name_th: "จังหวัดทดสอบสถิติ")
    @subdistrict = @province.subdistricts.create!(code: "H9701", name_th: "ทดสอบสถิติ", center: factory.point(100.92, 19.13),
      boundary: factory.multi_polygon([factory.polygon(factory.linear_ring(ring))]))
    @user = User.create!(username: "disaster_history_user", email: "disaster_history_user@example.test", password: "Password123!",
      role: :subdistrict_admin, subdistrict: @subdistrict)
    event = ->(hazard, at, rain, moo, simulated: false) do
      DisasterEvent.create!(hazard:, title: "#{hazard} #{at}", subdistrict_id: @subdistrict.id, started_at: Time.zone.parse(at), rain_3d_mm: rain,
                            villages: [moo], severity: 2, affected_households: 12, simulated:)
    end
    event.call("drought", "2023-03-01 09:00", nil, 1)
    event.call("flood", "2025-10-30 03:00", 60.0, 3)
    event.call("flood", "2024-10-29 03:00", 150.0, 5)
    event.call("flood", "2025-12-15 03:00", 80.0, 4)
    DemoData.visible_flag = false
  end

  teardown do
    DisasterEvent.where(subdistrict_id: @subdistrict.id).delete_all
    @user&.destroy
    @subdistrict&.destroy
    @province&.destroy
    DemoData.reset
  end

  def history(rain: [9.4, 40.0, 95.2, nil]) = Broadcasts::HazardOutlook.new(@user, now: @now, weather_client: FakeWeather.new(rain)).disaster_history(years: 5)

  test "lists this week's past events and the places hit after no more rain than forecast" do
    result = history

    assert_equal 135.2, result["rain_next_3_days_mm"]
    assert_equal [2568, 2567], result["past_events_this_week"].map { |row| row["year"] }
    assert_equal "หมู่ 3 ต.ทดสอบสถิติ", result["past_events_this_week"].first["place"]
    assert_equal [{ "hazard" => "น้ำท่วม", "place" => "หมู่ 3 ต.ทดสอบสถิติ", "times" => 1, "years" => [2568] }], result["places_hit_after_similar_rain"]
    flood = result["hazards"].find { |row| row["hazard"] == "น้ำท่วม" }
    assert_equal "สูงมาก", flood["risk"], "135 mm forecast is above the 80 mm median before past floods"
    assert_equal({ "watch" => 60, "median" => 80 }, flood["rain_3d_before_past_events_mm"])
    assert_nil result["demo_data"]
    assert_match "ไม่ใช่การพยากรณ์", result["note"]
  end

  test "dry forecast matches no places and simulated events stay out while demo data is off" do
    DisasterEvent.create!(hazard: "flood", title: "จำลอง", subdistrict_id: @subdistrict.id, started_at: Time.zone.parse("2025-10-29 03:00"),
                          rain_3d_mm: 5.0, villages: [9], severity: 1, simulated: true)
    result = history(rain: [0.0, 0.0, 0.0, 0.0])

    assert_nil result["places_hit_after_similar_rain"]
    assert_equal 2, result["past_events_this_week"].size
    assert_nil result["demo_data"]

    DemoData.visible_flag = true
    result = history(rain: [0.0, 0.0, 0.0, 0.0])
    assert_equal 3, result["past_events_this_week"].size
    assert_match "ข้อมูลจำลอง", result["demo_data"]
  end

  test "alerts come from heavy rain days and high-risk hazards only" do
    assert_nil Broadcasts::Context.alerts({ "weather_forecast" => { "heavy_rain_days" => [] }, "disaster_history" => { "hazards" => [{ "hazard" => "น้ำท่วม", "risk" => "ต่ำ" }] } })
    alerts = Broadcasts::Context.alerts({ "weather_forecast" => { "heavy_rain_days" => [{ "date" => "ศุกร์ 30 ต.ค. 2569", "rain_mm" => 95.2, "rain_level" => "ฝนหนักมาก" }] },
                                          "disaster_history" => { "hazards" => [{ "hazard" => "น้ำท่วม", "risk" => "สูง" }] } })
    assert_equal ["ฝนหนักมาก ศุกร์ 30 ต.ค. 2569 (95.2 มม.)", "น้ำท่วม ความเสี่ยงสูง ตามสถิติย้อนหลัง"], alerts
  end

  test "alert-only programme skips a quiet day without calling the AI or publishing" do
    program = BroadcastProgram.from_template("forecast_alert", organization_key: "test:history")
    program.save!
    broadcast = Broadcasts::Runner.queue(program, trigger: "schedule", slot_key: "2026-10-28 06:30")
    broadcast.set(pending_tasks: %w[generate synthesize publish])
    writer = ->(*) { flunk "writer must not run on a quiet day" }

    Broadcasts::Context.stub(:for, { "today" => "พุธ 28 ต.ค. 2569", "alerts" => nil }) do
      Broadcasts::Writer.stub(:call, writer) { Broadcasts::Runner.new(broadcast, Rails.logger).process }
    end

    broadcast.reload
    assert_equal "skipped", broadcast.status
    assert_empty broadcast.pending_tasks
    assert_match "ไม่มีเรื่องต้องเตือน", broadcast.title
  ensure
    Broadcast.where(broadcast_program_id: program&.id).delete_all
    program&.destroy
  end

  test "templates build valid prevention programmes" do
    BroadcastProgram::TEMPLATES.each_key do |key|
      program = BroadcastProgram.from_template(key, organization_key: "test:history")
      assert program.valid?, program.errors.full_messages.to_sentence
      assert_includes program.data_sources, "disaster_history"
    end
    assert BroadcastProgram.from_template("forecast_alert").alert_only?
    assert_equal ["1"], BroadcastProgram.from_template("weekly_outlook").schedule_days
  end
end
