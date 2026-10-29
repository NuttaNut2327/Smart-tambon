require "test_helper"
require_relative "../support/object_store_stub"

class LibraryImagesControllerTest < ActionDispatch::IntegrationTest
  include ObjectStoreStub

  setup do
    LibraryImage.delete_all
    stub_object_store
    @province = Province.create!(code: "P97", name_th: "จังหวัดทดสอบคลังภาพ")
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    ring = [[100.0, 14.0], [100.1, 14.0], [100.1, 14.1], [100.0, 14.1], [100.0, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    polygon = factory.multi_polygon([factory.polygon(factory.linear_ring(ring))])
    @subdistrict = @province.subdistricts.create!(code: "P9701", name_th: "ตำบลคลังภาพ", boundary: polygon)
    @other_subdistrict = @province.subdistricts.create!(code: "P9702", name_th: "ตำบลอื่น", boundary: polygon)
    @admin = User.create!(username: "library_admin", password: "Password123!", role: :subdistrict_admin, subdistrict: @subdistrict)
    @outsider = User.create!(username: "library_outsider", password: "Password123!", role: :subdistrict_admin, subdistrict: @other_subdistrict)
  end

  teardown do
    LibraryImage.delete_all
    Project.where(user_id: @admin&.id).delete_all
    [@admin, @outsider].each { |user| user&.destroy }
    @province&.destroy
    restore_object_store
  end

  test "uploads into the library and lists thumbnails for the organization only" do
    sign_in @admin
    post library_images_path, params: { images: [png_upload("แผนที่.png")] }
    assert_redirected_to library_images_path
    image = LibraryImage.last
    assert_equal [@admin.id, @subdistrict.id], [image.owner_user_id, image.subdistrict_id]

    get library_images_path
    assert_response :success
    assert_select ".image-library-card img[src=?]", library_image_file_path(image, variant: "thumb")

    get library_images_path(format: :json, q: "แผน")
    assert_equal [image.id.to_s], response.parsed_body["images"].map { |item| item["id"] }

    get library_image_file_path(image, variant: "thumb")
    assert_response :success
    assert_equal "image/webp", response.media_type

    sign_out @admin
    sign_in @outsider
    get library_images_path(format: :json)
    assert_empty response.parsed_body["images"]
    get library_image_file_path(image)
    assert_response :not_found
  end

  test "pictures still attached cannot be deleted" do
    image = ImageLibrary.import!(upload: png_upload, owner_user_id: @admin.id, subdistrict_id: @subdistrict.id)
    project = Project.create!(user_id: @admin.id, subdistrict_id: @subdistrict.id, name: "ถนนคลังภาพ", group: "infrastructure",
                              project_type: "ถนน", agency: "อบต.", fiscal_year: 2570, photos: [image.attachment])
    sign_in @admin

    delete library_image_path(image)
    assert LibraryImage.where(id: image.id).exists?
    assert_match "ยังถูกใช้งานอยู่", flash[:alert]

    project.set(photos: [])
    delete library_image_path(image)
    assert_not LibraryImage.where(id: image.id).exists?
    assert_empty @stored_objects
  end

  test "projects attach uploads and picked library pictures" do
    picked = ImageLibrary.import!(upload: png_upload("เดิม.png", width: 800, height: 600), owner_user_id: @admin.id, subdistrict_id: @subdistrict.id)
    sign_in @admin

    post projects_path, params: { project: { name: "ถนนใหม่", group: "infrastructure", project_type: "ถนน", agency: "อบต.",
                                             fiscal_year: 2570, status: "planned", photos: [png_upload("ใหม่.png")],
                                             library_image_ids: [picked.id.to_s] } }
    assert_redirected_to projects_path
    project = Project.where(name: "ถนนใหม่").first
    assert_equal 2, project.photos.size
    assert project.photos.all? { |photo| photo["library_image_id"].present? && photo["thumbnail_key"].present? }
    assert_equal %w[project library], project.photos.map { |photo| LibraryImage.find(photo["library_image_id"]).source }

    get photo_project_path(project, project.photos.first["id"], variant: "thumb")
    assert_response :success
    assert_equal "image/webp", response.media_type
  end
end
