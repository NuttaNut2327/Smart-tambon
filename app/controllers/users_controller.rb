class UsersController < ApplicationController
  before_action :require_system_admin!
  before_action :set_user, only: %i[edit update destroy]

  def index
    @users = User.includes(subdistrict: :province).order(:username)
  end

  def new
    @user = User.new(role: :subdistrict_admin)
  end

  def create
    @user = User.new(user_attributes)
    if save_user_and_access_area
      redirect_to users_path, notice: "สร้างผู้ใช้เรียบร้อยแล้ว"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attributes = user_attributes
    attributes.delete(:password) if attributes[:password].blank?
    attributes.delete(:password_confirmation) if attributes[:password_confirmation].blank?
    if update_user_and_access_area(attributes)
      redirect_to users_path, notice: "อัปเดตผู้ใช้เรียบร้อยแล้ว"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    return redirect_to users_path, alert: "ไม่สามารถลบบัญชีที่กำลังใช้งานอยู่" if @user == current_user

    @user.destroy
    redirect_to users_path, notice: "ลบผู้ใช้เรียบร้อยแล้ว"
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:username, :password, :password_confirmation, :role, :subdistrict_id)
  end

  def user_attributes
    attributes = user_params
    selected_ids = Array(access_area_params[:subdistrict_ids]).reject(&:blank?)
    attributes[:subdistrict_id] = selected_ids.first if attributes[:role] != "system_admin" && selected_ids.any?
    attributes
  end

  def access_area_params
    params.fetch(:access_area, {}).permit(:name, :boundary_file, subdistrict_ids: [])
  end

  def save_user_and_access_area
    User.transaction do
      @user.access_area_file_pending = file_access_area_mode?
      @user.save!
      raise ArgumentError, @user.errors.full_messages.to_sentence unless save_access_area
    end
    true
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    @user.errors.add(:base, error.message) if @user.errors.empty?
    false
  end

  def update_user_and_access_area(attributes)
    User.transaction do
      @user.access_area_file_pending = file_access_area_mode?
      @user.update!(attributes)
      raise ArgumentError, @user.errors.full_messages.to_sentence unless save_access_area
    end
    true
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    @user.errors.add(:base, error.message) if @user.errors.empty?
    false
  end

  def save_access_area
    if @user.system_admin?
      @user.access_area&.destroy!
      return true
    end

    submitted_ids = Array(access_area_params[:subdistrict_ids]).reject(&:blank?)
    selected_ids = submitted_ids.presence || [@user.subdistrict_id]
    mode = params[:access_area_mode].presence || "subdistricts"
    raise ArgumentError, "กรุณาแนบไฟล์ขอบเขต" if mode == "file" && access_area_params[:boundary_file].blank?
    raise ArgumentError, "กรุณาเลือกตำบลอย่างน้อย 1 ตำบล" if mode == "subdistricts" && submitted_ids.blank?

    UserAccessAreaService.new(user: @user, name: access_area_params[:name], subdistrict_ids: selected_ids, boundary_file: access_area_params[:boundary_file]).save!
    true
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    @user.errors.add(:base, error.message)
    false
  end

  def file_access_area_mode?
    params[:access_area_mode] == "file" && access_area_params[:boundary_file].present?
  end
end
