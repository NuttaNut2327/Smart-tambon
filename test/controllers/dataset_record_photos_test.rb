require "test_helper"
require_relative "../support/object_store_stub"

class DatasetRecordPhotosTest < ActionDispatch::IntegrationTest
  include ObjectStoreStub

  setup do
    DatasetRecordPhoto.delete_all
    LibraryImage.delete_all
    @owner = User.create!(username: "photo_owner", email: "photo_owner@example.test", password: "Password123!", role: :system_admin)
    @province = Province.create!(code: "P98", name_th: "จังหวัดทดสอบภาพ")
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    ring = [[100.0, 14.0], [100.1, 14.0], [100.1, 14.1], [100.0, 14.1], [100.0, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    subdistrict = @province.subdistricts.create!(code: "P9801", name_th: "ตำบลทดสอบภาพ",
      boundary: factory.multi_polygon([factory.polygon(factory.linear_ring(ring))]))
    @viewer = User.create!(username: "photo_viewer", email: "photo_viewer@example.test", password: "Password123!",
      role: :subdistrict_user, subdistrict:)
    @dataset = ImportedDataset.create!(user: @owner, name: "ทรัพยากร", data_type: "resources", geometry_type: "none",
      schema_definition: ImportedDataset.schema_for("resources"))
    version = DatasetVersionImportService.new(dataset: @dataset, user: @owner,
      manual_records: [{ code: "R-1", name: "รถดับเพลิง", resource_type: "ยานพาหนะ", status: "พร้อมใช้", responsible_person: "อบต.ทดสอบ", agency_code: "AG-1" }]).import!
    @record_id = version.records.first["record_id"]
  end

  teardown do
    DatasetRecordPhoto.delete_all
    LibraryImage.delete_all
    [@owner, @viewer].each { |user| user&.destroy }
    @province&.destroy
  end

  def image_upload(name = "photo.png") = png_upload(name, width: 640, height: 480)

  def stub_storage
    stub_object_store
    yield
  ensure
    restore_object_store
  end

  test "editor attaches a photo through the image library and removes it" do
    sign_in @owner
    stub_storage do
      post imported_dataset_record_photos_path(@dataset, @record_id), params: { photos: [image_upload] }
      assert_response :created
      photo = DatasetRecordPhoto.for_record(@dataset.id, @record_id).first
      library_image = LibraryImage.find(photo.library_image_id)
      assert_equal "dataset_record", library_image.source
      assert_equal library_image.thumbnail["key"], photo.thumbnail["key"]
      assert_equal 1, response.parsed_body["photos"].size

      delete imported_dataset_record_photo_path(@dataset, @record_id, photo), as: :json
      assert_response :success
      assert_equal 0, DatasetRecordPhoto.count
      assert LibraryImage.where(id: library_image.id).exists?, "removing the photo keeps the library picture"
    end
  end

  test "editor attaches a picture picked from the library" do
    sign_in @owner
    stub_storage do
      picked = ImageLibrary.import!(upload: image_upload, owner_user_id: @owner.id, subdistrict_id: nil)
      post imported_dataset_record_photos_path(@dataset, @record_id), params: { library_image_ids: [picked.id.to_s] }
      assert_response :created
      assert_equal picked.id.to_s, DatasetRecordPhoto.for_record(@dataset.id, @record_id).first.library_image_id
    end
  end

  test "rejects uploads for rows that do not exist and beyond the per-row limit" do
    sign_in @owner
    stub_storage do
      post imported_dataset_record_photos_path(@dataset, "missing"), params: { photos: [image_upload] }
      assert_response :not_found

      DatasetRecordPhoto::MAX_PER_RECORD.times { DatasetRecordPhoto.create!(imported_dataset_id: @dataset.id, record_id: @record_id, image: { "key" => "x" }) }
      post imported_dataset_record_photos_path(@dataset, @record_id), params: { photos: [image_upload] }
      assert_response :unprocessable_entity
    end
  end

  test "photos survive editing the row" do
    DatasetRecordPhoto.create!(imported_dataset_id: @dataset.id, record_id: @record_id, image: { "key" => "x" })
    sign_in @owner
    patch imported_dataset_record_path(@dataset, 0), params: { record: { code: "R-1", name: "รถดับเพลิงคันใหม่", resource_type: "ยานพาหนะ", status: "พร้อมใช้", responsible_person: "อบต.ทดสอบ", agency_code: "AG-1" } }, as: :json
    assert_response :success
    assert_equal @record_id, @dataset.reload.current_version.records.first["record_id"]
    assert_equal 1, DatasetRecordPhoto.for_record(@dataset.id, @record_id).count
  end

  test "users outside the dataset's organization cannot see or upload photos" do
    sign_in @viewer
    post imported_dataset_record_photos_path(@dataset, @record_id), params: { photos: [image_upload] }
    assert_response :not_found
  end
end
