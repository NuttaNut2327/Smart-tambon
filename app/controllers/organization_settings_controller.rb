# Settings for one อบต., edited by its subdistrict admins and shared by every account in the organisation.
class OrganizationSettingsController < ApplicationController
  skip_before_action :authenticate_user!, only: :logo
  skip_before_action :require_access_configuration!, only: :logo
  before_action :require_organization_admin!, except: :logo
  before_action :set_setting, except: :logo

  def show; end

  def update
    @setting.assign_attributes(setting_params)
    @setting.report_sources_text = params.dig(:organization_setting, :report_sources_text) if params.dig(:organization_setting).key?(:report_sources_text)
    # "ใช้ค่าของระบบ" leaves map layers unset so the system default applies.
    @setting.map_layers = params.dig(:organization_setting, :map_layers_mode) == "custom" ? Array(params.dig(:organization_setting, :map_layers)).compact_blank : nil
    @setting.map_zoom = nil if params.dig(:organization_setting, :map_zoom).blank?
    @setting.updated_by = current_user.username
    replace_logo
    if @setting.save
      redirect_to organization_settings_path(anchor: params[:section]), notice: "บันทึกการตั้งค่า อบต. เรียบร้อยแล้ว"
    else
      render :show, status: :unprocessable_entity
    end
  rescue IncidentPhotoUploadService::InvalidUpload => error
    @setting.errors.add(:logo, error.message)
    render :show, status: :unprocessable_entity
  end

  def regenerate_public_link
    @setting.inc(public_report_version: 1)
    @setting.set(updated_by: current_user.username)
    redirect_to organization_settings_path(anchor: "settings-public-report"), notice: "สร้างลิงก์แจ้งเหตุใหม่แล้ว ลิงก์เดิมทั้งหมดใช้งานไม่ได้อีกต่อไป"
  end

  def logo
    setting = OrganizationSetting.where(organization_key: params[:key]).first
    return redirect_to(view_context.image_path("logo-smart-tambon.png")) if setting&.logo.blank?

    object = IncidentPhotoUploadService.download(setting.logo)
    expires_in 1.hour, public: true
    send_data object.body.read, type: setting.logo["content_type"], disposition: "inline"
  rescue IncidentPhotoUploadService::ObjectNotFound, Aws::S3::Errors::ServiceError
    redirect_to view_context.image_path("logo-smart-tambon.png")
  end

  private

  def require_organization_admin!
    return if current_user.subdistrict_admin?

    redirect_to(system_admin? ? system_settings_path : root_path, alert: "เฉพาะผู้ดูแลประจำ อบต. เท่านั้นที่ตั้งค่า อบต. ได้")
  end

  def set_setting = @setting = OrganizationSetting.for(current_user)

  def setting_params
    params.require(:organization_setting).permit(:organization_name, :executive_name, :address, :phone, :email, :website,
                                                 :notify_new_incidents, :notification_sound, :notify_pending_activities,
                                                 :map_basemap, :map_zoom, :public_report_enabled, :public_report_welcome)
  end

  def replace_logo
    if params.dig(:organization_setting, :remove_logo) == "1"
      IncidentPhotoUploadService.delete_photo(@setting.logo) if @setting.logo
      @setting.logo = nil
    end
    upload = params.dig(:organization_setting, :logo_file).presence
    return unless upload

    previous = @setting.logo
    @setting.logo = IncidentPhotoUploadService.store!(prefix: "settings/organizations/#{@setting.id}", upload:)
    IncidentPhotoUploadService.delete_photo(previous) if previous
  end
end
