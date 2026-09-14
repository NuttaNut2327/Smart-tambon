require "chunky_png"
require_dependency "terrain_tile_store"

module Api
  class TerrainTilesController < ApplicationController
    MAX_ZOOM = 15

    def show
      z, x, y = %i[z x y].map { |key| Integer(params[key], exception: false) }
      return render json: { error: "พิกัด terrain tile ไม่ถูกต้อง" }, status: :unprocessable_entity unless valid_tile?(z, x, y)

      image_data = terrain_image_data(z, x, y)
      return render json: { error: "ไม่พบข้อมูลความสูงของพื้นที่นี้" }, status: :not_found unless image_data

      expires_in 7.days, public: false
      send_data image_data, type: "image/png", disposition: "inline"
    rescue ::TerrainTileStore::Unavailable
      render json: { error: "ไม่สามารถโหลดข้อมูลความสูงได้" }, status: :bad_gateway
    end

    def color
      z, x, y = %i[z x y].map { |key| Integer(params[key], exception: false) }
      return render json: { error: "พิกัด terrain tile ไม่ถูกต้อง" }, status: :unprocessable_entity unless valid_tile?(z, x, y)

      terrain_data = terrain_image_data(z, x, y)
      return render json: { error: "ไม่พบข้อมูลความสูงของพื้นที่นี้" }, status: :not_found unless terrain_data

      image_data = Rails.cache.fetch("terrain-color-v7/#{z}/#{x}/#{y}", expires_in: 7.days) do
        colorized_terrain_png(terrain_data)
      end
      return render json: { error: "ไม่พบข้อมูลความสูงของพื้นที่นี้" }, status: :not_found unless image_data

      expires_in 7.days, public: false
      send_data image_data, type: "image/png", disposition: "inline"
    rescue ChunkyPNG::ExpectationFailed
      render json: { error: "ข้อมูล Terrain Tile ไม่อยู่ในรูปแบบ PNG" }, status: :bad_gateway
    rescue ::TerrainTileStore::Unavailable
      render json: { error: "ไม่สามารถโหลดข้อมูลความสูงได้" }, status: :bad_gateway
    end

    private

    def valid_tile?(z, x, y)
      z && x && y && z.between?(0, MAX_ZOOM) && x.between?(0, (1 << z) - 1) && y.between?(0, (1 << z) - 1)
    end

    def terrain_image_data(z, x, y)
      ::TerrainTileStore.fetch(z: z, x: x, y: y)
    end

    def colorized_terrain_png(png_data)
      image = ChunkyPNG::Image.from_blob(png_data)
      elevations = image.pixels.map { |pixel| elevation_from_pixel(pixel) }
      width = image.width
      height = image.height

      elevations.each_index do |index|
        row = index / width
        column = index % width
        elevation = elevations[index]
        red, green, blue = elevation_color(elevation)
        brightness = hillshade_brightness(elevations, index, row, column, width, height)
        image.pixels[index] = ChunkyPNG::Color.rgba(
          (red * brightness).round.clamp(0, 255),
          (green * brightness).round.clamp(0, 255),
          (blue * brightness).round.clamp(0, 255),
          190
        )
      end
      image.to_blob
    end

    def elevation_color(elevation)
      return [222, 241, 202] if elevation <= 0
      return interpolate(elevation, 0, 100, [222, 241, 202], [174, 213, 137]) if elevation < 100
      return interpolate(elevation, 100, 250, [174, 213, 137], [91, 154, 90]) if elevation < 250
      return interpolate(elevation, 250, 500, [91, 154, 90], [38, 105, 67]) if elevation < 500
      return interpolate(elevation, 500, 1_000, [38, 105, 67], [20, 71, 54]) if elevation < 1_000
      return interpolate(elevation, 1_000, 1_500, [20, 71, 54], [14, 52, 44]) if elevation < 1_500
      return interpolate(elevation, 1_500, 2_500, [14, 52, 44], [7, 31, 29]) if elevation < 2_500

      [7, 31, 29]
    end

    def elevation_from_pixel(pixel)
      ChunkyPNG::Color.r(pixel) * 256 + ChunkyPNG::Color.g(pixel) + ChunkyPNG::Color.b(pixel) / 256.0 - 32_768
    end

    def hillshade_brightness(elevations, index, row, column, width, height)
      left = elevations[index - (column.positive? ? 1 : 0)]
      right = elevations[index + (column < width - 1 ? 1 : 0)]
      top = elevations[index - (row.positive? ? width : 0)]
      bottom = elevations[index + (row < height - 1 ? width : 0)]
      light_from_northwest = ((left - right) + (top - bottom)) * 0.024

      [[1.0 + light_from_northwest, 0.72].max, 1.18].min
    end

    def interpolate(value, start, finish, from, to)
      ratio = [[(value - start) / (finish - start), 0.0].max, 1.0].min
      from.zip(to).map { |first, last| (first + (last - first) * ratio).round }
    end
  end
end
