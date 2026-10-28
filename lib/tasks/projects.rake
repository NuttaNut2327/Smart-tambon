namespace :projects do
  desc "Generate simulated projects for the past fiscal years (SUBDISTRICT_ID, YEARS=5, PER_YEAR=18, SEED=2570). Rerunning replaces earlier simulated data."
  task simulate: :environment do
    ProjectSimulator.new(
      subdistrict_id: ENV["SUBDISTRICT_ID"],
      years: ENV.fetch("YEARS", 5).to_i,
      per_year: ENV.fetch("PER_YEAR", 18).to_i,
      seed: ENV.fetch("SEED", 2570).to_i
    ).run
  end

  desc "Remove simulated projects (code starting with SIM-)"
  task clear_simulated: :environment do
    puts "Removed #{DemoData.purge!("projects")} simulated projects"
  end
end
