class ProjectsController < ApplicationController
  before_action :set_project, only: %i[edit update destroy photo]
  before_action :require_project_manager!, only: %i[edit update destroy]

  def index
    scope = Project.visible_to(current_user)
    @fiscal_years = scope.distinct(:fiscal_year).compact.sort.reverse
    @filters = params.permit(:fiscal_year, :group, :status, :approval_status, :q).to_h.compact_blank
    scope = scope.where(group: @filters["group"]) if @filters["group"]
    scope = scope.where(status: @filters["status"]) if @filters["status"]
    scope = scope.where(approval_status: @filters["approval_status"]) if @filters["approval_status"]
    if @filters["q"]
      pattern = /#{Regexp.escape(@filters["q"])}/i
      scope = scope.any_of({ name: pattern }, { code: pattern }, { agency: pattern }, { project_type: pattern })
    end
    # The chart compares years, so it ignores the fiscal-year filter; the list below applies it.
    @budget_summary = ProjectBudgetSummary.new(scope)
    scope = scope.where(fiscal_year: @filters["fiscal_year"].to_i) if @filters["fiscal_year"]
    @projects = scope.order_by(fiscal_year: :desc, name: :asc).to_a
    @subdistricts_by_id = Subdistrict.where(id: @projects.map(&:subdistrict_id).compact.uniq).index_by(&:id)
  end

  def new
    @project = Project.new(status: "planned", fiscal_year: Project.current_fiscal_year)
  end

  def create
    uploads = ProjectPhotoUploadService.uploads_from(params)
    picked = ImageLibrary.pick(current_user, ProjectPhotoUploadService.library_ids_from(params))
    @project = Project.new(project_params.merge(user_id: current_user.id))
    @project.acting_user = current_user
    ProjectPhotoUploadService.validate!(uploads, picked_count: picked.size)
    return render(:new, status: :unprocessable_entity) unless @project.save

    begin
      ProjectPhotoUploadService.attach!(project: @project, uploads: uploads, picked: picked, uploaded_by: current_user.username)
    rescue StandardError => error
      Rails.logger.error("Project photo upload failed: #{error.class}: #{error.message}")
      @project.destroy
      @project = Project.new(project_params)
      @project.errors.add(:base, "อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่อีกครั้ง")
      return render(:new, status: :unprocessable_entity)
    end
    redirect_to projects_path, notice: "เพิ่มโครงการ #{@project.name} เรียบร้อยแล้ว"
  rescue ProjectPhotoUploadService::InvalidUpload => error
    @project.errors.add(:base, error.message)
    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    uploads = ProjectPhotoUploadService.uploads_from(params)
    removed_ids = Array(params.dig(:project, :remove_photo_ids)).compact_blank
    kept_count = Array(@project.photos).count { |photo| !removed_ids.include?(photo["id"]) }
    picked = ImageLibrary.pick(current_user, ProjectPhotoUploadService.library_ids_from(params))
    ProjectPhotoUploadService.validate!(uploads, existing_count: kept_count, picked_count: picked.size)
    @project.acting_user = current_user
    return render(:edit, status: :unprocessable_entity) unless @project.update(project_params)

    ProjectPhotoUploadService.remove!(project: @project, photo_ids: removed_ids)
    ProjectPhotoUploadService.attach!(project: @project, uploads: uploads, picked: picked, uploaded_by: current_user.username)
    redirect_to projects_path, notice: "อัปเดตโครงการ #{@project.name} เรียบร้อยแล้ว"
  rescue ProjectPhotoUploadService::InvalidUpload => error
    @project.errors.add(:base, error.message)
    render :edit, status: :unprocessable_entity
  rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError => error
    Rails.logger.error("Project photo upload failed: #{error.class}: #{error.message}")
    redirect_to edit_project_path(@project), alert: "บันทึกข้อมูลแล้ว แต่จัดการรูปไม่สำเร็จ กรุณาลองใหม่อีกครั้ง"
  end

  def destroy
    ProjectPhotoUploadService.purge_for(@project)
    @project.destroy
    redirect_to projects_path, notice: "ลบโครงการ #{@project.name} เรียบร้อยแล้ว"
  end

  def photo
    photo = Array(@project.photos).find { |item| item["id"] == params[:photo_id] }
    return head :not_found unless photo

    object = ProjectPhotoUploadService.download(photo, variant: params[:variant])
    expires_in 1.hour, public: false
    send_data object.body.read,
      filename: photo["filename"].presence || "project-photo",
      type: photo["content_type"].presence || object.content_type,
      disposition: "inline"
  rescue ProjectPhotoUploadService::ObjectNotFound
    head :not_found
  end

  private

  def set_project
    @project = Project.visible_to(current_user).find(params[:id])
  rescue Mongoid::Errors::DocumentNotFound
    return head(:not_found) if action_name == "photo"

    redirect_to projects_path, alert: "ไม่พบโครงการที่ต้องการ"
  end

  def require_project_manager!
    return if @project.nil? || current_user.can_manage_organization_data?(@project.user_id)

    redirect_to projects_path, alert: "คุณไม่มีสิทธิ์แก้ไขโครงการนี้"
  end

  def project_params
    params.require(:project).permit(
      :name, :code, :group, :project_type, :budget, :budget_source, :agency, :fiscal_year,
      :status, :approval_status, :progress_percent, :location_name, :description, :latitude, :longitude,
      *(current_user.system_admin? ? [:simulated] : [])
    )
  end
end
