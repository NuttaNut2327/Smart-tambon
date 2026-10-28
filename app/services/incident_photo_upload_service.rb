require "aws-sdk-s3"

# Photos on incidents and activities. New uploads go through the image library (WebP + thumbnail) and the incident
# keeps the library's attachment hash; photos stored before the library existed are plain objects under incidents/.
class IncidentPhotoUploadService
  InvalidUpload = ImageLibrary::InvalidUpload
  class ObjectNotFound < StandardError; end

  MAX_FILES = 8
  MAX_FILE_SIZE = ImageLibrary::MAX_FILE_SIZE
  ALLOWED_TYPES = ImageLibrary::ALLOWED_TYPES

  def self.uploads_from(params)
    Array(params.dig(:incident, :photos)).compact_blank
  end

  def self.library_ids_from(params)
    Array(params.dig(:incident, :library_image_ids)).compact_blank
  end

  def self.validate!(uploads, picked_count: 0)
    raise InvalidUpload, "แนบรูปได้ไม่เกิน #{MAX_FILES} รูปต่อเหตุการณ์" if uploads.size + picked_count > MAX_FILES

    ImageLibrary.validate!(uploads)
  end

  # Adds uploads (stored in the library) and already-picked library images to the incident's photos.
  def self.attach!(incident:, uploads:, picked: [], uploaded_by: nil)
    added = ImageLibrary.attachments!(uploads:, picked:, existing: incident.photos,
                                      owner_user_id: incident.owner_user_id, subdistrict_id: incident.subdistrict_id,
                                      source: incident.category == "activity" ? "activity" : "incident",
                                      uploaded_by: uploaded_by || incident.reporter_name)
    incident.set(photos: Array(incident.photos) + added) if added.any?
    added
  end

  # variant "thumb" serves the library thumbnail; legacy photos have none and fall back to the full image.
  def self.download(photo, variant: nil)
    key = variant.to_s == "thumb" ? photo["thumbnail_key"].presence || photo.fetch("key") : photo.fetch("key")
    client.get_object(bucket: bucket, key:)
  rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
    raise ObjectNotFound
  end

  # Stores one image as-is under <prefix>/ and returns its photo record. Only broadcasts use this: Instagram and
  # Facebook need the JPEG/PNG the user uploaded, not the library's WebP.
  def self.store!(prefix:, upload:)
    content_type = ImageLibrary.content_type_for(upload)
    raise InvalidUpload, "รองรับเฉพาะไฟล์ JPG, PNG และ WebP" unless %w[image/jpeg image/png image/webp].include?(content_type)
    raise InvalidUpload, "รูปแต่ละรูปต้องมีขนาดไม่เกิน 10 MB" if upload.size > 10.megabytes

    id = SecureRandom.uuid
    extension = Rack::Mime::MIME_TYPES.key(content_type).to_s.delete_prefix(".").presence || "bin"
    key = "#{prefix}/#{id}.#{extension}"
    upload.tempfile.rewind
    client.put_object(bucket: bucket, key: key, body: upload.tempfile, content_type: content_type)
    { "id" => id, "key" => key, "filename" => upload.original_filename.to_s, "content_type" => content_type, "byte_size" => upload.size, "uploaded_at" => Time.current }
  end

  # Library pictures outlive their attachments, so only legacy objects are deleted here.
  def self.delete_photo(photo)
    delete_object(photo["key"]) if photo["key"].present? && photo["library_image_id"].blank?
  end

  def self.purge_for(incident)
    Array(incident.photos).each { |photo| delete_photo(photo) }
    incident.set(photos: []) if incident.persisted?
  end

  def self.delete_object(key)
    client.delete_object(bucket: bucket, key: key)
  rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
    nil
  end

  def self.client
    @client ||= Aws::S3::Client.new(
      endpoint: ENV.fetch("MINIO_ENDPOINT", "http://minio:9000"),
      access_key_id: ENV.fetch("MINIO_ACCESS_KEY", "minioadmin"),
      secret_access_key: ENV.fetch("MINIO_SECRET_KEY", "minioadmin123"),
      region: ENV.fetch("MINIO_REGION", "us-east-1"),
      force_path_style: true
    )
  end

  def self.bucket
    ENV.fetch("MINIO_BUCKET", "smart-tambon-incidents")
  end

  private_class_method :client, :bucket, :delete_object
end
