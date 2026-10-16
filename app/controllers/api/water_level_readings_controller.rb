module Api
  class WaterLevelReadingsController < SensorSubmissionsController
    private

    def sensor_type = "water_level"
  end
end
