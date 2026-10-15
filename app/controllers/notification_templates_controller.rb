# อบต. admin: message templates (name, tag, body with {{variables}}).
class NotificationTemplatesController < ApplicationController
  include OrganizationNotifications

  before_action :set_template, only: %i[edit update destroy]

  def index
    @templates = NotificationTemplate.for_organization(organization_key).order_by(tag: :asc, updated_at: :desc).to_a
    @in_use = @templates.group_by(&:tag).transform_values { |list| list.max_by(&:updated_at).id }
  end

  def new
    tag = params[:tag].presence_in(NotificationChannel::TAGS.keys) || "incident.created"
    @template = NotificationTemplate.new(tag: tag, name: NotificationChannel::TAGS[tag], body: NotificationTemplate::DEFAULTS[tag])
  end

  def create
    @template = NotificationTemplate.new(template_params.merge(organization_key: organization_key, updated_by: current_user.username))
    return render(:new, status: :unprocessable_entity) unless @template.save

    redirect_to notification_templates_path, notice: "บันทึกเทมเพลต #{@template.name} แล้ว"
  end

  def edit; end

  def update
    return render(:edit, status: :unprocessable_entity) unless @template.update(template_params.merge(updated_by: current_user.username))

    redirect_to notification_templates_path, notice: "บันทึกเทมเพลต #{@template.name} แล้ว"
  end

  def destroy
    @template.destroy
    redirect_to notification_templates_path, notice: "ลบเทมเพลต #{@template.name} แล้ว"
  end

  private

  def set_template = @template = NotificationTemplate.for_organization(organization_key).find(params[:id])

  def template_params = params.require(:notification_template).permit(:name, :tag, :body)
end
