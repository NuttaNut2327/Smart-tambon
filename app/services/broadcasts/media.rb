require "aws-sdk-s3"

module Broadcasts
  # Audio and image files for broadcasts live in MinIO. Devices on the PA system and Meta's servers fetch them through
  # signed, expiring public links (/broadcast_media/:token) because they cannot log in.
  module Media
    LINK_TTL = 7.days

    def self.public_url(broadcast, kind)
      record = broadcast.public_send(kind)
      return unless record

      token = verifier.generate({ "id" => broadcast.id.to_s, "kind" => kind.to_s, "file" => record["id"] }, expires_in: LINK_TTL)
      "#{base_url}/broadcast_media/#{token}"
    end

    def self.resolve(token)
      payload = verifier.verified(token)
      return unless payload.is_a?(Hash) && %w[audio image].include?(payload["kind"])

      broadcast = Broadcast.where(id: payload["id"]).first
      record = broadcast&.public_send(payload["kind"])
      record if record && record["id"] == payload["file"]
    end

    def self.store(broadcast, kind, data:, content_type:, filename:)
      extension = { "audio/mpeg" => "mp3", "image/png" => "png", "image/jpeg" => "jpg", "image/webp" => "webp" }.fetch(content_type, "bin")
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: Tempfile.new(["broadcast", ".#{extension}"]).tap { |file| file.binmode; file.write(data); file.rewind },
                                                      filename:, type: content_type)
      record = kind.to_s == "audio" ? store_audio(broadcast, upload, content_type, data) : IncidentPhotoUploadService.store!(prefix: "broadcasts/#{broadcast.id}", upload:)
      previous = broadcast.public_send(kind)
      broadcast.set(kind => record)
      IncidentPhotoUploadService.delete_photo(previous) if previous
      record
    end

    # Audio isn't an image, so it skips the image validation and is written straight to the bucket.
    def self.store_audio(broadcast, upload, content_type, data)
      key = "broadcasts/#{broadcast.id}/voice-#{SecureRandom.hex(6)}.mp3"
      client = Aws::S3::Client.new(
        endpoint: ENV.fetch("MINIO_ENDPOINT", "http://localhost:9000"), region: "us-east-1", force_path_style: true,
        access_key_id: ENV.fetch("MINIO_ACCESS_KEY", "minioadmin"), secret_access_key: ENV.fetch("MINIO_SECRET_KEY", "minioadmin123")
      )
      client.put_object(bucket: ENV.fetch("MINIO_BUCKET", "smart-tambon-incidents"), key:, body: upload.tempfile, content_type:)
      { "id" => SecureRandom.uuid, "key" => key, "filename" => upload.original_filename, "content_type" => content_type,
        "byte_size" => data.bytesize, "sha256" => Digest::SHA256.hexdigest(data), "uploaded_at" => Time.current }
    end

    def self.base_url
      (NotificationSetting.current.base_url.presence || ENV["APP_URL"].presence || "http://localhost:3000").delete_suffix("/")
    end

    def self.verifier = Rails.application.message_verifier(:broadcast_media)
  end
end
