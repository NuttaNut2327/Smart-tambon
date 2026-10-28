# Summaries of the DisasterEvent archive: totals, per-year and per-month counts, impact sums and repeat locations.
class DisasterStatistics
  MONTHS_TH = %w[ม.ค. ก.พ. มี.ค. เม.ย. พ.ค. มิ.ย. ก.ค. ส.ค. ก.ย. ต.ค. พ.ย. ธ.ค.].freeze
  IMPACT_FIELDS = %i[affected_households affected_people damaged_houses farmland_rai roads_km injuries deaths estimated_loss_baht area_rai].freeze

  def initialize(scope)
    @events = scope.only(:hazard, :severity, :subdistrict_id, :villages, :started_at, :ended_at, :rain_3d_mm, *IMPACT_FIELDS).to_a
  end

  attr_reader :events

  def call
    {
      period: period,
      totals: totals,
      by_year: by_year,
      by_month: by_month,
      top_subdistricts: top_subdistricts,
      repeat_villages: repeat_villages
    }
  end

  def period
    return {} if events.empty?

    first, last = events.map(&:started_at).minmax
    { from: first.to_date, to: last.to_date, years: ((last - first) / 1.year).round(1) }
  end

  def totals
    DisasterEvent::HAZARDS.keys.index_with do |hazard|
      list = events.select { |event| event.hazard == hazard }
      { label: DisasterEvent::HAZARDS[hazard][:label], count: list.size, **impact_sum(list) }
    end
  end

  def by_year
    events.group_by { |event| event.started_at.year + 543 }.sort.to_h.transform_values do |list|
      DisasterEvent::HAZARDS.keys.index_with { |hazard| list.count { |event| event.hazard == hazard } }
    end
  end

  # Average events per year in each calendar month, the seasonal fingerprint of each hazard.
  def by_month
    years = [period[:years].to_f, 1.0].max
    DisasterEvent::HAZARDS.keys.index_with do |hazard|
      counts = events.select { |event| event.hazard == hazard }.group_by { |event| event.started_at.month }
      MONTHS_TH.each_with_index.map { |label, index| { month: label, total: counts.fetch(index + 1, []).size, per_year: (counts.fetch(index + 1, []).size / years).round(2) } }
    end
  end

  def top_subdistricts(limit: 10)
    names = Subdistrict.where(id: events.map(&:subdistrict_id).uniq).pluck(:id, :name_th).to_h
    events.group_by(&:subdistrict_id).map do |id, list|
      { subdistrict_id: id, name: names[id], count: list.size, by_hazard: list.map(&:hazard).tally, **impact_sum(list).slice(:affected_households, :estimated_loss_baht) }
    end.sort_by { |row| -row[:count] }.first(limit)
  end

  # Villages hit again and again by the same hazard: the places to warn first.
  def repeat_villages(hazard: nil, limit: 10)
    names = Subdistrict.where(id: events.map(&:subdistrict_id).uniq).pluck(:id, :name_th).to_h
    events.select { |event| hazard.nil? || event.hazard == hazard }
      .flat_map { |event| Array(event.villages).map { |moo| [event.hazard, event.subdistrict_id, moo] } }
      .tally.select { |_, count| count > 1 }.sort_by { |_, count| -count }.first(limit)
      .map { |(event_hazard, subdistrict_id, moo), count| { hazard: event_hazard, label: "หมู่ที่ #{moo} ต.#{names[subdistrict_id]}", count: } }
  end

  private

  def impact_sum(list)
    IMPACT_FIELDS.index_with { |field| list.sum { |event| event[field].to_f }.round(1) }
  end
end
