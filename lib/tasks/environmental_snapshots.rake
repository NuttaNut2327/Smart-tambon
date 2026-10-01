namespace :environmental_snapshots do
  desc "Refresh hourly PM2.5 and weather cache for subdistricts in managed areas"
  task sync: :environment do
    subdistrict_ids = User.where.not(role: :system_admin).flat_map(&:accessible_subdistrict_ids).uniq
    snapshots = EnvironmentalSnapshotService.sync(Subdistrict.where(id: subdistrict_ids).to_a)
    puts "Updated #{snapshots.compact.size} environmental snapshots"
  end
end
