namespace :activities do
  desc "Mark area activities whose end time has passed as finished"
  task finish_expired: :environment do
    before = Incident.activities.where(status: "completed").count
    Incident.finish_expired_activities!
    puts "Finished #{Incident.activities.where(status: 'completed').count - before} activities"
  end
end
