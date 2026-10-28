require "test_helper"
require_relative "../support/object_store_stub"

class ImageLibraryTest < ActiveSupport::TestCase
  include ObjectStoreStub

  setup do
    LibraryImage.delete_all
    stub_object_store
  end

  teardown do
    LibraryImage.delete_all
    Project.where(name: "โครงการทดสอบคลังภาพ").delete_all
    restore_object_store
  end

  test "converts uploads to capped WebP with a thumbnail" do
    image = ImageLibrary.import!(upload: png_upload("ถนน.png"), owner_user_id: 1, subdistrict_id: 10, uploaded_by: "tester")

    assert_equal "ถนน", image.title
    assert_equal [ImageLibrary::MAX_DIMENSION, 1024], [image.width, image.height]
    assert_equal "image/webp", image.image["content_type"]
    full = Vips::Image.new_from_buffer(@stored_objects.fetch(image.image["key"]), "")
    thumb = Vips::Image.new_from_buffer(@stored_objects.fetch(image.thumbnail["key"]), "")
    assert_equal ImageLibrary::MAX_DIMENSION, full.width
    assert_equal ImageLibrary::THUMB_DIMENSION, thumb.width
    assert_operator image.image["byte_size"], :<, image.original_byte_size
  end

  test "reuses the existing picture when the same file is uploaded again in the same area" do
    first = ImageLibrary.import!(upload: png_upload, owner_user_id: 1, subdistrict_id: 10)
    again = ImageLibrary.import!(upload: png_upload("copy.png"), owner_user_id: 1, subdistrict_id: 10)

    assert_equal first.id, again.id
    assert_equal 1, LibraryImage.count
  end

  test "rejects files that are not images and broken images" do
    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", true, original_filename: "doc.png")
    assert_raises(ImageLibrary::InvalidUpload) { ImageLibrary.import!(upload: pdf, owner_user_id: 1, subdistrict_id: 10) }

    broken = Rack::Test::UploadedFile.new(StringIO.new("\x89PNG\r\n\x1A\n".b + ("\x00" * 64)), "image/png", true, original_filename: "x.png")
    error = assert_raises(ImageLibrary::InvalidUpload) { ImageLibrary.import!(upload: broken, owner_user_id: 1, subdistrict_id: 10) }
    assert_match "เปิดไฟล์ภาพไม่ได้", error.message
    assert_empty @stored_objects
  end

  test "attachments reference the library and removing them keeps the picture" do
    image = ImageLibrary.import!(upload: png_upload, owner_user_id: 1, subdistrict_id: 10)
    project = Project.create!(user_id: 1, subdistrict_id: 10, name: "โครงการทดสอบคลังภาพ", group: "infrastructure",
                              project_type: "ถนน", agency: "อบต.", fiscal_year: 2570)

    ProjectPhotoUploadService.attach!(project:, uploads: [], picked: [image, image])
    assert_equal [image.id.to_s], project.reload.photos.map { |photo| photo["library_image_id"] }
    assert_equal [{ kind: "โครงการ", label: project.name }], image.usages

    ProjectPhotoUploadService.remove!(project:, photo_ids: [image.id.to_s])
    assert_empty project.reload.photos
    assert @stored_objects.key?(image.image["key"])
    assert_not image.in_use?
  end

  test "backfill moves legacy attachments into the library" do
    @stored_objects["projects/legacy/a.png"] = png_upload.read
    project = Project.create!(user_id: 1, subdistrict_id: 10, name: "โครงการทดสอบคลังภาพ", group: "infrastructure",
                              project_type: "ถนน", agency: "อบต.", fiscal_year: 2570,
                              photos: [{ "id" => "legacy-1", "key" => "projects/legacy/a.png", "filename" => "a.png", "content_type" => "image/png" }])

    result = ImageLibraryBackfill.new.call

    assert_equal 1, result.converted
    photo = project.reload.photos.first
    assert photo["library_image_id"].present?
    assert photo["thumbnail_key"].present?
    assert_not @stored_objects.key?("projects/legacy/a.png")
    assert_equal 0, ImageLibraryBackfill.new.call.converted
  end
end
