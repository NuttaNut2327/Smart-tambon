require "test_helper"

class ApiAreaScopingTest < ActionDispatch::IntegrationTest
  setup do
    @province = Province.create!(code: "A98", name_th: "จังหวัดขอบเขตทดสอบ")
    @first = create_subdistrict("A9801", "ตำบลแรก", 100.0)
    @second = create_subdistrict("A9802", "ตำบลที่สอง", 100.2)
    @admin = User.create!(username: "area_scope_admin", email: "area_scope_admin@example.test",
      password: "Password123!", role: :subdistrict_admin, subdistrict: @first)
    @owner = User.create!(username: "poi_owner", email: "poi_owner@example.test",
      password: "Password123!", role: :system_admin)
    UserAccessAreaService.new(user: @admin, name: "พื้นที่สองตำบล",
      subdistrict_ids: [@first.id, @second.id], boundary_file: nil).save!
    sign_in @admin
  end

  teardown do
    DynamicLayer.where(:name.in => ["POI แรก", "POI สอง", "POI นอกพื้นที่"]).delete_all
    WaterStation.where(:station_id.in => %w[AREA-1 AREA-2 AREA-OUT]).delete_all
    LongdoPlaceCache.where(category: "government").delete_all
    @admin&.destroy
    @owner&.destroy
    @province&.destroy
  end

  test "subdistrict admin receives imported POI across every assigned subdistrict" do
    create_poi("POI แรก", 100.05, 14.05, @first.id)
    create_poi("POI สอง", 100.25, 14.05, @second.id)
    create_poi("POI นอกพื้นที่", 101.05, 15.05, nil)

    get api_dynamic_layers_path, params: { layer_key: "important_place" }

    assert_response :success
    assert_equal ["POI สอง", "POI แรก"], response.parsed_body.map { |item| item["name"] }.sort
  end

  test "subdistrict admin receives water stations across every assigned subdistrict" do
    create_station("AREA-1", 100.05, 14.05)
    create_station("AREA-2", 100.25, 14.05)
    create_station("AREA-OUT", 101.05, 15.05)

    get api_water_stations_path

    assert_response :success
    assert_equal %w[AREA-1 AREA-2], response.parsed_body.map { |item| item["id"] }.sort
  end

  test "subdistrict admin receives cached Longdo POI inside the complete access boundary" do
    area = @admin.access_area
    LongdoPlaceCache.create!(query_key: "access_area:#{area.id}:#{area.updated_at.to_i}:government",
      category: "government", span: "30km", expires_at: 1.hour.from_now,
      places: [
        { "name" => "Longdo ตำบลแรก", "lon" => 100.05, "lat" => 14.05 },
        { "name" => "Longdo ตำบลสอง", "lon" => 100.25, "lat" => 14.05 },
        { "name" => "Longdo นอกพื้นที่", "lon" => 101.05, "lat" => 15.05 }
      ], response_meta: { "tags" => %w[government municipality] })

    get api_places_path, params: { category: "government" }

    assert_response :success
    assert_equal ["Longdo ตำบลสอง", "Longdo ตำบลแรก"],
      response.parsed_body.fetch("data").map { |item| item["name"] }.sort
  end

  private

  def create_subdistrict(code, name, longitude)
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    points = [[longitude, 14.0], [longitude + 0.1, 14.0], [longitude + 0.1, 14.1],
              [longitude, 14.1], [longitude, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    boundary = factory.multi_polygon([factory.polygon(factory.linear_ring(points))])
    @province.subdistricts.create!(code: code, name_th: name, boundary: boundary)
  end

  def create_poi(name, longitude, latitude, subdistrict_id)
    DynamicLayer.create!(layer_key: "important_place", name: name, location: [longitude, latitude],
      subdistrict_id: subdistrict_id, owner_user_id: @owner.id, shared_with_all: false,
      payload: { source: "upload" })
  end

  def create_station(id, longitude, latitude)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    WaterStation.create!(station_id: id, station_code: id, station_name_th: id,
      location: factory.point(longitude, latitude))
  end
end
