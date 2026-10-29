require "aws-sdk-s3"

# Swaps the MinIO client used by the image services for an in-memory stubbed S3 client.
module ObjectStoreStub
  SERVICES = [ImageLibrary, IncidentPhotoUploadService, ProjectPhotoUploadService].freeze

  def stub_object_store
    @stored_objects = {}
    client = Aws::S3::Client.new(stub_responses: true)
    client.stub_responses(:put_object, lambda { |context|
      body = context.params[:body]
      @stored_objects[context.params[:key]] = body.respond_to?(:read) ? body.read : body.to_s
      {}
    })
    client.stub_responses(:get_object, lambda { |context|
      @stored_objects.key?(context.params[:key]) ? { body: @stored_objects[context.params[:key]] } : "NoSuchKey"
    })
    client.stub_responses(:delete_object, lambda { |context| @stored_objects.delete(context.params[:key]); {} })
    @previous_clients = SERVICES.to_h { |service| [service, service.instance_variable_get(:@client)] }
    SERVICES.each { |service| service.instance_variable_set(:@client, client) }
  end

  def restore_object_store
    @previous_clients&.each { |service, client| service.instance_variable_set(:@client, client) }
  end

  def png_upload(name = "photo.png", width: 3000, height: 1500)
    require "vips"
    data = Vips::Image.black(width, height, bands: 3).add([40, 120, 80]).cast(:uchar).pngsave_buffer
    Rack::Test::UploadedFile.new(StringIO.new(data), "image/png", true, original_filename: name)
  end
end
