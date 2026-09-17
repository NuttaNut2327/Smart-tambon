class DatasetImportDraft
  include Mongoid::Document
  include Mongoid::Timestamps
  field :user_id, type: Integer
  field :data_type, type: String
  field :target_dataset_id, type: BSON::ObjectId
  field :schema_definition, type: Array, default: []
  field :source_filename, type: String
  field :source_content_type, type: String
  field :source_file_id, type: BSON::ObjectId
  field :source_headers, type: Array, default: []
  field :column_mapping, type: Hash, default: {}
  field :validation_summary, type: Hash, default: {}
  field :expires_at, type: Time
  has_many :rows, class_name: "DatasetImportDraftRow", dependent: :destroy
  index({ user_id: 1 }); index({ expires_at: 1 }, expire_after_seconds: 0)
  validates :user_id, :source_filename, :expires_at, presence: true
  validates :data_type, inclusion: { in: ImportedDataset::TYPE_LABELS.keys }
  scope :active, -> { where(:expires_at.gt => Time.current) }
  def user = User.find_by(id: user_id)
  def schema = schema_definition.presence || ImportedDataset.schema_for(data_type)
  def source_rows = rows.asc(:position).pluck(:raw_payload)
  def validated_records
    rows.where(ready_for_import: true).asc(:position).pluck(:validated_payload).compact
  end
  before_destroy { DatasetGridFileStore.delete(source_file_id) if source_file_id }
end
