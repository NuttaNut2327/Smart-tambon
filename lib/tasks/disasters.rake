namespace :disasters do
  desc "Generate a simulated disaster history (YEARS=3, SEED=2026, SUBDISTRICT_IDS=1,2 or DISTRICT_OF=<subdistrict id>; default: the district of the first area account). Rerunning replaces earlier simulated events in those subdistricts."
  task simulate: :environment do
    ids = ENV["SUBDISTRICT_IDS"].to_s.split(",").map(&:to_i).reject(&:zero?)
    if ids.empty?
      anchor = ENV["DISTRICT_OF"].present? ? Subdistrict.find(ENV["DISTRICT_OF"]) : User.where.not(subdistrict_id: nil).order(:id).first&.subdistrict
      abort "Pass SUBDISTRICT_IDS or DISTRICT_OF" unless anchor
      ids = Subdistrict.where(district_code: anchor.district_code).pluck(:id)
    end
    result = DisasterSimulator.new(subdistrict_ids: ids, years: ENV.fetch("YEARS", 3).to_i, seed: ENV.fetch("SEED", 2026).to_i).run
    puts "Removed #{result[:removed]} old simulated events; created #{result[:created]} in #{result[:subdistricts].size} subdistricts (#{result[:subdistricts].join(', ')})"
    puts "Period #{result[:range].begin.to_date} to #{result[:range].end.to_date}; year wetness (-1 dry .. +1 wet): #{result[:wetness]}"
  end

  desc "Remove all simulated disaster events"
  task clear_simulated: :environment do
    puts "Removed #{DemoData.purge!("disaster_events")} simulated disaster events"
  end
end
