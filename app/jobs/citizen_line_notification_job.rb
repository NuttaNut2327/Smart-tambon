class CitizenLineNotificationJob < ActiveJob::Base
  queue_as :default

  retry_on Notifications::Senders::DeliveryError, wait: 30.seconds, attempts: 5

  def perform(incident_id, event)
    incident = Incident.find(incident_id)
    return unless incident.line_notification_enabled? && incident.reporter_line_user_id.present?
    owner = User.find_by(id: incident.owner_user_id)
    setting = OrganizationSetting.for(owner)
    return unless setting&.citizen_line_ready?

    delivery = CitizenLineDelivery.find_or_create_by!(incident_id: incident.id, event:) do |record|
      record.line_user_id = incident.reporter_line_user_id
    end
    return if delivery.status == "sent"

    tag = "citizen.#{event}"
    body = NotificationTemplate.body_for(setting.organization_key, tag)
    variables = Notifications::Dispatcher.incident_variables(incident, setting.organization_key)
      .slice(*NotificationTemplate::CITIZEN_VARIABLES.keys)
      .merge(
        "organization_name" => setting.display_name.to_s,
        "reporter_name" => incident.reporter_name.to_s,
        "reporter_contact" => incident.reporter_contact.to_s,
        "initial_impact" => incident.initial_impact.to_s
      )
    text = Notifications::Dispatcher.render(body, variables)
    delivery.inc(attempts: 1)
    CitizenLine::Client.new(setting:).push(incident.reporter_line_user_id, text)
    delivery.set(status: "sent", message: text, sent_at: Time.current, error_message: nil)
  rescue Notifications::Senders::DeliveryError => error
    delivery&.set(status: "failed", error_message: error.message.to_s.truncate(500))
    raise
  rescue Mongoid::Errors::DocumentNotFound
    nil
  end

end
