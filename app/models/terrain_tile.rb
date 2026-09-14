class TerrainTile < ApplicationRecord
  MAX_ZOOM = 15

  validates :zoom_level, inclusion: { in: 0..MAX_ZOOM }
  validates :tile_x, :tile_y, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :image_data, :imported_at, presence: true
  validate :coordinates_within_zoom

  private

  def coordinates_within_zoom
    return unless zoom_level && tile_x && tile_y

    tile_limit = 1 << zoom_level
    errors.add(:tile_x, "อยู่นอกขอบเขตของระดับซูม") if tile_x >= tile_limit
    errors.add(:tile_y, "อยู่นอกขอบเขตของระดับซูม") if tile_y >= tile_limit
  end
end
