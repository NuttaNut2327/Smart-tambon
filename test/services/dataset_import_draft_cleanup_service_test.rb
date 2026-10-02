require "test_helper"

class DatasetImportDraftCleanupServiceTest < ActiveSupport::TestCase
  test "removes expired drafts and their rows while preserving active drafts" do
    expired = DatasetImportDraft.create!(user_id: 1, data_type: "population", source_filename: "expired.csv",
      expires_at: 1.minute.ago)
    active = DatasetImportDraft.create!(user_id: 1, data_type: "population", source_filename: "active.csv",
      expires_at: 1.hour.from_now)
    DatasetImportDraftRow.create!(dataset_import_draft: expired, position: 0, raw_payload: { "value" => "old" })
    DatasetImportDraftRow.create!(dataset_import_draft: active, position: 0, raw_payload: { "value" => "current" })

    result = DatasetImportDraftCleanupService.call

    assert_equal 1, result[:expired_drafts]
    assert_nil DatasetImportDraft.where(id: expired.id).first
    assert_equal 0, DatasetImportDraftRow.where(dataset_import_draft_id: expired.id).count
    assert DatasetImportDraft.where(id: active.id).exists?
    assert_equal 1, DatasetImportDraftRow.where(dataset_import_draft_id: active.id).count
  end

  test "removes rows whose parent draft no longer exists" do
    missing_id = BSON::ObjectId.new
    DatasetImportDraftRow.collection.insert_one(
      dataset_import_draft_id: missing_id, position: 0, raw_payload: { "value" => "orphan" }
    )

    result = DatasetImportDraftCleanupService.call

    assert_equal 1, result[:orphan_rows]
    assert_equal 0, DatasetImportDraftRow.where(dataset_import_draft_id: missing_id).count
  end
end
