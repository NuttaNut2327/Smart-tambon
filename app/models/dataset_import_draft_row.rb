class DatasetImportDraftRow
  include Mongoid::Document
  belongs_to :dataset_import_draft
  field :position, type: Integer
  field :raw_payload, type: Hash, default: {}
  field :validated_payload, type: Hash, default: {}
  field :ready_for_import, type: Boolean, default: false
  index({ dataset_import_draft_id: 1, position: 1 }, unique: true)
end
