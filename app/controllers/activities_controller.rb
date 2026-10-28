# Planned activities in the area (annual fairs, ceremonies, markets), stored as Incident category "activity".
class ActivitiesController < ApplicationController
  before_action :finish_expired_activities
  before_action :set_activity, only: %i[edit update destroy acknowledge]
  before_action :require_activity_manager!, only: %i[edit update destroy]

  FILTERS = { "current" => "กำลังจัด/กำลังจะเริ่ม", "finished" => "สิ้นสุดแล้ว", "all" => "ทั้งหมด" }.freeze

  def index
    @filter = FILTERS.key?(params[:filter]) ? params[:filter] : "current"
    scope = Incident.visible_to(current_user).activities
    @counts = { "current" => scope.where(:status.ne => "completed").count, "finished" => scope.where(status: "completed").count, "all" => scope.count }
    scope = scope.where(:status.ne => "completed") if @filter == "current"
    scope = scope.where(status: "completed") if @filter == "finished"
    @activities = scope.to_a.sort_by { |activity| [%w[ongoing upcoming finished].index(activity.activity_phase), @filter == "finished" ? -activity.ends_at.to_i : activity.starts_at.to_i] }
  end

  def new
    @activity = Incident.new(category: "activity", incident_type: "festival", starts_at: Time.current.beginning_of_hour + 1.day, ends_at: Time.current.beginning_of_hour + 1.day + 8.hours)
  end

  def create
    @activity = Incident.new(activity_params)
    cover, photos, picked = uploads
    @activity.assign_attributes(
      category: "activity", status: "pending", severity: "general",
      user_id: current_user.id, owner_user_id: current_user.id, access_area_id: current_user.access_area&.id,
      report_source_type: "staff", report_source_name: "เจ้าหน้าที่",
      subdistrict_id: subdistrict_for(@activity) || current_user.subdistrict_id
    )
    @activity.histories = [history("บันทึกกิจกรรม", "บันทึกกิจกรรมใหม่ในระบบ")]
    return render(:new, status: :unprocessable_entity) unless location_allowed?(@activity) && @activity.save

    attach_photos(@activity, cover, photos, picked)
    redirect_to activities_path, notice: "บันทึกกิจกรรม #{@activity.title} เรียบร้อยแล้ว"
  rescue IncidentPhotoUploadService::InvalidUpload => error
    @activity.errors.add(:base, error.message)
    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    cover, photos, picked = uploads
    @activity.assign_attributes(activity_params)
    @activity.subdistrict_id = subdistrict_for(@activity) || @activity.subdistrict_id if @activity.latitude_changed? || @activity.longitude_changed?
    # Moving the end time into the future reopens an activity that had finished automatically.
    @activity.status = @activity.received_at ? "in_progress" : "pending" if @activity.status == "completed" && @activity.ends_at&.future?
    return render(:edit, status: :unprocessable_entity) unless location_allowed?(@activity) && @activity.save

    remove_photos(@activity)
    attach_photos(@activity, cover, photos, picked)
    redirect_to activities_path, notice: "อัปเดตกิจกรรม #{@activity.title} เรียบร้อยแล้ว"
  rescue IncidentPhotoUploadService::InvalidUpload => error
    @activity.errors.add(:base, error.message)
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @activity.set(deleted_at: Time.current, deleted_by: current_user.username)
    redirect_to activities_path, notice: "ลบกิจกรรม #{@activity.title} เรียบร้อยแล้ว"
  end

  def acknowledge
    return redirect_to activities_path, notice: "กิจกรรมนี้ถูกรับเรื่องแล้ว" unless @activity.status == "pending"

    @activity.histories << history("รับเรื่องแล้ว", "เจ้าหน้าที่รับทราบกิจกรรมและติดตามจนสิ้นสุดตามเวลาที่กำหนด")
    @activity.assign_attributes(status: "in_progress", received_by: current_user.username, received_by_user_id: current_user.id, received_at: Time.current)
    @activity.save!(validate: false)
    redirect_to activities_path(filter: params[:filter]), notice: "รับเรื่องกิจกรรม #{@activity.title} เรียบร้อยแล้ว"
  end

  private

  def finish_expired_activities = Incident.finish_expired_activities!

  def set_activity
    @activity = Incident.visible_to(current_user).activities.find(params[:id])
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to activities_path, alert: "ไม่พบกิจกรรมที่ต้องการ"
  end

  def require_activity_manager!
    return if @activity.nil? || current_user.can_manage_organization_data?(@activity.owner_user_id)

    redirect_to activities_path, alert: "คุณไม่มีสิทธิ์แก้ไขกิจกรรมนี้"
  end

  def activity_params
    params.require(:incident).permit(:title, :incident_type, :description, :starts_at, :ends_at, :organizer, :expected_attendees,
                                     :location_name, :latitude, :longitude, :reporter_name, :reporter_contact)
  end

  # The cover is either a new upload or one picture picked from the image library.
  def uploads
    cover = params.dig(:incident, :cover_photo).presence || ImageLibrary.pick(current_user, params.dig(:incident, :cover_library_image_id)).first
    photos = Array(params.dig(:incident, :photos)).compact_blank
    picked = ImageLibrary.pick(current_user, IncidentPhotoUploadService.library_ids_from(params))
    all = [cover, *photos, *picked].compact
    existing = (@activity&.photos || []).size - Array(params.dig(:incident, :remove_photo_ids)).size
    raise IncidentPhotoUploadService::InvalidUpload, "แนบรูปได้ไม่เกิน #{IncidentPhotoUploadService::MAX_FILES} รูปต่อกิจกรรม" if existing + all.size > IncidentPhotoUploadService::MAX_FILES

    ImageLibrary.validate!([cover, *photos].grep_v(LibraryImage).compact)
    [cover, photos, picked]
  end

  def attach_photos(activity, cover, photos, picked)
    if cover
      cover = ImageLibrary.import!(upload: cover, owner_user_id: activity.owner_user_id, subdistrict_id: activity.subdistrict_id,
                                   source: "activity", uploaded_by: current_user.username) unless cover.is_a?(LibraryImage)
      IncidentPhotoUploadService.attach!(incident: activity, uploads: [], picked: [cover])
      activity.set(cover_photo_id: cover.id.to_s)
    end
    IncidentPhotoUploadService.attach!(incident: activity, uploads: photos, picked:, uploaded_by: current_user.username) if photos.any? || picked.any?
  rescue IncidentPhotoUploadService::InvalidUpload => error
    flash[:alert] = "บันทึกกิจกรรมแล้ว แต่แนบรูปไม่สำเร็จ: #{error.message}"
  rescue StandardError => error
    Rails.logger.error("Activity photo upload failed: #{error.class}: #{error.message}")
    flash[:alert] = "บันทึกกิจกรรมแล้ว แต่อัปโหลดรูปไม่สำเร็จ กรุณาลองแนบรูปอีกครั้ง"
  end

  def remove_photos(activity)
    ids = Array(params.dig(:incident, :remove_photo_ids)).map(&:to_s)
    return if ids.empty?

    removed, kept = Array(activity.photos).partition { |photo| ids.include?(photo["id"]) }
    removed.each { |photo| IncidentPhotoUploadService.delete_photo(photo) }
    activity.set(photos: kept, cover_photo_id: ids.include?(activity.cover_photo_id) ? nil : activity.cover_photo_id)
  end

  def subdistrict_for(activity)
    return if activity.latitude.blank? || activity.longitude.blank?

    Subdistrict.where("ST_Covers(boundary::geometry, ST_SetSRID(ST_Point(?, ?), 4326))", activity.longitude.to_f, activity.latitude.to_f).pick(:id)
  end

  def location_allowed?(activity)
    return true if system_admin? || activity.latitude.blank? || activity.longitude.blank?
    return true if activity.subdistrict_id.present? && current_user.accessible_subdistrict_ids.include?(activity.subdistrict_id)

    activity.valid?
    activity.errors.add(:base, "ตำแหน่งกิจกรรมอยู่นอกพื้นที่ที่คุณดูแล")
    false
  end

  def history(title, description)
    { "title" => title, "description" => description, "occurred_at" => Time.current.utc.iso8601, "actor" => current_user.username, "resources" => [] }
  end
end
