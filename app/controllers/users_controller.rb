class UsersController < ApplicationController
  before_action :require_user_manager!
  before_action :set_user, only: %i[edit update destroy]

  def index
    @users = manageable_users.includes(subdistrict: :province).order(:username)
  end

  def new
    @user = User.new(role: current_user.system_admin? ? :subdistrict_admin : :subdistrict_user)
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
    return redirect_to users_path, alert: "ต้องมีผู้ดูแลประจำ อบต. อย่างน้อย 1 บัญชี" if removing_last_local_admin?

    @user.destroy
    redirect_to users_path, notice: "ลบผู้ใช้เรียบร้อยแล้ว"
  end

  private

  def set_user
    @user = manageable_users.find(params[:id])
  end

  def manageable_users
    return User.all if current_user.system_admin?

    User.where(organization_key: current_user.organization_key).where.not(role: :system_admin)
  end

  def user_params
    params.require(:user).permit(:username, :password, :password_confirmation, :role, :subdistrict_id)
  end

  def user_attributes
    attributes = user_params
    unless current_user.system_admin?
      attributes[:role] = "subdistrict_user" unless %w[subdistrict_admin subdistrict_user].include?(attributes[:role])
      attributes[:subdistrict_id] = current_user.subdistrict_id
      attributes[:organization_key] = current_user.organization_key
      return attributes
    end
    selected_ids = Array(access_area_params[:subdistrict_ids]).reject(&:blank?)
    attributes[:subdistrict_id] = selected_ids.first if attributes[:role] != "system_admin" && selected_ids.any?
    attributes
  end

  def access_area_params
    params.fetch(:access_area, {}).permit(:name, :boundary_file, :selected_subdistrict_count, subdistrict_ids: [])
  end

  def save_user_and_access_area
    User.transaction do
      @user.access_area_file_pending = current_user.system_admin? ? file_access_area_mode? : current_user.access_area.present?
      @user.save!
      if current_user.system_admin?
        raise ArgumentError, @user.errors.full_messages.to_sentence unless save_access_area
      else
        copy_current_access_area!
      end
    end
    true
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    @user.errors.add(:base, error.message) if @user.errors.empty?
    false
  end

  def update_user_and_access_area(attributes)
    old_role = @user.role
    User.transaction do
      if !current_user.system_admin? && old_role == "subdistrict_admin" && attributes[:role] != "subdistrict_admin" && local_admin_count <= 1
        raise ArgumentError, "ต้องมีผู้ดูแลประจำ อบต. อย่างน้อย 1 บัญชี"
      end
      @user.access_area_file_pending = current_user.system_admin? ? file_access_area_mode? : current_user.access_area.present?
      @user.update!(attributes)
      if current_user.system_admin?
        raise ArgumentError, @user.errors.full_messages.to_sentence unless save_access_area
      elsif @user.access_area.blank?
        copy_current_access_area!
      end
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
    submitted_ids = submitted_ids.map { |id| Integer(id.to_s, 10) }.uniq
    selected_ids = submitted_ids.presence || [@user.subdistrict_id]
    mode = params[:access_area_mode].presence || "subdistricts"
    raise ArgumentError, "กรุณาแนบไฟล์ขอบเขต" if mode == "file" && access_area_params[:boundary_file].blank?
    raise ArgumentError, "กรุณาเลือกตำบลอย่างน้อย 1 ตำบล" if mode == "subdistricts" && submitted_ids.blank?
    expected_count = Integer(access_area_params[:selected_subdistrict_count].presence || submitted_ids.size)
    if mode == "subdistricts" && expected_count != submitted_ids.size
      raise ArgumentError, "จำนวนตำบลที่ส่งมาไม่ครบ (เลือก #{expected_count} แต่ได้รับ #{submitted_ids.size}) กรุณาเลือกใหม่แล้วบันทึกอีกครั้ง"
    end

    area = UserAccessAreaService.new(user: @user, name: access_area_params[:name], subdistrict_ids: selected_ids, boundary_file: access_area_params[:boundary_file]).save!
    if mode == "subdistricts" && area.subdistrict_ids.map(&:to_i).sort != submitted_ids.sort
      raise ArgumentError, "บันทึกรายการตำบลไม่ครบ กรุณาลองอีกครั้ง"
    end
    true
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    @user.errors.add(:base, error.message)
    false
  end

  def file_access_area_mode?
    params[:access_area_mode] == "file" && access_area_params[:boundary_file].present?
  end

  def copy_current_access_area!
    source = current_user.access_area
    return unless source

    area = @user.access_area || @user.build_access_area
    area.assign_attributes(name: source.name, source: source.source,
      subdistrict_ids: source.subdistrict_ids, boundary: source.boundary)
    area.save!
  end

  def local_admin_count
    User.where(organization_key: @user.organization_key, role: :subdistrict_admin).count
  end

  def removing_last_local_admin?
    @user.subdistrict_admin? && !current_user.system_admin? && local_admin_count <= 1
  end
end
