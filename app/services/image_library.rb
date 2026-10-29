require "aws-sdk-s3"
require "digest"

# Stores every uploaded picture in the image library (LibraryImage): the upload is auto-rotated, capped at
# MAX_DIMENSION, re-encoded as WebP and given a THUMB_DIMENSION thumbnail. The original is not kept: phone photos are
# 3-10 MB and the WebP copy is plenty for reports and the map, at a fraction of the space.
class ImageLibrary
  class InvalidUpload < StandardError; end

  MAX_FILE_SIZE = 15.megabytes
  ALLOWED_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif image/avif].freeze
  ACCEPT = (ALLOWED_TYPES + %w[.heic .heif]).join(",").freeze
  MAX_DIMENSION = 2048
  THUMB_DIMENSION = 480
  QUALITY = 80
  THUMB_QUALITY = 70

  def self.content_type_for(upload)
    Marcel::MimeType.for(upload.tempfile, name: upload.original_filename, declared_type: upload.content_type)
  end

  def self.validate!(uploads)
    uploads.each do |upload|
      raise InvalidUpload, "รองรับเฉพาะไฟล์ภาพ JPG, PNG, WebP, HEIC และ AVIF" unless ALLOWED_TYPES.include?(content_type_for(upload))
      raise InvalidUpload, "ภาพแต่ละภาพต้องมีขนาดไม่เกิน #{MAX_FILE_SIZE / 1.megabyte} MB" if upload.size > MAX_FILE_SIZE
    end
  end

  # Adds one upload to the library and returns its LibraryImage.
  def self.import!(upload:, owner_user_id:, subdistrict_id:, source: "library", uploaded_by: nil)
    validate!([upload])
    upload.tempfile.rewind
    import_data!(data: upload.tempfile.read, filename: upload.original_filename.to_s, original_content_type: content_type_for(upload),
                 owner_user_id:, subdistrict_id:, source:, uploaded_by:)
  end

  # Same as import! for bytes already in memory (the backfill of legacy attachments). The same file uploaded again
  # in the same area returns the existing picture instead of storing a copy.
  def self.import_data!(data:, filename:, owner_user_id:, subdistrict_id:, source:, uploaded_by: nil, original_content_type: nil)
    checksum = Digest::SHA256.hexdigest(data)
    existing = LibraryImage.where(checksum:, owner_user_id:, subdistrict_id:).first
    return existing if existing

    converted = convert(data)
    image = LibraryImage.new(title: File.basename(filename, ".*").presence || "ภาพ", original_filename: filename,
                             original_content_type:, original_byte_size: data.bytesize, checksum:, source:,
                             owner_user_id:, subdistrict_id:, uploaded_by:, width: converted[:width], height: converted[:height])
    base = "library/#{subdistrict_id || 'shared'}/#{image.id}"
    webp_name = "#{image.title}.webp"
    image.image = put!("#{base}.webp", converted[:image], webp_name)
    image.thumbnail = put!("#{base}_thumb.webp", converted[:thumbnail], webp_name)
    image.save!
    image
  rescue StandardError
    [image&.image, image&.thumbnail].compact.each { |object| delete_object(object["key"]) }
    raise
  end

  def self.convert(data)
    require "vips"
    full = Vips::Image.thumbnail_buffer(data, MAX_DIMENSION, height: MAX_DIMENSION, size: :down)
    thumb = Vips::Image.thumbnail_buffer(data, THUMB_DIMENSION, height: THUMB_DIMENSION, size: :down)
    { image: full.webpsave_buffer(Q: QUALITY, strip: true), thumbnail: thumb.webpsave_buffer(Q: THUMB_QUALITY, strip: true),
      width: full.width, height: full.height }
  rescue Vips::Error => error
    Rails.logger.warn("Image conversion failed: #{error.message.lines.first}")
    raise InvalidUpload, "เปิดไฟล์ภาพไม่ได้ ไฟล์อาจเสียหายหรือไม่ใช่ไฟล์ภาพ"
  end

  # Library pictures the user may attach, in the order the ids were given.
  def self.pick(user, ids)
    ids = Array(ids).compact_blank.map(&:to_s).uniq
    return [] if ids.empty?

    found = LibraryImage.visible_to(user).where(:id.in => ids).index_by { |image| image.id.to_s }
    ids.filter_map { |id| found[id] }
  end

  # Turns uploads plus picked library ids into attachment hashes, skipping pictures already in `existing`.
  def self.attachments!(uploads:, picked: [], existing: [], owner_user_id:, subdistrict_id:, source:, uploaded_by: nil)
    images = uploads.map { |upload| import!(upload:, owner_user_id:, subdistrict_id:, source:, uploaded_by:) } + picked
    known = Array(existing).filter_map { |photo| photo["library_image_id"] }
    images.uniq(&:id).reject { |image| known.include?(image.id.to_s) }.map(&:attachment)
  end

  def self.download(image, variant: nil)
    client.get_object(bucket:, key: image.variant(variant).fetch("key"))
  rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
    raise IncidentPhotoUploadService::ObjectNotFound
  end

  def self.destroy!(image)
    [image.image, image.thumbnail].compact.each { |object| delete_object(object["key"]) }
    image.destroy
  end

  def self.put!(key, body, filename)
    client.put_object(bucket:, key:, body:, content_type: "image/webp")
    { "key" => key, "filename" => filename, "content_type" => "image/webp", "byte_size" => body.bytesize }
  end

  def self.delete_object(key)
    client.delete_object(bucket:, key:)
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

  private_class_method :client, :bucket, :put!
end
