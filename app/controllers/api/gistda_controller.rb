module Api
  # GISTDA disaster layers for the dashboard map, scoped to the user's access boundary. Data comes from the
  # weather service's database cache; the GISTDA key (อบต. key, else system key) never reaches the browser.
  class GistdaController < ApplicationController
    def index
      dataset = params[:dataset].to_s
      return render(json: { error: "ไม่รู้จักชั้นข้อมูล #{dataset}" }, status: :not_found) unless GistdaDisasterLayer::DATASETS.include?(dataset)
      return render(json: { error: "ยังไม่มีขอบเขตพื้นที่สำหรับบัญชีนี้" }, status: :forbidden) if !global_viewer? && current_user.access_boundary.blank?

      layer = GistdaDisasterLayer.new(client:, boundary: current_user.access_boundary, global: global_viewer?,
                                      tambon_codes: (Subdistrict.where(id: current_user.accessible_subdistrict_ids).pluck(:code) unless global_viewer?))
      render json: layer.call(dataset, period:, bbox: params[:bbox])
    rescue GistdaDisasterClient::MissingKey
      render json: { error: "ยังไม่ได้ตั้งค่า GISTDA API key (ตั้งได้ที่หน้าตั้งค่าระบบ หรือหน้าตั้งค่า อบต.)", code: "gistda_key_missing" }, status: :service_unavailable
    rescue GistdaDisasterClient::Error => e
      Rails.logger.warn("[gistda] #{e.message}")
      render json: { error: e.message }, status: :bad_gateway
    end

    def tile
      layer = params[:layer].to_s
      z, x, y = params.values_at(:z, :x, :y).map { |value| Integer(value, exception: false) }
      return head(:not_found) unless GistdaDisasterClient::TILE_LAYERS.include?(layer) && z&.between?(5, 18) && x && y && x.between?(0, 2**z - 1) && y.between?(0, 2**z - 1)
      return head(:no_content) unless global_viewer? || tile_in_area?(z, x, y)

      png, content_type = client.tile(layer, z:, x:, y:, period:)
      return head(:no_content) unless png

      expires_in 1.hour, public: false
      send_data png, type: content_type, disposition: "inline"
    rescue GistdaDisasterClient::Error => e
      Rails.logger.warn("[gistda] tile #{layer}/#{z}/#{x}/#{y}: #{e.message}")
      head :no_content
    end

    private

    def client = @client ||= GistdaDisasterClient.for(current_user)

    def period
      value = params[:period].to_i
      GistdaDisasterClient::PERIODS.include?(value) ? value : 1
    end

    # True when the XYZ tile overlaps the envelope of the user's access boundary.
    def tile_in_area?(z, x, y)
      boundary = current_user.access_boundary
      return false if boundary.blank?

      n = 2.0**z
      lat = ->(row) { Math.atan(Math.sinh(Math::PI * (1 - 2 * row / n))) * 180 / Math::PI }
      ActiveModel::Type::Boolean.new.cast(ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql_array([
        "SELECT ST_Intersects(ST_Envelope(ST_GeomFromText(?, 4326)), ST_MakeEnvelope(?, ?, ?, ?, 4326))",
        boundary.as_text, x / n * 360 - 180, lat.call(y + 1), (x + 1) / n * 360 - 180, lat.call(y)
      ])))
    end
  end
end
