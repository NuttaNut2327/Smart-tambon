class ImportedDatasetRecord
  include Mongoid::Document
  include Mongoid::Timestamps::Created
  belongs_to :imported_dataset_version
  field :position, type: Integer
  field :payload, type: Hash, default: {}
  field :location, type: Array
  index({ imported_dataset_version_id: 1, position: 1 }, unique: true)
  index({ location: "2dsphere" })
end
