# Moves images attached before the image library existed into it: each legacy object is downloaded, converted to
# WebP with a thumbnail, and the attachment is rewritten to point at the library picture. The old object is deleted
# afterwards unless keep_originals is set. Safe to run repeatedly; attachments already in the library are skipped.
class ImageLibraryBackfill
  Result = Struct.new(:converted, :skipped, :failed, keyword_init: true)

  def initialize(dry_run: false, keep_originals: false, logger: Rails.logger)
    @dry_run = dry_run
    @keep_originals = keep_originals
    @logger = logger
    @result = Result.new(converted: 0, skipped: 0, failed: 0)
  end

  def call
    backfill_incidents
    backfill_projects
    backfill_dataset_record_photos
    backfill_logos
    @result
  end

  private

  LEGACY_PHOTOS = { "photos" => { "$elemMatch" => { "key" => { "$exists" => true }, "library_image_id" => { "$exists" => false } } } }.freeze

  def backfill_incidents
    Incident.where(LEGACY_PHOTOS).each do |incident|
      source = incident.category == "activity" ? "activity" : "incident"
      photos, cover_id, legacy = rewrite(incident.photos, cover_id: incident.cover_photo_id) do |photo|
        library_image(photo, owner_user_id: incident.owner_user_id, subdistrict_id: incident.subdistrict_id, source:,
                             uploaded_by: incident.reporter_name)
      end
      next unless photos

      incident.set(photos:, cover_photo_id: cover_id)
      legacy.each { |photo| discard(photo) }
    end
  end

  def backfill_projects
    Project.where(LEGACY_PHOTOS).each do |project|
      photos, _, legacy = rewrite(project.photos) do |photo|
        library_image(photo, owner_user_id: project.user_id, subdistrict_id: project.subdistrict_id, source: "project")
      end
      next unless photos

      project.set(photos:)
      legacy.each { |photo| discard(photo) }
    end
  end

  def backfill_dataset_record_photos
    DatasetRecordPhoto.where(library_image_id: nil).each do |record_photo|
      dataset = ImportedDataset.where(id: record_photo.imported_dataset_id).first
      legacy = [record_photo.image, record_photo.thumbnail].compact
      image = library_image(record_photo.image, owner_user_id: dataset&.user_id, subdistrict_id: dataset&.subdistrict_id,
                                                source: "dataset_record", uploaded_by: record_photo.uploaded_by)
      next unless image

      record_photo.update!(**DatasetRecordPhoto.attributes_for(image))
      legacy.each { |object| discard(object) }
    end
  end

  def backfill_logos
    [*OrganizationSetting.where(:"logo.key".exists => true), *SystemSetting.where(:"logo.key".exists => true)].each do |setting|
      next if setting.logo["library_image_id"].present?

      owner = setting.respond_to?(:organization_key) ? User.where(organization_key: setting.organization_key).order(:id).first : nil
      image = library_image(setting.logo, owner_user_id: owner&.id, subdistrict_id: owner&.subdistrict_id, source: "logo")
      next unless image

      legacy = setting.logo
      setting.set(logo: image.attachment)
      discard(legacy)
    end
  end

  # Yields each legacy photo; returns the rewritten list (nil when nothing changed), the remapped cover id and the
  # legacy photos to delete once the new list is saved.
  def rewrite(photos, cover_id: nil)
    legacy = []
    rewritten = Array(photos).map do |photo|
      next photo if photo["library_image_id"].present?

      image = yield(photo)
      next photo unless image

      legacy << photo
      cover_id = image.id.to_s if cover_id.present? && cover_id == photo["id"]
      image.attachment
    end
    [legacy.any? ? rewritten.uniq { |photo| photo["id"] } : nil, cover_id, legacy]
  end

  def library_image(photo, **attributes)
    if @dry_run
      @result.converted += 1
      return nil
    end

    data = IncidentPhotoUploadService.download(photo).body.read
    image = ImageLibrary.import_data!(data:, filename: photo["filename"].presence || File.basename(photo["key"].to_s),
                                      original_content_type: photo["content_type"], **attributes)
    @result.converted += 1
    image
  rescue IncidentPhotoUploadService::ObjectNotFound
    @logger.warn("Image library backfill: missing object #{photo['key']}")
    @result.skipped += 1
    nil
  rescue ImageLibrary::InvalidUpload, Aws::S3::Errors::ServiceError => error
    @logger.warn("Image library backfill: #{photo['key']} failed: #{error.message}")
    @result.failed += 1
    nil
  end

  def discard(object)
    IncidentPhotoUploadService.delete_photo(object) unless @keep_originals || @dry_run
  end
end
