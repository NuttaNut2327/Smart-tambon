# Photos on resource and consumable rows: upload into the image library or pick from it, view and remove.
class DatasetRecordPhotosController < ApplicationController
  before_action :set_dataset
  before_action :require_editor!, only: %i[create destroy]

  def show
    photo = DatasetRecordPhoto.for_record(@dataset.id, params[:record_id]).find(params[:id])
    object = photo.variant(params[:variant])
    data = IncidentPhotoUploadService.download(object)
    expires_in 1.day, public: false
    send_data data.body.read, type: object["content_type"], disposition: "inline", filename: object["filename"]
  rescue Mongoid::Errors::DocumentNotFound, IncidentPhotoUploadService::ObjectNotFound, Aws::S3::Errors::ServiceError
    head :not_found
  end

  def create
    record_id = params[:record_id].to_s
    unless Array(@dataset.current_version&.records).any? { |record| record["record_id"] == record_id }
      return render(json: { error: "ไม่พบรายการที่ต้องการแนบภาพ" }, status: :not_found)
    end

    uploads = Array(params[:photos]).compact_blank
    picked = ImageLibrary.pick(current_user, params[:library_image_ids])
    existing = DatasetRecordPhoto.for_record(@dataset.id, record_id).to_a
    raise ImageLibrary::InvalidUpload, "เลือกรูปอย่างน้อย 1 รูป" if uploads.empty? && picked.empty?
    if existing.size + uploads.size + picked.size > DatasetRecordPhoto::MAX_PER_RECORD
      raise ImageLibrary::InvalidUpload, "แนบรูปได้ไม่เกิน #{DatasetRecordPhoto::MAX_PER_RECORD} รูปต่อรายการ"
    end

    ImageLibrary.validate!(uploads)
    images = uploads.map do |upload|
      ImageLibrary.import!(upload:, owner_user_id: @dataset.user_id, subdistrict_id: @dataset.subdistrict_id,
                           source: "dataset_record", uploaded_by: current_user.username)
    end
    attached = existing.map(&:library_image_id)
    (images + picked).uniq(&:id).reject { |image| attached.include?(image.id.to_s) }.each do |image|
      DatasetRecordPhoto.create!(imported_dataset_id: @dataset.id, record_id:, uploaded_by: current_user.username,
                                 **DatasetRecordPhoto.attributes_for(image))
    end
    render json: { photos: photos_payload(record_id) }, status: :created
  rescue ImageLibrary::InvalidUpload => error
    render json: { error: error.message }, status: :unprocessable_entity
  rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError
    render json: { error: "จัดเก็บรูปไม่สำเร็จ กรุณาลองใหม่อีกครั้ง" }, status: :service_unavailable
  end

  def destroy
    DatasetRecordPhoto.for_record(@dataset.id, params[:record_id]).find(params[:id]).purge!
    render json: { photos: photos_payload(params[:record_id]) }
  rescue Mongoid::Errors::DocumentNotFound
    render json: { error: "ไม่พบรูปที่ต้องการลบ" }, status: :not_found
  end

  private

  def set_dataset
    @dataset = ImportedDataset.visible_to(current_user).where(id: params[:imported_dataset_id], :data_type.in => DatasetRecordPhoto::DATA_TYPES).first
    head :not_found unless @dataset
  end

  def require_editor!
    return if @dataset.editable_by?(current_user)

    render json: { error: "คุณไม่มีสิทธิ์แก้ไขรูปของรายการนี้" }, status: :forbidden
  end

  def photos_payload(record_id)
    DatasetRecordPhoto.for_record(@dataset.id, record_id).map { |photo| helpers.dataset_record_photo_json(@dataset, photo) }
  end
end
