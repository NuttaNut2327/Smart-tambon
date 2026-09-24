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
          next if lat.blank? || lon.blank?
          { type: "Feature", id: "#{dataset.id}-#{index}",
            geometry: { type: "Point", coordinates: [lon.to_f, lat.to_f] },
            properties: record.except("latitude", "longitude").merge(
              "data_type" => dataset.data_type, "dataset_id" => dataset.id.to_s, "dataset_name" => dataset.name,
              "version" => dataset.current_version.version_number) }
        rescue JSON::ParserError
          nil
        end
      end
      { type: "FeatureCollection", features: }
    end
  end
end
