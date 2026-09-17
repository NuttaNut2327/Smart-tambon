require "test_helper"

class UserAccessAreaServiceTest < ActiveSupport::TestCase
  setup do
    @province = Province.create!(code: "T99", name_th: "จังหวัดทดสอบ")
    @first = create_subdistrict("T9901", "ตำบลหนึ่ง", 100.0)
    @second = create_subdistrict("T9902", "ตำบลสอง", 100.2)
    @user = User.create!(username: "multi_area_admin", email: "multi_area_admin@example.test",
      password: "Password123!", role: :subdistrict_admin, subdistrict: @first)
  end

  teardown do
    @user&.destroy
    @province&.destroy
  end

  test "stores every selected subdistrict and returns every boundary in GeoJSON" do
    area = UserAccessAreaService.new(user: @user, name: "สองตำบล",
      subdistrict_ids: [@first.id, @second.id], boundary_file: nil).save!

    assert_equal [@first.id, @second.id].sort, area.reload.subdistrict_ids.map(&:to_i).sort
    assert_equal 2, area.boundary.num_geometries
    assert_equal 2, area.as_geojson.dig(:properties, :subdistrict_count)
    assert_equal 2, area.as_geojson.dig(:geometry, "coordinates").size
  end

  test "rejects a selection when any subdistrict id does not exist" do
    error = assert_raises(ArgumentError) do
      UserAccessAreaService.new(user: @user, name: "ข้อมูลไม่ครบ",
        subdistrict_ids: [@first.id, 99_999_999], boundary_file: nil).save!
    end

    assert_match "ไม่พบตำบลที่เลือก", error.message
  end

  private

  def create_subdistrict(code, name, longitude)
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    points = [[longitude, 14.0], [longitude + 0.1, 14.0], [longitude + 0.1, 14.1],
              [longitude, 14.1], [longitude, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    boundary = factory.multi_polygon([factory.polygon(factory.linear_ring(points))])
    @province.subdistricts.create!(code: code, name_th: name, boundary: boundary)
  end
end
