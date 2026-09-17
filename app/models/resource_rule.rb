class ResourceRule
  include Mongoid::Document
  include Mongoid::Timestamps

  DISASTER_TYPES = %w[flood fire wind drought other].freeze
  SEVERITY_LEVELS = %w[watch urgent critical].freeze

  field :user_id, type: Integer
  field :name, type: String
  field :disaster_type, type: String
  field :description, type: String
  field :severity, type: String, default: "watch"
  field :conditions, type: Array, default: []
  field :formulas, type: Array, default: []
  field :active, type: Boolean, default: true

  index({ user_id: 1, updated_at: -1 })

  validates :user_id, :name, presence: true
  validates :disaster_type, inclusion: { in: DISASTER_TYPES }
  validates :severity, inclusion: { in: SEVERITY_LEVELS }
  validate :has_valid_conditions
  validate :has_valid_hotspot_areas
  validate :has_valid_formulas

  scope :visible_to, ->(user) { user.system_admin? ? all : where(user_id: user.id) }

  # Hotspot metrics must be supplied per measured area, for example:
  # { "hotspot_scopes" => [{ "area_value" => 10, "area_unit" => "sqkm", "count" => 4 }] }
  def matches_metrics?(metrics)
    conditions.all? do |condition|
      observed = if condition["variable"] == "hotspot_count"
        hotspot_count_for(metrics, condition)
      else
        metrics[condition["variable"]] || metrics[condition["variable"].to_sym]
      end
      observed.present? && compare_values(observed.to_f, condition["value"].to_f, condition["comparator"])
    end
  end

  private

  def has_valid_conditions
    errors.add(:conditions, "ต้องมีอย่างน้อย 1 เงื่อนไข") if conditions.blank?
  end

  def has_valid_hotspot_areas
    conditions.select { |item| item["variable"] == "hotspot_count" }.each do |item|
      unless item["area_value"].to_f.positive? && %w[sqm sqkm rai].include?(item["area_unit"])
        errors.add(:conditions, "เงื่อนไขจำนวน Hotspot ต้องระบุขนาดและหน่วยพื้นที่")
        break
      end
    end
  end

  def has_valid_formulas
    errors.add(:formulas, "ต้องมีอย่างน้อย 1 สูตรคำนวณ") if formulas.blank?
  end

  def hotspot_count_for(metrics, condition)
    target_area = area_in_sqkm(condition["area_value"], condition["area_unit"])
    scope = Array(metrics["hotspot_scopes"] || metrics[:hotspot_scopes]).find do |item|
      value = item["area_value"] || item[:area_value]
      unit = item["area_unit"] || item[:area_unit]
      (area_in_sqkm(value, unit) - target_area).abs < 0.000001
    end
    scope && (scope["count"] || scope[:count])
  end

  def area_in_sqkm(value, unit)
    case unit
    when "sqm" then value.to_f / 1_000_000
    when "rai" then value.to_f * 0.0016
    else value.to_f
    end
  end

  def compare_values(observed, expected, comparator)
    case comparator
    when "gt" then observed > expected
    when "lte" then observed <= expected
    when "lt" then observed < expected
    when "eq" then observed == expected
    else observed >= expected
    end
  end
end
