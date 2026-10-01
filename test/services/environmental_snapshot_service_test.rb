require "test_helper"

class EnvironmentalSnapshotServiceTest < ActiveSupport::TestCase
  test "ThaiWater station temperature overrides the Open-Meteo fallback" do
    snapshot = EnvironmentalSnapshot.new(subdistrict_code: "140101")
    open_meteo = {
      "current" => { "temperature_2m" => 31.0, "time" => "2026-10-01T13:00" },
      "hourly" => { "precipitation" => Array.new(24, 0.0) }
    }
    thaiwater = {
      "temperature" => 33.2, "temperature_datetime" => "2026-10-01 13:00",
      "station" => { "id" => 123, "tele_station_name" => { "th" => "สถานีทดสอบ" } },
      "agency" => { "agency_name" => { "th" => "หน่วยงานทดสอบ" } }
    }

    EnvironmentalSnapshotService.send(:apply_weather, snapshot, open_meteo)
    assert_equal "open_meteo", snapshot.temperature_source

    EnvironmentalSnapshotService.send(:apply_thaiwater_temperature, snapshot, thaiwater)
    assert_equal 33.2, snapshot.temperature_c
    assert_equal "thaiwater", snapshot.temperature_source
    assert_equal "สถานีทดสอบ", snapshot.temperature_station_name
    assert_equal "หน่วยงานทดสอบ", snapshot.temperature_station_agency
  end

  test "keeps Open-Meteo when no ThaiWater station is available" do
    snapshot = EnvironmentalSnapshot.new(subdistrict_code: "140101")
    payload = {
      "current" => { "temperature_2m" => 30.5, "time" => "2026-10-01T13:00" },
      "hourly" => { "precipitation" => Array.new(24, 0.0) }
    }

    EnvironmentalSnapshotService.send(:apply_weather, snapshot, payload)
    EnvironmentalSnapshotService.send(:apply_thaiwater_temperature, snapshot, nil)

    assert_equal 30.5, snapshot.temperature_c
    assert_equal "open_meteo", snapshot.temperature_source
    assert_equal "ข้อมูลประมาณการจากแบบจำลอง Open-Meteo", snapshot.temperature_source_label
  end
end
