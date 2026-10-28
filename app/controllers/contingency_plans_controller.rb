class ContingencyPlansController < ApplicationController
  before_action :require_plan_manager!
  before_action :set_plan, only: %i[update destroy add_version update_version]

  def create
    @plan = ContingencyPlan.new(plan_params.merge(
      status: "draft",
      organization_key: current_user.organization_key.presence || "system",
      user_id: current_user.id, created_by: current_user.username, updated_by: current_user.username
    ))
    if @plan.save
      if params.dig(:contingency_plan, :from_assessment) == "1"
        append_version!
        redirect_to disasters_path(view: "plans", plan_id: @plan.id), notice: "สร้างแผนรับมือและบันทึกผลวิเคราะห์ Version 1 แล้ว"
      else
        redirect_to situation_assessment_path(plan_id: @plan.id), notice: "สร้างแผนรับมือฉบับร่างแล้ว กรุณาวิเคราะห์พื้นที่"
      end
    else
      redirect_to disasters_path(view: "plans"), alert: @plan.errors.full_messages.join(", ")
    end
  rescue JSON::ParserError
    @plan&.destroy
    redirect_to situation_assessment_path, alert: "ข้อมูลผลวิเคราะห์ไม่ถูกต้อง กรุณาวิเคราะห์พื้นที่ใหม่"
  end

  def update
    @plan.assign_attributes(plan_params)
    @plan.updated_by = current_user.username
    if @plan.save
      redirect_to disasters_path(view: "plans", plan_id: @plan.id), notice: "บันทึกข้อมูลแผนรับมือแล้ว"
    else
      redirect_to disasters_path(view: "plans", plan_id: @plan.id), alert: @plan.errors.full_messages.join(", ")
    end
  end

  def add_version
    append_version!
    redirect_to disasters_path(view: "plans", plan_id: @plan.id), notice: "บันทึกผลวิเคราะห์เป็น Version #{@plan.active_version} แล้ว"
  rescue JSON::ParserError
    redirect_to situation_assessment_path(plan_id: @plan.id), alert: "ข้อมูลผลวิเคราะห์ไม่ถูกต้อง กรุณาวิเคราะห์พื้นที่ใหม่"
  end

  def update_version
    version_number = params[:version].to_i
    submitted_entries = params.require(:contingency_plan).fetch(:entries, {}).to_unsafe_h.values
    updated = false
    @plan.versions = @plan.versions.map do |item|
      next item unless item["version"].to_i == version_number

      updated = true
      item.merge("entries" => normalize_entries(submitted_entries),
        "updated_at" => Time.current.utc.iso8601, "updated_by" => current_user.username)
    end
    raise Mongoid::Errors::DocumentNotFound.new(ContingencyPlan, version_number) unless updated

    @plan.updated_by = current_user.username
    @plan.save!
    redirect_to disasters_path(view: "plans", plan_id: @plan.id, plan_version: version_number),
      notice: "บันทึกจำนวนทรัพยากรที่ต้องใช้แล้ว"
  end

  def destroy
    reason = params.dig(:contingency_plan, :deletion_reason).to_s.strip
    if reason.blank?
      redirect_to disasters_path(view: "plans", plan_id: @plan.id), alert: "กรุณาระบุเหตุผลในการลบแผนรับมือ"
      return
    end

    AdminAuditLog.record!(current_user, "delete_contingency_plan", "contingency_plan:#{@plan.id}", request:,
      plan_name: @plan.name, disaster_type: @plan.disaster_type, organization_key: @plan.organization_key,
      active_version: @plan.active_version, reason: reason.truncate(500))
    @plan.destroy
    redirect_to disasters_path(view: "plans"), notice: "ลบแผนรับมือแล้ว"
  end

  private

  def append_version!
    entries = JSON.parse(params.require(:contingency_plan).fetch(:entries_json, "[]"))
    geometry = JSON.parse(params.require(:contingency_plan).fetch(:geometry_json, "{}"))
    selected_disaster_type = params.dig(:contingency_plan, :disaster_type).presence
    @plan.disaster_type = selected_disaster_type if selected_disaster_type.in?(ContingencyPlan::DISASTER_TYPES.keys)
    version_number = @plan.versions.map { |item| item["version"].to_i }.max.to_i + 1
    snapshot = {
      "version" => version_number,
      "title" => params.dig(:contingency_plan, :version_title).presence || "วิเคราะห์พื้นที่ Version #{version_number}",
      "geometry" => geometry,
      "area_sq_km" => params.dig(:contingency_plan, :area_sq_km).to_f,
      "affected_people" => params.dig(:contingency_plan, :affected_people).to_i,
      "affected_households" => params.dig(:contingency_plan, :affected_households).to_i,
      "affected_villages" => params.dig(:contingency_plan, :affected_villages).to_i,
      "entries" => normalize_entries(entries),
      "assessed_at" => Time.current.utc.iso8601,
      "created_by" => current_user.username
    }
    @plan.versions << snapshot
    @plan.active_version = version_number
    @plan.status = params.dig(:contingency_plan, :mark_ready) == "1" ? "ready" : "draft"
    @plan.updated_by = current_user.username
    @plan.save!
  end

  def set_plan
    @plan = ContingencyPlan.visible_to(current_user).find(params[:id])
  end

  def plan_params
    params.require(:contingency_plan).permit(:name, :description, :disaster_type, :status)
  end

  def normalize_entries(entries)
    Array(entries).filter_map do |entry|
      name = entry["name"].to_s.strip
      next if name.blank?
      required = [entry["required"].to_f, 0].max
      available = [entry["available"].to_f, 0].max
      { "category" => entry["category"].presence_in(%w[teams resources consumables]) || "resources",
        "name" => name, "unit" => entry["unit"].to_s.strip.presence || "หน่วย",
        "required" => required, "available" => available, "sufficient" => available >= required }
    end
  end

  def require_plan_manager!
    return if current_user.system_admin? || current_user.subdistrict_admin?
    redirect_to disasters_path, alert: "เฉพาะผู้ดูแลระบบหรือผู้ดูแลประจำตำบลเท่านั้นที่จัดการแผนรับมือได้"
  end
end
