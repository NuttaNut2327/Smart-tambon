ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  parallelize(workers: 1)
  setup do
    [DatasetImportDraftRow, DatasetImportDraft, ImportedDatasetRecord, ImportedDatasetVersion, ImportedDataset].each(&:delete_all)
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
