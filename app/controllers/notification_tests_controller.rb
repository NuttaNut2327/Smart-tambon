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
    @form = params.permit(:mode, :tag, :data, :template_id, :message, :citizen_incident_id, channel_ids: []).to_h
    @form["mode"] = @form["mode"].presence_in(MODES.keys) || "simulate"
    @form["tag"] = @form["tag"].presence_in(NotificationTemplate::TAGS.keys) || "incident.created"
    @preview = preview_for(@form)
    return render(:show) if params[:commit_action] == "preview"
    return send_citizen_test if citizen_tag?(@form["tag"])

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
    @citizen_recipients = Incident.visible_to(current_user)
      .where(line_notification_enabled: true, :reporter_line_user_id.ne => nil)
      .desc(:created_at).limit(20).to_a
    @history_start_date = history_date(:history_start_date)
    @history_end_date = history_date(:history_end_date)
    @history_tag = params[:history_tag].presence_in(NotificationChannel::TAGS.keys)
    deliveries = NotificationDelivery.for_organization(organization_key)
    deliveries = deliveries.where(:created_at.gte => @history_start_date.in_time_zone.beginning_of_day) if @history_start_date
    deliveries = deliveries.where(:created_at.lte => @history_end_date.in_time_zone.end_of_day) if @history_end_date
    deliveries = deliveries.where(tag: @history_tag) if @history_tag
    @deliveries = deliveries.desc(:created_at).limit(30).to_a
  end

  def history_date(key)
    Date.iso8601(params[key]) if params[key].present?
  rescue Date::Error
    nil
  end

  # Simulation follows the real event path: channels that are enabled and subscribed to the tag.
  def selected_channels(form)
    return @channels.select { |channel| channel.enabled? && channel.subscribed?(form["tag"]) } if form["mode"] == "simulate"

    ids = Array(form["channel_ids"])
    @channels.select { |channel| ids.include?(channel.id.to_s) }
  end

  def preview_for(form)
    incident = if citizen_tag?(form["tag"])
      @citizen_recipients.find { |item| item.id.to_s == form["citizen_incident_id"].to_s }
    elsif form["data"] == "latest" && form["mode"] != "custom"
      latest_incident(form["tag"])
    end
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

  def citizen_tag?(tag) = NotificationTemplate::CITIZEN_TAGS.key?(tag)

  def send_citizen_test
    incident = @preview[:incident]
    unless incident&.reporter_line_user_id.present?
      flash.now[:alert] = "กรุณาเลือกเรื่องที่เชื่อม LINE เพื่อเป็นผู้รับข้อความทดสอบ"
      return render(:show, status: :unprocessable_entity)
    end

    setting = OrganizationSetting.for(current_user)
    unless setting&.citizen_line_ready?
      flash.now[:alert] = "ยังไม่ได้ตั้งค่า LINE OA สำหรับรับแจ้งเหตุประจำตำบล"
      return render(:show, status: :unprocessable_entity)
    end

    CitizenLine::Client.new(setting:).push(incident.reporter_line_user_id, @preview[:text])
    redirect_to notification_tests_path, notice: "ส่งข้อความทดสอบให้ผู้แจ้งเรื่อง #{incident.reference_code} สำเร็จ"
  rescue Notifications::Senders::DeliveryError => error
    redirect_to notification_tests_path, alert: "ส่งข้อความทดสอบไม่สำเร็จ: #{error.message}"
  end
end
