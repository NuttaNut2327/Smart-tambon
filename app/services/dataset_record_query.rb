# Text search, column filters and sorting for the standard dataset tables on /data_layers.
# Works on the already-built row items ({ dataset:, record:, position:, editable: }) so pagination counts
# reflect the filtered result, not just the current page.
class DatasetRecordQuery
  # Columns offered as dropdown filters, per data type. Other types still get search and sort.
  FILTER_FIELDS = {
    "resources" => %w[resource_type status responsible_person storage_location],
    "consumables" => %w[category agency_name storage_location unit]
  }.freeze
  STOCK_FILTERS = { "low" => "ใกล้หมด / ต่ำกว่าจุดแจ้งเตือน", "ok" => "คงเหลือปกติ" }.freeze
  UPDATED_AT = "updated_at".freeze

  attr_reader :query, :filters, :stock, :sort, :direction, :filter_options

  def initialize(items, data_type:, schema:, params:)
    @items = items
    @data_type = data_type
    @schema = schema
    @query = params[:q].to_s.strip.first(100)
    @filter_keys = FILTER_FIELDS.fetch(data_type, [])
    @filters = @filter_keys.index_with { |key| params.dig(:f, key).to_s.strip }.compact_blank
    @stock = data_type == "consumables" && STOCK_FILTERS.key?(params[:stock]) ? params[:stock] : nil
    sortable = schema.map { |field| field["key"] } << UPDATED_AT
    @sort = sortable.include?(params[:sort]) ? params[:sort] : nil
    @direction = params[:dir] == "desc" ? "desc" : "asc"
    @filter_options = build_filter_options
  end

  def results
    rows = @items.select { |item| matches_query?(item) && matches_filters?(item) && matches_stock?(item) }
    return rows unless sort

    rows = rows.sort_by.with_index { |item, index| [sort_key(item), index] }
    direction == "desc" ? rows.reverse : rows
  end

  def active? = query.present? || filters.any? || stock.present?
  def filter_fields = @schema.select { |field| @filter_keys.include?(field["key"]) }

  # Params for links that must keep the current search/filter/sort (pagination, column headers).
  def to_params
    { q: query.presence, f: filters.presence, stock:, sort:, dir: (direction if sort) }.compact
  end

  def self.low_stock?(record)
    record["minimum_quantity"].present? && record["current_quantity"].to_f <= record["minimum_quantity"].to_f
  end

  private

  def build_filter_options
    @filter_keys.index_with do |key|
      @items.map { |item| item[:record][key].to_s.strip }.compact_blank.tally.sort_by { |value, _| value }
    end
  end

  # Every whitespace-separated term must appear somewhere in the row (case-insensitive).
  def matches_query?(item)
    return true if query.blank?

    haystack = item[:record].values.join(" ").downcase
    query.downcase.split.all? { |term| haystack.include?(term) }
  end

  def matches_filters?(item)
    filters.all? { |key, value| item[:record][key].to_s.strip == value }
  end

  def matches_stock?(item)
    return true unless stock

    self.class.low_stock?(item[:record]) == (stock == "low")
  end

  # Numbers sort numerically; text uses a natural order so "R-2" comes before "R-10". Blank values go last.
  def sort_key(item)
    return [0, item[:dataset].updated_at.to_f] if sort == UPDATED_AT

    value = item[:record][sort]
    return [direction == "desc" ? -1 : 1, []] if value.blank?

    field = @schema.find { |entry| entry["key"] == sort }
    if %w[number integer].include?(field&.dig("type"))
      [0, [value.to_f]]
    else
      [0, value.to_s.downcase.scan(/\d+|\D+/).map { |part| part.match?(/\A\d+\z/) ? [0, part.to_i] : [1, part] }]
    end
  end
end
