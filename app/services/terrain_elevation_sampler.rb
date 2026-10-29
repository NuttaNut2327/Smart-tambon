require "chunky_png"

# Reads ground elevation (metres) from the cached Terrarium terrain tiles. Returns nil when a tile is unavailable.
class TerrainElevationSampler
  ZOOM = 12

  def initialize(zoom: ZOOM)
    @zoom = zoom
    @tiles = {}
  end

  def elevation(longitude, latitude)
    scale = 2**@zoom
    x = (longitude + 180.0) / 360.0 * scale
    lat_rad = latitude * Math::PI / 180.0
    y = (1.0 - Math.log(Math.tan(lat_rad) + 1.0 / Math.cos(lat_rad)) / Math::PI) / 2.0 * scale
    image = tile(x.floor, y.floor)
    return unless image

    pixel = image[((x - x.floor) * image.width).floor.clamp(0, image.width - 1), ((y - y.floor) * image.height).floor.clamp(0, image.height - 1)]
    ChunkyPNG::Color.r(pixel) * 256 + ChunkyPNG::Color.g(pixel) + ChunkyPNG::Color.b(pixel) / 256.0 - 32_768
  end

  private

  def tile(x, y)
    @tiles.fetch([x, y]) do
      data = TerrainTileStore.fetch(z: @zoom, x:, y:)
      @tiles[[x, y]] = data && ChunkyPNG::Image.from_blob(data)
    end
  rescue TerrainTileStore::Unavailable, ChunkyPNG::Exception
    @tiles[[x, y]] = nil
  end
end
