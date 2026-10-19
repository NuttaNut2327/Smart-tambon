require "test_helper"
require "minitest/mock"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @province = Province.create!(code: "U99", name_th: "จังหวัดทดสอบผู้ใช้")
    @first_subdistrict = create_subdistrict("U9901", "ตำบลหนึ่ง", 100.0)
    @second_subdistrict = create_subdistrict("U9902", "ตำบลสอง", 100.2)
    @admin = create_user("local_admin", :subdistrict_admin, @first_subdistrict)
    @same_area_user = create_user("local_staff", :subdistrict_user, @first_subdistrict)
    @other_area_user = create_user("other_staff", :subdistrict_user, @second_subdistrict)
    UserAccessAreaService.new(user: @admin, name: "อบต.ตำบลหนึ่ง",
      subdistrict_ids: [@first_subdistrict.id], boundary_file: nil).save!
    sign_in @admin
  end

  teardown do
    [@same_area_user, @other_area_user, @admin].each { |user| user&.destroy }
    @created_user&.destroy
    @system_admin&.destroy
    @province&.destroy
  end

  test "local admin sees only users in the same organization" do
    get users_path

    assert_response :success
    assert_includes response.body, @same_area_user.username
    assert_not_includes response.body, @other_area_user.username
  end

  test "local admin creates another local account using the same access area" do
    assert_difference("User.count", 1) do
      post users_path, params: { user: {
        username: "additional_admin", password: "Password123!",
        password_confirmation: "Password123!", role: "subdistrict_admin"
      } }
    end

    @created_user = User.find_by!(username: "additional_admin")
    assert_redirected_to users_path
    assert @created_user.subdistrict_admin?
    assert_equal @first_subdistrict.id, @created_user.subdistrict_id
    assert_equal @admin.access_area.subdistrict_ids, @created_user.access_area.subdistrict_ids
  end

  test "local admin cannot create a system administrator" do
    post users_path, params: { user: {
      username: "restricted_role", password: "Password123!",
      password_confirmation: "Password123!", role: "system_admin"
    } }

    @created_user = User.find_by!(username: "restricted_role")
    assert @created_user.subdistrict_user?
    assert_equal @first_subdistrict.id, @created_user.subdistrict_id
  end

  test "local admin cannot edit an account from another organization" do
    get edit_user_path(@other_area_user)

    assert_response :not_found
  end

  test "system admin starts the first environmental sync for a new organization" do
    sign_out @admin
    @system_admin = User.create!(username: "system_admin", email: "system_admin@example.test",
      password: "Password123!", role: :system_admin)
    sign_in @system_admin
    synced_codes = []

    EnvironmentalSnapshotService.stub(:sync_missing, ->(areas) { synced_codes = areas.map(&:code) }) do
      post users_path, params: {
        user: { username: "new_area_admin", password: "Password123!",
                password_confirmation: "Password123!", role: "subdistrict_admin" },
        access_area_mode: "subdistricts",
        access_area: { name: "อบต.พื้นที่ใหม่", organization_type: "subdistrict_administrative_organization",
                       selected_subdistrict_count: "1", subdistrict_ids: [@second_subdistrict.id] }
      }
    end

    @created_user = User.find_by!(username: "new_area_admin")
    assert_redirected_to users_path
    assert_equal [@second_subdistrict.code], synced_codes
  end

  private

  def create_user(username, role, subdistrict)
    User.create!(username: username, email: "#{username}@example.test",
      password: "Password123!", role: role, subdistrict: subdistrict)
  end

  def create_subdistrict(code, name, longitude)
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    points = [[longitude, 14.0], [longitude + 0.1, 14.0], [longitude + 0.1, 14.1],
              [longitude, 14.1], [longitude, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    boundary = factory.multi_polygon([factory.polygon(factory.linear_ring(points))])
    @province.subdistricts.create!(code: code, name_th: name, boundary: boundary)
  end
end
