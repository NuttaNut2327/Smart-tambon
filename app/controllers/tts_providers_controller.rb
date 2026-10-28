# Text-to-speech services used to voice news broadcasts (เสียงตามสาย). The system admin manages the central
# providers every อบต. can use; an อบต. admin manages the account's own (e.g. its own ElevenLabs key), seen only there.
class TtsProvidersController < ApplicationController
  SAMPLE_TEXT = "สวัสดีครับพี่น้องชาวตำบล นี่คือเสียงทดสอบระบบข่าวประชาสัมพันธ์ วันนี้อากาศแจ่มใส อุณหภูมิประมาณสามสิบสององศาเซลเซียส".freeze

  before_action :require_tts_manager!
  before_action :set_provider, only: %i[edit update destroy test make_default voices]
  helper_method :central_scope?

  def index
    @providers = provider_scope.ordered.to_a
    @central_providers = TtsProvider.central.enabled.ordered.to_a unless central_scope?
  end

  def new
    kind = TtsProvider::KINDS.key?(params[:kind]) ? params[:kind] : (central_scope? ? "google" : "elevenlabs")
    @provider = provider_scope.new(kind:, name: TtsProvider::KINDS.dig(kind, :label), is_default: !provider_scope.exists?)
  end

  def create
    @provider = provider_scope.new(provider_params)
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

  # ElevenLabs: the voices in the account, so the form can offer them instead of a hand-typed Voice ID.
  def voices
    return render(json: { error: "ดึงรายการเสียงได้เฉพาะ ElevenLabs" }, status: :unprocessable_entity) unless @provider.kind == "elevenlabs"

    render json: { voices: Tts::Synthesizer.elevenlabs_voices(@provider) }
  rescue Tts::Synthesizer::Error => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def central_scope? = system_admin?

  def provider_scope = central_scope? ? TtsProvider.central : TtsProvider.for_organization(current_user.organization_key)

  def set_provider
    @provider = provider_scope.find(params[:id])
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to tts_providers_path, alert: "ไม่พบผู้ให้บริการเสียง"
  end

  # An อบต. can't point a provider at a custom endpoint: the server would call any URL it is given.
  def provider_params
    keys = %i[name kind model voice speaking_rate enabled is_default]
    keys << :base_url if central_scope?
    params.require(:tts_provider).permit(*keys)
  end

  def save_provider(template, notice)
    @provider.assign_api_key(params.dig(:tts_provider, :api_key), clear: params.dig(:tts_provider, :clear_api_key) == "1")
    @provider.updated_by = current_user.username
    return render(template, status: :unprocessable_entity) unless @provider.save

    redirect_to tts_providers_path, notice:
  end

  def require_tts_manager!
    return if system_admin? || (current_user.subdistrict_admin? && current_user.organization_key.present?)

    redirect_to root_path, alert: "เฉพาะผู้ดูแลระบบหรือผู้ดูแลประจำ อบต. เท่านั้นที่ตั้งค่าผู้ให้บริการเสียงได้"
  end
end
