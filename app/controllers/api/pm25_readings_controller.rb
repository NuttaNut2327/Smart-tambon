module Api
  class Pm25ReadingsController < SensorSubmissionsController
    private

    def sensor_type = "pm25"
  end
end
