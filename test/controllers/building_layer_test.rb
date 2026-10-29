require "test_helper"

# Building footprint vector-tile layer: the system admin sets the tile URL, the map page hands it to the browser.
class BuildingLayerTest < ActionDispatch::IntegrationTest
  TILEJSON = "https://map.example.test/data/building-polygon.json".freeze

  setup do
    SystemSetting.delete_all
    @admin = User.create!(username: "building_system_admin", password: "Password123!", role: :system_admin)
    sign_in @admin
  end

  teardown do
    SystemSetting.delete_all
    @admin&.destroy
  end

  test "the system admin saves a TileJSON URL and source layer" do
    patch system_settings_path, params: { system_setting: { system_name: "ระบบทดสอบ", system_short_name: "ทดสอบ", map_basemap: "street",
                                                            map_center_lat: 13.7, map_center_lon: 100.5, map_zoom: 6,
                                                            building_tiles_url: " #{TILEJSON} ", building_tiles_layer: "building-polygon",
                                                            map_layers: %w[cctv buildings] } }
    assert_redirected_to system_settings_path

    setting = SystemSetting.current
    assert_equal({ url: TILEJSON, layer: "building-polygon" }, setting.building_tiles)
    assert_includes setting.map_layers, "buildings"
  end

  test "tile URLs must be http(s); {z}/{x}/{y} templates are accepted" do
    setting = SystemSetting.current
    setting.building_tiles_url = "https://tiles.example.test/building/{z}/{x}/{y}.pbf"
    assert setting.valid?, setting.errors.full_messages.to_sentence

    setting.building_tiles_url = "javascript:alert(1)"
    assert_not setting.valid?
    assert setting.errors[:building_tiles_url].any?
  end

  test "the layer is off until a tile URL is configured, then the map gets it" do
    assert_nil SystemSetting.current.building_tiles
    assert_not_includes SystemSetting.new.map_layers, "buildings", "buildings are not on by default"

    get area_analysis_path
    assert_response :success
    assert_select "input[data-building-layer-toggle][disabled]"
    assert_includes response.body, "ยังไม่ได้ตั้งค่า URL"

    SystemSetting.current.update!(building_tiles_url: TILEJSON, map_layers: %w[buildings])
    get area_analysis_path
    assert_select "input[data-building-layer-toggle][checked]:not([disabled])"
    shell = css_select(".dashboard-shell").first
    assert_equal TILEJSON, JSON.parse(shell["data-building-tiles"])["url"]
  end
end
