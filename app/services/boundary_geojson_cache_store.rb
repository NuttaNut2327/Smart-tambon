class BoundaryGeojsonCacheStore
  TTL = 7.days

  def self.fetch(key, source_version:)
    cached = BoundaryGeojsonCache.where(key: key).first
    return cached.payload if cached&.fresh_for?(source_version)

    payload = yield
    BoundaryGeojsonCache.where(key: key).find_one_and_update(
      {
        "$set" => {
          key: key,
          source_version: source_version.to_s,
          payload: payload,
          expires_at: TTL.from_now,
          updated_at: Time.current
        },
        "$setOnInsert" => { created_at: Time.current }
      },
      upsert: true,
      return_document: :after
    )
    payload
  rescue Mongo::Error => error
    Rails.logger.warn("Boundary GeoJSON cache unavailable: #{error.class}: #{error.message}")
    yield
  end
end
