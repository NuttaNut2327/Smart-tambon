class WaterStationMapService
  SAME_LOCATION_METERS = 100
  SOURCE_PRIORITY = { "own" => 0, "dwr" => 1, "thaiwater" => 2 }.freeze

  class << self
    def call(scope)
      clusters = []
      canonical_index = {}
      code_index = {}
      name_index = {}
      location_index = Hash.new { |hash, key| hash[key] = [] }

      scope.to_a.sort_by { |station| [SOURCE_PRIORITY.fetch(station.source, 9), -(station.source_observed_at&.to_i || 0)] }.each do |station|
        cluster = indexed_cluster(station, canonical_index, code_index, name_index, location_index)
        unless cluster
          cluster = []
          clusters << cluster
        end
        cluster << station
        index_station(station, cluster, canonical_index, code_index, name_index, location_index)
      end
      clusters.map { |cluster| merged_json(cluster) }
    end

    private

    def indexed_cluster(station, canonical_index, code_index, name_index, location_index)
      canonical_key = station.canonical_station_key.presence
      return canonical_index[canonical_key] if canonical_key && canonical_index.key?(canonical_key)

      code_key = normalize(station.station_code)
      return code_index[code_key] if code_key.present? && code_index.key?(code_key)

      owner_key = normalize(station.agency)
      name_key = normalize(station.station_name_th)
      identity_key = [owner_key, name_key]
      return name_index[identity_key] if owner_key.present? && name_key.present? && name_index.key?(identity_key)

      nearby_clusters(station, owner_key, location_index).find do |cluster|
        distance_meters(cluster.first, station) <= SAME_LOCATION_METERS
      end
    end

    def index_station(station, cluster, canonical_index, code_index, name_index, location_index)
      canonical_key = station.canonical_station_key.presence
      canonical_index[canonical_key] = cluster if canonical_key

      code_key = normalize(station.station_code)
      code_index[code_key] = cluster if code_key.present?

      owner_key = normalize(station.agency)
      name_key = normalize(station.station_name_th)
      name_index[[owner_key, name_key]] = cluster if owner_key.present? && name_key.present?
      location_index[[owner_key, *location_bucket(station)]].append(cluster) if owner_key.present?
    end

    def nearby_clusters(station, owner_key, location_index)
      return [] if owner_key.blank?

      x, y = location_bucket(station)
      (-1..1).flat_map do |dx|
        (-1..1).flat_map { |dy| location_index[[owner_key, x + dx, y + dy]] }
      end.uniq
    end

    def location_bucket(station)
      # Roughly 100 metres per bucket. Adjacent buckets are inspected before the
      # exact Haversine check, keeping nationwide de-duplication close to O(n).
      [(station.location.x * 1_000).floor, (station.location.y * 1_000).floor]
    end

    def merged_json(cluster)
      primary = cluster.min_by { |station| SOURCE_PRIORITY.fetch(station.source, 9) }
      water_level = best_metric(cluster, :water_level_m_msl, :water_level_observed_at, :water_level_source)
      rainfall = best_metric(cluster, :rainfall_value, :rainfall_observed_at, :rainfall_source)
      primary.as_map_json.merge(
        water_level_m_msl: water_level&.water_level_m_msl,
        water_level_observed_at: water_level&.water_level_observed_at,
        water_level_source: water_level&.water_level_source || water_level&.source,
        rainfall_value: rainfall&.rainfall_value,
        rainfall_observed_at: rainfall&.rainfall_observed_at,
        rainfall_source: rainfall&.rainfall_source || rainfall&.source,
        sources: cluster.map { |station| station.source }.uniq.sort_by { |source| SOURCE_PRIORITY.fetch(source, 9) },
        duplicate_count: cluster.size
      )
    end

    def best_metric(cluster, value_field, time_field, source_field)
      current = Time.current
      available = cluster.select { |station| station.public_send(value_field).present? && station.public_send(time_field).present? }
      fresh = available.select { |station| station.public_send(time_field).between?(current - 1.hour, current + 5.minutes) }
      candidates = fresh.presence || available
      candidates.min_by do |station|
        source = station.public_send(source_field).presence || station.source
        [SOURCE_PRIORITY.fetch(source, 9), -(station.public_send(time_field)&.to_i || 0)]
      end
    end

    def distance_meters(left, right)
      lat1 = left.location.y * Math::PI / 180
      lat2 = right.location.y * Math::PI / 180
      dlat = lat2 - lat1
      dlon = (right.location.x - left.location.x) * Math::PI / 180
      a = Math.sin(dlat / 2)**2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dlon / 2)**2
      6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9ก-๙]/, "")
    end
  end
end
