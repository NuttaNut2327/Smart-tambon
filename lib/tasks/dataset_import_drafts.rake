namespace :dataset_import_drafts do
  desc "Delete expired import drafts together with their rows and uploaded source files"
  task cleanup: :environment do
    result = DatasetImportDraftCleanupService.call
    puts "Removed #{result[:expired_drafts]} expired drafts and #{result[:orphan_rows]} orphan draft rows"
  end
end
