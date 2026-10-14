module Ai
  # Runs a declarative query spec written by the LLM against a DataCatalog source. There is no SQL or Mongo
  # query from the model: rows come from the scoped loader and are filtered, grouped and aggregated here.
  #
  #   { "source" => "incidents",
  #     "filters" => [{ "field" => "category", "op" => "eq", "value" => "ภัยพิบัติ" }],
  #     "group_by" => [{ "field" => "reported_at", "bucket" => "month" }],
  #     "measures" => [{ "agg" => "count" }, { "agg" => "sum", "field" => "affected_people", "label" => "ผู้ได้รับผลกระทบ" }],
  #     "columns" => ["title", "status"],          # list mode, used when there is no group_by/measures
  #     "sort" => { "by" => "count", "dir" => "desc" }, "limit" => 20 }
  #
  # Run-time params { "from", "to" } narrow the source's date field; snippets use them to re-run on a new period.
  class QueryEngine
    class InvalidSpec < StandardError; end

    OPS = %w[eq ne in not_in gt gte lt lte between contains is_null not_null].freeze
    AGGS = %w[count count_distinct sum avg min max median].freeze
    BUCKETS = %w[hour day week month quarter year fiscal_year].freeze
    MAX_LIMIT = 500

    Result = Struct.new(:source, :columns, :rows, :total, :truncated, :hints, keyword_init: true) do
      def as_json(*) = { source: source, columns: columns, rows: rows, total: total, truncated: truncated, hints: hints.presence }.compact
    end

    def initialize(catalog)
      @catalog = catalog
      @loaded = {}
    end

    def run(spec, params: {})
      spec = normalize_spec(spec)
      source = @catalog.source(spec["source"]) or raise InvalidSpec, "ไม่รู้จักแหล่งข้อมูล #{spec['source'].inspect} — ดูรายการใน catalog หรือ list_imported_datasets"
      rows = load(source)
      rows = apply_period(rows, source, params)
      hints = {}
      rows = Array(spec["filters"]).reduce(rows) do |memo, filter|
        filtered = apply_filter(memo, source, filter)
        hints.merge!(value_hints(memo, source, filter)) if filtered.empty? && memo.any?
        filtered
      end
      matched = rows.size

      if Array(spec["group_by"]).any? || Array(spec["measures"]).any?
        columns, output = aggregate(rows, source, spec)
      else
        columns = Array(spec["columns"]).presence || source.fields.first(8).map(&:key)
        columns.each { |key| field!(source, key) }
        output = rows.map { |row| columns.to_h { |key| [label_for(source, key), present(row[key])] } }
        columns = columns.map { |key| label_for(source, key) }
      end

      output = sort(output, spec["sort"], columns)
      limit = spec["limit"].to_i.positive? ? [spec["limit"].to_i, MAX_LIMIT].min : (columns_mode?(spec) ? 50 : MAX_LIMIT)
      Result.new(source: source.key, columns: columns, rows: output.first(limit), total: matched, truncated: output.size > limit, hints: hints)
    end

    private

    def columns_mode?(spec) = Array(spec["group_by"]).empty? && Array(spec["measures"]).empty?

    def normalize_spec(spec)
      spec = spec.to_h.deep_stringify_keys
      raise InvalidSpec, "ต้องระบุ source" if spec["source"].blank?

      spec["group_by"] = Array(spec["group_by"]).map { |group| group.is_a?(Hash) ? group : { "field" => group.to_s } }
      spec["measures"] = Array(spec["measures"]).map { |measure| measure.is_a?(Hash) ? measure : { "agg" => measure.to_s } }
      spec["measures"] = [{ "agg" => "count" }] if spec["group_by"].any? && spec["measures"].empty?
      spec
    end

    def load(source) = @loaded[source.key] ||= source.loader.call

    def field!(source, key)
      source.field(key) or raise InvalidSpec, "แหล่งข้อมูล #{source.key} ไม่มีฟิลด์ #{key.inspect} (มี: #{source.fields.map(&:key).join(', ')})"
    end

    def label_for(source, key) = source.field(key)&.key || key.to_s

    def apply_period(rows, source, params)
      return rows if source.date_field.blank?

      from = parse_time(params["from"] || params[:from])
      to = parse_time(params["to"] || params[:to])
      to = to.end_of_day if to && to == to.beginning_of_day
      return rows unless from || to

      rows.select do |row|
        value = row[source.date_field]
        value && (!from || value >= from) && (!to || value <= to)
      end
    end

    def apply_filter(rows, source, filter)
      filter = filter.to_h.stringify_keys
      field = field!(source, filter["field"])
      op = filter["op"].presence || "eq"
      raise InvalidSpec, "ไม่รู้จักตัวดำเนินการ #{op.inspect} (ใช้ได้: #{OPS.join(', ')})" unless OPS.include?(op)

      value = filter["value"]
      rows.select { |row| match?(cast(row[field.key], field), op, value, field) }
    end

    # When a text filter matches nothing, show the model the values that do exist so it can correct itself.
    def value_hints(rows, source, filter)
      field = source.field(filter.to_h.stringify_keys["field"])
      return {} unless field && %w[text enum].include?(field.type)

      values = rows.map { |row| row[field.key] }.compact.map(&:to_s).tally.sort_by { |_, count| -count }.first(15).map(&:first)
      { field.key => "ไม่พบค่าที่ตรง ตัวอย่างค่าที่มีอยู่: #{values.join(' | ')}" }
    end

    def match?(actual, op, value, field)
      case op
      when "is_null" then actual.nil? || actual == ""
      when "not_null" then !(actual.nil? || actual == "")
      when "contains" then actual.to_s.downcase.include?(value.to_s.downcase)
      when "in" then Array(value).map { |item| cast(item, field) }.include?(actual)
      when "not_in" then !Array(value).map { |item| cast(item, field) }.include?(actual)
      when "between"
        low, high = Array(value).map { |item| cast(item, field) }
        high = high.end_of_day if field.type == "date" && high && high == high.beginning_of_day
        !actual.nil? && (low.nil? || actual >= low) && (high.nil? || actual <= high)
      else
        expected = cast(value, field)
        return op == "ne" if actual.nil? || expected.nil?

        case op
        when "eq" then actual == expected
        when "ne" then actual != expected
        when "gt" then actual > expected
        when "gte" then actual >= expected
        when "lt" then actual < expected
        when "lte" then actual <= expected
        end
      end
    rescue ArgumentError, NoMethodError
      false
    end

    def aggregate(rows, source, spec)
      groups = spec["group_by"].map do |group|
        field = field!(source, group["field"])
        bucket = group["bucket"].presence
        # A bucket only means something on a date field; elsewhere it is ignored rather than failing the query.
        bucket = nil unless field.type == "date" && BUCKETS.include?(bucket)

        { field: field, bucket: bucket || (field.type == "date" ? "day" : nil), label: group["label"].presence || field.key }
      end
      measures = spec["measures"].map do |measure|
        agg = measure["agg"].to_s
        raise InvalidSpec, "agg ต้องเป็น #{AGGS.join(', ')}" unless AGGS.include?(agg)

        field = measure["field"].present? ? field!(source, measure["field"]) : nil
        raise InvalidSpec, "#{agg} ต้องระบุ field" if field.nil? && agg != "count"
        raise InvalidSpec, "#{agg} ใช้ได้กับฟิลด์ตัวเลขเท่านั้น" if %w[sum avg median].include?(agg) && field&.type != "number"

        { agg: agg, field: field, label: measure["label"].presence || [agg, field&.key].compact.join("_") }
      end

      grouped = rows.group_by { |row| groups.map { |group| bucket_value(row[group[:field].key], group[:bucket]) } }
      output = grouped.map do |keys, members|
        row = groups.each_with_index.to_h { |group, index| [group[:label], keys[index].nil? ? "(ไม่ระบุ)" : keys[index]] }
        measures.each { |measure| row[measure[:label]] = measure_value(members, measure) }
        row
      end
      output.sort_by! { |row| groups.map { |group| row[group[:label]].to_s } } if groups.any? { |group| group[:bucket] }
      [groups.map { |group| group[:label] } + measures.map { |measure| measure[:label] }, output]
    end

    def measure_value(rows, measure)
      return rows.size if measure[:agg] == "count" && measure[:field].nil?

      values = rows.map { |row| cast(row[measure[:field].key], measure[:field]) }.compact
      case measure[:agg]
      when "count" then values.size
      when "count_distinct" then values.uniq.size
      when "sum" then round(values.sum)
      when "avg" then values.empty? ? nil : round(values.sum.to_f / values.size)
      when "median" then values.empty? ? nil : round(median(values))
      when "min" then present(values.min)
      when "max" then present(values.max)
      end
    end

    def bucket_value(value, bucket)
      return present(value) if bucket.nil?
      return nil unless value.respond_to?(:in_time_zone)

      time = value.in_time_zone
      case bucket
      when "hour" then time.strftime("%Y-%m-%d %H:00")
      when "day" then time.strftime("%Y-%m-%d")
      when "week" then time.strftime("%G-W%V")
      when "month" then time.strftime("%Y-%m")
      when "quarter" then "#{time.year}-Q#{((time.month - 1) / 3) + 1}"
      when "year" then time.year.to_s
      when "fiscal_year" then "ปีงบ #{(time.month >= 10 ? time.year + 1 : time.year) + 543}"
      end
    end

    def sort(rows, sort, columns)
      return rows if sort.blank?

      sort = sort.to_h.stringify_keys
      key = sort["by"].to_s
      key = columns.find { |column| column == key } || columns.find { |column| column.end_with?(key) } || key
      sorted = rows.sort_by { |row| sortable(row[key]) }
      sort["dir"].to_s == "asc" ? sorted : sorted.reverse
    end

    def sortable(value)
      case value
      when Numeric then [1, value, ""]
      when nil then [0, 0, ""]
      else [2, 0, value.to_s]
      end
    end

    def cast(value, field)
      return nil if value.nil? || value == ""

      case field.type
      when "number" then value.is_a?(Numeric) ? value : Float(value.to_s.delete(","), exception: false)
      when "date" then value.respond_to?(:in_time_zone) && !value.is_a?(String) ? value.in_time_zone : parse_time(value)
      else value.to_s
      end
    end

    def present(value)
      case value
      when Time, DateTime, ActiveSupport::TimeWithZone then value.in_time_zone.iso8601
      when Date then value.iso8601
      when Float then round(value)
      else value
      end
    end

    def round(value) = value.is_a?(Float) ? value.round(2) : value

    def median(values)
      sorted = values.sort
      middle = sorted.size / 2
      sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
