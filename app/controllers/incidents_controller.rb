class IncidentsController < ApplicationController
  def create
    incident = Incident.new(incident_attributes)
    incident.user_id = current_user.id
    incident.subdistrict_id = current_user.subdistrict_id || params.dig(:incident, :subdistrict_id)
    if incident.subdistrict_id.blank?
      return redirect_to disasters_path, alert: "กรุณาเลือกบัญชีประจำพื้นที่ก่อนบันทึกเหตุการณ์"
    end

    incident.save!
    redirect_to disasters_path(incident_id: incident.id), notice: "บันทึกเหตุการณ์ใหม่เรียบร้อยแล้ว"
  rescue Mongoid::Errors::Validations => error
    redirect_to disasters_path, alert: error.document.errors.full_messages.join(" · ")
  end

  def update
    incident = find_incident
    incident.update!(incident_attributes)
    redirect_to disasters_path(incident_id: incident.id), notice: "แก้ไขข้อมูลเหตุการณ์เรียบร้อยแล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  rescue Mongoid::Errors::Validations => error
    redirect_to disasters_path(incident_id: params[:id]), alert: error.document.errors.full_messages.join(" · ")
  end

  def add_progress
    incident = find_incident
    progress = params.require(:progress).permit(:status, :title, :description, :assigned_to)
    incident.status = progress[:status] if Incident::STATUSES.include?(progress[:status])
    incident.assigned_to = progress[:assigned_to] if progress[:assigned_to].present?
    incident.histories << {
      "title" => progress[:title].presence || "อัปเดตการทำงาน",
      "description" => progress[:description],
      "occurred_at" => Time.current.strftime("%d/%m/%Y %H:%M"),
      "actor" => current_user.username,
      "resources" => []
    }
    incident.save!
    redirect_to disasters_path(incident_id: incident.id), notice: "อัปเดตการทำงานเรียบร้อยแล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def assess
    incident = find_incident
    assessment = params.require(:assessment).permit(:title, :affected_people, :budget, :resource_lines, :activate)
    next_version = incident.response_plan_versions.map { |item| item["version"].to_i }.max.to_i + 1
    resources = assessment[:resource_lines].to_s.lines.filter_map do |line|
      name, required, available, unit = line.strip.split("|").map(&:strip)
      next if name.blank?

      { "name" => name, "required" => required.to_f, "available" => available.to_f, "unit" => unit.presence || "รายการ" }
    end
    incident.response_plan_versions << {
      "version" => next_version,
      "title" => assessment[:title].presence || "ประเมินสถานการณ์ครั้งที่ #{next_version}",
      "affected_people" => assessment[:affected_people].to_i,
      "budget" => assessment[:budget].to_i,
      "assessed_at" => Time.current.strftime("%d/%m/%Y %H:%M"),
      "resources" => resources
    }
    incident.active_plan_version = next_version if assessment[:activate] == "1"
    incident.status = "assessing" if incident.status.in?(%w[pending acknowledged])
    incident.save!
    redirect_to disasters_path(incident_id: incident.id, plan_version: next_version), notice: "บันทึกผลประเมิน Version #{next_version} แล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def acknowledge
    incident = Incident.visible_to(current_user).find(params[:id])
    return redirect_to disasters_path(incident_id: incident.id), notice: "เหตุการณ์นี้ถูกรับเรื่องแล้ว" unless incident.status == "pending"

    assigned_to = params.require(:incident).require(:assigned_to)

    incident.histories << {
      "title" => "รับเรื่องแล้ว",
      "description" => "เจ้าหน้าที่รับเรื่องและอยู่ระหว่างประสานงานตรวจสอบ",
      "occurred_at" => Time.current.strftime("%d/%m/%Y %H:%M"),
      "actor" => current_user.username,
      "resources" => []
    }
    incident.status = "acknowledged"
    incident.assigned_to = assigned_to
    incident.received_by = current_user.username
    incident.received_by_user_id = current_user.id
    incident.received_at = Time.current
    incident.save!

    redirect_to disasters_path(incident_id: incident.id), notice: "รับเรื่องเรียบร้อยแล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  def activate_plan
    incident = Incident.visible_to(current_user).find(params[:id])
    version_number = params.require(:version).to_i
    unless incident.response_plan_versions.any? { |version| version["version"].to_i == version_number }
      return redirect_to disasters_path(incident_id: incident.id), alert: "ไม่พบ Version แผนรับมือที่เลือก"
    end

    incident.update!(active_plan_version: version_number)
    redirect_to disasters_path(incident_id: incident.id, plan_version: version_number), notice: "เลือกใช้แผนรับมือ Version #{version_number} แล้ว"
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to disasters_path, alert: "ไม่พบเหตุการณ์ที่ต้องการ"
  end

  private

  def find_incident
    Incident.visible_to(current_user).find(params[:id])
  end

  def incident_attributes
    params.require(:incident).permit(
      :category, :incident_type, :title, :description, :severity, :status,
      :reporter_name, :reporter_contact, :location_name, :longitude, :latitude,
      :affected_people, :affected_households, :initial_impact, :assigned_to
    )
  end
end
