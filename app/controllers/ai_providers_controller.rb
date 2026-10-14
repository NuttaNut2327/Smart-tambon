# System admin: the LLMs available to the AI assistant of every อบต.
class AiProvidersController < ApplicationController
  before_action :require_system_admin!
  before_action :set_provider, only: %i[edit update destroy test]

  def index
    @providers = AiProvider.ordered.to_a
  end

  def new
    @provider = AiProvider.new(api_format: "anthropic", model: AiProvider::DEFAULT_MODELS["anthropic"], is_default: !AiProvider.exists?)
  end

  def create
    @provider = AiProvider.new(provider_params)
    save_provider(:new, "เพิ่มผู้ให้บริการ AI #{@provider.name} เรียบร้อยแล้ว")
  end

  def edit; end

  def update
    @provider.assign_attributes(provider_params)
    save_provider(:edit, "บันทึกผู้ให้บริการ AI #{@provider.name} เรียบร้อยแล้ว")
  end

  def destroy
    @provider.destroy
    redirect_to ai_providers_path, notice: "ลบผู้ให้บริการ AI #{@provider.name} แล้ว"
  end

  def test
    message = Ai::Llm.for(@provider).test!
    redirect_to ai_providers_path, notice: "#{@provider.name}: #{message}"
  rescue Ai::Llm::Error => error
    redirect_to ai_providers_path, alert: "#{@provider.name}: #{error.message}"
  end

  private

  def set_provider = @provider = AiProvider.find(params[:id])

  def provider_params
    params.require(:ai_provider).permit(:name, :api_format, :base_url, :model, :effort, :max_tokens, :enabled, :is_default, :position)
  end

  def save_provider(template, notice)
    @provider.assign_api_key(params.dig(:ai_provider, :api_key), clear: params.dig(:ai_provider, :clear_api_key) == "1")
    @provider.updated_by = current_user.username
    return render(template, status: :unprocessable_entity) unless @provider.save

    redirect_to ai_providers_path, notice: notice
  end

  def require_system_admin!
    return if system_admin?

    redirect_to root_path, alert: "เฉพาะผู้ดูแลระบบเท่านั้นที่ตั้งค่าผู้ให้บริการ AI ได้"
  end
end
