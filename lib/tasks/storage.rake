require "aws-sdk-s3"

namespace :storage do
  desc "Create the configured MinIO bucket when it does not exist"
  task prepare: :environment do
    client = Aws::S3::Client.new(
      endpoint: ENV.fetch("MINIO_ENDPOINT", "http://minio:9000"),
      access_key_id: ENV.fetch("MINIO_ACCESS_KEY", "minioadmin"),
      secret_access_key: ENV.fetch("MINIO_SECRET_KEY", "minioadmin123"),
      region: ENV.fetch("MINIO_REGION", "us-east-1"),
      force_path_style: true
    )
    bucket = ENV.fetch("MINIO_BUCKET", "smart-tambon-incidents")
    client.head_bucket(bucket: bucket)
    puts "MinIO bucket #{bucket} is ready"
  rescue Aws::S3::Errors::NotFound
    client.create_bucket(bucket: bucket)
    puts "Created MinIO bucket #{bucket}"
  end
end
