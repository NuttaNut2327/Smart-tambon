require "stringio"

class DatasetGridFileStore
  class << self
    def upload(filename, content, content_type: nil)
      bucket.upload_from_stream(filename, StringIO.new(content), metadata: { content_type: content_type })
    end

    def download(file_id)
      bucket.open_download_stream(BSON::ObjectId.from_string(file_id.to_s)).read
    end

    def delete(file_id)
      bucket.delete(BSON::ObjectId.from_string(file_id.to_s))
    rescue Mongo::Error::FileNotFound
      nil
    end

    private

    def bucket = Mongo::Grid::FSBucket.new(Mongoid.default_client.database)
  end
end
