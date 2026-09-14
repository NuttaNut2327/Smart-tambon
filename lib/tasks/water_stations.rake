namespace :water_stations do
  desc "Fetch DWR water-level and rainfall stations into PostGIS"
  task sync: :environment do
    imported = DwrStationSync.new.call
    puts "Imported #{imported} DWR stations"
  end
end
