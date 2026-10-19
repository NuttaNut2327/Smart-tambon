# Public, signed and expiring links to broadcast audio/images for PA devices and Meta (no login possible there).
class BroadcastMediaController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_access_configuration!

  def show
    record = Broadcasts::Media.resolve(params[:token])
    return head :not_found unless record

    object = IncidentPhotoUploadService.download(record)
    expires_in 1.hour, public: true
    send_data object.body.read, type: record["content_type"], disposition: "inline", filename: record["filename"].presence || "broadcast"
  rescue IncidentPhotoUploadService::ObjectNotFound, Aws::S3::Errors::ServiceError
    head :not_found
  end
end
