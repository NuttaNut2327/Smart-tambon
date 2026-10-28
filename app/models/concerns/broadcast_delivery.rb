# How a news programme (BroadcastProgram) or one of its broadcasts (Broadcast) reaches people. Several modes can be on
# at once: the village PA system, outside notifications (LINE, Telegram, Facebook, …) and an in-app alert that pops up
# for every signed-in staff member of the อบต. Channel picks are kept when a mode is switched off, but only channels of
# the active modes are used.
module BroadcastDelivery
  extend ActiveSupport::Concern

  MODES = {
    "pa" => { label: "ส่งออกระบบเสียงตามสาย", icon: "campaign", hint: "สร้างไฟล์เสียงแล้วส่งไปอุปกรณ์เสียงตามสายผ่าน MQTT", kinds: %w[pa_mqtt] },
    "notification" => { label: "ระบบแจ้งเตือน (LINE ฯลฯ)", icon: "notifications_active", hint: "ส่งข้อความไปกลุ่ม LINE, Telegram, Signal, Facebook Page, Instagram หรือ Webhook",
                        kinds: %w[line telegram signal webhook facebook instagram] },
    "internal" => { label: "แจ้งเตือนภายในระบบ (Internal Alert)", icon: "notification_important", hint: "แสดง popup ให้เจ้าหน้าที่ของ อบต. ที่กำลังใช้งานระบบเห็นทันที และคนที่เข้าระบบภายหลังจนกว่าจะหมดเวลา",
                    kinds: [] }
  }.freeze
  INTERNAL_KIND = "internal_alert".freeze

  included do
    # nil on records saved before modes existed; #delivery_modes then derives them from the chosen channels.
    field :delivery_modes, type: Array
    field :internal_alert_level, type: String, default: "warning"
    field :internal_alert_hours, type: Integer, default: 24

    validates :internal_alert_level, inclusion: { in: Announcement::LEVELS.keys }
    validates :internal_alert_hours, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 168, message: "ต้องอยู่ระหว่าง 1 ถึง 168 ชั่วโมง" }
    before_validation :normalize_delivery_modes
  end

  def self.kind_label(kind) = kind == INTERNAL_KIND ? MODES.dig("internal", :label) : NotificationChannel::KINDS.dig(kind, :label)

  def delivery_modes
    super || legacy_delivery_modes
  end

  def delivers?(mode) = delivery_modes.include?(mode.to_s)
  def delivery_mode_labels = delivery_modes.map { |mode| MODES.dig(mode, :label) }
  def delivery_kinds = MODES.values_at(*delivery_modes).compact.flat_map { |mode| mode[:kinds] }

  def selected_channels
    NotificationChannel.for_organization(organization_key).where(:_id.in => Array(channel_ids)).to_a
  end

  # The channels this record will actually publish to.
  def channels = selected_channels.select { |channel| delivery_kinds.include?(channel.kind) }
  def delivery_targets? = channels.any? || delivers?("internal")

  # e.g. "เสียงตามสาย: หอกระจายข่าว ม.1 · แจ้งเตือนภายในระบบ"
  def delivery_summary
    picked = channels
    delivery_modes.filter_map do |mode|
      config = MODES[mode]
      next config[:label] if mode == "internal"

      names = picked.select { |channel| config[:kinds].include?(channel.kind) }.map(&:name)
      "#{config[:label]}: #{names.join(', ')}" if names.any?
    end.join(" · ")
  end

  private

  def legacy_delivery_modes
    kinds = selected_channels.map(&:kind)
    MODES.filter_map { |mode, config| mode if (config[:kinds] & kinds).any? }
  end

  def normalize_delivery_modes
    self.delivery_modes = Array(self[:delivery_modes]).compact_blank.map(&:to_s) & MODES.keys unless self[:delivery_modes].nil?
    self.internal_alert_level = "warning" if internal_alert_level.blank?
  end
end
