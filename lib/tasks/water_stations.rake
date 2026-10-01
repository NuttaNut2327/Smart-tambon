namespace :water_stations do
  desc "Cache nationwide DWR and ThaiWater stations for spatial queries"
  task sync: :environment do
    dwr = DwrStationSync.new.call
    thaiwater = ThaiwaterStationSync.new.call
    puts "Cached #{dwr} DWR and #{thaiwater} ThaiWater stations nationwide"
  end
end
