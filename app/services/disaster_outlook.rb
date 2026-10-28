# Seasonal outlook from the disaster archive: how often each hazard struck around this time in past years,
# whether it was rising or easing in the following weeks, and how the coming rain compares with the rain
# that preceded past floods and landslides. History drives the outlook; the rain forecast only sharpens it.
class DisasterOutlook
  WEEKS_BEFORE = 2
  WEEKS_AFTER = 4
  RAIN_HAZARDS = %w[flood landslide].freeze

  # rain_3d_mm: optional override of the forecast 3-day rain total (for demos and "what if" questions).
  def initialize(user, scope:, date: Date.current, rain_3d_mm: nil, weather: nil)
    @user = user
    @events = scope.only(:hazard, :severity, :subdistrict_id, :villages, :started_at, :rain_3d_mm, :affected_households, :simulated).to_a
    @date = date
    @rain_override = rain_3d_mm
    @weather = weather
  end

  def call
    rain = rain_forecast
    hazards = DisasterEvent::HAZARDS.keys.map { |hazard| hazard_outlook(hazard, rain) }
    {
      date: @date,
      data_from: @events.map(&:started_at).min&.to_date,
      rain_forecast: rain,
      hazards: hazards.sort_by { |row| [-risk_rank(row[:risk]), -row[:this_week_avg]] },
      summary: hazards.sort_by { |row| -risk_rank(row[:risk]) }.flat_map { |row| row[:messages] }.first(6)
    }
  end

  # Archive events that started in this same week (the outlook date and the 6 days after) in earlier years, newest first.
  def events_in_week(offset = 0)
    start = @date + (offset * 7)
    finish = start + 6
    first = @events.map(&:started_at).min
    return [] unless first

    years = (first.year...@date.year).to_a
    @events.select { |event| years.any? { |year| in_window?(event.started_at.to_date, start, finish, year) } }
      .sort_by { |event| -event.started_at.to_i }
  end

  private

  def hazard_outlook(hazard, rain)
    list = @events.select { |event| event.hazard == hazard }
    label = DisasterEvent::HAZARDS[hazard][:label]
    weeks = (-WEEKS_BEFORE..WEEKS_AFTER).map { |offset| week_row(list, offset) }
    current = weeks.find { |row| row[:offset].zero? }
    ahead = weeks.select { |row| row[:offset].between?(1, 2) }.sum { |row| row[:average] } / 2
    behind = weeks.select { |row| row[:offset].between?(-2, -1) }.sum { |row| row[:average] } / 2
    trend = trend_label(behind, current[:average], ahead)
    trigger = rain_trigger(list) if RAIN_HAZARDS.include?(hazard)
    # A single subdistrict has few events per week, so judge the season over the five weeks around the date.
    seasonal = weeks.select { |row| row[:offset].between?(-2, 2) }.sum { |row| row[:average] } / 5
    risk = risk_level([current[:average], ahead, seasonal].max, seasonal, rain, trigger)
    {
      hazard:, label:, risk:, trend:,
      this_week_avg: current[:average], this_week_last_year: current[:last_year],
      weeks:, rain_trigger_mm: trigger,
      hotspots: hotspots(list),
      messages: messages(label, weeks, current, trend, rain, seasonal.positive? ? trigger : nil, risk)
    }
  end

  # Events in the 7 days starting `offset` weeks from the outlook date, averaged over past years and for last year alone.
  def week_row(list, offset)
    start = @date + (offset * 7)
    finish = start + 6
    years = past_years(start, finish)
    hits = years.to_h { |year| [year, list.count { |event| in_window?(event.started_at.to_date, start, finish, year) }] }
    {
      offset:, from: start, to: finish, label: week_label(start),
      average: years.empty? ? 0.0 : (hits.values.sum.to_f / years.size).round(2),
      last_year: hits.fetch(@date.year - 1, 0),
      years: years.size
    }
  end

  # Years whose copy of this window is fully covered by the archive; this year counts once the window has passed.
  def past_years(start, finish)
    first = @events.map(&:started_at).min&.to_date
    return [] unless first

    last_year = finish < @date ? @date.year : @date.year - 1
    (first.year..last_year).select { |year| shift(start, year) >= first }
  end

  def in_window?(day, start, finish, year)
    day.between?(shift(start, year), shift(finish, year))
  end

  def shift(day, year)
    target = year - (@date.year - day.year)
    Date.valid_date?(target, day.month, day.day) ? day.change(year: target) : Date.new(target, day.month, 28)
  end

  # Median 3-day rain before past events, and the lower quartile as the "watch" level.
  def rain_trigger(list)
    values = list.filter_map(&:rain_3d_mm).sort
    return if values.empty?

    { watch_mm: values[(values.size * 0.25).floor].round, median_mm: values[values.size / 2].round, events: values.size }
  end

  def risk_level(peak, seasonal, rain, trigger)
    rain_mm = rain && rain[:total_mm]
    if trigger && rain_mm && seasonal.positive?
      return "สูงมาก" if rain_mm >= trigger[:median_mm]
      return "สูง" if rain_mm >= trigger[:watch_mm]
    end
    return "สูง" if peak >= 2
    return "ปานกลาง" if peak >= 0.5

    "ต่ำ"
  end

  def risk_rank(risk) = { "สูงมาก" => 3, "สูง" => 2, "ปานกลาง" => 1 }.fetch(risk, 0)

  def trend_label(behind, now, ahead)
    return "นอกฤดูกาล" if [behind, now, ahead].max.zero?
    return "เพิ่มขึ้น" if ahead > now * 1.25 && ahead - now >= 0.2
    recent = [now, behind].max
    return "ลดลง" if ahead < recent * 0.75 && recent - ahead >= 0.2

    "ทรงตัว"
  end

  def messages(label, weeks, current, trend, rain, trigger, risk)
    lines = []
    last_year_now = current[:last_year]
    following = weeks.select { |row| row[:offset].between?(1, 3) }
    if weeks.any? { |row| row[:average].positive? }
      lines << "#{label}: ช่วง#{current[:label]} ในอดีตเกิดเฉลี่ย #{format_avg(current[:average])} ครั้ง/สัปดาห์ (ปีที่แล้ว #{last_year_now} ครั้ง) แนวโน้มสัปดาห์ถัดไป#{trend}"
      if trend == "ลดลง"
        recent = weeks.select { |row| row[:offset] <= 0 }.map { |row| row[:average] }.max
        easing = following.find { |row| row[:average] < recent * 0.5 } || following.last
        lines << "จากสถิติย้อนหลัง #{easing[:years]} ปี #{label}เริ่มลดลงตั้งแต่#{easing[:label]} (เฉลี่ย #{format_avg(easing[:average])} ครั้ง/สัปดาห์ ปีที่แล้ว #{easing[:last_year]} ครั้ง)"
      elsif trend == "เพิ่มขึ้น"
        peak = following.max_by { |row| row[:average] }
        lines << "ช่วง#{peak[:label]} เป็นช่วงที่#{label}เกิดบ่อยที่สุดในอดีต (เฉลี่ย #{format_avg(peak[:average])} ครั้ง/สัปดาห์) ควรเตรียมพร้อม"
      end
    end
    if trigger && rain && rain[:total_mm]
      compare = rain[:total_mm] >= trigger[:median_mm] ? "สูงกว่า" : (rain[:total_mm] >= trigger[:watch_mm] ? "ใกล้เคียง" : "ต่ำกว่า")
      lines << "ฝนคาดการณ์ 3 วัน #{rain[:total_mm].round} มม. #{compare}ระดับฝนก่อนเกิด#{label}ในอดีต (ค่ากลาง #{trigger[:median_mm]} มม.) ความเสี่ยง#{risk}"
    end
    lines
  end

  def hotspots(list)
    names = Subdistrict.where(id: list.map(&:subdistrict_id).uniq).pluck(:id, :name_th).to_h
    nearby = list.select { |event| (event.started_at.yday - @date.yday).abs <= 30 || (event.started_at.yday - @date.yday).abs >= 335 }
    nearby.flat_map { |event| Array(event.villages).map { |moo| [event.subdistrict_id, moo] } }
      .tally.sort_by { |_, count| -count }.first(5)
      .map { |(subdistrict_id, moo), count| { label: "หมู่ที่ #{moo} ต.#{names[subdistrict_id]}", count: } }
  end

  def rain_forecast
    return { total_mm: @rain_override.to_f, source: "กำหนดเอง (จำลองสถานการณ์)", days: [] } if @rain_override

    forecast = (@weather || Broadcasts::HazardOutlook.new(@user)).weather_forecast
    return { error: forecast["error"] } if forecast["error"]

    days = Array(forecast["days"]).drop(1).first(3)
    { total_mm: days.sum { |day| day["rain_mm"].to_f }.round(1), source: forecast["source"], location: forecast["location"], days: }
  rescue StandardError => error
    Rails.logger.warn("Disaster outlook rain forecast failed: #{error.class}: #{error.message}")
    { error: "ยังดึงพยากรณ์ฝนไม่ได้" }
  end

  def week_label(start)
    month = DisasterStatistics::MONTHS_TH[start.month - 1]
    week = (start.day - 1) / 7 + 1
    week >= 4 && start.end_of_month.day - start.day < 7 ? "สัปดาห์สุดท้ายของ #{month}" : "สัปดาห์ที่ #{week} ของ #{month}"
  end

  def format_avg(value) = value.round(1).to_s.sub(/\.0\z/, "")
end
