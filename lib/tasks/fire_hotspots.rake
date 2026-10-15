namespace :fire_hotspots do
  desc "Fetch NASA FIRMS active fire hotspots for the configured area"
  task sync: :environment do
    mode = ENV["FIRMS_MAP_KEY"].present? ? "area API" : "public 24h files (no FIRMS_MAP_KEY)"
    result = FirmsHotspotSync.new.call
    pruned = result.delete("pruned")
    summary = result.map { |source, count| "#{source}=#{count}" }.join(", ")
    puts "Synced FIRMS hotspots via #{mode} (#{summary}); pruned #{pruned} expired"
  end
end
