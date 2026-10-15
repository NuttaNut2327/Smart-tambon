# Sends the "new incident" notifications in the background so reporting an incident never waits on LINE/Telegram.
class NotificationDispatchJob < ActiveJob::Base
  queue_as :default

  def perform(incident_id)
    incident = Incident.where(id: incident_id).first
    return unless incident && incident.deleted_at.nil?

    tag = Notifications::Dispatcher.tag_for(incident)
    Notifications::Dispatcher.organization_keys_for(incident).each do |key|
      Notifications::Dispatcher.new(organization_key: key)
                               .dispatch(tag: tag, variables: Notifications::Dispatcher.incident_variables(incident, key), incident_id: incident.id)
    end
  end
end
