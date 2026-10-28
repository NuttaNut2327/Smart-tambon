require "test_helper"

class SensorIngestionLocationTest < ActiveSupport::TestCase
  setup do
    LocationTrackerReading.delete_all
    @user = User.create!(username: "tracker_admin", email: "tracker_admin@example.test", password: "Password123!", role: :system_admin)
    @dataset = ImportedDataset.create!(user: @user, name: "ข้อมูลตำแหน่ง", data_type: "location_trackers",
      geometry_type: "point", map_enabled: true, schema_definition: ImportedDataset.schema_for("location_trackers"))
    version = DatasetVersionImportService.new(dataset: @dataset, user: @user,
      manual_records: [{ sensor_id: "GPS-001", name: "รถกู้ภัย 1" }]).import!
    @token = version.records.first["token"]
  end

  test "stores the position reported by the device" do
    result = SensorIngestion.call(sensor_type: "location", sensor_id: "GPS-001", token: @token, source: "http",
      payload: { "lat" => 13.75, "lng" => 100.5, "speed_kmh" => 32, "observed_at" => "2026-10-28T10:00:00+07:00" })

    reading = result.reading
    assert_equal 13.75, reading.latitude
    assert_equal 100.5, reading.longitude
    assert_equal 32.0, reading.speed_kmh
    assert_equal @dataset.id, reading.imported_dataset_id
  end

  test "rejects readings without coordinates" do
    assert_raises(SensorIngestion::Invalid) do
      SensorIngestion.call(sensor_type: "location", sensor_id: "GPS-001", token: @token, source: "http", payload: { "speed_kmh" => 10 })
    end
  end

  test "rejects out of range coordinates" do
    assert_raises(SensorIngestion::Invalid) do
      SensorIngestion.call(sensor_type: "location", sensor_id: "GPS-001", token: @token, source: "mqtt",
        payload: { "latitude" => 120, "longitude" => 100.5 })
    end
  end

  test "mqtt gps topic maps to location readings" do
    listener = MqttSensorListener.new(url: "mqtt://unused", logger: Logger.new(nil))
    response = listener.handle("smart-tambon/sensors/gps/GPS-001", { token: @token, latitude: 13.8, longitude: 100.6 }.to_json)

    assert_equal "accepted", response[:status]
    assert_equal 13.8, LocationTrackerReading.last.latitude
  end
end
