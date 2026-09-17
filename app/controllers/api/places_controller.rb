require "net/http"

module Api
  class PlacesController < ApplicationController
    CATEGORIES = {
      "government" => %w[government municipality],
      "education" => %w[school university library],
      "health" => %w[hospital clinic pharmacy],
      "culture" => %w[temple mosque church museum],
      "tourism" => ["tourist attraction", "hotel", "park", "viewpoint"],
      "transport" => ["bus station", "train station", "pier", "parking"],
      "service" => %w[restaurant cafe shopping convenience],
      "emergency" => %w[police fire_station rescue]
    }.freeze
    CACHE_BUCKETS = {
      "300km" => 1.0,
      "120km" => 0.5,
      "50km" => 0.2,
      "20km" => 0.1,
      "8km" => 0.04
    }.freeze
    POPULATION_ESTIMATES = {
      "government" => 150, "education" => 500, "health" => 120,
      "culture" => 200, "tourism" => 300, "transport" => 250,
      "service" => 100, "emergency" => 80
    }.freeze
    RESULTS_PER_PAGE = 50

    def index
      longdo_tags = CATEGORIES[params[:category]]
      return render json: { error: "ไม่พบหมวดหมู่สถานที่" }, status: :unprocessable_entity unless longdo_tags

      subdistrict = selected_subdistrict
      province = selected_province
      access_area = selected_access_area
      if subdistrict
        query_span = "20km"
        query_area = subdistrict.code
        lon, lat = subdistrict_center(subdistrict)
        key = subdistrict_cache_key(subdistrict.code, params[:category])
      elsif province
        query_span = "300km"
        query_area = province.code
        lon, lat = province_center(province)
        key = province_cache_key(params[:category], longdo_tags.join(","), province.id)
      elsif access_area
        query_span, lon, lat = access_area_query(access_area)
        query_area = nil
        key = access_area_cache_key(access_area.id, params[:category])
      else
        query_span = span
        query_area = area
        lon, lat = cache_center(query_span)
        key = cache_key(params[:category], longdo_tags.join(","), query_span, lon, lat, query_area)
      end
      cached = find_cache(key)
      if cached&.fresh? && params[:load_more] != "1"
        track_usage(cache_hits: 1)
        return render_cache(cached)
      end
      if api_key.blank? && cached
        track_usage(cache_hits: 1)
        return render_cache(cached, stale: true)
      end
      return render json: { error: "ยังไม่ได้กำหนด LONGDO_MAP_KEY" }, status: :service_unavailable if api_key.blank?

      base_places = cached ? cached.places : []
      tag_states = cached ? cached_tag_states(cached.response_meta, longdo_tags) : initial_tag_states(longdo_tags)
      tag, state = next_tag_to_fetch(longdo_tags, tag_states)
      return render_cache(cached) if tag.blank? && cached&.fresh?

      result = fetch_places_page(tag, lon, lat, query_span, query_area, state.fetch("offset", 0))
      unless result[:payload]
        meta = response_meta(longdo_tags, tag_states, province: province, subdistrict: subdistrict, access_area: access_area)
        meta["pagination"]["retry_after_seconds"] = result[:status].between?(400, 499) ? 300 : 15
        meta["upstream_status"] = result[:status]
        saved_cache = write_cache(key, params[:category], longdo_tags.join(","), query_span, query_area, lon, lat, base_places, meta)
        return render json: cache_response(base_places, meta, hit: false, cache: saved_cache, stale: cached.present?)
      end
      payload = result[:payload]

      page_places = normalize_places(payload, params[:category])
      places = merge_places(base_places, page_places)
      state["pages"] = state.fetch("pages", 0) + 1
      state["offset"] = state.fetch("offset", 0) + Array(payload["data"]).length
      state["complete"] = !has_more?(payload) || Array(payload["data"]).empty?
      tag_states[tag] = state
      meta = response_meta(longdo_tags, tag_states, province: province, subdistrict: subdistrict, access_area: access_area)
      saved_cache = write_cache(key, params[:category], longdo_tags.join(","), query_span, query_area, lon, lat, places, meta)
      render json: cache_response(places, meta, hit: false, cache: saved_cache)
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError
      track_usage(failed_requests: 1)
      return render_cache(cached, stale: true) if cached
      render json: { error: "ไม่สามารถเชื่อมต่อ Longdo Map ได้" }, status: :bad_gateway
    end

    def usage
      stat = LongdoUsageStat.where(stat_key: "all_time").first
      render json: {
        longdo_requests: stat&.longdo_requests || 0,
        cache_hits: stat&.cache_hits || 0,
        cache_misses: stat&.cache_misses || 0,
        failed_requests: stat&.failed_requests || 0
      }
    end

    private

    def api_key
      ENV["LONGDO_MAP_KEY"]
    end

    def coordinate(name, fallback, range)
      value = Float(params[name], exception: false)
      value && range.cover?(value) ? value : fallback
    end

    def span
      value = params[:span].to_s
      value.match?(/\A\d+(?:\.\d+)?(?:m|km|deg)\z/) ? value : "30km"
    end

    def cache_center(query_span)
      bucket = CACHE_BUCKETS.fetch(query_span, 0.1)
      lon = coordinate(:lon, 100.5018, -180..180)
      lat = coordinate(:lat, 13.7563, -90..90)
      [(lon / bucket).round * bucket, (lat / bucket).round * bucket]
    end

    def cache_key(category, longdo_tag, query_span, lon, lat, query_area)
      [category, longdo_tag, query_span, query_area || "nearby", format("%.4f", lon), format("%.4f", lat)].join(":")
    end

    def province_cache_key(category, longdo_tag, province_id)
      ["province", province_id, category, longdo_tag].join(":")
    end

    def subdistrict_cache_key(subdistrict_code, category)
      ["subdistrict", subdistrict_code, category].join(":")
    end

    def access_area_cache_key(access_area_id, category)
      area = UserAccessArea.find(access_area_id)
      ["access_area", access_area_id, area.updated_at.to_i, category].join(":")
    end

    def selected_subdistrict
      return current_user.subdistrict if !global_viewer? && current_user.access_area.blank?
      return unless global_viewer?

      code = params[:area].to_s
      return if code.blank?

      Subdistrict.find_by(code: code)
    end

    def selected_province
      return unless global_viewer? && params[:province_id].present?

      Province.find_by(id: params[:province_id])
    end

    def selected_access_area
      current_user.access_area unless global_viewer?
    end

    def province_center(province)
      center = province.center
      return [center.x, center.y] if center.present?

      [100.5018, 13.7563]
    end

    def subdistrict_center(subdistrict)
      center = subdistrict.center
      return [center.x, center.y] if center.present?

      province_center(subdistrict.province)
    end

    def access_area_query(access_area)
      points = boundary_points(access_area.boundary)
      raise ArgumentError, "ขอบเขตพื้นที่ดูแลไม่มีพิกัด Polygon" if points.empty?
      longitudes = points.map(&:x)
      latitudes = points.map(&:y)
      lon = (longitudes.min + longitudes.max) / 2.0
      lat = (latitudes.min + latitudes.max) / 2.0
      horizontal_km = (longitudes.max - longitudes.min).abs * 111.32 * Math.cos(lat * Math::PI / 180)
      vertical_km = (latitudes.max - latitudes.min).abs * 110.57
      radius_km = Math.sqrt((horizontal_km / 2.0)**2 + (vertical_km / 2.0)**2)
      ["#{[[radius_km.ceil + 1, 1].max, 300].min}km", lon, lat]
    end

    def boundary_points(geometry)
      case geometry.geometry_type.type_name
      when "Polygon"
        geometry.exterior_ring.points
      when "MultiPolygon"
        geometry.to_a.flat_map { |polygon| polygon.exterior_ring.points }
      else
        []
      end
    end

    def cache_ttl
      value = Integer(ENV.fetch("LONGDO_CACHE_TTL", "86400"), exception: false)
      value&.positive? ? value : 86_400
    end

    def find_cache(key)
      LongdoPlaceCache.where(query_key: key).first
    rescue Mongo::Error => error
      Rails.logger.warn("Longdo cache read failed: #{error.class}: #{error.message}")
      nil
    end

    def write_cache(key, category, longdo_tag, query_span, query_area, lon, lat, places, response_meta)
      cache = LongdoPlaceCache.where(query_key: key).find_one_and_update(
        { "$set" => {
          query_key: key,
          category: category,
          longdo_tag: longdo_tag,
          center: [lon, lat],
          span: query_span,
          area: query_area,
          places: places,
          response_meta: response_meta,
          expires_at: cache_ttl.seconds.from_now,
          updated_at: Time.current
        }, "$setOnInsert" => { created_at: Time.current } },
        upsert: true,
        return_document: :after
      )
      cache
    rescue Mongo::Error => error
      Rails.logger.warn("Longdo cache write failed: #{error.class}: #{error.message}")
      nil
    end

    def area
      return current_user.subdistrict&.code unless global_viewer?

      value = params[:area].to_s
      value.match?(/\A\d{2,6}\z/) ? value : nil
    end

    def render_cache(cache, stale: false)
      render json: cache_response(cache.places, cache.response_meta, hit: true, cache: cache, stale: stale)
    end

    def cache_response(places, response_meta, hit:, cache:, stale: false)
      meta = response_meta.to_h.deep_dup
      meta["pagination"] ||= pagination_meta(initial_tag_states(Array(meta["tags"])))
      {
        data: places_visible_to_current_user(places),
        meta: meta.merge("cache" => {
          "hit" => hit,
          "stale" => stale,
          "cached_at" => cache&.updated_at,
          "expires_at" => cache&.expires_at
        })
      }
    end

    def places_visible_to_current_user(places)
      return places if global_viewer?

      boundary = current_user.access_boundary
      return [] unless boundary

      AccessBoundaryPointFilter.new(boundary).filter(places) { |place| [place["lon"], place["lat"]] }
    end

    def fetch_places_page(tag, lon, lat, query_span, query_area, offset)
      uri = URI("https://api.longdo.com/POIService/json/search")
      query = {
        key: api_key, tag: tag, lon: lon, lat: lat, span: query_span,
        offset: offset, limit: RESULTS_PER_PAGE, locale: "th"
      }
      query[:area] = query_area if query_area
      uri.query = URI.encode_www_form(query)
      track_usage(longdo_requests: 1, cache_misses: 1)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri, { "Accept" => "application/json" })
      end
      unless response.is_a?(Net::HTTPSuccess)
        track_usage(failed_requests: 1)
        return { payload: nil, status: response.code.to_i }
      end

      { payload: JSON.parse(response.body), status: response.code.to_i }
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError => error
      Rails.logger.warn("Longdo places request failed: #{error.class}: #{error.message}")
      track_usage(failed_requests: 1)
      { payload: nil, status: 0 }
    end

    def initial_tag_states(tags)
      tags.to_h { |tag| [tag, { "offset" => 0, "pages" => 0, "complete" => false }] }
    end

    def cached_tag_states(meta, tags)
      states = meta.to_h.dig("pagination", "tag_states")
      return initial_tag_states(tags) unless states.is_a?(Hash)

      tags.to_h do |tag|
        saved = states[tag].to_h
        [tag, {
          "offset" => saved.fetch("offset", 0).to_i,
          "pages" => saved.fetch("pages", 0).to_i,
          "complete" => ActiveModel::Type::Boolean.new.cast(saved["complete"])
        }]
      end
    end

    def next_tag_to_fetch(tags, tag_states)
      tag = tags.reject { |candidate| tag_states[candidate]["complete"] }
        .min_by { |candidate| [tag_states[candidate]["pages"], tags.index(candidate)] }
      [tag, tag && tag_states[tag]]
    end

    def normalize_places(payload, category)
      Array(payload["data"]).filter_map do |place|
        next unless place["lat"].present? && place["lon"].present?

        place.slice("id", "name", "lat", "lon", "address", "tel", "url", "verified", "tag").merge(
          "category" => category,
          "estimated_population" => estimated_population_for(place, category),
          "population_estimate_source" => "category_estimate"
        )
      end
    end

    def merge_places(existing_places, new_places)
      (Array(existing_places) + new_places).uniq do |place|
        place["id"].presence || [place["name"], place["lat"], place["lon"]].join(":")
      end
    end

    def has_more?(payload)
      ActiveModel::Type::Boolean.new.cast(payload["hasmore"])
    end

    def response_meta(tags, tag_states, province: nil, subdistrict: nil, access_area: nil)
      {
        "tags" => tags,
        "sources" => tag_states.count { |_tag, state| state["pages"].positive? },
        "pagination" => pagination_meta(tag_states),
        "cache_scope" => if subdistrict
          { "type" => "subdistrict", "subdistrict_id" => subdistrict.id, "subdistrict_code" => subdistrict.code }
        elsif province
          { "type" => "province", "province_id" => province.id, "province_code" => province.code }
        elsif access_area
          { "type" => "access_area", "access_area_id" => access_area.id,
            "source" => access_area.source, "subdistrict_ids" => access_area.subdistrict_ids }
        else
          { "type" => "nearby" }
        end
      }
    end

    def pagination_meta(tag_states)
      {
        "complete" => tag_states.values.all? { |state| state["complete"] },
        "loaded_tags" => tag_states.count { |_tag, state| state["pages"].positive? },
        "total_tags" => tag_states.length,
        "pages_fetched" => tag_states.sum { |_tag, state| state["pages"] },
        "tag_states" => tag_states
      }
    end

    def track_usage(longdo_requests: 0, cache_hits: 0, cache_misses: 0, failed_requests: 0)
      LongdoUsageStat.where(stat_key: "all_time").find_one_and_update(
        { "$inc" => {
          longdo_requests: longdo_requests,
          cache_hits: cache_hits,
          cache_misses: cache_misses,
          failed_requests: failed_requests
        }, "$setOnInsert" => { created_at: Time.current }, "$set" => { updated_at: Time.current } },
        upsert: true,
        return_document: :after
      )
    rescue Mongo::Error => error
      Rails.logger.warn("Longdo usage tracking failed: #{error.class}: #{error.message}")
    end

    def estimated_population_for(place, category)
      reported_value = place["population"] || place["capacity"] || place["number_of_people"]
      parsed_value = Integer(reported_value, exception: false)
      return parsed_value if parsed_value&.positive?

      POPULATION_ESTIMATES.fetch(category, 0)
    end
  end
end
