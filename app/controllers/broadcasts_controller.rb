# News broadcasts (ข่าวประชาสัมพันธ์/เสียงตามสาย): review and edit what the AI wrote, voice it, attach a news image and
# publish. LLM, TTS and publishing run in the broadcast worker; the page polls #status while work is pending.
class BroadcastsController < ApplicationController
  before_action :set_broadcast, except: :index
  before_action :require_editor!, only: %i[update destroy regenerate synthesize image publish]
  before_action :require_publisher!, only: :publish

  def index
    scope = system_admin? ? Broadcast.all : Broadcast.for_organization(current_user.organization_key)
    @broadcasts = scope.desc(:created_at).limit(50).to_a
    @programs = system_admin? ? BroadcastProgram.all.to_a : BroadcastProgram.for_organization(current_user.organization_key).order_by(name: :asc).to_a
  end

  def show
    @channels = NotificationChannel.for_organization(@broadcast.organization_key).order_by(kind: :asc, name: :asc).to_a
  end

  def update
    @broadcast.assign_attributes(params.require(:broadcast).permit(:title, :script, :internal_alert_level, :internal_alert_hours, channel_ids: [], delivery_modes: []).merge(updated_by: current_user.username))
    @broadcast.bullets_text = params.dig(:broadcast, :bullets_text) if params.dig(:broadcast).key?(:bullets_text)
    @broadcast.save!
    redirect_to broadcast_path(@broadcast), notice: @broadcast.audio.present? && !@broadcast.audio_current? ? "บันทึกแล้ว — ข้อความเปลี่ยน กรุณาสร้างเสียงใหม่ก่อนส่งไปเสียงตามสาย" : "บันทึกข่าวเรียบร้อยแล้ว"
  end

  def destroy
    [@broadcast.audio, @broadcast.image].compact.each { |record| IncidentPhotoUploadService.delete_photo(record) }
    @broadcast.destroy
    redirect_to broadcasts_path, notice: "ลบข่าวแล้ว"
  end

  def regenerate = queue("generate", "กำลังสรุปข่าวใหม่จากข้อมูลล่าสุด…")
  def synthesize = queue("synthesize", "กำลังสร้างเสียงอ่านข่าว…")

  def publish
    return redirect_to(broadcast_path(@broadcast), alert: "เลือกรูปแบบการแจ้งเตือนและช่องทางอย่างน้อย 1 ช่องทางก่อน") unless @broadcast.delivery_targets?

    tasks = []
    tasks << "synthesize" if @broadcast.channels.any? { |channel| channel.kind == "pa_mqtt" } && !@broadcast.audio_current?
    queue([*tasks, "publish"], "กำลังเผยแพร่ข่าว…")
  end

  # The news card is drawn in the browser (canvas renders Thai text well) and uploaded as PNG.
  def image
    upload = params[:image]
    return render(json: { error: "ไม่พบไฟล์ภาพ" }, status: :unprocessable_entity) unless upload.respond_to?(:read)

    data = upload.read
    content_type = Marcel::MimeType.for(StringIO.new(data))
    return render(json: { error: "รองรับเฉพาะ PNG, JPG หรือ WebP" }, status: :unprocessable_entity) unless %w[image/png image/jpeg image/webp].include?(content_type)

    Broadcasts::Media.store(@broadcast, :image, data:, content_type:, filename: "broadcast-#{@broadcast.id}.png")
    render json: { url: Broadcasts::Media.public_url(@broadcast.reload, :image) }
  end

  def audio
    return head :not_found unless @broadcast.audio

    object = IncidentPhotoUploadService.download(@broadcast.audio)
    send_data object.body.read, type: "audio/mpeg", disposition: params[:download] ? "attachment" : "inline",
                                filename: "#{@broadcast.title.presence || 'broadcast'}.mp3".gsub(%r{[/\\]}, "-")
  rescue IncidentPhotoUploadService::ObjectNotFound
    head :not_found
  end

  def status
    render json: { status: @broadcast.status, status_label: @broadcast.status_label, busy: @broadcast.busy?, pending: @broadcast.pending_tasks,
                   error: @broadcast.error_message, audio_current: @broadcast.audio_current?, updated_at: @broadcast.updated_at.to_i }
  end

  private

  def set_broadcast
    scope = system_admin? ? Broadcast.all : Broadcast.for_organization(current_user.organization_key)
    @broadcast = scope.find(params[:id])
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to broadcasts_path, alert: "ไม่พบข่าว"
  end

  def queue(tasks, notice)
    return redirect_to(broadcast_path(@broadcast), alert: "ข่าวนี้กำลังประมวลผลอยู่ กรุณารอสักครู่") if @broadcast.busy?

    @broadcast.set(error_message: nil, status: Array(tasks).include?("generate") ? "queued" : @broadcast.status)
    @broadcast.enqueue!(tasks)
    redirect_to broadcast_path(@broadcast), notice:
  end

  def require_editor!
    return if !system_admin? && current_user.organization_key == @broadcast&.organization_key

    redirect_to broadcast_path(@broadcast), alert: "แก้ไขได้เฉพาะเจ้าหน้าที่ของ อบต. เจ้าของข่าว"
  end

  def require_publisher!
    return if current_user.subdistrict_admin?

    redirect_to broadcast_path(@broadcast), alert: "เฉพาะผู้ดูแลประจำ อบต. เท่านั้นที่เผยแพร่ข่าวได้"
  end
end
