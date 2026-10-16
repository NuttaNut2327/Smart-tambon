# Budget and project counts per fiscal year, split by approval status, for the stacked bar chart.
class ProjectBudgetSummary
  METRICS = %i[budget count].freeze

  Year = Struct.new(:fiscal_year, :segments, keyword_init: true) do
    def total(metric) = segments.values.sum { |segment| segment[metric] }
  end

  attr_reader :years

  def initialize(scope)
    rows = scope.pluck(:fiscal_year, :approval_status, :budget)
    @years = rows.group_by(&:first).compact.sort_by(&:first).filter_map do |fiscal_year, year_rows|
      next if fiscal_year.nil?

      segments = Project::APPROVAL_STATUSES.keys.index_with { { budget: 0.0, count: 0 } }
      year_rows.each do |_, approval_status, budget|
        segment = segments[approval_status.presence || "pending"] || segments["pending"]
        segment[:budget] += budget.to_f
        segment[:count] += 1
      end
      Year.new(fiscal_year:, segments:)
    end
  end

  def empty? = years.empty?

  def total(metric, approval_status = nil)
    years.sum { |year| approval_status ? year.segments[approval_status][metric] : year.total(metric) }
  end

  # Rounded y-axis maximum and tick values so gridlines land on readable numbers.
  def axis(metric)
    max = years.map { |year| year.total(metric) }.max.to_f
    return { max: 1, ticks: [0, 1] } if max <= 0

    step = nice_step(max / 4)
    step = [step.ceil, 1].max if metric == :count
    top = (max / step).ceil * step
    { max: top, ticks: (0..(top / step).round).map { |index| index * step } }
  end

  private

  def nice_step(raw)
    magnitude = 10**Math.log10(raw).floor
    fraction = raw / magnitude
    nice = [1, 2, 2.5, 5, 10].find { |candidate| fraction <= candidate }
    nice * magnitude
  end
end
