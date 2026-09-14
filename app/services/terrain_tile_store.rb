require "net/http"

class TerrainTileStore
  SOURCE_NAME = "AWS Open Data Terrain Tiles".freeze
  LOCKS_GUARD = Mutex.new
  TILE_LOCKS = {}

  class Unavailable < StandardError; end

  def self.fetch(z:, x:, y:)
    existing_tile = TerrainTile.find_by(zoom_level: z, tile_x: x, tile_y: y)
    return existing_tile.image_data if existing_tile

    lock_for(z, x, y).synchronize do
      existing_tile = TerrainTile.find_by(zoom_level: z, tile_x: x, tile_y: y)
      return existing_tile.image_data if existing_tile

      image_data = download(z, x, y)
      return unless image_data

      TerrainTile.create!(
        zoom_level: z,
        tile_x: x,
        tile_y: y,
        image_data: image_data,
        source: SOURCE_NAME,
        imported_at: Time.current
      )
      image_data
    end
  rescue ActiveRecord::RecordNotUnique
    TerrainTile.find_by!(zoom_level: z, tile_x: x, tile_y: y).image_data
  end

  def self.lock_for(z, x, y)
    key = [z, x, y].join(":")
    LOCKS_GUARD.synchronize { TILE_LOCKS[key] ||= Mutex.new }
  end
  private_class_method :lock_for

  def self.download(z, x, y)
    uri = URI("https://s3.amazonaws.com/elevation-tiles-prod/terrarium/#{z}/#{x}/#{y}.png")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 12) do |http|
      http.get(uri.request_uri)
    end

    response.body if response.is_a?(Net::HTTPSuccess)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => error
    raise Unavailable, error.message
  end
  private_class_method :download
end
