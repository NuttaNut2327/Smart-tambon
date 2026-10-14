module Ai
  class SessionsController < BaseController
    def index
      render json: AiChatSession.owned_by(current_user).desc(:updated_at).limit(200).map(&:as_list_json)
    end

    def show
      render json: find_session(params[:id]).as_detail_json
    end

    def create
      session = AiChatSession.create!(user_id: current_user.id, organization_key: current_user.organization_key,
                                      title: params[:title].to_s.strip.truncate(60).presence || AiChatSession::DEFAULT_TITLE,
                                      ai_provider_id: provider_id_param)
      render json: session.as_detail_json, status: :created
    end

    def update
      session = find_session(params[:id])
      session.title = params[:title].to_s.strip.truncate(60) if params[:title].present?
      session.ai_provider_id = provider_id_param if params.key?(:ai_provider_id)
      session.save!
      render json: session.as_list_json
    end

    def destroy
      find_session(params[:id]).destroy
      head :no_content
    end

    private

    def provider_id_param
      AiProvider.enabled.where(id: params[:ai_provider_id]).pick(:_id) if params[:ai_provider_id].present?
    end
  end
end
