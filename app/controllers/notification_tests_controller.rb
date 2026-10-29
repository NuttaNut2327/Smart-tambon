# อบต. admin: preview and send test messages, including a full "new incident" simulation that goes through the
# same template + channel selection as a real incident.
class NotificationTestsController < ApplicationController
  include OrganizationNotifications

  MODES = { "simulate" => "จำลองเหตุใหม่เข้ามา", "template" => "ส่งเทมเพลต", "custom" => "ข้อความอิสระ" }.freeze
  DATA_SOURCES = { "latest" => "เหตุล่าสุดของ อบต. (ข้อมูลจริง)", "sample" => "ข้อมูลตัวอย่าง" }.freeze

  def show
    load_page
    @form = { "mode" => "simulate", "tag" => "incident.created", "data" => "latest", "channel_ids" => @channels.select(&:enabled?).map { |channel| channel.id.to_s } }
    @preview = preview_for(@form)
  end

  def create
    load_page
    @form = params.permit(:mode, :tag, :data, :template_id, :message, channel_ids: []).to_h
    @form["mode"] = @form["mode"].presence_in(MODES.keys) || "simulate"
    @form["tag"] = @form["tag"].presence_in(NotificationChannel::TAGS.keys) || "incident.created"
    @preview = preview_for(@form)
    return render(:show) if params[:commit_action] == "preview"

    targets = selected_channels(@form)
    if targets.empty?
      flash.now[:alert] = @form["mode"] == "simulate" ? "ไม่มีช่องทางที่เปิดใช้และรับแท็ก “#{NotificationChannel::TAGS[@form['tag']]}”" : "กรุณาเลือกช่องทางอย่างน้อย 1 ช่องทาง"
      return render(:show, status: :unprocessable_entity)
    end

    deliveries = targets.map do |channel|
      Notifications::Service.deliver(
        organization_key: organization_key,
        channel: channel,
        text: @preview[:text],
        event: @form["tag"],
        variables: @preview[:variables],
        resource_id: @preview[:incident]&.id,
        sent_by: current_user.username,
        source: @form["mode"] == "simulate" ? "simulation" : "test"
      )
    end
    sent, failed = deliveries.partition(&:sent?)
    message = "ส่งสำเร็จ #{sent.size} ช่องทาง#{failed.any? ? " · ไม่สำเร็จ #{failed.size} (#{failed.map { |delivery| "#{delivery.channel_name}: #{delivery.error}" }.join(' | ')})" : ''}"
    redirect_to notification_tests_path, failed.any? ? { alert: message } : { notice: message }
  end

  private

  def load_page
    @channels = NotificationChannel.for_organization(organization_key).order_by(created_at: :asc).to_a
    @templates = NotificationTemplate.for_organization(organization_key).order_by(tag: :asc, updated_at: :desc).to_a
    @deliveries = NotificationDelivery.for_organization(organization_key).desc(:created_at).limit(30).to_a
  end

  # Simulation follows the real event path: channels that are enabled and subscribed to the tag.
  def selected_channels(form)
    return @channels.select { |channel| channel.enabled? && channel.subscribed?(form["tag"]) } if form["mode"] == "simulate"

    ids = Array(form["channel_ids"])
    @channels.select { |channel| ids.include?(channel.id.to_s) }
  end

  def preview_for(form)
    incident = latest_incident(form["tag"]) if form["data"] == "latest" && form["mode"] != "custom"
    variables = incident ? Notifications::Dispatcher.incident_variables(incident, organization_key) : Notifications::Dispatcher.sample_variables(organization_key)
    variables = variables.merge("message" => form["message"].to_s) if form["message"].present?
    body = case form["mode"]
           when "custom" then form["message"].to_s
           when "template" then @templates.find { |template| template.id.to_s == form["template_id"].to_s }&.body || NotificationTemplate.body_for(organization_key, form["tag"])
           else NotificationTemplate.body_for(organization_key, form["tag"])
           end
    { text: Notifications::Dispatcher.render(body, variables), variables: variables, incident: incident }
  end

  def latest_incident(tag)
    category = { "disaster.created" => "disaster", "activity.created" => "activity" }.fetch(tag, "general")
    Incident.visible_to(current_user).where(category: category).desc(:created_at).first
  end
end
