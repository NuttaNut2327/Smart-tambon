module Api
  class ImportedDatasetsController < ApplicationController
    def index
      datasets = ImportedDataset.visible_to(current_user).where(map_enabled: true)
      render json: feature_collection(datasets)
    end

    def show
      dataset = ImportedDataset.visible_to(current_user).find(params[:id])
      render json: feature_collection([dataset])
    end

    private

    def feature_collection(datasets)
      features = datasets.flat_map do |dataset|
        latest_positions = latest_tracker_positions(dataset)
        Array(dataset.current_version&.records).filter_map.with_index do |record, index|
          if dataset.data_type == "village_boundaries"
            geometry = JSON.parse(record["geometry"].to_s)
            next unless %w[Polygon MultiPolygon].include?(geometry["type"])

            next({ type: "Feature", id: "#{dataset.id}-#{index}", geometry: geometry,
              properties: record.except("geometry").merge(
                "data_type" => dataset.data_type, "dataset_id" => dataset.id.to_s,
                "dataset_name" => dataset.name, "version" => dataset.current_version.version_number) })
          end

          lat, lon = record["latitude"], record["longitude"]
          if (latest = latest_positions[record["sensor_id"].to_s])
            lat, lon = latest.latitude, latest.longitude
            record = record.merge("observed_at" => latest.observed_at&.iso8601, "speed_kmh" => latest.speed_kmh)
          end
          next if lat.blank? || lon.blank?
          { type: "Feature", id: "#{dataset.id}-#{index}",
            geometry: { type: "Point", coordinates: [lon.to_f, lat.to_f] },
            properties: record.except("latitude", "longitude", "token").merge(
              "data_type" => dataset.data_type, "dataset_id" => dataset.id.to_s, "dataset_name" => dataset.name,
              "version" => dataset.current_version.version_number) }
        rescue JSON::ParserError
          nil
        end
      end
      metadata = datasets.map do |dataset|
        { id: dataset.id.to_s, name: dataset.name, data_type: dataset.data_type,
          geometry_type: dataset.geometry_type, record_count: dataset.record_count }
      end
      { type: "FeatureCollection", features:, datasets: metadata }
    end

    # Location trackers move, so their map position is the latest reading rather than the registered point.
    def latest_tracker_positions(dataset)
      return {} unless dataset.data_type == "location_trackers"

      LocationTrackerReading.collection.aggregate([
        { "$match" => { "imported_dataset_id" => dataset.id } },
        { "$sort" => { "observed_at" => -1 } },
        { "$group" => { "_id" => "$sensor_id", "reading" => { "$first" => "$$ROOT" } } }
      ]).to_h { |row| [row["_id"].to_s, Mongoid::Factory.from_db(LocationTrackerReading, row["reading"])] }
    end
  end
end
