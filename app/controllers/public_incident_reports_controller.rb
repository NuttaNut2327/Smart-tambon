class PublicIncidentReportsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_access_configuration!

  before_action :load_report_scope
  before_action :load_subdistrict_options

  def show
    @incident = Incident.new
  end

  def create
    return head :unprocessable_entity if params[:website].present?

    @incident = Incident.new(public_incident_params)
    @incident.category = "general"
    @incident.status = "pending"
    @incident.owner_user_id = @report_owner&.id || @report_access_area&.user_id
    @incident.access_area_id = @report_access_area&.id
    @incident.user_id = @incident.owner_user_id
    @incident.report_source_type = @report_source_type
    @incident.report_source_name = @report_source_name
    @incident.subdistrict_id = @report_subdistrict&.id
    @incident.location_name = "ตำแหน่งที่ผู้แจ้งเหตุปักหมุด" if @incident.location_name.blank?
    @incident.errors.add(:description, "กรุณาระบุรายละเอียดเหตุการณ์") if @incident.description.blank?
    @incident.errors.add(:reporter_name, "กรุณาระบุชื่อผู้แจ้ง") if @incident.reporter_name.blank?
    @incident.errors.add(:reporter_contact, "กรุณาระบุเบอร์ติดต่อ") if @incident.reporter_contact.blank?
    @incident.errors.add(:base, "กรุณายืนยันว่าข้อมูลที่แจ้งเป็นความจริง") unless params[:consent] == "1"
    unless @incident.latitude&.between?(-90, 90) && @incident.longitude&.between?(-180, 180)
      @incident.errors.add(:latitude, "กรุณาปักตำแหน่งที่เกิดเหตุบนแผนที่")
    else
      point = @report_boundary.factory.point(@incident.longitude, @incident.latitude)
      @incident.errors.add(:latitude, "ตำแหน่งเกิดเหตุต้องอยู่ภายในพื้นที่รับแจ้ง") unless @report_boundary&.contains?(point)
    end
    if @incident.errors.any?
      load_subdistrict_options
      return render :show, status: :unprocessable_entity
    end

    @incident.save!
    render :success
  rescue Mongoid::Errors::Validations
    load_subdistrict_options
    render :show, status: :unprocessable_entity
  end

  private

  def load_report_scope
    payload = Rails.application.message_verifier(:public_incident_form).verify(params[:token])
    @report_source_type = (payload["source_type"] || payload[:source_type]).presence_in(%w[citizen organization]) || "citizen"
    @report_source_name = (payload["source_name"] || payload[:source_name]).to_s.strip.presence || "ประชาชน"
    case payload["scope"] || payload[:scope]
    when "access_area"
      @report_access_area = UserAccessArea.find_by(id: payload["id"] || payload[:id])
      @report_owner = @report_access_area&.user
    when "account"
      @report_owner = User.includes(:subdistrict, :access_area).find_by(id: payload["id"] || payload[:id])
      @report_access_area = @report_owner&.access_area
      @report_subdistrict = @report_owner&.subdistrict
    else
      # Keep previously shared links working after switching to permanent form links.
      @report_subdistrict = Subdistrict.includes(:province).find_by(id: payload["subdistrict_id"] || payload[:subdistrict_id])
      @report_access_area = UserAccessArea.find_by(id: payload["access_area_id"] || payload[:access_area_id])
    end
    @report_boundary = @report_access_area&.boundary || @report_subdistrict&.boundary
    @report_area_name = @report_access_area&.name.presence || "ตำบล#{@report_subdistrict&.name_th}"
    return head :not_found unless @report_boundary
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    head :not_found
  end

  def load_subdistrict_options
    @subdistricts = if @report_access_area
      Subdistrict.where(id: @report_access_area.subdistrict_ids).includes(:province).alphabetical
    elsif @report_subdistrict
      [@report_subdistrict]
    else
      []
    end
    @report_boundary_feature = @report_access_area ? @report_access_area.as_geojson : @report_subdistrict&.as_geojson
    @important_places = cached_important_places
  end

  def public_incident_params
    params.require(:incident).permit(
      :incident_type, :title, :description, :severity, :reporter_name, :reporter_contact,
      :location_name, :longitude, :latitude, :initial_impact
    )
  end

  def cached_important_places
    places = Api::PlacesController::CATEGORIES.keys.flat_map do |category|
      cache = if @report_access_area
        key = ["access_area", @report_access_area.id, @report_access_area.updated_at.to_i, category].join(":")
        LongdoPlaceCache.where(query_key: key).first
      else
        key = ["subdistrict", @report_subdistrict.code, category].join(":")
        LongdoPlaceCache.where(query_key: key).first
      end
      Array(cache&.places).map { |place| place.merge("category" => category) }
    end
    AccessBoundaryPointFilter.new(@report_boundary)
      .filter(places) { |place| [place["lon"], place["lat"]] }
      .uniq { |place| [place["lon"], place["lat"], place["name"]] }
      .first(350)
  rescue Mongo::Error
    []
  end

end
