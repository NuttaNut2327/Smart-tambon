# System admin: the central LINE OA, shared Telegram bot and Signal gateway used by every อบต.
class NotificationSettingsController < ApplicationController
  before_action :require_system_admin!
  before_action :set_setting

  def show
    @line_groups = LineGroup.desc(:last_event_at).limit(100).to_a
    @channel_counts = NotificationChannel.collection.aggregate([{ "$group" => { "_id" => "$kind", "count" => { "$sum" => 1 } } }]).to_h { |row| [row["_id"], row["count"]] }
  end

  def update
    @setting.assign_attributes(setting_params)
    %w[line_channel_access_token line_channel_secret telegram_bot_token].each do |name|
      @setting.public_send(:"assign_#{name}", params.dig(:notification_setting, name), clear: params.dig(:notification_setting, "clear_#{name}") == "1")
    end
    @setting.updated_by = current_user.username
    if @setting.save
      redirect_to notification_settings_path, notice: "บันทึกการตั้งค่าการแจ้งเตือนส่วนกลางแล้ว"
    else
      show
      render :show, status: :unprocessable_entity
    end
  end

  def test_line
    info = Notifications::Service.line_client(setting: @setting).bot_info
    @setting.set(line_bot_name: info["displayName"]) if info["displayName"].present?
    redirect_to notification_settings_path, notice: "เชื่อมต่อ LINE OA สำเร็จ: #{info['displayName']} (#{info['basicId']}) · โหมดตอบกลับ #{info['chatMode']}"
  rescue Notifications::Senders::DeliveryError => error
    redirect_to notification_settings_path, alert: error.message
  end

  private

  def set_setting = @setting = NotificationSetting.current

  def setting_params
    params.require(:notification_setting).permit(:line_enabled, :line_reply_group_id, :telegram_enabled, :signal_enabled,
                                                 :signal_api_url, :signal_number, :webhook_enabled, :public_base_url)
  end

  def require_system_admin!
    return if system_admin?

    redirect_to(current_user.subdistrict_admin? ? notification_channels_path : root_path, alert: "เฉพาะผู้ดูแลระบบเท่านั้นที่ตั้งค่าการแจ้งเตือนส่วนกลางได้")
  end
end
