module Api
  # Historical disaster archive: GeoJSON footprints, statistics and the seasonal outlook.
  class DisasterEventsController < ApplicationController
    def index
      events = filtered_scope.order_by(started_at: :desc).limit(params.fetch(:limit, 1000).to_i.clamp(1, 5000))
      render json: { type: "FeatureCollection", features: events.map(&:as_feature) }
    end

    def statistics
      render json: DisasterStatistics.new(filtered_scope).call
    end

    # GET /api/disaster_events/outlook?date=2026-10-24&rain_3d_mm=120
    def outlook
      date = params[:date].present? ? Date.parse(params[:date]) : Date.current
      rain = params[:rain_3d_mm].presence&.to_f
      render json: DisasterOutlook.new(current_user, scope: filtered_scope(skip_dates: true), date:, rain_3d_mm: rain).call
    rescue Date::Error
      render json: { error: "รูปแบบวันที่ไม่ถูกต้อง ใช้ YYYY-MM-DD" }, status: :unprocessable_entity
    end

    private

    def filtered_scope(skip_dates: false)
      scope = DisasterEvent.visible_to(current_user)
      scope = scope.where(:hazard.in => params[:hazard].to_s.split(",")) if params[:hazard].present?
      scope = scope.where(subdistrict_id: params[:subdistrict_id].to_i) if params[:subdistrict_id].present?
      scope = scope.where(simulated: ActiveModel::Type::Boolean.new.cast(params[:simulated])) if params.key?(:simulated)
      return scope if skip_dates

      scope = scope.where(:started_at.gte => Date.parse(params[:from]).beginning_of_day) if params[:from].present?
      scope = scope.where(:started_at.lte => Date.parse(params[:to]).end_of_day) if params[:to].present?
      scope
    end
  end
end
