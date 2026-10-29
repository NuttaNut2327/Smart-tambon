require "test_helper"

class DatasetRecordQueryTest < ActiveSupport::TestCase
  Dataset = Struct.new(:updated_at)
  SCHEMA = [
    { "key" => "code", "label" => "รหัส", "type" => "text" },
    { "key" => "name", "label" => "ชื่อ", "type" => "text" },
    { "key" => "resource_type", "label" => "ประเภท", "type" => "text" },
    { "key" => "status", "label" => "สถานะ", "type" => "text" },
    { "key" => "current_quantity", "label" => "คงเหลือ", "type" => "number" }
  ].freeze

  setup do
    dataset = Dataset.new(Time.current)
    @items = [
      { "code" => "R-10", "name" => "รถดับเพลิง", "resource_type" => "ยานพาหนะ", "status" => "พร้อมใช้", "current_quantity" => 3 },
      { "code" => "R-2", "name" => "รถพยาบาล", "resource_type" => "ยานพาหนะ", "status" => "กำลังใช้งาน", "current_quantity" => 12 },
      { "code" => "R-1", "name" => "เครื่องสูบน้ำ", "resource_type" => "อุปกรณ์บรรเทาภัย", "status" => "พร้อมใช้", "current_quantity" => nil }
    ].each_with_index.map { |record, position| { dataset:, record:, position:, editable: true } }
  end

  def query(type: "resources", **params)
    DatasetRecordQuery.new(@items, data_type: type, schema: SCHEMA, params: ActionController::Parameters.new(params))
  end

  def codes(result) = result.map { |item| item[:record]["code"] }

  test "text search matches every term across fields" do
    assert_equal %w[R-10 R-2], codes(query(q: "รถ").results)
    assert_equal %w[R-2], codes(query(q: "รถ กำลังใช้").results)
    assert_empty query(q: "ไม่มีคำนี้").results
  end

  test "filters by column value and lists options with counts" do
    result = query("f" => { "resource_type" => "ยานพาหนะ", "status" => "พร้อมใช้" })
    assert_equal %w[R-10], codes(result.results)
    assert_equal [["ยานพาหนะ", 2], ["อุปกรณ์บรรเทาภัย", 1]], result.filter_options["resource_type"]
    assert result.active?
  end

  test "ignores filters on columns that are not filterable" do
    assert_equal 3, query("f" => { "name" => "รถพยาบาล" }).results.size
  end

  test "natural sort for codes, numeric sort for numbers, blanks last both ways" do
    assert_equal %w[R-1 R-2 R-10], codes(query(sort: "code").results)
    assert_equal %w[R-10 R-2 R-1], codes(query(sort: "code", dir: "desc").results)
    assert_equal %w[R-10 R-2 R-1], codes(query(sort: "current_quantity").results)
    assert_equal %w[R-2 R-10 R-1], codes(query(sort: "current_quantity", dir: "desc").results)
  end

  test "unknown sort keys keep the original order" do
    assert_equal %w[R-10 R-2 R-1], codes(query(sort: "password", dir: "desc").results)
  end

  test "consumable stock filter" do
    @items.first[:record]["minimum_quantity"] = 5
    assert_equal %w[R-10], codes(query(type: "consumables", stock: "low").results)
    assert_equal %w[R-2 R-1], codes(query(type: "consumables", stock: "ok").results)
  end
end
