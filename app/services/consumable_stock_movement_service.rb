class ConsumableStockMovementService
  Result = Data.define(:quantity_before, :quantity_after, :unit, :version)

  def initialize(dataset:, record_position:, movement_type:, quantity:, user:, incident_reference: nil, note: nil)
    @dataset = dataset
    @record_position = Integer(record_position)
    @movement_type = movement_type.to_s
    @quantity = Float(quantity)
    @user = user
    @incident_reference = incident_reference
    @note = note
  end

  def call
    raise ArgumentError, "ชุดข้อมูลไม่ใช่วัสดุสิ้นเปลือง" unless @dataset.data_type == "consumables"
    raise ArgumentError, "ประเภทรายการไม่ถูกต้อง" unless ConsumableMovement::TYPES.include?(@movement_type)
    raise ArgumentError, "จำนวนไม่ถูกต้อง" unless @quantity.finite?
    raise ArgumentError, "จำนวนต้องไม่น้อยกว่า 0" if @quantity.negative?
    raise ArgumentError, "กรุณาระบุจำนวนมากกว่า 0" if @movement_type != "adjustment" && @quantity.zero?

    records = Array(@dataset.current_version&.records).map(&:deep_dup)
    record = records.fetch(@record_position)
    before_quantity = record["current_quantity"].to_f
    after_quantity = calculate_after(before_quantity)
    if after_quantity.negative?
      raise ArgumentError, "จำนวนเบิกมากกว่ายอดคงเหลือ #{before_quantity.to_fs(:delimited)} #{record['unit']}"
    end

    record["current_quantity"] = after_quantity
    version = DatasetVersionImportService.new(dataset: @dataset, user: @user, manual_records: records,
      source_kind: "manual", change_note: "#{movement_label} #{record['name']} #{@quantity.to_fs(:delimited)} #{record['unit']}").import!
    ConsumableMovement.create!(imported_dataset_id: @dataset.id, consumable_code: record["consumable_code"],
      consumable_name: record["name"], unit: record["unit"], agency_code: record["agency_code"],
      agency_name: record["agency_name"], movement_type: @movement_type, quantity: @quantity,
      quantity_before: before_quantity, quantity_after: after_quantity,
      incident_reference: @incident_reference.presence, note: @note.presence, user_id: @user.id)
    Result.new(quantity_before: before_quantity, quantity_after: after_quantity, unit: record["unit"], version: version)
  rescue IndexError
    raise ArgumentError, "ไม่พบวัสดุสิ้นเปลืองที่เลือก"
  end

  private

  def calculate_after(before_quantity)
    case @movement_type
    when "receive", "return" then before_quantity + @quantity
    when "issue" then before_quantity - @quantity
    when "adjustment" then @quantity
    end
  end

  def movement_label
    { "receive" => "รับเข้า", "issue" => "เบิกออก", "return" => "คืนเข้า", "adjustment" => "ปรับยอด" }.fetch(@movement_type)
  end
end
