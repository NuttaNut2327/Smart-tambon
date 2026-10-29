# Historical disaster record (one row per event) used for statistics and seasonal outlooks.
# Live response work stays in Incident; this archive holds what happened, where, and how much damage it did.
class DisasterEvent
  include Mongoid::Document
  include Mongoid::Timestamps

  # Labels match Incident::DISASTER_INCIDENT_TYPES so the two can be compared side by side.
  HAZARDS = {
    "flood" => { label: "น้ำท่วม", icon: "flood", color: "#2f6fb0" },
    "landslide" => { label: "ดินถล่ม", icon: "landslide", color: "#8a5d0e" },
    "wildfire" => { label: "ไฟป่า", icon: "local_fire_department", color: "#d03b3b" },
    "drought" => { label: "ภัยแล้ง", icon: "water_drop", color: "#c17d11" },
    "storm" => { label: "พายุ", icon: "storm", color: "#5b4f93" }
  }.freeze
  SEVERITIES = { 1 => "เล็กน้อย", 2 => "ปานกลาง", 3 => "รุนแรง", 4 => "รุนแรงมาก" }.freeze

  field :hazard, type: String
  field :title, type: String
  field :description, type: String
  field :subdistrict_id, type: Integer
  field :villages, type: Array, default: []
  field :started_at, type: Time
  field :peak_at, type: Time
  field :ended_at, type: Time
  field :severity, type: Integer, default: 1
  field :cause, type: String
  # Origin point and affected footprint (GeoJSON geometry, EPSG:4326).
  field :latitude, type: Float
  field :longitude, type: Float
  field :elevation_m, type: Float
  field :affected_area, type: Hash
  field :area_rai, type: Float
  # Impact.
  field :affected_households, type: Integer, default: 0
  field :affected_people, type: Integer, default: 0
  field :damaged_houses, type: Integer, default: 0
  field :farmland_rai, type: Float, default: 0.0
  field :roads_km, type: Float, default: 0.0
  field :injuries, type: Integer, default: 0
  field :deaths, type: Integer, default: 0
  field :estimated_loss_baht, type: Float, default: 0.0
  # Hydro-met context at onset (rain is the 3-day accumulation before the event).
  field :rain_3d_mm, type: Float
  field :max_temperature_c, type: Float
  field :days_without_rain, type: Integer
  field :source, type: String, default: "manual"
  field :simulated, type: Boolean, default: false

  index({ subdistrict_id: 1, started_at: -1 })
  index({ hazard: 1, started_at: -1 })
  index({ simulated: 1 })

  validates :hazard, inclusion: { in: HAZARDS.keys }
  validates :severity, inclusion: { in: SEVERITIES.keys }
  validates :title, :started_at, :subdistrict_id, presence: true

  scope :visible_to, ->(user) { DemoData.filter(user.system_admin? ? all : where(:subdistrict_id.in => user.accessible_subdistrict_ids)) }
  scope :started_between, ->(range) { where(:started_at.gte => range.begin, :started_at.lte => range.end) }

  def hazard_label = HAZARDS.dig(hazard, :label) || hazard
  def severity_label = SEVERITIES.fetch(severity, severity.to_s)
  def duration_days = ended_at && started_at ? ((ended_at - started_at) / 1.day).ceil : nil

  def as_feature
    {
      type: "Feature",
      id: id.to_s,
      geometry: affected_area,
      properties: {
        hazard:, hazard_label:, title:, severity:, severity_label:, cause:, villages:,
        started_at: started_at&.iso8601, peak_at: peak_at&.iso8601, ended_at: ended_at&.iso8601, duration_days:,
        latitude:, longitude:, elevation_m:, area_rai:, affected_households:, affected_people:, damaged_houses:,
        farmland_rai:, roads_km:, injuries:, deaths:, estimated_loss_baht:, rain_3d_mm:, simulated:
      }
    }
  end
end
