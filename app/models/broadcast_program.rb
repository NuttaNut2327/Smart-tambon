# A recurring news programme for one อบต. (e.g. "ข่าวเช้า 07:00"): the user's prompt, which real data to summarise,
# when to run, how to read it aloud and where to publish. Each run produces a Broadcast.
class BroadcastProgram
  include Mongoid::Document
  include Mongoid::Timestamps
  include BroadcastDelivery

  DATA_SOURCES = {
    "weather" => "สภาพอากาศ ฝน และอุณหภูมิ",
    "pm25" => "ฝุ่น PM2.5",
    "water" => "ระดับน้ำจากสถานีวัดน้ำ",
    "fire_hotspots" => "จุดความร้อน (ไฟป่า)",
    "activities" => "กิจกรรมในพื้นที่",
    "incidents" => "เหตุการณ์ที่แจ้งเข้ามา (ไม่เปิดเผยข้อมูลผู้แจ้ง)",
    "disasters" => "ภัยพิบัติที่กำลังดำเนินการ",
    "projects" => "โครงการของ อบต."
  }.freeze
  DAYS = { "1" => "จ.", "2" => "อ.", "3" => "พ.", "4" => "พฤ.", "5" => "ศ.", "6" => "ส.", "0" => "อา." }.freeze
  DEFAULT_PROMPT = <<~PROMPT.freeze
    สรุปข่าวประจำวันสำหรับประกาศเสียงตามสายของ อบต. ให้ชาวบ้านฟังเข้าใจง่าย
    - เริ่มด้วยคำทักทายและวันที่ แล้วบอกสภาพอากาศกับคุณภาพอากาศวันนี้ พร้อมคำแนะนำการดูแลตัวเอง
    - แจ้งกิจกรรมที่กำลังจัดและที่จะจัดในสัปดาห์นี้ พร้อมวัน เวลา และสถานที่
    - ถ้ามีเหตุการณ์หรือความเสี่ยงที่ต้องระวัง ให้บอกสั้น ๆ ว่าต้องทำอะไร
    - ปิดท้ายด้วยช่องทางติดต่อ อบต.
  PROMPT

  field :organization_key, type: String
  field :subdistrict_id, type: Integer
  field :name, type: String
  field :prompt, type: String, default: DEFAULT_PROMPT
  field :data_sources, type: Array, default: -> { %w[weather pm25 activities incidents] }
  field :lookahead_days, type: Integer, default: 7
  field :schedule_enabled, type: Boolean, default: true
  field :schedule_times, type: Array, default: -> { ["07:00"] }
  field :schedule_days, type: Array, default: -> { DAYS.keys }
  field :auto_publish, type: Boolean, default: false
  field :channel_ids, type: Array, default: []
  field :ai_provider_id, type: BSON::ObjectId
  field :tts_provider_id, type: BSON::ObjectId
  field :tts_voice, type: String
  field :max_words, type: Integer, default: 250
  field :enabled, type: Boolean, default: true
  field :created_by, type: String
  field :updated_by, type: String

  has_many :broadcasts, dependent: :nullify

  index({ organization_key: 1, enabled: 1 })

  validates :organization_key, :name, :prompt, presence: true
  validates :lookahead_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 31 }
  validates :max_words, numericality: { only_integer: true, greater_than_or_equal_to: 50, less_than_or_equal_to: 1000, message: "ต้องอยู่ระหว่าง 50 ถึง 1,000" }
  validate :schedule_times_must_be_valid
  before_validation :normalize

  scope :for_organization, ->(key) { where(organization_key: key) }
  scope :enabled, -> { where(enabled: true) }

  attr_writer :schedule_times_text

  def schedule_times_text = @schedule_times_text || Array(schedule_times).join(", ")
  def ai_provider = (ai_provider_id && AiProvider.enabled.where(id: ai_provider_id).first) || AiProvider.default_for_chat
  def tts_provider = (tts_provider_id && TtsProvider.enabled.where(id: tts_provider_id).first) || TtsProvider.default
  def data_source_labels = data_sources.map { |key| DATA_SOURCES.fetch(key, key) }
  def schedule_label
    return "สร้างเมื่อกดเท่านั้น" unless schedule_enabled? && schedule_times.any?

    days = schedule_days.sort == DAYS.keys.sort ? "ทุกวัน" : DAYS.slice(*schedule_days).values.join(" ")
    "#{days} เวลา #{schedule_times.join(', ')} น."
  end

  # Slots that should have run by `now` today and have no broadcast yet, e.g. ["2026-10-16 07:00"].
  def due_slots(now = Time.current)
    return [] unless enabled? && schedule_enabled? && schedule_days.include?(now.wday.to_s)

    taken = broadcasts.where(:slot_key.in => schedule_times.map { |time| slot_key(now.to_date, time) }).pluck(:slot_key)
    schedule_times.filter_map do |time|
      hour, minute = time.split(":").map(&:to_i)
      at = now.change(hour:, min: minute)
      key = slot_key(now.to_date, time)
      # Only catch up on slots from the last 2 hours, so a restarted worker doesn't read out stale morning news at night.
      key if at <= now && at > now - 2.hours && !taken.include?(key)
    end
  end

  def slot_key(date, time) = "#{date.iso8601} #{time}"

  private

  def normalize
    %i[name prompt tts_voice].each { |key| self[key] = self[key].to_s.strip.presence }
    self.data_sources = Array(data_sources).compact_blank & DATA_SOURCES.keys
    self.schedule_days = Array(schedule_days).compact_blank.map(&:to_s) & DAYS.keys
    self.channel_ids = Array(channel_ids).compact_blank.filter_map { |id| BSON::ObjectId.from_string(id.to_s) rescue nil }.uniq
    self.ai_provider_id = nil if ai_provider_id.blank?
    self.tts_provider_id = nil if tts_provider_id.blank?
    return if @schedule_times_text.nil?

    @invalid_times = []
    self.schedule_times = @schedule_times_text.to_s.split(/[\s,]+/).compact_blank.filter_map do |value|
      match = value.match(/\A(\d{1,2})[:.](\d{2})\z/)
      unless match && match[1].to_i < 24 && match[2].to_i < 60
        @invalid_times << value
        next
      end

      format("%02d:%02d", match[1].to_i, match[2].to_i)
    end.uniq.sort
  end

  def schedule_times_must_be_valid
    errors.add(:schedule_times, "รูปแบบเวลาไม่ถูกต้อง: #{@invalid_times.join(', ')} (ใช้แบบ 07:00)") if @invalid_times.present?
    errors.add(:schedule_times, "ระบุได้ไม่เกิน 6 เวลาต่อวัน") if schedule_times.size > 6
  end
end
