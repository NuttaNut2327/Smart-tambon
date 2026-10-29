# A photo attached to one row of a standard dataset (resources, consumables). Kept outside the dataset versions,
# keyed by the row's stable record_id, so editing a row or recording stock movements never drops its photos.
# The picture itself lives in the image library (library_image_id); image/thumbnail copy its object keys. Photos
# uploaded before the library existed own their objects directly.
class DatasetRecordPhoto
  include Mongoid::Document
  include Mongoid::Timestamps

  DATA_TYPES = %w[resources consumables].freeze
  MAX_PER_RECORD = 6

  field :imported_dataset_id, type: BSON::ObjectId
  field :record_id, type: String
  field :library_image_id, type: String
  field :image, type: Hash
  field :thumbnail, type: Hash
  field :uploaded_by, type: String

  index({ imported_dataset_id: 1, record_id: 1, created_at: 1 })
  index({ library_image_id: 1 })

  validates :imported_dataset_id, :record_id, :image, presence: true

  scope :for_record, ->(dataset_id, record_id) { where(imported_dataset_id: dataset_id, record_id:).asc(:created_at) }

  # { record_id => [photo, ...] } for every row of the given datasets, oldest first.
  def self.grouped_for(datasets)
    where(:imported_dataset_id.in => datasets.map(&:id)).asc(:created_at).group_by(&:record_id)
  end

  def variant(name) = name == "thumb" && thumbnail.present? ? thumbnail : image

  def self.attributes_for(library_image)
    { library_image_id: library_image.id.to_s, image: library_image.image, thumbnail: library_image.thumbnail }
  end

  def purge!
    [image, thumbnail].compact.uniq.each { |object| IncidentPhotoUploadService.delete_photo(object) } if library_image_id.blank?
    destroy
  end
end
