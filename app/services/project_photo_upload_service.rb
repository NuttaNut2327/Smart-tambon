require "aws-sdk-s3"

# Stores project photos in the same MinIO bucket as incident photos, under projects/<id>/.
class ProjectPhotoUploadService
  class InvalidUpload < StandardError; end
  class ObjectNotFound < StandardError; end

  MAX_FILES = 20
  MAX_FILE_SIZE = 10.megabytes
  ALLOWED_TYPES = %w[image/jpeg image/png image/webp].freeze

  def self.uploads_from(params)
    Array(params.dig(:project, :photos)).compact_blank
  end

  def self.validate!(uploads, existing_count: 0)
    raise InvalidUpload, "แนบรูปได้ไม่เกิน #{MAX_FILES} รูปต่อโครงการ" if uploads.size + existing_count > MAX_FILES

    uploads.each do |upload|
      raise InvalidUpload, "รองรับเฉพาะไฟล์ JPG, PNG และ WebP" unless ALLOWED_TYPES.include?(content_type_for(upload))
      raise InvalidUpload, "รูปแต่ละรูปต้องมีขนาดไม่เกิน 10 MB" if upload.size > MAX_FILE_SIZE
    end
  end

  def self.attach!(project:, uploads:)
    uploaded = []
    uploads.each do |upload|
      id = SecureRandom.uuid
      content_type = content_type_for(upload)
      extension = Rack::Mime::MIME_TYPES.key(content_type).to_s.delete_prefix(".").presence || "bin"
      key = "projects/#{project.id}/#{id}.#{extension}"
      upload.tempfile.rewind
      client.put_object(bucket: bucket, key: key, body: upload.tempfile, content_type: content_type)
      uploaded << {
        "id" => id,
        "key" => key,
        "filename" => upload.original_filename.to_s,
        "content_type" => content_type,
        "byte_size" => upload.size,
        "uploaded_at" => Time.current
      }
    end
    project.set(photos: Array(project.photos) + uploaded) if uploaded.any?
  rescue StandardError
    uploaded.each { |photo| delete_object(photo["key"]) }
    raise
  end

  def self.remove!(project:, photo_ids:)
    ids = Array(photo_ids).map(&:to_s)
    return if ids.empty?

    removed, kept = Array(project.photos).partition { |photo| ids.include?(photo["id"]) }
    removed.each { |photo| delete_object(photo["key"]) }
    project.set(photos: kept)
  end

  def self.download(photo)
    client.get_object(bucket: bucket, key: photo.fetch("key"))
  rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
    raise ObjectNotFound
  end

  def self.purge_for(project)
    Array(project.photos).each { |photo| delete_object(photo["key"]) }
  end

  def self.content_type_for(upload)
    Marcel::MimeType.for(upload.tempfile, name: upload.original_filename, declared_type: upload.content_type)
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

  private_class_method :client, :bucket, :delete_object, :content_type_for
end
