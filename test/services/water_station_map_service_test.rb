require "test_helper"

class WaterStationMapServiceTest < ActiveSupport::TestCase
  setup do
    @factory = RGeo::Geographic.spherical_factory(srid: 4326)
  end

  test "merges the same physical station and prefers fresh DWR readings" do
    dwr = create_station(source: "dwr", source_id: "dwr-1", code: "TA100", longitude: 100.5,
      water_level: 2.4, rainfall: 8.0, observed_at: 10.minutes.ago)
    thaiwater = create_station(source: "thaiwater", source_id: "tw-1", code: "G01-TA100", longitude: 100.5,
      water_level: 2.2, rainfall: 7.0, observed_at: 5.minutes.ago)

    result = WaterStationMapService.call(WaterStation.where(id: [dwr.id, thaiwater.id]))

    assert_equal 1, result.size
    assert_equal 2.4, result.first[:water_level_m_msl]
    assert_equal 8.0, result.first[:rainfall_value]
    assert_equal %w[dwr thaiwater], result.first[:sources]
    assert_equal 2, result.first[:duplicate_count]
  end

  test "uses a fresh ThaiWater reading when the DWR reading is stale" do
    dwr = create_station(source: "dwr", source_id: "dwr-2", code: "TA200", longitude: 100.6,
      rainfall: 20.0, observed_at: 2.hours.ago)
    thaiwater = create_station(source: "thaiwater", source_id: "tw-2", code: "TA200", longitude: 100.6,
      rainfall: 4.0, observed_at: 10.minutes.ago)

    result = WaterStationMapService.call(WaterStation.where(id: [dwr.id, thaiwater.id])).first

    assert_equal 4.0, result[:rainfall_value]
    assert_equal "thaiwater", result[:rainfall_source]
  end

  test "does not rewrite an unchanged reading and accepts a newer observation" do
    observed_at = 10.minutes.ago.change(usec: 0)
    station = create_station(source: "dwr", source_id: "dwr-3", code: "TA300", longitude: 100.7,
      rainfall: 5.0, observed_at:)
    original_updated_at = station.latest_reading.updated_at

    unchanged = WaterStationReadingUpdater.call(station:, attributes: {
      rainfall_value: 5.0, rainfall_observed_at: observed_at, rainfall_source: "dwr"
    })
    assert_not unchanged
    assert_equal original_updated_at, station.latest_reading.reload.updated_at

    newer_at = observed_at + 15.minutes
    changed = WaterStationReadingUpdater.call(station:, attributes: {
      rainfall_value: 7.5, rainfall_observed_at: newer_at, rainfall_source: "dwr"
    })
    assert changed
    assert_equal 7.5, station.latest_reading.reload.rainfall_value
    assert_equal newer_at, station.latest_reading.rainfall_observed_at
  end

  private

  def create_station(source:, source_id:, code:, longitude:, rainfall:, observed_at:, water_level: nil)
    station = WaterStation.create!(
      station_id: "#{source}:#{source_id}", source:, source_station_id: source_id,
      station_code: code, station_name_th: "สถานีทดสอบ", agency: "DWR",
      canonical_station_key: WaterStationCanonicalizer.key(agency: "DWR", code:, name: "สถานีทดสอบ", longitude:, latitude: 13.7),
      location: @factory.point(longitude, 13.7)
    )
    station.create_latest_reading!(
      water_level_m_msl: water_level, water_level_observed_at: water_level && observed_at,
      water_level_source: water_level && source, rainfall_value: rainfall,
      rainfall_observed_at: observed_at, rainfall_source: source, source_observed_at: observed_at
    )
    station
  end
end
