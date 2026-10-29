# System-wide settings for the system admin: branding, API keys, map defaults and service status.
class SystemSettingsController < ApplicationController
  skip_before_action :authenticate_user!, only: :logo
  skip_before_action :require_access_configuration!, only: :logo
  before_action :require_settings_admin!, except: :logo
  before_action :set_setting

  def show; end

  def update
    @setting.assign_attributes(setting_params)
    SystemSetting::SECRETS.each_key do |name|
      @setting.assign_secret(name, params.dig(:system_setting, name), clear: params.dig(:system_setting, "clear_#{name}") == "1")
    end
    @setting.map_layers = Array(params.dig(:system_setting, :map_layers)).compact_blank
    @setting.updated_by = current_user.username
    replace_logo
    if @setting.save
      redirect_to system_settings_path(anchor: params[:section]), notice: "บันทึกการตั้งค่าระบบเรียบร้อยแล้ว"
    else
      render :show, status: :unprocessable_entity
    end
  rescue IncidentPhotoUploadService::InvalidUpload => error
    @setting.errors.add(:logo, error.message)
    render :show, status: :unprocessable_entity
  end

  def status
    @checks = SystemStatusService.call
  end

  def purge_demo_data
    kind = params[:kind].to_s
    return redirect_to(system_settings_path(anchor: "settings-demo"), alert: "ไม่รู้จักชนิดข้อมูลสาธิต") unless DemoData::KINDS.key?(kind)

    removed = DemoData.purge!(kind)
    redirect_to system_settings_path(anchor: "settings-demo"), notice: "ลบ#{DemoData::KINDS[kind][:label]}ที่เป็นข้อมูลสาธิต #{removed} รายการแล้ว"
  end

  def logo
    return redirect_to(view_context.image_path("logo-smart-tambon.png")) if @setting.logo.blank?

    object = IncidentPhotoUploadService.download(@setting.logo)
    expires_in 1.hour, public: true
    send_data object.body.read, type: @setting.logo["content_type"], disposition: "inline"
  rescue IncidentPhotoUploadService::ObjectNotFound, Aws::S3::Errors::ServiceError
    redirect_to view_context.image_path("logo-smart-tambon.png")
  end

  private

  def set_setting = @setting = SystemSetting.current

  def require_settings_admin!
    return if system_admin?

    redirect_to(current_user.subdistrict_admin? ? organization_settings_path : root_path, alert: "เฉพาะผู้ดูแลระบบเท่านั้นที่ตั้งค่าระบบได้")
  end

  def setting_params
    params.require(:system_setting).permit(:system_name, :system_short_name, :organization_name, :contact_email, :contact_phone,
                                           :footer_text, :login_message, :geocoder_url, :building_tiles_url, :building_tiles_layer, :map_basemap, :map_center_lat, :map_center_lon, :map_zoom,
                                           :registration_enabled, :registration_terms, :registration_pdpa, :demo_data_visible)
  end

  def replace_logo
    if params.dig(:system_setting, :remove_logo) == "1"
      IncidentPhotoUploadService.delete_photo(@setting.logo) if @setting.logo
      @setting.logo = nil
    end
    # A new logo is an upload (stored in the image library) or a picture picked from the library.
    upload = params.dig(:system_setting, :logo_file).presence
    picked = ImageLibrary.pick(current_user, params.dig(:system_setting, :logo_library_image_id)).first
    return unless upload || picked

    previous = @setting.logo
    image = picked || ImageLibrary.import!(upload:, owner_user_id: current_user.id, subdistrict_id: current_user.subdistrict_id,
                                           source: "logo", uploaded_by: current_user.username)
    @setting.logo = image.attachment
    IncidentPhotoUploadService.delete_photo(previous) if previous
  end
end
