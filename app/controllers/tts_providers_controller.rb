# System admin: text-to-speech services used to voice news broadcasts (เสียงตามสาย).
class TtsProvidersController < ApplicationController
  SAMPLE_TEXT = "สวัสดีครับพี่น้องชาวตำบล นี่คือเสียงทดสอบระบบข่าวประชาสัมพันธ์ วันนี้อากาศแจ่มใส อุณหภูมิประมาณสามสิบสององศาเซลเซียส".freeze

  before_action :require_system_admin!
  before_action :set_provider, only: %i[edit update destroy test make_default]

  def index
    @providers = TtsProvider.ordered.to_a
  end

  def new
    kind = TtsProvider::KINDS.key?(params[:kind]) ? params[:kind] : "google"
    @provider = TtsProvider.new(kind:, name: TtsProvider::KINDS.dig(kind, :label), is_default: !TtsProvider.exists?)
  end

  def create
    @provider = TtsProvider.new(provider_params)
    save_provider(:new, "เพิ่มผู้ให้บริการเสียง #{@provider.name} เรียบร้อยแล้ว")
  end

  def edit; end

  def update
    @provider.assign_attributes(provider_params)
    save_provider(:edit, "บันทึกผู้ให้บริการเสียง #{@provider.name} เรียบร้อยแล้ว")
  end

  def destroy
    @provider.destroy
    redirect_to tts_providers_path, notice: "ลบผู้ให้บริการเสียง #{@provider.name} แล้ว"
  end

  def make_default
    return redirect_to(tts_providers_path, alert: "เปิดใช้งาน #{@provider.name} ก่อนจึงตั้งเป็นค่าเริ่มต้นได้") unless @provider.enabled?

    @provider.update!(is_default: true, updated_by: current_user.username)
    redirect_to tts_providers_path, notice: "ตั้ง #{@provider.name} เป็นค่าเริ่มต้นแล้ว"
  end

  # Synthesizes a short sample and returns the MP3 so the page can play it.
  def test
    result = Tts::Synthesizer.call(params[:text].presence&.truncate(300) || SAMPLE_TEXT, provider: @provider, voice: params[:voice].presence)
    send_data result.audio, type: result.content_type, disposition: "inline", filename: "tts-sample.mp3"
  rescue Tts::Synthesizer::Error => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def set_provider = @provider = TtsProvider.find(params[:id])

  def provider_params
    params.require(:tts_provider).permit(:name, :kind, :base_url, :model, :voice, :speaking_rate, :enabled, :is_default)
  end

  def save_provider(template, notice)
    @provider.assign_api_key(params.dig(:tts_provider, :api_key), clear: params.dig(:tts_provider, :clear_api_key) == "1")
    @provider.updated_by = current_user.username
    return render(template, status: :unprocessable_entity) unless @provider.save

    redirect_to tts_providers_path, notice:
  end

  def require_system_admin!
    return if system_admin?

    redirect_to root_path, alert: "เฉพาะผู้ดูแลระบบเท่านั้นที่ตั้งค่าผู้ให้บริการเสียงได้"
  end
end
