module ProjectsHelper
  # Short baht amounts for chart labels, e.g. 1250000 => "1.25 ล้าน".
  def compact_baht(amount)
    amount = amount.to_f
    return "#{number_with_precision(amount / 1_000_000, precision: 2, strip_insignificant_zeros: true, delimiter: ",")} ล้าน" if amount >= 1_000_000
    return "#{number_with_precision(amount / 1_000, precision: 1, strip_insignificant_zeros: true)} พัน" if amount >= 10_000

    number_with_delimiter(amount.round)
  end

  def project_metric_label(metric, value)
    metric == :budget ? compact_baht(value) : "#{value.to_i} โครงการ"
  end
end
