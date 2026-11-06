# Sends the "new incident" notifications in the background so reporting an incident never waits on LINE/Telegram.
class NotificationDispatchJob < ActiveJob::Base
  queue_as :default

  def perform(incident_id, event = nil)
    incident = Incident.where(id: incident_id).first
    return unless incident && incident.deleted_at.nil?

    tag = event.presence_in(NotificationChannel::TAGS.keys) || Notifications::Dispatcher.tag_for(incident)
    Notifications::Dispatcher.organization_keys_for(incident).each do |key|
      Notifications::Service.call(
        organization_key: key,
        event: tag,
        variables: Notifications::Dispatcher.incident_variables(incident, key),
        resource_id: incident.id
      )
    end
  end
end
