require "net/http"

module SmartImports
  # Gives each row a latitude/longitude inside the chosen subdistrict: coordinates written in the file (decimal or
  # degrees-minutes-seconds) are parsed first; otherwise the location text is geocoded with Longdo, then Nominatim,
  # and only results that fall inside the subdistrict boundary are accepted. Rows never default to the area center.
  class GeoResolver
    NOMINATIM_URL = "https://geocode.pcm-life.com/search".freeze
    LONGDO_URL = "https://search.longdo.com/mapsearch/json/search".freeze
    DECIMAL_PAIR = /(-?\d{1,3}\.\d{3,})\s*[,;\/ ]\s*(-?\d{1,3}\.\d{3,})/
    DMS = /(\d{1,3})\s*[°º]\s*(\d{1,2})\s*['′]\s*(\d{1,2}(?:\.\d+)?)\s*(?:["″]|'')?\s*([NSEWnsew])?/
    LOCATION_PREFIX = /\A(?:ใกล้|หน้า|ข้าง|ตรงข้าม|หลัง|ติด|บริเวณ|ริม|แถว)\s*/

    def initialize(subdistrict)
      @subdistrict = subdistrict
      @cache = {}
    end

    # Fills "latitude", "longitude", "_geo" and "_geo_note" on every row hash (keys are the column keys).
    def resolve(rows, columns, geocode: true)
      rows.each { |row| resolve_row(row, columns, geocode:) }
    end

    def resolve_row(row, columns, geocode: true)
      row.delete("_geo_note")
      lat, lon, note = from_columns(row, columns)
      if lat
        assign(row, lat, lon, inside?(lat, lon) ? "file" : "outside", note)
      elsif geocode && (query = location_query(row, columns)).present?
        found = geocode_query(query)
        found ? assign(row, found[:lat], found[:lon], "geocoded", found[:label]) : assign(row, nil, nil, "not_found", query)
      else
        assign(row, nil, nil, location_query(row, columns).present? ? "not_found" : "none", nil)
      end
      row
    end

    # A coordinate pair typed by the user in the table: only the boundary is checked.
    def check_manual(row)
      row.delete("_geo_note")
      lat, lon = Float(row["latitude"], exception: false), Float(row["longitude"], exception: false)
      return assign(row, nil, nil, "none", nil) unless lat && lon

      assign(row, lat, lon, inside?(lat, lon) ? "manual" : "outside", nil)
    end

    def self.parse_pair(text)
      text = text.to_s
      if (match = text.match(DECIMAL_PAIR))
        a, b = match[1].to_f, match[2].to_f
        return order(a, b)
      end
      parts = text.scan(DMS)
      return unless parts.size >= 2

      values = parts.first(2).map do |deg, min, sec, hemi|
        value = deg.to_f + min.to_f / 60 + sec.to_f / 3600
        %w[S W].include?(hemi.to_s.upcase) ? -value : value
      end
      lat_part = parts.first(2).index { |part| %w[N S].include?(part[3].to_s.upcase) }
      lat_part ? [values[lat_part], values[1 - lat_part]] : order(*values)
    end

    # Thailand: latitude 5–21, longitude 97–106, so a reversed pair is easy to spot.
    def self.order(a, b)
      a.abs > 90 || (b.between?(5, 21) && a.between?(97, 106)) ? [b, a] : [a, b]
    end

    private

    def assign(row, lat, lon, status, note)
      row["latitude"] = lat&.round(7)
      row["longitude"] = lon&.round(7)
      row["_geo"] = status
      row["_geo_note"] = note if note.present?
      row
    end

    def from_columns(row, columns)
      lat_col = columns.find { |column| column["role"] == "latitude" }
      lon_col = columns.find { |column| column["role"] == "longitude" }
      if lat_col && lon_col
        lat, lon = Float(row[lat_col["key"]].to_s.strip, exception: false), Float(row[lon_col["key"]].to_s.strip, exception: false)
        lat ||= dms_value(row[lat_col["key"]])
        lon ||= dms_value(row[lon_col["key"]])
        return [lat, lon, nil] if valid?(lat, lon)
      end
      # Coordinates columns first, then any other cell (people often type coordinates into the address column).
      ordered = columns.sort_by { |column| column["role"] == "coordinates" ? 0 : 1 }
      ordered.each do |column|
        pair = self.class.parse_pair(row[column["key"]])
        next unless pair && valid?(*pair)

        return [*pair, column["role"] == "coordinates" ? nil : "อ่านพิกัดจากคอลัมน์ #{column['label']}"]
      end
      nil
    end

    def dms_value(text)
      deg, min, sec, hemi = text.to_s.match(DMS)&.captures
      return unless deg

      value = deg.to_f + min.to_f / 60 + sec.to_f / 3600
      %w[S W].include?(hemi.to_s.upcase) ? -value : value
    end

    def valid?(lat, lon) = lat && lon && lat.between?(-90, 90) && lon.between?(-180, 180) && !(lat.zero? && lon.zero?)

    def location_query(row, columns)
      columns.select { |column| column["role"] == "location" }.map { |column| row[column["key"]].to_s.strip }.compact_blank.join(" ")
    end

    def geocode_query(query)
      return unless @subdistrict

      @cache[query] ||= begin
        cleaned = query.sub(LOCATION_PREFIX, "").gsub(/กม\.?\s*[\d.]+/, "").strip
        candidates = [query, cleaned, cleaned.sub(/\s*(?:หมู่(?:ที่)?|ม\.)\s*\d+.*\z/, "")].map(&:strip).uniq.compact_blank
        candidates.lazy.filter_map { |text| longdo(text) || nominatim(text) }.first || :none
      end
      @cache[query] == :none ? nil : @cache[query]
    end

    def longdo(text)
      key = SystemSetting.current.longdo_map_key
      return if key.blank? || center.nil?

      json = get_json(LONGDO_URL, keyword: text, key:, lat: center[0], lon: center[1], span: "20km", limit: 10, locale: "th")
      Array(json&.dig("data")).each do |item|
        # Skip the subdistrict/district itself: its centroid is not where the row's place is.
        next if item["name"].to_s.match?(/\A(?:ต\.|อ\.|จ\.|ตำบล|อำเภอ|จังหวัด)/)

        lat, lon = item["lat"].to_f, item["lon"].to_f
        return { lat:, lon:, label: [item["name"], item["address"]].compact_blank.join(" · ") } if valid?(lat, lon) && inside?(lat, lon)
      end
      nil
    end

    def nominatim(text)
      return unless bbox

      min_lon, min_lat, max_lon, max_lat = bbox
      json = get_json(NOMINATIM_URL, q: text, format: "json", limit: 10, "accept-language": "th", countrycodes: "th",
                                     viewbox: [min_lon, max_lat, max_lon, min_lat].join(","), bounded: 1)
      Array(json).each do |item|
        lat, lon = item["lat"].to_f, item["lon"].to_f
        return { lat:, lon:, label: item["display_name"].to_s.truncate(120) } if valid?(lat, lon) && inside?(lat, lon)
      end
      nil
    end

    def get_json(url, params)
      uri = URI(url)
      uri.query = URI.encode_www_form(params)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri, "User-Agent" => "SmartTambon/1.0", "Accept" => "application/json")
      end
      response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : nil
    rescue JSON::ParserError, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError
      nil
    end

    def inside?(lat, lon)
      return true unless @subdistrict&.boundary

      sql = ActiveRecord::Base.sanitize_sql_array(["SELECT ST_Covers(boundary, ST_SetSRID(ST_MakePoint(?, ?), 4326)) FROM subdistricts WHERE id = ?", lon, lat, @subdistrict.id])
      ActiveRecord::Base.connection.select_value(sql) == true
    end

    def center
      @center ||= begin
        point = @subdistrict&.center
        point ? [point.y, point.x] : nil
      end
    end

    def bbox
      @bbox ||= begin
        sql = ActiveRecord::Base.sanitize_sql_array(["SELECT ST_XMin(boundary), ST_YMin(boundary), ST_XMax(boundary), ST_YMax(boundary) FROM subdistricts WHERE id = ?", @subdistrict&.id])
        values = ActiveRecord::Base.connection.select_rows(sql).first
        values&.all? ? values.map(&:to_f) : nil
      end
    end
  end
end
