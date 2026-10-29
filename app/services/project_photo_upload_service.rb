require "aws-sdk-s3"

# Project photos. New uploads go through the image library (WebP + thumbnail); photos stored before the library
# existed are plain objects under projects/<id>/ in the incident bucket.
class ProjectPhotoUploadService
  InvalidUpload = ImageLibrary::InvalidUpload
  class ObjectNotFound < StandardError; end

  MAX_FILES = 20
  MAX_FILE_SIZE = ImageLibrary::MAX_FILE_SIZE
  ALLOWED_TYPES = ImageLibrary::ALLOWED_TYPES

  def self.uploads_from(params)
    Array(params.dig(:project, :photos)).compact_blank
  end

  def self.library_ids_from(params)
    Array(params.dig(:project, :library_image_ids)).compact_blank
  end

  def self.validate!(uploads, existing_count: 0, picked_count: 0)
    raise InvalidUpload, "แนบรูปได้ไม่เกิน #{MAX_FILES} รูปต่อโครงการ" if uploads.size + picked_count + existing_count > MAX_FILES

    ImageLibrary.validate!(uploads)
  end

  def self.attach!(project:, uploads:, picked: [], uploaded_by: nil)
    added = ImageLibrary.attachments!(uploads:, picked:, existing: project.photos, owner_user_id: project.user_id,
                                      subdistrict_id: project.subdistrict_id, source: "project", uploaded_by:)
    project.set(photos: Array(project.photos) + added) if added.any?
    added
  end

  def self.remove!(project:, photo_ids:)
    ids = Array(photo_ids).map(&:to_s)
    return if ids.empty?

    removed, kept = Array(project.photos).partition { |photo| ids.include?(photo["id"]) }
    removed.each { |photo| delete_photo(photo) }
    project.set(photos: kept)
  end

  def self.download(photo, variant: nil)
    key = variant.to_s == "thumb" ? photo["thumbnail_key"].presence || photo.fetch("key") : photo.fetch("key")
    client.get_object(bucket: bucket, key:)
  rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
    raise ObjectNotFound
  end

  def self.purge_for(project)
    Array(project.photos).each { |photo| delete_photo(photo) }
  end

  # Library pictures outlive their attachments, so only legacy objects are deleted here.
  def self.delete_photo(photo)
    delete_object(photo["key"]) if photo["key"].present? && photo["library_image_id"].blank?
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
