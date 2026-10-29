module Api
  class LocationReadingsController < SensorSubmissionsController
    private

    def sensor_type = "location"
  end
end
