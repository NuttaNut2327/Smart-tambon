namespace :image_library do
  desc "Move images attached before the image library existed into it (DRY_RUN=1 to count only, KEEP_ORIGINALS=1 to keep the old objects)"
  task backfill: :environment do
    result = ImageLibraryBackfill.new(dry_run: ENV["DRY_RUN"].present?, keep_originals: ENV["KEEP_ORIGINALS"].present?,
                                      logger: Logger.new($stdout)).call
    prefix = ENV["DRY_RUN"].present? ? "Would convert" : "Converted"
    puts "#{prefix} #{result.converted} image(s); #{result.skipped} missing; #{result.failed} failed"
  end
end
