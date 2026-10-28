# Look-back search on the incident and disaster pages: keeps incidents whose event time falls inside a start–end
# date range, and builds the map features (incident point plus the assessed impact area) for the results map.
class IncidentHistorySearch
  attr_reader :from, :to

  def initialize(incidents, params)
    @incidents = incidents
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])
    @from ||= @to if @to
    @to ||= Time.zone.today if @from
    @from, @to = @to, @from if @from && @to && @from > @to
  end

  def active? = from.present?

  def results
    return @incidents unless active?

    range = from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day
    @incidents.select { |incident| incident.event_time && range.cover?(incident.event_time) }
  end

  def to_params = active? ? { from: from.iso8601, to: to.iso8601 } : {}

  def map_features(incidents, url_for_incident:)
    incidents.filter_map do |incident|
      area = incident.assessment_area_geojson
      next if incident.longitude.blank? && area.blank?

      { id: incident.id.to_s, reference_code: incident.reference_code, title: incident.title, severity: incident.severity,
        status: incident.status, event_time: incident.event_time&.iso8601, longitude: incident.longitude,
        latitude: incident.latitude, area:, url: url_for_incident.call(incident) }
    end
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end
end
