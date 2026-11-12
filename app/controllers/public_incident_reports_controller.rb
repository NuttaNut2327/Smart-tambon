class PublicIncidentReportsController < ApplicationController
  DUPLICATE_RADIUS_METERS = 300
  DUPLICATE_LOOKBACK = 7.days
  DUPLICATE_STATUSES = %w[pending assessing in_progress].freeze
  skip_before_action :authenticate_user!
  skip_before_action :require_access_configuration!

  before_action :load_report_scope, except: :liff_bootstrap
  before_action :load_line_configuration, except: :liff_bootstrap
  before_action :load_subdistrict_options, only: %i[show create liff_show liff_create]

  def show
    @liff_mode = false
    @incident = Incident.new
    @incident.severity = nil
  end

  def liff_show
    @liff_mode = true
    @incident = Incident.new
    @incident.severity = nil
    render :show
  end

  def liff_follow
    @liff_mode = true
    @follow_incident = followable_incident
    return head :not_found unless @follow_incident

    render layout: false
  end

  def follow_existing
    incident = followable_incident
    return render(json: { error: "ไม่พบเหตุการณ์ที่สามารถติดตามได้" }, status: :not_found) unless incident

    identity = verify_line_identity(params[:line_id_token])
    return render(json: { error: "ไม่สามารถยืนยันบัญชี LINE ได้" }, status: :unprocessable_entity) unless identity

    follow_incident!(incident, identity)
    render json: { ok: true, reference_code: incident.reference_code, status_label: public_status_label(incident.status) }
  end

  # Primary LIFF endpoint. LINE first opens this URL with liff.state=/report/:token; liff.init then performs
  # the secondary redirect to /liff/report/:token, where the actual form verifies the user's ID token.
  def liff_bootstrap
    state_path = params["liff.state"].to_s
    token = state_path[%r{\A/report/([^/?]+)}, 1] || state_path[%r{\A/follow/([^/]+)/}, 1]
    return head :not_found if token.blank?

    payload = Rails.application.message_verifier(:public_incident_form).verify(token)
    owner = case payload["scope"] || payload[:scope]
            when "access_area" then UserAccessArea.find_by(id: payload["id"] || payload[:id])&.user
            when "account" then User.find_by(id: payload["id"] || payload[:id])
            end
    setting = OrganizationSetting.for(owner)
    return head :not_found unless setting&.citizen_liff_ready?

    @liff_id = setting.citizen_line_liff_id
    follow_incident_id = state_path[%r{\A/follow/[^/]+/([^/?]+)}, 1]
    @liff_report_path = if follow_incident_id
      liff_follow_public_incident_report_path(token:, incident_id: follow_incident_id)
    else
      liff_public_incident_report_path(token:)
    end
    render layout: false
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    head :not_found
  end

  def liff_create
    @liff_mode = true
    create
  end

  def reverse_geocode
    latitude = Float(params[:lat], exception: false)
    longitude = Float(params[:lon], exception: false)
    return render json: { error: "พิกัดไม่ถูกต้อง" }, status: :unprocessable_entity unless latitude&.between?(-90, 90) && longitude&.between?(-180, 180)

    point = @report_boundary.factory.point(longitude, latitude)
    return render json: { error: "ตำแหน่งอยู่นอกพื้นที่รับแจ้ง" }, status: :unprocessable_entity unless @report_boundary.contains?(point)

    render json: ReverseGeocoder.call(latitude: latitude, longitude: longitude)
  rescue ReverseGeocoder::ConfigurationError => error
    render json: { error: error.message }, status: :service_unavailable
  rescue ReverseGeocoder::Error => error
    render json: { error: error.message }, status: :bad_gateway
  end

  def similar_incidents
    latitude = Float(params[:latitude], exception: false)
    longitude = Float(params[:longitude], exception: false)
    incident_type = params[:incident_type].to_s.strip
    return render(json: { incidents: [] }) unless valid_duplicate_coordinates?(latitude, longitude) && incident_type.present?

    incidents = duplicate_candidates(incident_type:, latitude:, longitude:).first(5).map do |incident, distance|
      {
        id: incident.id.to_s,
        reference_code: incident.reference_code,
        title: public_duplicate_title(incident),
        incident_type: incident.incident_type,
        status: incident.status,
        status_label: public_status_label(incident.status),
        distance_meters: distance.round,
        reported_at: incident.created_at&.iso8601
      }
    end
    render json: { incidents:, radius_meters: DUPLICATE_RADIUS_METERS, lookback_days: 7 }
  end

  def confirm_similar_incident
    latitude = Float(params[:latitude], exception: false)
    longitude = Float(params[:longitude], exception: false)
    incident_type = params[:incident_type].to_s.strip
    candidate = duplicate_candidates(incident_type:, latitude:, longitude:)
      .find { |incident, _distance| incident.id.to_s == params[:incident_id].to_s }&.first
    return render(json: { error: "ไม่พบเหตุการณ์ที่ตรงตามเงื่อนไข" }, status: :not_found) unless candidate

    confirmation = {
      "fingerprint" => duplicate_confirmation_fingerprint,
      "confirmed_at" => Time.current.utc.iso8601,
      "source" => params[:line_id_token].present? ? "line_liff" : "public_web"
    }
    identity = attach_confirmation_line_identity(confirmation) if params[:line_id_token].present?
    unless Array(candidate.duplicate_confirmations).any? { |item| item["fingerprint"] == confirmation["fingerprint"] }
      candidate.add_to_set(duplicate_confirmations: confirmation)
    end
    follow_incident!(candidate, identity) if identity
    follow_path = "/follow/#{params[:token]}/#{candidate.id}"
    render json: {
      ok: true,
      reference_code: candidate.reference_code,
      status_label: public_status_label(candidate.status),
      line_following: identity.present?,
      connect_line_url: (@organization_setting.citizen_liff_url(follow_path) if !identity && @organization_setting&.citizen_liff_ready?),
      message: identity ? "ระบบจะส่งความคืบหน้าของเรื่องนี้ให้คุณผ่าน LINE" : "ระบบจะไม่สร้างเรื่องซ้ำ"
    }
  end

  def create
    return head :unprocessable_entity if params[:website].present?

    uploads = IncidentPhotoUploadService.uploads_from(params)
    @incident = Incident.new(public_incident_params)
    @incident.severity = params.dig(:incident, :severity).presence
    @incident.category = "general"
    @incident.status = "pending"
    @incident.owner_user_id = @report_owner&.id || @report_access_area&.user_id
    @incident.access_area_id = @report_access_area&.id
    @incident.user_id = @incident.owner_user_id
    @incident.report_source_type = @report_source_type
    @incident.report_source_name = @report_source_name
    @incident.submission_channel = @liff_mode ? "line_liff" : "public_web"
    @incident.subdistrict_id = @report_subdistrict&.id
    @incident.location_name = "ตำแหน่งที่ผู้แจ้งเหตุปักหมุด" if @incident.location_name.blank?
    attach_line_identity if @liff_mode
    @incident.errors.add(:description, "กรุณาระบุรายละเอียดเหตุการณ์") if @incident.description.blank?
    @incident.errors.add(:incident_type, "กรุณาเลือกประเภทเหตุการณ์") if @incident.incident_type.blank?
    @incident.errors.add(:severity, "กรุณาเลือกระดับความเร่งด่วน") if @incident.severity.blank?
    @incident.errors.add(:reporter_name, "กรุณาระบุชื่อผู้แจ้ง") if @incident.reporter_name.blank?
    @incident.errors.add(:reporter_contact, "กรุณาระบุเบอร์ติดต่อ") if @incident.reporter_contact.blank?
    @incident.errors.add(:base, "กรุณายืนยันว่าข้อมูลที่แจ้งเป็นความจริง") unless params[:consent] == "1"
    begin
      IncidentPhotoUploadService.validate!(uploads)
    rescue IncidentPhotoUploadService::InvalidUpload => error
      @incident.errors.add(:base, error.message)
    end
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
    begin
      IncidentPhotoUploadService.attach!(incident: @incident, uploads: uploads)
    rescue StandardError => error
      Rails.logger.error("Incident photo upload failed: #{error.class}: #{error.message}")
      IncidentPhotoUploadService.purge_for(@incident)
      @incident.destroy
      @incident.errors.add(:base, "อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่อีกครั้ง")
      load_subdistrict_options
      return render :show, status: :service_unavailable
    end
    CitizenLineNotificationJob.perform_later(@incident.id.to_s, "submitted") if @incident.line_notification_enabled?
    render :success
  rescue Mongoid::Errors::Validations
    load_subdistrict_options
    render :show, status: :unprocessable_entity
  end

  private

  def duplicate_candidates(incident_type:, latitude:, longitude:)
    return [] unless valid_duplicate_coordinates?(latitude, longitude)

    latitude_delta = DUPLICATE_RADIUS_METERS / 111_320.0
    longitude_scale = Math.cos(latitude * Math::PI / 180).abs
    longitude_delta = DUPLICATE_RADIUS_METERS / (111_320.0 * [longitude_scale, 0.01].max)
    duplicate_scope.where(
      incident_type:,
      :status.in => DUPLICATE_STATUSES,
      :created_at.gte => DUPLICATE_LOOKBACK.ago,
      :latitude.gte => latitude - latitude_delta,
      :latitude.lte => latitude + latitude_delta,
      :longitude.gte => longitude - longitude_delta,
      :longitude.lte => longitude + longitude_delta
    ).to_a.filter_map do |incident|
      distance = haversine_distance(latitude, longitude, incident.latitude, incident.longitude)
      [incident, distance] if distance <= DUPLICATE_RADIUS_METERS
    end.sort_by(&:last)
  end

  def duplicate_scope
    return Incident.none unless @report_owner

    Incident.visible_to(@report_owner).incidents_only.where(deleted_at: nil)
  end

  def valid_duplicate_coordinates?(latitude, longitude)
    latitude&.between?(-90, 90) && longitude&.between?(-180, 180)
  end

  def haversine_distance(latitude_a, longitude_a, latitude_b, longitude_b)
    return Float::INFINITY unless valid_duplicate_coordinates?(latitude_b, longitude_b)

    radius = 6_371_000.0
    lat1 = latitude_a * Math::PI / 180
    lat2 = latitude_b * Math::PI / 180
    delta_lat = (latitude_b - latitude_a) * Math::PI / 180
    delta_lon = (longitude_b - longitude_a) * Math::PI / 180
    value = Math.sin(delta_lat / 2)**2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(delta_lon / 2)**2
    radius * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value))
  end

  def public_status_label(status)
    { "pending" => "รอเจ้าหน้าที่ตรวจสอบ", "assessing" => "เจ้าหน้าที่รับเรื่องแล้ว", "in_progress" => "กำลังดำเนินการ" }.fetch(status, status)
  end

  def public_duplicate_title(incident)
    return "เหตุการณ์ประเภท #{incident.incident_type}" if incident.status == "pending"

    incident.title.to_s.truncate(100).presence || "เหตุการณ์ประเภท #{incident.incident_type}"
  end

  def duplicate_confirmation_fingerprint
    raw = [request.remote_ip, request.user_agent.to_s, session.id.to_s].join("|")
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw)
  end

  def followable_incident
    duplicate_scope.where(
      id: params[:incident_id],
      :status.in => DUPLICATE_STATUSES,
      :created_at.gte => DUPLICATE_LOOKBACK.ago
    ).first
  end

  def verify_line_identity(id_token)
    return unless @organization_setting&.citizen_liff_ready? && id_token.present?

    CitizenLine::IdTokenVerifier.call(id_token:, channel_id: @organization_setting.citizen_line_login_channel_id)
  rescue CitizenLine::IdTokenVerifier::VerificationError
    nil
  end

  def follow_incident!(incident, identity)
    CitizenIncidentFollower.find_or_create_by!(incident_id: incident.id, line_user_id: identity["sub"]) do |follower|
      follower.line_display_name = identity["name"].to_s.truncate(120)
    end
  end

  def attach_confirmation_line_identity(confirmation)
    identity = verify_line_identity(params[:line_id_token])
    return unless identity

    confirmation["line_user_id"] = identity["sub"]
    confirmation["line_display_name"] = identity["name"].to_s.truncate(120)
    identity
  end

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
    @report_owner ||= @report_access_area&.user
    @report_area_name = @report_access_area&.name.presence || "ตำบล#{@report_subdistrict&.name_th}"
    return head :not_found unless @report_boundary

    # อบต. settings: regenerating the link bumps the version (old links stop working); reporting can be paused.
    @organization_setting = OrganizationSetting.for(@report_owner)
    return unless @organization_setting
    return head :not_found if (payload["version"] || payload[:version]).to_i != @organization_setting.public_report_version.to_i
    render :closed, status: :service_unavailable unless @organization_setting.public_report_enabled
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

  def show_announcements? = false

  def public_incident_params
    params.require(:incident).permit(
      :incident_type, :incident_type_other, :title, :description, :severity, :reporter_name, :reporter_contact,
      :location_name, :longitude, :latitude, :initial_impact
    )
  end

  def attach_line_identity
    setting = @organization_setting
    unless setting.citizen_liff_ready?
      @incident.errors.add(:base, "ระบบ LINE สำหรับประชาชนยังตั้งค่าไม่ครบ")
      return
    end
    identity = CitizenLine::IdTokenVerifier.call(id_token: params[:line_id_token], channel_id: setting.citizen_line_login_channel_id)
    @incident.reporter_line_user_id = identity["sub"]
    @incident.reporter_line_display_name = identity["name"]
    @incident.reporter_line_verified_at = Time.current
    @incident.line_notification_enabled = true
  rescue CitizenLine::IdTokenVerifier::VerificationError => error
    @incident.errors.add(:base, error.message)
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

  def load_line_configuration
    @line_setting = @organization_setting || OrganizationSetting.new
  end

end
