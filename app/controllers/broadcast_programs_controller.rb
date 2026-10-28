# News programmes of one อบต.: prompt, data sources, schedule, voice and channels. Managed by the อบต. admin.
class BroadcastProgramsController < ApplicationController
  before_action :require_organization_member!
  before_action :require_program_manager!, except: :run
  before_action :set_program, only: %i[edit update destroy run]

  def new
    @program = BroadcastProgram.from_template(params[:template], organization_key: current_user.organization_key)
    @program.name ||= "ข่าวประจำวัน"
    load_options
  end

  def create
    @program = BroadcastProgram.new(program_params.merge(organization_key: current_user.organization_key, subdistrict_id: current_user.subdistrict_id,
                                                         created_by: current_user.username, updated_by: current_user.username))
    @program.schedule_times_text = params.dig(:broadcast_program, :schedule_times_text)
    return(load_options || render(:new, status: :unprocessable_entity)) unless @program.save

    redirect_to broadcasts_path, notice: "เพิ่มรายการข่าว #{@program.name} เรียบร้อยแล้ว"
  end

  def edit = load_options

  def update
    @program.assign_attributes(program_params.merge(updated_by: current_user.username))
    @program.schedule_times_text = params.dig(:broadcast_program, :schedule_times_text)
    return(load_options || render(:edit, status: :unprocessable_entity)) unless @program.save

    redirect_to broadcasts_path, notice: "บันทึกรายการข่าว #{@program.name} เรียบร้อยแล้ว"
  end

  def destroy
    @program.destroy
    redirect_to broadcasts_path, notice: "ลบรายการข่าว #{@program.name} แล้ว (ข่าวที่สร้างไว้ยังอยู่)"
  end

  # "สร้างข่าวตอนนี้": queue a manual run; the worker summarises it within a few seconds.
  def run
    broadcast = Broadcasts::Runner.queue(@program, trigger: "manual", user: current_user)
    redirect_to broadcast_path(broadcast), notice: "กำลังสรุปข่าวจากข้อมูลล่าสุด…"
  end

  private

  def set_program
    @program = BroadcastProgram.for_organization(current_user.organization_key).find(params[:id])
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to broadcasts_path, alert: "ไม่พบรายการข่าว"
  end

  def load_options
    @channels = NotificationChannel.for_organization(current_user.organization_key).order_by(kind: :asc, name: :asc).to_a
    @ai_providers = AiProvider.enabled.ordered.to_a
    @tts_providers = TtsProvider.available_to(current_user.organization_key).enabled.ordered.to_a
    nil
  end

  def program_params
    params.require(:broadcast_program).permit(:name, :prompt, :lookahead_days, :max_words, :schedule_enabled, :auto_publish, :enabled, :alert_only, :history_years,
                                              :ai_provider_id, :tts_provider_id, :tts_voice, :internal_alert_level, :internal_alert_hours,
                                              data_sources: [], schedule_days: [], channel_ids: [], delivery_modes: [])
  end

  def require_organization_member!
    return if current_user.organization_key.present? && !system_admin?

    redirect_to broadcasts_path, alert: "รายการข่าวเป็นของแต่ละ อบต. — เข้าสู่ระบบด้วยบัญชีของ อบต. เพื่อจัดการ"
  end

  def require_program_manager!
    return if current_user.subdistrict_admin?

    redirect_to broadcasts_path, alert: "เฉพาะผู้ดูแลประจำ อบต. เท่านั้นที่ตั้งค่ารายการข่าวได้"
  end
end
