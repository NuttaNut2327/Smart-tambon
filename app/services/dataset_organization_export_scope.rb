class DatasetOrganizationExportScope
  TYPES = %w[teams workforce resources consumables].freeze

  def initialize(data_type:, records:)
    @data_type = data_type
    @records = records
  end

  def agency_options
    @records.filter_map do |record|
      key = agency_key(record)
      { key: key, label: agency_label(record) } if key.present?
    end.uniq { |option| option[:key] }.sort_by { |option| option[:label] }
  end

  def team_options(agency_key)
    return [] unless @data_type == "workforce"

    @records.select { |record| agency_key(record) == agency_key }.filter_map do |record|
      key = team_key(record)
      { key: key, label: record["team_name"].presence || record["team_code"] } if key.present?
    end.uniq { |option| option[:key] }.sort_by { |option| option[:label] }
  end

  def select(agency:, team: nil)
    raise ArgumentError, "กรุณาเลือกหน่วยงาน" unless agency_options.any? { |option| option[:key] == agency }
    if @data_type == "workforce"
      raise ArgumentError, "กรุณาเลือกทีมของหน่วยงานนี้" unless team_options(agency).any? { |option| option[:key] == team }
    end

    @records.select do |record|
      agency_key(record) == agency && (@data_type != "workforce" || team_key(record) == team)
    end
  end

  def agency_label_for(key) = agency_options.find { |option| option[:key] == key }&.dig(:label)
  def team_label_for(agency, key) = team_options(agency).find { |option| option[:key] == key }&.dig(:label)

  private

  def agency_key(record)
    code = record["agency_code"].to_s.strip
    name = agency_label(record).to_s.strip
    code.present? ? "code:#{code}" : ("name:#{name}" if name.present?)
  end

  def agency_label(record)
    record["agency_name"].presence || record["responsible_person"].presence || record["agency_code"]
  end

  def team_key(record)
    code = record["team_code"].to_s.strip
    name = record["team_name"].to_s.strip
    code.present? ? "code:#{code}" : ("name:#{name}" if name.present?)
  end
end
