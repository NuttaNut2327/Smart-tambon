class ConsumableMovement
  include Mongoid::Document
  include Mongoid::Timestamps

  TYPES = %w[receive issue return adjustment].freeze

  field :imported_dataset_id, type: BSON::ObjectId
  field :consumable_code, type: String
  field :consumable_name, type: String
  field :unit, type: String
  field :agency_code, type: String
  field :agency_name, type: String
  field :movement_type, type: String
  field :quantity, type: Float
  field :quantity_before, type: Float
  field :quantity_after, type: Float
  field :incident_reference, type: String
  field :note, type: String
  field :user_id, type: Integer

  index({ imported_dataset_id: 1, created_at: -1 })
  index({ consumable_code: 1, created_at: -1 })
  validates :movement_type, inclusion: { in: TYPES }
  validates :consumable_code, :consumable_name, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }

  def type_label
    { "receive" => "รับเข้า", "issue" => "เบิกออก", "return" => "คืนเข้า", "adjustment" => "ปรับยอด" }.fetch(movement_type)
  end

  def user = User.find_by(id: user_id)
end
