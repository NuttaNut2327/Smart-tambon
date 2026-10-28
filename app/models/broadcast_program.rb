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
    "weather_forecast" => "พยากรณ์ฝนและอากาศ 3 วันข้างหน้า (เตือนฝนหนัก)",
    "gistda_hotspots" => "จุดความร้อนจาก GISTDA รอบล่าสุด/24 ชั่วโมง (ระบุหมู่บ้าน/ตำบล)",
    "gistda_flood" => "พื้นที่น้ำท่วมจาก GISTDA (7 วันล่าสุด)",
    "disaster_history" => "แนวโน้มภัยรายสัปดาห์จากสถิติภัยพิบัติย้อนหลัง และพื้นที่ที่เคยเกิดเหตุในสัปดาห์นี้",
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

  # เสียงตามสายควรสั้น: ค่าเริ่มต้นจำกัดบทอ่านให้อ่านจบในราว 1 นาที และยาวได้ไม่เกิน 2 นาที (อ่านภาษาไทยประมาณ 125 คำต่อนาที)
  WORDS_PER_MINUTE = 125
  DEFAULT_MAX_WORDS = WORDS_PER_MINUTE
  MAX_WORDS_LIMIT = WORDS_PER_MINUTE * 2

  # Ready-made "agents": prevention news programmes an อบต. can start from (BroadcastProgramsController#new?template=).
  TEMPLATES = {
    "forecast_alert" => {
      label: "เตือนภัยล่วงหน้า 3 วัน (ทุกเช้า)",
      description: "ทุกเช้า 06:30 ดูพยากรณ์ฝน 3 วัน ถ้ามีฝนหนักหรือความเสี่ยงสูงจึงออกข่าว พร้อมบอกพื้นที่ที่เคยเกิดภัยเมื่อฝนระดับนี้",
      attributes: {
        name: "เตือนภัยล่วงหน้า 3 วัน", schedule_times: ["06:30"], alert_only: true, history_years: 5, max_words: DEFAULT_MAX_WORDS,
        delivery_modes: %w[pa notification internal], internal_alert_level: "urgent",
        data_sources: %w[weather_forecast disaster_history gistda_flood disasters],
        prompt: <<~PROMPT
          เขียนข่าวเตือนภัยล่วงหน้าสำหรับเสียงตามสายตอนเช้า เน้นการเตรียมตัวป้องกัน
          - เปิดด้วยคำทักทาย วันที่ และบอกตรง ๆ ว่ามีเรื่องที่ต้องระวังในอีก 3 วันข้างหน้า
          - บอกวันที่คาดว่าฝนจะหนัก ปริมาณฝน และระดับฝนตาม weather_forecast พร้อมแหล่งที่มา
          - ถ้า disaster_history มี places_hit_after_similar_rain หรือ past_events_this_week ให้บอกว่าในอดีตช่วงสัปดาห์นี้
            เคยเกิดภัยอะไรที่หมู่ไหน ตำบลไหน และขอให้คนในพื้นที่นั้นเฝ้าระวังเป็นพิเศษ
          - ให้คำแนะนำที่ทำได้จริง เช่น ขนของขึ้นที่สูง ลอกทางระบายน้ำ เตรียมไฟฉายและยาประจำตัว เลี่ยงเส้นทางน้ำหลาก
          - ถ้ามีพื้นที่น้ำท่วมจาก GISTDA หรือภัยที่กำลังดำเนินการ ให้บอกสั้น ๆ
          - ปิดท้ายด้วยช่องทางแจ้งเหตุของ อบต.
        PROMPT
      }
    },
    "weekly_outlook" => {
      label: "แนวโน้มภัยประจำสัปดาห์จากสถิติย้อนหลัง",
      description: "ทุกวันจันทร์ 07:00 สรุปว่าสัปดาห์นี้ในอดีต 1–5 ปีเคยเกิดภัยอะไร ที่ไหน แนวโน้มเพิ่มหรือลด เทียบกับฝนที่คาดการณ์",
      attributes: {
        name: "แนวโน้มภัยประจำสัปดาห์", schedule_times: ["07:00"], schedule_days: ["1"], history_years: 5, max_words: DEFAULT_MAX_WORDS,
        data_sources: %w[disaster_history weather_forecast],
        prompt: <<~PROMPT
          เขียนข่าวประจำสัปดาห์เรื่องแนวโน้มภัยพิบัติจากสถิติย้อนหลังของตำบล เพื่อให้ชาวบ้านเตรียมป้องกันล่วงหน้า
          - บอกว่าเป็นสถิติจากอดีตกี่ปี และย้ำว่าไม่ใช่การพยากรณ์ว่าจะเกิดแน่นอน
          - ไล่ภัยที่มีความเสี่ยงสูงก่อน บอกว่าสัปดาห์นี้ในอดีตเกิดบ่อยแค่ไหน ปีที่แล้วเกิดกี่ครั้ง และแนวโน้มสัปดาห์ถัดไป
          - บอกหมู่บ้านหรือตำบลที่เคยเกิดเหตุบ่อยในช่วงนี้ และเทียบฝนที่คาดการณ์กับฝนก่อนเกิดเหตุในอดีต
          - ให้คำแนะนำการเตรียมตัวตามภัยแต่ละชนิด
          - ถ้าไม่มีภัยที่น่ากังวล ให้บอกสั้น ๆ ว่าสัปดาห์นี้ในอดีตไม่ค่อยเกิดภัย
        PROMPT
      }
    }
  }.freeze

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
  field :max_words, type: Integer, default: DEFAULT_MAX_WORDS
  # Skip the broadcast (status "skipped") when the data shows nothing to warn about.
  field :alert_only, type: Boolean, default: false
  # How many past years of the disaster archive the "disaster_history" source looks at.
  field :history_years, type: Integer, default: 5
  field :enabled, type: Boolean, default: true
  field :created_by, type: String
  field :updated_by, type: String

  has_many :broadcasts, dependent: :nullify

  index({ organization_key: 1, enabled: 1 })

  validates :organization_key, :name, :prompt, presence: true
  validates :lookahead_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 31 }
  validates :max_words, numericality: { only_integer: true, greater_than_or_equal_to: 50, less_than_or_equal_to: MAX_WORDS_LIMIT, message: "ต้องอยู่ระหว่าง 50 ถึง #{MAX_WORDS_LIMIT} คำ (อ่านไม่เกิน 2 นาที)" }
  validates :history_years, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5, message: "ต้องอยู่ระหว่าง 1 ถึง 5 ปี" }
  validate :schedule_times_must_be_valid
  before_validation :normalize

  scope :for_organization, ->(key) { where(organization_key: key) }
  scope :enabled, -> { where(enabled: true) }

  attr_writer :schedule_times_text

  def self.from_template(key, **attributes)
    template = TEMPLATES[key.to_s]
    new(delivery_modes: %w[pa notification], **(template ? template[:attributes] : {}), **attributes)
  end

  def schedule_times_text = @schedule_times_text || Array(schedule_times).join(", ")
  def ai_provider = (ai_provider_id && AiProvider.enabled.where(id: ai_provider_id).first) || AiProvider.default_for_chat
  def tts_provider = (tts_provider_id && TtsProvider.available_to(organization_key).enabled.where(id: tts_provider_id).first) || TtsProvider.default_for(organization_key)
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
