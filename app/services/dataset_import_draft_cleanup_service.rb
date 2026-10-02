class DatasetImportDraftCleanupService
  class << self
    def call(now: Time.current)
      ensure_callback_expiration_index!

      expired = DatasetImportDraft.where(:expires_at.lte => now).to_a
      expired.each(&:destroy)

      parent_ids = DatasetImportDraft.pluck(:id)
      orphan_scope = if parent_ids.empty?
                       DatasetImportDraftRow.all
                     else
                       DatasetImportDraftRow.where(:dataset_import_draft_id.nin => parent_ids)
                     end
      orphan_rows = orphan_scope.count
      orphan_scope.delete_all

      { expired_drafts: expired.size, orphan_rows: orphan_rows }
    end

    private

    def ensure_callback_expiration_index!
      indexes = DatasetImportDraft.collection.indexes.to_a
      expires_index = indexes.find { |index| index.fetch("key", {}) == { "expires_at" => 1 } }
      if expires_index&.key?("expireAfterSeconds")
        DatasetImportDraft.collection.indexes.drop_one(expires_index.fetch("name"))
        expires_index = nil
      end
      DatasetImportDraft.collection.indexes.create_one({ expires_at: 1 }) unless expires_index
    end
  end
end
