class AccessBoundaryPointFilter
  def initialize(boundary)
    @boundary = boundary
  end

  def filter(records)
    candidates = Array(records).filter_map.with_index do |record, index|
      longitude, latitude = yield(record)
      longitude = Float(longitude, exception: false)
      latitude = Float(latitude, exception: false)
      [index, longitude, latitude] if longitude&.between?(-180, 180) && latitude&.between?(-90, 90)
    end
    return [] if @boundary.blank? || candidates.empty?

    values = candidates.map { |index, longitude, latitude| "(#{index},#{longitude},#{latitude})" }.join(",")
    boundary_sql = ActiveRecord::Base.connection.quote(@boundary.as_text)
    sql = <<~SQL.squish
      WITH candidates(position, longitude, latitude) AS (VALUES #{values})
      SELECT position
      FROM candidates
      WHERE ST_Covers(
        ST_CollectionExtract(ST_MakeValid(ST_GeomFromText(#{boundary_sql}, 4326)), 3),
        ST_SetSRID(ST_Point(longitude, latitude), 4326)
      )
    SQL
    included_positions = ActiveRecord::Base.connection.select_values(sql).map(&:to_i).to_set
    Array(records).filter_map.with_index { |record, index| record if included_positions.include?(index) }
  end
end
