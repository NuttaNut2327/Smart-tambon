class ImportedDatasetVersion
  include Mongoid::Document
  include Mongoid::Timestamps
  belongs_to :imported_dataset
  field :user_id, type: Integer
  field :version_number, type: Integer
  field :source_kind, type: String
  field :source_filename, type: String
  field :source_content_type, type: String
  field :source_file_id, type: BSON::ObjectId
  field :record_count, type: Integer, default: 0
  field :validation_summary, type: Hash, default: {}
  field :change_note, type: String
  has_many :record_documents, class_name: "ImportedDatasetRecord", dependent: :destroy
  index({ imported_dataset_id: 1, version_number: -1 }, unique: true)
  validates :version_number, numericality: { only_integer: true, greater_than: 0 }
  validates :source_kind, inclusion: { in: %w[manual file restored] }
  def user = User.find_by(id: user_id)
  def records
    integer_keys = imported_dataset.effective_schema_definition.filter_map do |field|
      field["key"] if field["type"] == "integer"
    end
    record_documents.asc(:position).pluck(:payload).map do |source_record|
      record = source_record.deep_dup
      integer_keys.each { |key| record[key] = record[key].to_i if record[key].present? }
      record
    end
  end
  def downloadable? = source_file_id.present?
  before_destroy { DatasetGridFileStore.delete(source_file_id) if source_file_id }
end
