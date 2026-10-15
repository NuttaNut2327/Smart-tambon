require "test_helper"

class FirmsHotspotSyncTest < ActiveSupport::TestCase
  VIIRS_CSV = <<~CSV.freeze
    latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,instrument,confidence,version,bright_ti5,frp,daynight
    18.79512,98.95120,335.2,0.39,0.36,#{Date.current.iso8601},618,N,VIIRS,n,2.0NRT,290.1,4.8,D
    18.79600,98.95200,340.1,0.39,0.36,#{Date.current.iso8601},618,N,VIIRS,h,2.0NRT,291.4,7.2,D
    bad,98.9,1,1,1,#{Date.current.iso8601},618,N,VIIRS,n,2.0NRT,1,1,D
  CSV
  MODIS_CSV = <<~CSV.freeze
    latitude,longitude,brightness,scan,track,acq_date,acq_time,satellite,instrument,confidence,version,bright_t31,frp,daynight
    18.79512,98.95120,320.5,1.0,1.0,#{Date.current.iso8601},1530,Aqua,MODIS,77,6.1NRT,295.0,12.3,N
  CSV

  setup { FireHotspot.delete_all }

  test "upserts VIIRS and MODIS rows and skips malformed ones" do
    responses = { "VIIRS_SNPP_NRT" => VIIRS_CSV, "MODIS_NRT" => MODIS_CSV }
    sync = build_sync(sources: "VIIRS_SNPP_NRT,MODIS_NRT") { |url| responses.fetch(url.split("/")[-3]) }

    result = sync.call
    sync.call

    assert_equal({ "VIIRS_SNPP_NRT" => 2, "MODIS_NRT" => 1, "pruned" => 0 }, result)
    assert_equal 3, FireHotspot.count
    modis = FireHotspot.find_by(source: "MODIS_NRT")
    assert_equal "77", modis.confidence
    assert_equal 320.5, modis.brightness
    assert_equal Time.utc(Date.current.year, Date.current.month, Date.current.day, 15, 30), modis.acquired_at
    assert_in_delta 98.9512, modis.location.x, 0.00001
  end

  test "raises when FIRMS answers with an error message instead of CSV" do
    sync = build_sync { "Invalid MAP_KEY." }
    error = assert_raises(RuntimeError) { sync.call }
    assert_match "Invalid MAP_KEY", error.message
  end

  test "without a map key reads the public regional file and keeps only rows inside the bbox" do
    csv = <<~CSV
      latitude,longitude,bright_ti4,scan,track,acq_date,acq_time,satellite,confidence,version,bright_ti5,frp,daynight
      18.79512,98.95120,335.2,0.39,0.36,#{Date.current.iso8601},0618,N,nominal,2.0NRT,290.1,4.8,D
      -2.71534,150.99426,305.87,0.4,0.37,#{Date.current.iso8601},1537,N,nominal,2.0NRT,293.46,0.98,N
    CSV
    urls = []
    sync = FirmsHotspotSync.new(map_key: "", sources: "VIIRS_SNPP_NRT", fetcher: ->(url) { urls << url; csv })

    assert_equal 1, sync.call["VIIRS_SNPP_NRT"]
    assert_match "/data/active_fire/suomi-npp-viirs-c2/csv/SUOMI_VIIRS_C2_SouthEast_Asia_24h.csv", urls.first
    assert_equal "VIIRS", FireHotspot.sole.instrument
  end

  test "counts the densest cluster within the rule area" do
    build_sync { VIIRS_CSV }.call
    FireHotspot.create!(hotspot_key: "far", source: "VIIRS_SNPP_NRT", acquired_at: 1.hour.ago,
      location: RGeo::Geographic.spherical_factory(srid: 4326).point(99.5, 18.5))
    selection = "POLYGON((98 18, 100 18, 100 19.5, 98 19.5, 98 18))"

    assert_equal 2, FireHotspot.max_cluster_count(selected_wkt: selection, area_sq_km: 5)
    assert_equal 0, FireHotspot.max_cluster_count(selected_wkt: "POLYGON((100 10, 101 10, 101 11, 100 11, 100 10))", area_sq_km: 5)
  end

  private

  def build_sync(sources: "VIIRS_SNPP_NRT", &fetcher)
    FirmsHotspotSync.new(map_key: "test-key", sources:, bbox: "97,5,106,21", day_range: "1", retention_days: "30", fetcher:)
  end
end
