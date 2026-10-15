# อบต. admin: the group chats and webhooks this organisation sends notifications to.
class NotificationChannelsController < ApplicationController
  include OrganizationNotifications

  before_action :set_channel, only: %i[edit update destroy test]

  def index
    @channels = NotificationChannel.for_organization(organization_key).order_by(created_at: :asc).to_a
    @setting = NotificationSetting.current
  end

  def new
    @channel = NotificationChannel.new(kind: params[:kind].presence_in(NotificationChannel::KINDS.keys) || "line")
  end

  def create
    @channel = NotificationChannel.new(channel_params.merge(organization_key: organization_key, created_by: current_user.username))
    save_channel(:new, "เพิ่มช่องทาง #{@channel.name} แล้ว — กด “ทดสอบ” เพื่อลองส่งข้อความ")
  end

  def edit; end

  def update
    @channel.assign_attributes(channel_params)
    save_channel(:edit, "บันทึกช่องทาง #{@channel.name} แล้ว")
  end

  def destroy
    @channel.destroy
    redirect_to notification_channels_path, notice: "ลบช่องทาง #{@channel.name} แล้ว"
  end

  def test
    text = "✅ ทดสอบการแจ้งเตือนจาก #{SystemSetting.current.system_short_name}\nช่องทาง: #{@channel.name}\nเวลา: #{Notifications::Dispatcher.thai_time(Time.current)}\nโดย: #{current_user.username}"
    delivery = Notifications::Dispatcher.new(organization_key: organization_key, sent_by: current_user.username, source: "test")
                                        .deliver(@channel, text, tag: "announcement", variables: { "message" => text })
    if delivery.sent?
      redirect_to notification_channels_path, notice: "ส่งข้อความทดสอบไปยัง #{@channel.name} สำเร็จ"
    else
      redirect_to notification_channels_path, alert: "ส่งไปยัง #{@channel.name} ไม่สำเร็จ: #{delivery.error}"
    end
  end

  # Helps find a Telegram group's Chat ID from the bot's recent updates.
  def telegram_chats
    channel = NotificationChannel.new(kind: "telegram", organization_key: organization_key)
    channel.assign_token(params[:token])
    if params[:channel_id].present? && params[:token].blank?
      channel = NotificationChannel.for_organization(organization_key).find(params[:channel_id])
    end
    render json: Notifications::Senders::Telegram.new(channel, NotificationSetting.current).recent_chats
  rescue Notifications::Senders::DeliveryError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def signal_groups
    render json: Notifications::Senders::Signal.new(nil, NotificationSetting.current).groups
  rescue Notifications::Senders::DeliveryError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def set_channel = @channel = NotificationChannel.for_organization(organization_key).find(params[:id])

  def channel_params
    params.require(:notification_channel).permit(:name, :kind, :target, :enabled, tags: [])
  end

  def save_channel(template, notice)
    @channel.tags = Array(params.dig(:notification_channel, :tags)).compact_blank
    @channel.assign_token(params.dig(:notification_channel, :token), clear: params.dig(:notification_channel, :clear_token) == "1")
    @channel.updated_by = current_user.username
    return render(template, status: :unprocessable_entity) unless @channel.save

    redirect_to notification_channels_path, notice: notice
  end
end
