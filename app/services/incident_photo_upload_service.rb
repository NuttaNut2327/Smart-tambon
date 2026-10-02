require "aws-sdk-s3"

class IncidentPhotoUploadService
  class InvalidUpload < StandardError; end
  class ObjectNotFound < StandardError; end

  MAX_FILES = 8
  MAX_FILE_SIZE = 10.megabytes
  ALLOWED_TYPES = %w[image/jpeg image/png image/webp].freeze

  def self.uploads_from(params)
    Array(params.dig(:incident, :photos)).compact_blank
  end

  def self.validate!(uploads)
    raise InvalidUpload, "แนบรูปได้ไม่เกิน #{MAX_FILES} รูปต่อเหตุการณ์" if uploads.size > MAX_FILES

    uploads.each do |upload|
      detected_type = Marcel::MimeType.for(upload.tempfile, name: upload.original_filename, declared_type: upload.content_type)
      raise InvalidUpload, "รองรับเฉพาะไฟล์ JPG, PNG และ WebP" unless ALLOWED_TYPES.include?(detected_type)
      raise InvalidUpload, "รูปแต่ละรูปต้องมีขนาดไม่เกิน 10 MB" if upload.size > MAX_FILE_SIZE
    end
  end

  def self.attach!(incident:, uploads:)
    validate!(uploads)
    uploaded = uploads.map do |upload|
      id = SecureRandom.uuid
      content_type = Marcel::MimeType.for(upload.tempfile, name: upload.original_filename, declared_type: upload.content_type)
      extension = Rack::Mime::MIME_TYPES.key(content_type).to_s.delete_prefix(".").presence || "bin"
      key = "incidents/#{incident.id}/#{id}.#{extension}"
      upload.tempfile.rewind
      client.put_object(bucket: bucket, key: key, body: upload.tempfile, content_type: content_type)
      {
        "id" => id,
        "key" => key,
        "filename" => upload.original_filename.to_s,
        "content_type" => content_type,
        "byte_size" => upload.size,
        "uploaded_at" => Time.current
      }
    end
    incident.set(photos: Array(incident.photos) + uploaded)
  rescue StandardError
    Array(uploaded).each { |photo| delete_object(photo["key"]) }
    raise
  end

  def self.download(photo)
    client.get_object(bucket: bucket, key: photo.fetch("key"))
  rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
    raise ObjectNotFound
  end

  def self.purge_for(incident)
    Array(incident.photos).each { |photo| delete_object(photo["key"]) }
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
