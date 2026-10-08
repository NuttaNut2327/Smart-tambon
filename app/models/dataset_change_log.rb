class DatasetChangeLog
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  belongs_to :imported_dataset
  field :imported_dataset_version_id, type: BSON::ObjectId
  field :user_id, type: Integer
  field :action, type: String
  field :source_kind, type: String
  field :record_id, type: String
  field :record_label, type: String
  field :before_data, type: Hash, default: {}
  field :after_data, type: Hash, default: {}
  field :changed_fields, type: Array, default: []
  field :note, type: String

  index({ imported_dataset_id: 1, created_at: -1 })
  index({ imported_dataset_version_id: 1, created_at: -1 })
  index({ record_id: 1, created_at: -1 })
  index({ user_id: 1, created_at: -1 })

  validates :imported_dataset_id, :imported_dataset_version_id, :user_id, :action, presence: true
  validates :action, inclusion: { in: %w[add update delete import restore checkpoint] }

  def user = User.find_by(id: user_id)
end
