require "test_helper"

class IncidentPhotoUploadServiceTest < ActiveSupport::TestCase
  test "accepts supported image uploads" do
    upload = uploaded_file("photo.jpg", "image/jpeg", "\xFF\xD8\xFF\xE0test")

    assert_nothing_raised { IncidentPhotoUploadService.validate!([upload]) }
  ensure
    upload&.tempfile&.close!
  end

  test "rejects unsupported file contents" do
    upload = uploaded_file("photo.jpg", "image/jpeg", "%PDF-1.4")

    error = assert_raises(IncidentPhotoUploadService::InvalidUpload) do
      IncidentPhotoUploadService.validate!([upload])
    end
    assert_equal "รองรับเฉพาะไฟล์ JPG, PNG และ WebP", error.message
  ensure
    upload&.tempfile&.close!
  end

  test "rejects more than eight photos" do
    uploads = Array.new(9, Object.new)

    assert_raises(IncidentPhotoUploadService::InvalidUpload) do
      IncidentPhotoUploadService.validate!(uploads)
    end
  end

  private

  def uploaded_file(name, content_type, content)
    tempfile = Tempfile.new(["incident-photo", File.extname(name)])
    tempfile.binmode
    tempfile.write(content)
    tempfile.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: name, type: content_type)
  end
end
