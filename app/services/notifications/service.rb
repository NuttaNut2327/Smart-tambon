module Notifications
  # Single backend entry point for outbound notifications. Controllers, jobs
  # and domain services should use this facade instead of provider clients.
  class Service
    class << self
      def call(organization_key:, event:, variables:, resource_id: nil, channels: nil, body: nil, sent_by: nil, source: "event")
        dispatcher(organization_key:, sent_by:, source:).dispatch(
          tag: event,
          variables: variables,
          incident_id: resource_id,
          channels: channels,
          body: body
        )
      end

      def deliver(organization_key:, channel:, text:, event:, variables: {}, resource_id: nil, sent_by: nil, source: "manual")
        dispatcher(organization_key:, sent_by:, source:).deliver(
          channel,
          text,
          tag: event,
          variables: variables,
          incident_id: resource_id
        )
      end

      # Publishers keep their own delivery history, while provider selection
      # and credentials remain behind this common service boundary.
      def publish(channel:, text:, event:, data: {}, setting: NotificationSetting.current)
        Senders.for(channel, setting).deliver(text, tag: event, data: data)
      end

      # Webhook replies and connection checks use the same LINE client without
      # exposing the provider implementation outside this facade.
      def line_client(setting: NotificationSetting.current)
        Senders::Line.client(setting)
      end

      private

      def dispatcher(organization_key:, sent_by:, source:)
        Dispatcher.new(organization_key: organization_key, sent_by: sent_by, source: source)
      end
    end
  end
end
