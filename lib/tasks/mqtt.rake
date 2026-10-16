namespace :mqtt do
  desc "Subscribe to sensor topics on the MQTT broker and store readings (MQTT_URL, MQTT_TOPIC_PREFIX)"
  task listen: :environment do
    $stdout.sync = true
    MqttSensorListener.new.run
  end
end
