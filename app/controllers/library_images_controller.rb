# The image library (คลังข้อมูลภาพ): browse, upload, rename and delete pictures. The JSON index feeds the
# "เลือกจากคลังภาพ" picker on every form that attaches images.
class LibraryImagesController < ApplicationController
  PAGE_SIZE = 48

  before_action :set_image, only: %i[show update destroy]
  before_action :require_editor!, only: %i[update destroy]

  def index
    scope = LibraryImage.visible_to(current_user).matching(params[:q])
    scope = scope.where(source: params[:source]) if LibraryImage::SOURCES.key?(params[:source])
    @total = scope.count
    @page_count = [(@total.to_f / PAGE_SIZE).ceil, 1].max
    @page = params[:page].to_i.clamp(1, @page_count)
    @images = scope.desc(:created_at).skip((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE).to_a
    respond_to do |format|
      format.html do
        @usages = LibraryImage.usages_for(@images)
        @area_label = current_user.access_area&.name.presence || current_user.subdistrict&.name_th || "ทุกพื้นที่"
      end
      format.json { render json: { images: @images.map { |image| image_json(image) }, page: @page, page_count: @page_count, total: @total } }
    end
  end

  def show
    object = ImageLibrary.download(@image, variant: params[:variant])
    expires_in 1.day, public: false
    send_data object.body.read, type: "image/webp", disposition: "inline", filename: @image.image["filename"]
  rescue IncidentPhotoUploadService::ObjectNotFound, Aws::S3::Errors::ServiceError
    head :not_found
  end

  def create
    uploads = Array(params[:images]).compact_blank
    raise ImageLibrary::InvalidUpload, "เลือกภาพอย่างน้อย 1 ภาพ" if uploads.empty?

    ImageLibrary.validate!(uploads)
    images = uploads.map do |upload|
      ImageLibrary.import!(upload:, owner_user_id: current_user.id, subdistrict_id: current_user.subdistrict_id,
                           uploaded_by: current_user.username)
    end
    respond_to do |format|
      format.html { redirect_to library_images_path, notice: "เพิ่มภาพเข้าคลังแล้ว #{images.size} ภาพ" }
      format.json { render json: { images: images.map { |image| image_json(image) } }, status: :created }
    end
  rescue ImageLibrary::InvalidUpload => error
    respond_to do |format|
      format.html { redirect_to library_images_path, alert: error.message }
      format.json { render json: { error: error.message }, status: :unprocessable_entity }
    end
  rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError
    respond_to do |format|
      format.html { redirect_to library_images_path, alert: "จัดเก็บภาพไม่สำเร็จ กรุณาลองใหม่อีกครั้ง" }
      format.json { render json: { error: "จัดเก็บภาพไม่สำเร็จ กรุณาลองใหม่อีกครั้ง" }, status: :service_unavailable }
    end
  end

  def update
    title = params.dig(:library_image, :title).to_s.strip
    return redirect_to(library_images_path(q: params[:q], page: params[:page]), alert: "กรุณาระบุชื่อภาพ") if title.blank?

    @image.update!(title: title.truncate(120))
    redirect_to library_images_path(q: params[:q], page: params[:page]), notice: "เปลี่ยนชื่อภาพเรียบร้อยแล้ว"
  end

  # Pictures still attached somewhere stay, so deleting from the library never breaks an incident or project.
  def destroy
    usages = @image.usages
    if usages.any?
      return redirect_to library_images_path(q: params[:q], page: params[:page]),
                         alert: "ลบไม่ได้: ภาพนี้ยังถูกใช้งานอยู่ #{usages.size} รายการ (#{usages.first(3).map { |usage| "#{usage[:kind]} #{usage[:label]}" }.join(', ')})"
    end

    ImageLibrary.destroy!(@image)
    redirect_to library_images_path(q: params[:q], page: params[:page]), notice: "ลบภาพ #{@image.title} ออกจากคลังแล้ว"
  end

  private

  def set_image
    @image = LibraryImage.visible_to(current_user).find(params[:id])
  rescue Mongoid::Errors::DocumentNotFound
    action_name == "show" ? head(:not_found) : redirect_to(library_images_path, alert: "ไม่พบภาพที่ต้องการ")
  end

  def require_editor!
    return if @image.editable_by?(current_user)

    redirect_to library_images_path, alert: "คุณไม่มีสิทธิ์แก้ไขภาพนี้"
  end

  def image_json(image)
    { id: image.id.to_s, title: image.title, source: image.source_label, width: image.width, height: image.height,
      byte_size: image.image["byte_size"], url: library_image_file_path(image), thumb_url: library_image_file_path(image, variant: "thumb"),
      created_at: image.created_at }
  end
end
