class CitizenLineNotificationJob < ActiveJob::Base
  queue_as :default

  retry_on Notifications::Senders::DeliveryError, wait: 30.seconds, attempts: 5

  def perform(incident_id, event)
    incident = Incident.find(incident_id)
    followers = CitizenIncidentFollower.where(incident_id: incident.id).to_a
    primary_enabled = incident.line_notification_enabled? && incident.reporter_line_user_id.present?
    return unless primary_enabled || followers.any?
    owner = User.find_by(id: incident.owner_user_id)
    setting = OrganizationSetting.for(owner)
    return unless setting&.citizen_line_ready?

    tag = "citizen.#{event}"
    body = NotificationTemplate.body_for(setting.organization_key, tag)
    variables = Notifications::Dispatcher.incident_variables(incident, setting.organization_key)
      .slice(*NotificationTemplate::CITIZEN_VARIABLES.keys)
    primary_variables = variables.merge(
        "organization_name" => setting.display_name.to_s,
        "reporter_name" => incident.reporter_name.to_s,
        "reporter_contact" => incident.reporter_contact.to_s,
        "initial_impact" => incident.initial_impact.to_s
      )
    text = Notifications::Dispatcher.render(body, primary_variables)
    follower_text = Notifications::Dispatcher.render(body, variables.merge(
      "organization_name" => setting.display_name.to_s,
      "reporter_name" => "",
      "reporter_contact" => "",
      "initial_impact" => ""
    ))
    client = CitizenLine::Client.new(setting:)

    if primary_enabled
      delivery = CitizenLineDelivery.find_or_create_by!(incident_id: incident.id, event:) do |record|
        record.line_user_id = incident.reporter_line_user_id
      end
      unless delivery.status == "sent"
        delivery.inc(attempts: 1)
        client.push(incident.reporter_line_user_id, text)
        delivery.set(status: "sent", message: text, sent_at: Time.current, error_message: nil)
      end
    end

    followers.each do |follower|
      next if follower.line_user_id == incident.reporter_line_user_id
      next if follower.notified_events.include?(event)

      client.push(follower.line_user_id, follower_text)
      follower.add_to_set(notified_events: event)
    end
  rescue Notifications::Senders::DeliveryError => error
    delivery&.set(status: "failed", error_message: error.message.to_s.truncate(500))
    raise
  rescue Mongoid::Errors::DocumentNotFound
    nil
  end

end
