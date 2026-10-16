class CctvCamerasController < ApplicationController
  before_action :set_camera, only: %i[edit update destroy]
  before_action :require_camera_manager!, only: %i[edit update destroy]

  def index
    @cameras = CctvCamera.visible_to(current_user).order_by(name: :asc).to_a
    @subdistricts_by_id = Subdistrict.where(id: @cameras.map(&:subdistrict_id).compact.uniq).index_by(&:id)
  end

  def new
    @camera = CctvCamera.new(status: "active")
  end

  def create
    @camera = CctvCamera.new(camera_params.merge(user_id: current_user.id))
    @camera.acting_user = current_user
    if @camera.save
      redirect_to cctv_cameras_path, notice: "เพิ่มกล้อง #{@camera.name} เรียบร้อยแล้ว"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @camera.acting_user = current_user
    if @camera.update(camera_params)
      redirect_to cctv_cameras_path, notice: "อัปเดตกล้อง #{@camera.name} เรียบร้อยแล้ว"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @camera.destroy
    redirect_to cctv_cameras_path, notice: "ลบกล้อง #{@camera.name} เรียบร้อยแล้ว"
  end

  private

  def set_camera
    @camera = CctvCamera.visible_to(current_user).find(params[:id])
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to cctv_cameras_path, alert: "ไม่พบกล้องที่ต้องการ"
  end

  def require_camera_manager!
    return if @camera.nil? || @camera.editable_by?(current_user)

    redirect_to cctv_cameras_path, alert: "คุณไม่มีสิทธิ์แก้ไขกล้องนี้"
  end

  def camera_params
    params.require(:cctv_camera).permit(:name, :code, :stream_url, :stream_type, :status, :location_name, :description, :latitude, :longitude)
  end
end
