module Api
  class AnalysisRecordsController < ApplicationController
    def index
      records = AnalysisRecord.where(user: current_user).order(created_at: :desc).limit(50)
      render json: records.map { |record| serialize(record) }
    end

    def create
      record = AnalysisRecord.create!(record_params.merge(user: current_user, subdistrict: current_user.subdistrict))
      render json: serialize(record), status: :created
    end

    private

    def record_params
      params.require(:analysis_record).permit(:name, :selection_type, geometry: {}, summary: {}, places: %i[id name category lon lat address])
    end

    def serialize(record)
      record.as_json(only: %i[id name selection_type geometry summary places created_at])
    end
  end
end
