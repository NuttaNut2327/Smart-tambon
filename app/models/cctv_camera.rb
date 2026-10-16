class CctvCamera
  include Mongoid::Document
  include Mongoid::Timestamps

  STREAM_TYPES = {
    "hls" => "HLS (.m3u8)",
    "mjpeg" => "MJPEG",
    "video" => "ไฟล์วิดีโอ (MP4/WebM)",
    "embed" => "หน้าเว็บผู้ให้บริการ (Embed)"
  }.freeze
  STATUSES = { "active" => "ใช้งาน", "maintenance" => "ซ่อมบำรุง", "inactive" => "ปิดใช้งาน" }.freeze
  # Protocols that cameras commonly expose but browsers cannot play without a gateway.
  GATEWAY_SCHEMES = %w[rtsp rtsps rtmp rtmps rtp srt].freeze

  field :user_id, type: Integer
  field :subdistrict_id, type: Integer
  field :name, type: String
  field :code, type: String
  field :stream_url, type: String
  field :stream_type, type: String
  field :status, type: String, default: "active"
  field :location_name, type: String
  field :description, type: String
  field :latitude, type: Float
  field :longitude, type: Float

  index({ user_id: 1, updated_at: -1 })
  index({ subdistrict_id: 1 })

  # Set by the controller so location can be checked against the editor's area.
  attr_accessor :acting_user

  before_validation :normalize_fields
  before_validation :assign_stream_type
  before_validation :assign_subdistrict

  validates :user_id, :name, :stream_url, :latitude, :longitude, presence: true
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90, message: "ต้องอยู่ระหว่าง -90 ถึง 90" }, allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180, message: "ต้องอยู่ระหว่าง -180 ถึง 180" }, allow_nil: true
  validates :stream_type, inclusion: { in: STREAM_TYPES.keys, message: "ไม่สามารถระบุประเภทสตรีมจาก URL ได้ กรุณาเลือกประเภทสตรีม" }
  validates :status, inclusion: { in: STATUSES.keys }
  validate :stream_url_must_be_browser_playable
  validate :location_must_be_inside_acting_user_area

  scope :visible_to, lambda { |user|
    user.system_admin? ? all : any_of(
      { :user_id.in => user.organization_user_ids },
      { :subdistrict_id.in => user.accessible_subdistrict_ids }
    )
  }

  def self.detect_stream_type(url)
    path = URI.parse(url.to_s).path.to_s.downcase
    return "hls" if path.end_with?(".m3u8")
    return "video" if path.match?(/\.(mp4|webm|ogv|ogg)\z/)
    return "mjpeg" if path.match?(/\.(mjpg|mjpeg)\z/) || path.match?(/(mjpe?g|video\.cgi|faststream|nphmotionjpeg)/)

    nil
  rescue URI::InvalidURIError
    nil
  end

  # Owners' organisations can edit, and so can a tambon admin for cameras located in their own area
  # (e.g. cameras the system admin registered on their behalf).
  def editable_by?(user)
    return true if user.can_manage_organization_data?(user_id)

    user.subdistrict_admin? && subdistrict_id.present? && user.accessible_subdistrict_ids.include?(subdistrict_id)
  end

  def stream_type_label = STREAM_TYPES.fetch(stream_type, stream_type)
  def status_label = STATUSES.fetch(status, status)
  def subdistrict = subdistrict_id && Subdistrict.find_by(id: subdistrict_id)

  def as_map_json
    area = subdistrict
    {
      id: id.to_s, name:, code:, stream_url:, stream_type:, stream_type_label:,
      status:, status_label:, location_name:, description:,
      latitude:, longitude:,
      subdistrict_name: area&.name_th, district_name: area&.district_name_th
    }
  end

  private

  def normalize_fields
    %i[name code stream_url location_name description].each { |name| self[name] = self[name].to_s.strip.presence }
    self.stream_type = stream_type.to_s.strip.presence
  end

  def assign_stream_type
    self.stream_type ||= self.class.detect_stream_type(stream_url)
  end

  def assign_subdistrict
    return unless latitude.present? && longitude.present?
    return unless new_record? || latitude_changed? || longitude_changed? || subdistrict_id.blank?

    self.subdistrict_id = Subdistrict.where(
      "ST_Covers(boundary::geometry, ST_SetSRID(ST_Point(?, ?), 4326))", longitude.to_f, latitude.to_f
    ).pick(:id)
  end

  def stream_url_must_be_browser_playable
    return if stream_url.blank?

    uri = URI.parse(stream_url)
    if GATEWAY_SCHEMES.include?(uri.scheme.to_s.downcase)
      errors.add(:stream_url, "เป็น #{uri.scheme.upcase} ซึ่งเบราว์เซอร์เล่นโดยตรงไม่ได้ กรุณาแปลงเป็น HLS ผ่าน gateway เช่น MediaMTX หรือ go2rtc แล้วใช้ URL .m3u8")
    elsif !%w[http https].include?(uri.scheme.to_s.downcase) || uri.host.blank?
      errors.add(:stream_url, "ต้องเป็น URL ที่ขึ้นต้นด้วย http:// หรือ https://")
    end
  rescue URI::InvalidURIError
    errors.add(:stream_url, "ไม่ใช่ URL ที่ถูกต้อง")
  end

  def location_must_be_inside_acting_user_area
    return if acting_user.nil? || acting_user.system_admin? || latitude.blank? || longitude.blank?
    return unless latitude.to_f.between?(-90, 90) && longitude.to_f.between?(-180, 180)
    return if subdistrict_id.present? && acting_user.accessible_subdistrict_ids.include?(subdistrict_id)

    errors.add(:base, "ตำแหน่งกล้องอยู่นอกพื้นที่ที่คุณดูแล")
  end
end
